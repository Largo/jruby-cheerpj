> Research notes from building this project (October 2026). They describe experiments whose code is
> not part of this repository; file names below refer to that original working tree.

# Attempt B: JRuby 9.4.15.0 on CheerpJ 4.3 (stock jruby-complete jar)

Status: **works**. In headless Chromium (Playwright 1.60), the page loads CheerpJ 4.3 from the CDN, boots JRuby
9.4.15.0 (Ruby 3.1.7) on Java 17, 11 or 8, and evaluates Ruby repeatedly in one live runtime. Output is
captured per eval. `test.mjs` passes on all three Java versions.

## Run it

```sh
cd attempt-b-jruby94-main
python3 serve.py 8092                       # Range-capable static server, 127.0.0.1 only
# open http://127.0.0.1:8092/                (REPL; over SSH: ssh -L 8092:127.0.0.1:8092 <box>)
# open http://127.0.0.1:8092/main.html       (one-shot cheerpjRunMain demo; ?code=... runs it)

NODE_PATH=$(npm root -g) node test.mjs                  # REPL test (starts/stops serve.py itself)
WARM=1 MAIN=1 NODE_PATH=$(npm root -g) node test.mjs    # + warm reload + one-shot cheerpjRunMain
JAVA=8 NODE_PATH=$(npm root -g) node test.mjs           # other Java runtimes (8 / 11 / 17)
NODE_PATH=$(npm root -g) node bench.mjs "java=17" "java=17&gems=1"   # boot comparison (server must be running)
```

`jruby-complete.jar` is a symlink to `../jars/jruby-complete-9.4.15.0.jar`. That is the newest 9.4.x on Maven
Central, and its sha1 `7563d453...` matches Maven. CheerpJ maps `/app/jruby-complete.jar` to `<server root>/jruby-complete.jar`.

Page options (query string): `java=17|11|8` (default 17), `gems=1` (load RubyGems at boot), `preload=0`,
`props=a=b,c=d` (replaces the default javaProperties) or `extra=a=b` (adds to them).
JS API: `await jruby.ready` resolves when the runtime is up. `await jruby.eval(code)` returns `{out, result, error, ms}`.

## What makes it work

