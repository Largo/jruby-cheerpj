#!/usr/bin/env python3
"""Static server for the JRuby-on-CheerpJ REPL (used by run.sh).

`python3 -m http.server` is not enough: CheerpJ reads jars with HTTP Range
requests and needs 206 + Content-Range. This server adds single-range support
("bytes=a-b", "bytes=a-", "bytes=-n", 416), HTTP/1.1 keep-alive, ETag/304,
gzip for full text responses, and MIME types for .js/.mjs/.wasm/.jar.

Usage: python3 serve.py [--port 8017] [--bind 127.0.0.1] [--root DIR] [--quiet]
"""
import argparse, email.utils, gzip, os, re, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TYPES = {
    ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript",
    ".css": "text/css", ".json": "application/json", ".wasm": "application/wasm",
    ".jar": "application/java-archive", ".txt": "text/plain; charset=utf-8",
    ".md": "text/plain; charset=utf-8", ".rb": "text/plain; charset=utf-8",
    ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon",
}
GZIP = (".html", ".js", ".mjs", ".css", ".json", ".txt", ".md", ".rb", ".svg")
RANGE_RE = re.compile(r"^bytes=(\d*)-(\d*)$")
_gz = {}


class Handler(BaseHTTPRequestHandler):
    server_version = "jruby-cheerpj/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        if not self.server.quiet:
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _file(self):
        p = urllib.parse.unquote(self.path.split("?", 1)[0].split("#", 1)[0])
        p = os.path.normpath("/" + p).lstrip("/") or "index.html"
        full = os.path.realpath(os.path.join(self.server.root, p))
        if os.path.isdir(full):
            full = os.path.join(full, "index.html")
        if os.path.commonpath([full, self.server.root]) != self.server.root:
            return None
        return full if os.path.isfile(full) else None

    def _empty(self, code, headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        f = self._file()
        if f is None:
            return self._empty(404)
        st = os.stat(f)
        size, ext = st.st_size, os.path.splitext(f)[1].lower()
        etag = '"%x-%x"' % (st.st_mtime_ns, size)
        hdrs = [("Content-Type", TYPES.get(ext, "application/octet-stream")), ("Accept-Ranges", "bytes"),
                ("ETag", etag), ("Last-Modified", email.utils.formatdate(st.st_mtime, usegmt=True)),
                ("Cache-Control", "no-cache" if ext in (".html", ".js") else "public, max-age=3600")]
        rng = self.headers.get("Range")
        if not rng and self.headers.get("If-None-Match") == etag:
            return self._empty(304, hdrs[1:])
        if rng and self.headers.get("If-Range") in (None, etag):
            m = RANGE_RE.match(rng.strip())
            if not m or m.group(1) == m.group(2) == "":
                return self._empty(416, [("Content-Range", "bytes */%d" % size)])
            if m.group(1) == "":
                start, end = max(0, size - int(m.group(2))), size - 1
            else:
                start = int(m.group(1))
                end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
            if start >= size or start > end:
                return self._empty(416, [("Content-Range", "bytes */%d" % size)])
            self.send_response(206)
            for k, v in hdrs:
                self.send_header(k, v)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
            self.send_header("Content-Length", str(end - start + 1))
            self.end_headers()
            if self.command != "HEAD":
                with open(f, "rb") as fh:
                    fh.seek(start)
                    self.wfile.write(fh.read(end - start + 1))
            return
        body = None
        if ext in GZIP and "gzip" in (self.headers.get("Accept-Encoding") or ""):
            key = (f, st.st_mtime_ns, size)
            if key not in _gz:
                with open(f, "rb") as fh:
                    _gz[key] = gzip.compress(fh.read(), 9)
            body = _gz[key]
            hdrs += [("Content-Encoding", "gzip"), ("Vary", "Accept-Encoding")]
        self.send_response(200)
        for k, v in hdrs:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body) if body is not None else size))
        self.end_headers()
        if self.command == "HEAD":
            return
        if body is not None:
            self.wfile.write(body)
        else:
            with open(f, "rb") as fh:
                while chunk := fh.read(1 << 20):
                    self.wfile.write(chunk)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8017")))
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--root", default=here)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.bind, a.port), Handler)
    srv.daemon_threads = True
    srv.root = os.path.realpath(a.root)
    srv.quiet = a.quiet
    print("serving %s on http://%s:%d/" % (srv.root, a.bind, a.port), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
