> Research notes from building this project (October 2026). They describe experiments whose code is
> not part of this repository; file names below refer to that original working tree.

# Attempt A: JRuby 10.1.2.0 on CheerpJ, library mode

Result: **JRuby 10 does not run on CheerpJ today (blocked).** The same page and REPL code
**works with JRuby 9.4.15.0 on CheerpJ Java 17**, which is the page's default.

## Run it

```sh
cd attempt-a-jruby10-library
python3 serve.py                      # http://127.0.0.1:8091/ (Range-capable; plain `python3 -m http.server` is NOT)
# remote box: ssh -L 8091:127.0.0.1:8091 <host>, then open http://127.0.0.1:8091/
NODE_PATH=$(npm root -g) node test.mjs          # headless test of the working config
NODE_PATH=$(npm root -g) node test.mjs --all    # also probe JRuby 10 on Java 21 and 17 (expected failures)
```
test.mjs starts serve.py on 127.0.0.1:8091 itself if nothing is listening there, and kills it when done.
Query params pick the config: `index.html?jar=jruby-complete-10.1.2.0.jar&java=21` (the dropdown on the page does the same).

Files:
- `index.html` is the REPL (textarea, Run button / Ctrl+Enter, output pane). It also exposes `window.jrubyReady` and `window.rubyEval(src)`.
- `serve.py` is a static server with HTTP Range support (206 + Content-Range), keep-alive and the right MIME types for js/wasm.
- `test.mjs` is the Playwright test. `tools/downgrade_classver.py` is the class-version hack experiment (see below).
- `jars/`: a copy of jruby-complete-10.1.2.0.jar, plus a symlink to ../../jars/jruby-complete-9.4.15.0.jar.

## How the page works

```js
await cheerpjInit({ version: 17, status: "none",
  javaProperties: ["jruby.compile.mode=OFF"],          // interpreter only; JIT needs MutableCallSite (broken, cheerpj-meta #205)
  natives: { Java_jdk_internal_misc_Unsafe_fullFence(){}, Java_jdk_internal_misc_Unsafe_loadFence(){},
             Java_jdk_internal_misc_Unsafe_storeFence(){} } });   // missing JNI natives in CheerpJ 11/17
const lib = await cheerpjRunLibrary("/app/jars/jruby-complete-9.4.15.0.jar");
const container = await new (await lib.org.jruby.embed.ScriptingContainer)();
const out = await new (await lib.java.io.StringWriter)();
await container.setOutput(out);  await container.setError(errWriter);
await container.runScriptlet(PRELUDE);              // defines __cheerpj_repl(src): TOPLEVEL_BINDING.eval + rescue
// each eval:
await container.put("$__repl_src", src);
const result = await container.runScriptlet("__cheerpj_repl($__repl_src)");   // "=> inspect" or "!! Class: msg"
const stdout = await out.toString(); await (await out.getBuffer()).setLength(0);
```
Evaluating in `TOPLEVEL_BINDING` keeps classes **and local variables** between evals. Ruby exceptions come back
as text, not as Java exceptions. Output goes through `StringWriter`, so there is no scraping of `#console`;
`<pre id="console">` only receives the JVM's own System.out/err.

## Measured (headless Chromium, Playwright 1.60, CheerpJ 4.3, cold cache, final run)

JRuby 9.4.15.0 / Java 17:
| phase | ms |
|---|---|
| cheerpjInit | 432 |
| cheerpjRunLibrary | 3880 |
| load classes | 187 |
| new ScriptingContainer + setOutput | 1449 |
| Ruby runtime init (first runScriptlet) | 21738 |
| **cold boot total** | **27685** (an earlier run took 20443) |
| eval#1 (required snippet, via the UI) | 159 |
| eval#2 `x = Foo.new.hi * 2; puts x; x.size` -> `hihi`, `=> 4` | 8 |
| eval#3 `x + "!"` (local persists) -> `=> "hihi!"` | 8 |
| eval#4 `raise ArgumentError, "boom"` -> `!! ArgumentError: boom` | 21 |
| eval#5 `fib(20)` -> `=> 6765` | 1188 |

Traffic: 179 requests (169 with a Range header), about 10.6 MB from the CheerpJ CDN plus jar chunks.
Required output, verbatim:
```
jruby 9.4.15.0 (3.1.7) 2026-06-08 6114208a31 CheerpJ Unknown JVM version on 17.0.19-internal+0-adhoc..jdk17 [cheerpj-linux]
[2, 4, 6]
hi
#<Set: {1, 2}>
```

## What failed for JRuby 10.1.2.0, and why (exact errors)

1. `cheerpjInit({version: 21})` rejects with **`Unsupported Java version: 21`** (CheerpJ 4.3, the latest stable;
   Java 21 exists only in private nightlies).
2. Loading it on Java 17 fails with **`java.lang.UnsupportedClassVersionError: Required Java version 21, but CheerpJ only
   supports up to Java 17 at this time. Unsupported class: org/jruby/embed/ScriptingContainer`**. JRuby 10 has
   6440 classes at major version 65.
3. Hack: I rewrote major 65 -> 61 in every class (`tools/downgrade_classver.py`). On CheerpJ 17 it gets through
   ScriptingContainer creation, then **hangs in Ruby runtime init**. The page's main thread stays pegged
   (Playwright `evaluate` cannot even get a post-mortem) and no exception appears. To find out why, I ran the same jar on a real Temurin
   JDK 17: `ExceptionInInitializerError` in `TraceEventManager.<clinit>`, caused by `NoClassDefFoundError:
   java/lang/MatchException`. JRuby 10 is compiled with Java 21 pattern-matching `switch`
   (15 classes use `java/lang/runtime/SwitchBootstraps`, 5 use `MatchException`) and it uses `Thread.ofVirtual`.
   Getting it onto Java 17 would mean recompiling or back-porting JRuby 10's sources, which is not a quick hack.
   **Blocked until CheerpJ ships Java 21 in a stable release** (roadmap: 6.0).

## Gotchas hit

- A Java exception that reaches JS (a CheerpJ proxy) cannot be passed to `String(e)` ("Cannot convert object to
  primitive value"). Use `await e.toString()`, and check `e instanceof Error` for plain JS errors.
- `pkill -f <pattern>` inside a bash command whose own text contains the pattern kills that shell (exit 144).
- The harmless boot log `JIT failure - please report a bug: ... org/joni/ArrayCompiler.compileNonCECQuantifierNode` still appears.
- Licensing: the CheerpJ Community License requires the CDN-hosted runtime and credits (the page has a footer
  credit). Non-personal or company use needs a commercial license. The runtime is not mirrored locally.
