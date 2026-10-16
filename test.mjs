// Headless Playwright test for the JRuby-on-CheerpJ REPL page.
//
//   ./run.sh test                         (preferred: fetches the jar first)
//   NODE_PATH=$(npm root -g) node test.mjs [query]     e.g. "java=11" or "warmup=0"
//
// Starts serve.py on a free 127.0.0.1 port, loads index.html in a fresh (cold-cache) Chromium
// context, waits for JRuby to boot, drives the REPL UI (textarea + Ctrl+Enter, then the Run
// button) and the window.jruby.eval API, asserts the captured output, prints timings and
// download sizes, and stops the server. Exit code 0 = all passed.
import { createRequire } from "node:module";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import net from "node:net";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const DIR = path.dirname(fileURLToPath(import.meta.url));
const QUERY = process.argv[2] || "";
const BOOT_TIMEOUT = 5 * 60_000, EVAL_TIMEOUT = 2 * 60_000;
const hardStop = setTimeout(() => { console.log("FAIL: global timeout (15 min)"); cleanup(3); }, 15 * 60_000);

const SNIPPET = `puts RUBY_DESCRIPTION
puts [1,2,3].map { |x| x * 2 }.inspect
class Foo; def hi = "hi"; end
puts Foo.new.hi
require 'set'
p Set[1,2]`;

