> Research notes from building this project (October 2026). They describe experiments whose code is
> not part of this repository; file names below refer to that original working tree.

# Attempt C: JRuby on CheerpJ, slim and fast

The goal was a JRuby REPL in the browser with the smallest download and the fastest boot.

**Result: it works.** JRuby 9.4.15.0 (Ruby 3.1.7) runs on CheerpJ 4.3 with Java 17 in headless Chromium.
`test.mjs` drives the REPL UI, and every assertion passes; see `tools/last-test-output.txt`.

## Run it

```sh
cd attempt-c-slim-fast
./build.sh                     # only if jars/jruby-slim-lazy.jar is missing (downloads jruby-complete, ~5 s)
python3 serve.py               # http://127.0.0.1:8093/  (Range + gzip + ETag; 127.0.0.1 only)
NODE_PATH=$(npm root -g) node test.mjs    # e2e test; starts/stops serve.py itself if 8093 is free
```

## Numbers

All numbers come from headless Chromium (Playwright 1.60) with a cold cache (new browser context), on this shared box (load avg 3-4).

| | naive (stock settings, jruby-complete) | this attempt |
|---|---|---|
| jar file | 34.38 MB, 13 661 entries | **13.86 MB**, 10 948 entries (`jars/jruby-slim-lazy.jar`) |
| jar bytes fetched at boot | 17.57 MB in 111 range requests | **6.10 MB in 7 requests** (5.84 MB in 47 without preload) |
| CheerpJ CDN bytes (Java 17 runtime) | 13.02 MB, 77 requests | 12.48 MB, 41 requests (12.10 MB without preload) |
| **total download** | **30.6 MB** | **18.6 MB** |
| cold boot until the REPL is ready | 22.0 / 27.9 / 26.1 s (bench), 21.9 / 30.0 s (test) | **13.0 / 13.3 / 12.8 s** (bench), 14.0 s (test) |
| warm reload (HTTP cache, 0 bytes) | 25.7 s (one run, busy box) | 13.2 s (boot is CPU-bound) |
| first eval / second eval | 137 ms / 12 ms | 171 ms / 11 ms |
| fib(24), 300k `times`, strings, hash, objs | 1.6 / 2.2 / 0.32 / 0.67 / 1.5 s | 1.45 / 2.1 / 0.31 / 0.59 / 1.4 s |

Where the time goes in the final boot, measured in the page:
- 0.45 s: `cheerpjInit`
- 2.9 s: `cheerpjRunLibrary`. This is CheerpJ's own JVM start. It is the same with a 1.6 KB hello.jar, so the jar size does not affect it.
- 0.8 s: `org.jruby.Ruby` class load
- about 7.9 s: `Ruby.newInstance`
- about 1.9 s: REPL prelude plus warm-up

Measured with the CPU profiler, the boot is about 85% CPU (CheerpJ JIT plus the JRuby init code) and only about 15% network.

## What the build does (`build.sh` → `tools/build-slim.py`)

1. **Drops what cannot work or is not needed** (−2 615 entries, −18.1 MB compressed):
   - `jni/` (jffi natives for 20 platforms) and `com/kenai/jffi`
   - `jnr/x86asm` and `jnr/a64asm`
   - jnr-constants for non-Linux platforms (CheerpJ reports `linux`)
   - Windows launchers
   - BouncyCastle and jopenssl (10.6 MB)
   - RubyGems, Bundler, RDoc, IRB, Reline, jline, FFI/Fiddle, libfixposix and did_you_mean
   - the bundled gems (they are only reachable through RubyGems)

   The removal list keeps `org/jruby/ext/ffi`, `jnr/ffi` and `META-INF/maven`, because the boot touches them.