1. **Interpreter only.** The page sets `jruby.compile.mode=OFF` (CLI: `-X-C`). CheerpJ's `MutableCallSite`
   is broken (cheerpj-meta #205). With the JIT on, the compiled `-e` script dies with
   `IllegalStateException: uninitialized call site`. The page also sets
   `jruby.compile.invokedynamic=false` and `jruby.native.enabled=false`. Neither changes boot time measurably,
   but they keep JRuby away from indy and jnr-ffi. In 9.4, `jruby.native.enabled` has no `-X` form:
   `-Xnative.enabled=false` makes `org.jruby.Main` exit 1 with "invalid extended option". Pass it as a Java
   property instead.
2. **Unsafe fence natives on Java 11 and 17.** The page passes no-op JS natives for
   `Java_jdk_internal_misc_Unsafe_{full,load,store}Fence`. Without them `Ruby.newInstance` throws
   `UnsatisfiedLinkError` on 11 and 17. Java 8 does not need them, but passing them is harmless.
3. **A Range-capable server.** CheerpJ reads the 34 MB jar in about 85 byte-range requests.
   `serve.py` is `http.server` plus `Range` support: 206 with `Content-Range`, suffix ranges, 416, and
   correct MIME types for .js, .wasm and .jar.
4. **Library mode for the REPL.** The page calls `cheerpjRunLibrary(jar)`, then
   `Ruby.newInstance(RubyInstanceConfig)` once. Each input goes through a small Ruby harness (`CheerpREPL.run`):
   - The code arrives base64-encoded, so no quoting or `#{}` problems.
   - It is evaluated in `TOPLEVEL_BINDING`, so locals, classes and requires persist between evals.
   - `$stdout` and `$stderr` are swapped for a StringIO during the eval.
   - The result's `inspect`, or the exception and its backtrace, is stored in globals that JS reads back.

   Java-level System.out and System.err still land in the page's `<pre id="console">`, in the collapsible
   "JVM console" section.
5. **RubyGems off at boot** (`cfg.setDisableGems(true)`, or `--disable-gems` on the CLI). This is the largest
   single speedup: it roughly halves `Ruby.newInstance`, from about 17 s to about 8.5 s. Stdlib requires
   (`set`, `json`, `stringio`) still work. `require 'rubygems'` later loads it on demand (about 9 s, and
   `Gem::VERSION` returns "3.6.3"). `?gems=1` restores the default behaviour.

## Measurements (headless Chromium, cold cache, this box; timings vary ±30% with box load)

The box was shared with other jobs, with load average 5-6 on 8 cores during most runs. The best numbers are from quiet moments.

| configuration | boot (page load to ready) | Ruby.newInstance | eval 1 (required snippet) | eval 2 | trivial eval |
|---|---|---|---|---|---|
| Java 17, gems off (default), quiet box | **13.9 s** | 8.2 s | 213 ms | 40 ms | 5-6 ms |
| Java 17, gems off, loaded box | 15.5-21.9 s | 9.5-12.6 s | 210-310 ms | 17-33 ms | 5 ms |
| Java 17, gems on | 23.1-24.6 s | 17.4-18.9 s | 160-220 ms | 9-14 ms | |
| Java 11, gems off | 15.1-20.3 s | 8.9-11.8 s | 270-470 ms | 15-45 ms | 7 ms |
| Java 8, gems off | 18.8-19.5 s | 11.6-12.2 s | 410-430 ms | 21-36 ms | 12 ms |
| warm reload (same context, HTTP cache), Java 17 | 16.5-17.4 s | 11-12 s | | | |
| one-shot `cheerpjRunMain` `-X-C --disable-gems`, Java 17 | 13.4-19.1 s per run | | | | |
| one-shot `cheerpjRunMain` `-X-C --disable-gems`, Java 8 | 17.2 s per run | | | | |
| one-shot `cheerpjRunMain` `-X-C` (gems on), Java 8 | 26.4 s per run | | | | |

Other measurements from the same run:

- Boot breakdown, Java 17, quiet box: `cheerpjInit` 0.6 s, `cheerpjRunLibrary` 2.8 s, class load 0.9 s,
  config 0.5 s, `Ruby.newInstance` 8.2 s, harness 0.8 s.
- Network on a cold boot: about 84 local requests (83 range) and about 45 CheerpJ CDN requests.
- `fib(20)`: 0.3-1.2 s. `require 'json'` the first time: 0.9-1.5 s.

Findings:
- The boot is CPU-bound (CheerpJ translating thousands of JRuby classes, plus interpreted Ruby kernel code),
  not network-bound. A warm HTTP cache saves nothing measurable.
- `preloadResources` (the list from `cjGetRuntimeResources()`, embedded for Java 17) also made no measurable
  difference on localhost. It is kept because it should help over a real, high-latency network.
- Java 17 is the fastest runtime here, then 11, then 8.

## What failed or did not help

- Default JIT (`cheerpjRunMain` without `-X-C`) fails: exit 1 after about 19.5 s with `IllegalStateException: uninitialized call site` at `RUBY$script at DashE:0` (re-verified here on Java 17 with `--disable-gems`).
- `-Xnative.enabled=false` on the command line gives "invalid extended option" and exit 1. Use the javaProperty instead.
- Java 21 is unsupported on CheerpJ 4.3 (`Unsupported Java version: 21`), so JRuby 10 cannot run.
- A warm HTTP cache and `preloadResources` gave no measurable boot win locally.
- A slim or shrunk jar was not tried. The jar has 13,661 entries; 16 MB of it is `META-INF/jruby.home/lib/ruby`,
  of which BouncyCastle is 10.6 MB. Only touched ranges are fetched, so size matters less than entry count. It
  could shave part of `cheerpjRunLibrary`, about 3 s. ProGuard (`cjGetProguardConfiguration()`) is the next
  step if boot time matters.
- `ScriptingContainer` was not used. `Ruby.newInstance(config)` plus `evalScriptlet` is the lighter equivalent
  and gives one long-lived runtime.

## Gotchas and limitations

- Every boot logs a harmless `JIT failure - please report a bug: ... org/joni/ArrayCompiler...` to the browser console.
- Gems: there is no `gem install` (no network sockets or native code). Only the stdlib and default gems
  bundled in the jar are available.
- There is no stdin. `gets` will not read user input, because the REPL is eval-based rather than IRB.
- Eval is cooperative. A busy loop in Ruby freezes the page, because CheerpJ runs Java on the main JS thread.
  Code with JIT-heavy behaviour stays slow in interpreter mode (`fib(20)` takes about 0.3-1.2 s).
- `browser.close()` can hang after CheerpJ runs, so test.mjs races it against a 5 s timer and then calls `process.exit`.
- Licensing: the CheerpJ Community License covers personal and FOSS use with the CDN-hosted runtime. Company
  use, or self-hosting the runtime, needs a commercial license, so the CDN runtime is not mirrored here.