let failures = 0;
const check = (name, cond, detail = "") => {
  console.log(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? "  -- " + detail : ""}`);
  if (!cond) failures++;
};

const freePort = () => new Promise((res, rej) => {
  const s = net.createServer();
  s.on("error", rej);
  s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => res(p)); });
});
const portOpen = (port) => new Promise((res) => {
  const s = net.connect(port, "127.0.0.1", () => { s.destroy(); res(true); });
  s.on("error", () => res(false));
});

let server = null, browser = null;
async function cleanup(code) {
  clearTimeout(hardStop);
  // browser.close() can hang after CheerpJ has run; never wait on it for long.
  if (browser) await Promise.race([browser.close().catch(() => {}), new Promise((r) => setTimeout(r, 5000))]);
  if (server) { server.kill(); console.log(`stopped server (pid ${server.pid})`); }
  process.exit(code);
}

const PORT = await freePort();
const BASE = `http://127.0.0.1:${PORT}`;
server = spawn("python3", ["-I", path.join(DIR, "serve.py"), "--port", String(PORT), "--bind", "127.0.0.1", "--quiet"], { stdio: "ignore" });
for (let i = 0; i < 100 && !(await portOpen(PORT)); i++) await new Promise((r) => setTimeout(r, 100));
console.log(`started serve.py on ${BASE} (pid ${server.pid})`);

try {
  browser = await chromium.launch();
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const pageErrors = [];
  page.on("pageerror", (e) => pageErrors.push(String(e)));
  const bytes = { local: [0, 0], cdn: [0, 0], other: [] };
  page.on("requestfinished", async (r) => {
    const u = r.url();
    const k = u.startsWith(BASE) ? "local" : u.includes("cjrtnc.leaningtech.com") ? "cdn" : null;
    if (!k) { if (/^https?:/.test(u)) bytes.other.push(u); return; }
    try { const s = await r.sizes(); bytes[k][0]++; bytes[k][1] += s.responseBodySize + s.responseHeadersSize; } catch {}
  });

  const url = `${BASE}/index.html${QUERY ? "?" + QUERY : ""}`;
  console.log(`loading ${url} (fresh browser context, cold cache)`);
  const t0 = Date.now();
  await page.goto(url);
  let T;
  try {
    T = await Promise.race([page.evaluate(() => window.jruby.ready),
      new Promise((_, rej) => setTimeout(() => rej(new Error("boot timeout")), BOOT_TIMEOUT))]);
  } catch (e) {
    console.log(`FAIL  boot: ${e.message}\nstatus: ${await page.textContent("#msg")}`);
    console.log((await page.textContent("#console")).slice(-3000));
    failures++;
    throw e;
  }
  const wall = Date.now() - t0;
  check("CheerpJ loads and JRuby boots", true, `${(T.bootTotal / 1000).toFixed(1)} s in page, ${(wall / 1000).toFixed(1)} s navigation->ready`);
  console.log(`  boot phases (ms): ${JSON.stringify(T)}`);
  console.log(`  downloaded during boot: CheerpJ CDN ${(bytes.cdn[1] / 1e6).toFixed(1)} MB in ${bytes.cdn[0]} requests, ` +
    `local ${(bytes.local[1] / 1e6).toFixed(1)} MB in ${bytes.local[0]} requests`);
  console.log(`  status line: "${await page.textContent("#msg")}"`);

  // Eval 1 through the UI: type into the textarea, press Ctrl+Enter.
  await page.fill("#code", SNIPPET);
  await page.press("#code", "Control+Enter");
  await page.locator(".entry").nth(0).locator(".meta").waitFor({ timeout: EVAL_TIMEOUT });
  const e1 = page.locator(".entry").nth(0);
  const out1 = await e1.locator(".out").textContent();
  const res1 = await e1.locator(".res, .err").textContent();
  const ms1 = await e1.locator(".meta").textContent();
  console.log(`--- eval 1 via textarea + Ctrl+Enter (${ms1}) ---\n${out1}\n${res1}\n---`);
  const L = out1.split("\n");
  check("puts RUBY_DESCRIPTION", /^jruby 9\.4\.15\.0 \(3\.1\.7\)/.test(L[0]), L[0]);
  check("puts [1,2,3].map { |x| x * 2 }.inspect", L[1] === "[2, 4, 6]", L[1]);
  check("class Foo; def hi = \"hi\"; end; puts Foo.new.hi", L[2] === "hi", L[2]);
  check("require 'set'; p Set[1,2]", L[3] === "#<Set: {1, 2}>", L[3]);
  check("eval 1 result value", res1 === "=> #<Set: {1, 2}>", res1);

  // Eval 2 through the UI: Run button. Foo from eval 1 must still exist.
  await page.fill("#code", "puts Foo.new.hi * 2\nx = 21");
  await page.click("#run");
  await page.locator(".entry").nth(1).locator(".meta").waitFor({ timeout: EVAL_TIMEOUT });
  const e2 = page.locator(".entry").nth(1);
  const out2 = await e2.locator(".out").textContent();
  const res2 = await e2.locator(".res, .err").textContent();
  const ms2 = await e2.locator(".meta").textContent();
  console.log(`--- eval 2 via Run button (${ms2}) ---\n${out2}\n${res2}\n---`);
  check("second eval sees class Foo from the first", out2 === "hihi", out2);
  check("second eval result", res2 === "=> 21", res2);

  // More evals through the JS API, same runtime.
  const ev = (code) => Promise.race([page.evaluate((c) => window.jruby.eval(c), code),
    new Promise((_, rej) => setTimeout(() => rej(new Error("eval timeout")), EVAL_TIMEOUT))]);
  const cases = [
    ["locals persist", "x * 2", (r) => r.ok && r.result === "=> 42"],
    ["exceptions are reported", 'raise ArgumentError, "boom"', (r) => !r.ok && r.result.startsWith("ArgumentError: boom")],
    ["runtime survives an exception", '"after: #{Foo.new.hi}"', (r) => r.result === '=> "after: hi"'],
    ["$stderr / warn captured", '$stderr.puts "e1"; warn "w2"; :ok', (r) => r.out === "e1\nw2\n" && r.result === "=> :ok"],
    ["UTF-8 source", 's = "grüezi ✓"; [s.length, s.bytesize, s.encoding]', (r) => r.result === "=> [8, 11, #<Encoding:UTF-8>]"],
    ["require 'json'", "require 'json'; JSON.generate({a: [1, nil]})", (r) => r.result === '=> "{\\"a\\":[1,null]}"'],
    ["Java interop", 'java.lang.System.getProperty("java.version")', (r) => /^=> "(17|11|1\.8)\./.test(r.result)],
    ["Thread", "Thread.new { 6 * 7 }.value", (r) => r.result === "=> 42"],
    ["fib(20)", "def fib(n) = n < 2 ? n : fib(n-1) + fib(n-2)\nfib(20)", (r) => r.result === "=> 6765"],
    ["fib(24) (CPU-bound, interpreter)", "fib(24)", (r) => r.result === "=> 46368"],
    ["300k times loop", "s = 0; 300_000.times { |i| s += i }; s", (r) => r.result === "=> 44999850000"],
    // Java GUI + constants run last: they load AWT/Swing and keep threads alive.
    ["Java constants (char/float/Locale; jars/cheerpj-patch.jar)",
      "[java.lang.Character::MAX_RADIX, java.util.Locale::GERMAN.to_s, java.lang.Float::MAX_VALUE > 1e38]",
      (r) => r.result === '=> [36, "de", true]'],
    ["Swing JFrame + Ruby ActionListener",
      "f = javax.swing.JFrame.new('test'); $n = 0\nb = javax.swing.JButton.new('go'); b.add_action_listener { $n += 1 }\n" +
      "f.content_pane.add(b); f.set_size(200, 100); f.visible = true\n3.times { b.doClick }\nsleep 0.3; f.dispose; $n",
      (r) => r.result === "=> 3"],
    ["Processing sketch (Ruby draw loop)",
      "java_import 'processing.core.PApplet'\nclass TestSketch < PApplet\n  def settings = size(200, 150)\n" +
      "  def draw = ellipse(frameCount % 200, 75, 20, 20)\nend\n$s = TestSketch.new\n" +
      "PApplet.run_sketch(['TestSketch'].to_java(:string), $s)\nsleep 2\nf = $s.frameCount; $s.noLoop; f > 10",
      (r) => r.result === "=> true"],
    ["Glimmer DSL for Swing (jars/glimmer-swing-gems.jar)",
      "require 'glimmer-cheerpj'\ninclude Glimmer\nm = Struct.new(:n).new(0)\n" +
      "observe(m, :n) { |v| @gb.text = \"n=#{v}\" }\n" +
      "f = jframe('glimmer test') { @gb = jbutton('n=0') { on_action_performed { m.n += 1 } } }\nf.show\n" +
      "2.times { @gb.original.doClick }\nsleep 0.3\nf.original.dispose\n@gb.original.text",
      (r) => r.result === '=> "n=2"'],
    ["Ruby IDE app (apps/ide.rb: RSyntaxTextArea + FlatLaf)",
      "load '/app/apps/ide.rb'\n" +   // CheerpJ's /app/ = the web server root, read over HTTP
      "ide = RubyIDE.ide\nide.editor.text = %q(def ide_sq(n) = n * n; puts ide_sq(7); ide_sq(8))\n" +
      "ide.run\nsleep 2\nout = ide.instance_variable_get(:@output).text\nide.frame.dispose\n" +
      "[out.include?(%q(49)), out.include?(%q(=> 64)), ide_sq(3)]",
      (r) => r.result === "=> [true, true, 9]"],
  ];
  for (const [name, code, ok] of cases) {
    const r = await ev(code);
    check(name, !!ok(r), `${r.ms} ms  ${JSON.stringify(r.result.split("\n")[0])}${r.out ? "  out=" + JSON.stringify(r.out) : ""}`);
  }
  let tot = 0;
  for (let i = 0; i < 5; i++) tot += (await ev("1 + 1")).ms;
  console.log(`  trivial eval (1 + 1): avg ${(tot / 5).toFixed(0)} ms over 5`);
  check("no uncaught page errors", pageErrors.length === 0, pageErrors.join(" | "));
  check("runtime only from 127.0.0.1 + cjrtnc.leaningtech.com", bytes.other.length === 0, bytes.other.slice(0, 3).join(" "));
} catch (e) {
  console.log("ERROR " + (e && e.stack || e));
  failures++;
}
console.log(`\n${failures === 0 ? "ALL PASSED" : failures + " FAILURE(S)"}`);
await cleanup(failures === 0 ? 0 : 1);