2. **Strips LocalVariableTable and LineNumberTable** from classes (`tools/classstrip.py`, pure Python, about 14% smaller). Ruby backtraces are unaffected. Java frames lose their line numbers, which the REPL filters out anyway.
3. **Flattens the 11 nested stdlib extension jars** into the main jar: stringio, json/ext, psych and snakeyaml, strscan, digest, nkf, racc, cgi/escape and io/wait. It removes their `require 'x.jar'` lines and writes `json/ext/parser.rb`-style `load_ext` stubs. Loading a nested jar makes `JRubyClassLoader` copy it to a temp dir and ask `ManagementFactory` for the pid, which took 0.75 s the first time on CheerpJ. The prelude's `require 'stringio'` dropped from about 0.8 s to about 0.1 s.
4. **Lazy Java integration.** This is a 2-class bytecode patch (`tools/patch/`). `Ruby.initJavaSupport` calls `LazyJava.doesReflectionWork(Ruby)`. With `-Djruby.cheerpj.lazy_java=true`, boot skips `Java.load` and `jruby/java.rb`, which together are about 25% of JRuby's boot (the `jruby/java.rb` part alone was 1.8 s on CheerpJ). Java integration then loads on the first `require 'java'` (stdlib `java.rb`) or on the first Java proxy, through a hook in `Java.getProxyClass`. That includes Java exceptions that reach Ruby. The REPL also auto-requires it when the input mentions `java`, `javax` or `Java::`. Without the property, JRuby behaves as stock.
5. **Boot-orders the jar.** `tools/cjtrace.mjs` runs `TraceLoader` inside CheerpJ, which loads JRuby through a logging `URLClassLoader` and records the order in which jar entries are first touched. The jar is written in that order. CheerpJ reads jars in 128 KB blocks, so boot now reads one contiguous 4.9 MB region plus the 1 MB central directory, where before it read 92 scattered requests.
6. **Preload list.** `tools/make-preload.mjs` records `cjGetRuntimeResources()` and the jar ranges into `preload-jruby-slim-lazy-17.json`. The page passes that file as `cheerpjInit({preloadResources})`, so the JDK `lib/modules` blocks and our jar region download in parallel at init. That cut 77+47 requests to 41+7 and saved about 2-4 s (median 13.0 s vs 16.9 s over 3 cold runs).

The page also runs JRuby with these settings:
- `jruby.compile.mode=OFF`: required, because of CheerpJ's broken `MutableCallSite` (cheerpj-meta #205)
- `jruby.native.enabled=false`
- `jruby.cli.rubygems.enable=false` and `jruby.cli.did_you_mean.enable=false`: together these roughly halve `Ruby.newInstance`
- no-op JS natives for `Unsafe.fullFence/loadFence/storeFence`, which the Java 11/17 runtimes lack

The REPL runs in library mode (`cheerpjRunLibrary`), with one `evalScriptlet` per input. Each input runs through a Ruby helper, `__cj_eval`. The helper evaluates it in a persistent `TOPLEVEL_BINDING`, so locals, methods and classes survive between runs. It captures `$stdout`/`$stderr` into a StringIO, and it turns exceptions into `Class: message` plus the `(irb)` backtrace lines. `#console` (CheerpJ's System.out) is kept in a collapsed "JVM console" panel.

## The surprise: what runs first decides eval speed (warm-up)

CheerpJ's JIT seems to specialise a method on the types it saw before it compiled the method, and not to re-specialise it later. In the CPU profile of the slow case, most time sits in a cj3.js function that handles "CheerpJStub/Restart/Cast", which means the code keeps falling back to the slow path. As a result, whatever Ruby code runs first after boot fixes the speed of all later code:

- With RubyGems loaded at boot (stock), evals have medium speed. With RubyGems off, fib(24) took 4-6 s instead of 1.3 s, and a 300k `times` loop took 11-14 s instead of 2.2 s.
- A late `require 'rubygems'` does not fix it. Loading it *before* the first wrapped eval does.
- `require 'optparse'` alone made fib, loop and strings fast but made object allocation slow (6.5 s).
- `require 'optparse'` plus 300 `attr_reader`/`new` calls fixed everything for about 1.5 s. That is the warm-up at the top of the prelude in `index.html` and `tools/trace/snippets.rb`. It was replicated twice, and the final numbers (table above) match or beat stock JRuby.

This is empirical. Other workloads can still hit a slow path. `tools/cjperf.mjs` is the harness for trying other warm-ups.

## Tried and rejected

- **Java 21 / JRuby 10**: CheerpJ 4.3 has no Java 21 (`Unsupported Java version: 21`), so I used 9.4.15.0.
- **Java 8 / 11**: Java 8 boots slower (16.4-17.0 s) and downloads more (16.8 MB rt.jar on the CDN). Java 11 is about the same as 17, maybe 1 s slower, and 0.4 MB smaller. Java 17 is the default; use `?java=11` to switch.
- **No generated populators/invokers, binding core methods via MethodHandles instead** (`--no-populators` + `jruby.invokedynamic.handles=true`):
  - Good: a much smaller jar (11.4 MB, 4.2 MB fetched, 7 600 entries), and boot about 0.5 s faster.
  - Bad: on CheerpJ, MethodHandle-bound core methods made evals 2-5x slower whatever the warm-up (fib(24) 5.2 s, objects 8 s).
  - It is still available in `build-slim.py --no-populators`, and the page adds the property for any `*-mh*` jar.
- **Removing debug info only** (−7% LVT, −14% with LNT): kept, but it is a small win. The class bytes are not what the boot is waiting on.
- **A Java sampling profiler inside CheerpJ**: got 0 samples. CheerpJ threads are cooperative, and a sampler thread never runs while the main thread computes.
- **`jruby.jit.background=false`**: no effect on the eval-speed problem.
- **gzip for the jar**: pointless. CheerpJ fetches jars with Range requests, and jar entries are already deflated. `serve.py` gzips only full responses of html/js/json/rb/txt. index.html is 4.3 KB gzipped.

## Limitations

- **Boot is still about 13 s, and it is CPU-bound.** About 3.3 s of that is CheerpJ's own JVM start, which no jar change can affect. Warm reloads are not faster, because CheerpJ re-JITs every page load. The remaining JRuby init costs are:
  - core class setup via about 2 000 generated invoker classes
  - `RubyParser` static tables (`YyTables`, 190 KB)
  - the `jruby/kernel/*.rb` boot files, about 1.6 s
- **No RubyGems.** `require 'some_gem'` and bundled gems such as matrix, prime and rake are not available. `jars/jruby-complete.jar` with `?jar=jars/jruby-complete.jar&gems=1` has them, at the cost of +9 s or more of boot.
- **No OpenSSL**, so no `require 'openssl'`. There are no sockets, subprocesses, FFI or native extensions, and `$stdin` and IRB do not work.
- **Java interop works, but loads lazily.** The first use costs about 0.8 s. Code that reaches a Java proxy without going through `getProxyClass` might, in theory, hit an NPE.
- **Timings are noisy.** Other agents run headless Chrome on the same box, and runs vary ±2 s.
- **Licence.** The CheerpJ runtime must come from cjrtnc.leaningtech.com. The page does not mirror it. The Community License covers personal and evaluation use. Commercial use needs a CheerpJ licence, and the page footer carries the required credit.

## Files

- `index.html`: the REPL page. Query params for benchmarking: `jar=`, `java=8|11|17`, `preload=0`, `gems=1`, `naive=1`, `props=k=v,...`.
- `serve.py`: static server with Range (206), gzip, ETag/304 and MIME types for .js/.wasm/.jar. Binds 127.0.0.1:8093.
- `test.mjs`: Playwright end-to-end test of the UI with assertions and timings.
- `build.sh`: builds the jar. `--retrace` re-records the boot order and preload list.
- `jars/jruby-slim-lazy.jar` and `preload-jruby-slim-lazy-17.json`: build outputs. `jars/jruby-complete.jar` is a symlink kept for comparisons.
- `tools/`:
  - `build-slim.py` and `classstrip.py`: the jar builder
  - `patch/`: the LazyJava source and the ASM patcher; `build-overlay.sh` builds the overlay
  - `trace/`: `TraceLoader` and the boot order
  - `bench.mjs`: boot benchmarks with renderer main-thread CPU, `--net LAT,MBPS` throttling and `--perf`
  - `cjperf.mjs`: eval-speed experiments
  - `cjtrace.mjs`, `make-preload.mjs`, `cjprobe.mjs`, `cjbase.mjs`, `cdnlist.mjs`, `profile.mjs` and `console.mjs`: diagnostics
