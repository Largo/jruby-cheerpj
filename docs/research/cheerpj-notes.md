> Research notes from building this project (October 2026). They describe experiments whose code is
> not part of this repository; file names below refer to that original working tree.

# CheerpJ notes for JRuby-in-the-browser (researched 2026-10-16)

Sources: docs source repo `github.com/leaningtech/labs` (sites/cheerpj/src/content/docs,
cloned 2026-10-16, HEAD 2026-10-14). cheerpj.com/docs itself returns 403 to curl/WebFetch
(Cloudflare), so the docs repo is the way to read it. GitHub issues: leaningtech/cheerpj-meta.

## Version / loader

- Latest stable: **CheerpJ 4.3**, released 2026-04-21.
  `<script src="https://cjrtnc.leaningtech.com/4.3/loader.js"></script>`
- Checked with curl on 2026-10-16: `4.0` `4.1` `4.2` `4.3` -> 200 (loader.js 7521 B, 4.3 last-modified
  2026-04-20; `4.3/cj3.js` is 666 KB, `cj3.wasm` is also there). `4.4`, `5.0`, `5.1` and `nightly` -> 204 (do not exist).
  `/latest/loader.js` is the **old CheerpJ 2** runtime, so do not use it.
- 3.x used `cj3loader.js`. 4.x uses `loader.js`.
- Nightly builds exist, but the URL scheme is not public. In issue #205 a dev gave
  `https://cjrtnc.leaningtech.com/3_20241216_574/cj3loader.js`. A 4.x nightly would presumably look like
  `4_YYYYMMDD_NNN/loader.js`, which I could not enumerate. Ask on the CheerpJ Discord.

## Java versions

- `cheerpjInit({version: 8 | 11 | 17})`. The default is 8. Applets work on 8 only.
- **Java 21 is NOT supported in 4.3**. I verified this: `cheerpjInit({version:21})` rejects with
  `Unsupported Java version: 21`. The Leaning blog (2026-10-08 internship post) says Java 21 is "released in the
  nightly build" and that work on Java 25 has started. Roadmap: 5.0 = Java 17 (now in 4.x), 6.0 = 21, 7.0 = 26.
- Consequence: **JRuby 10.x (needs Java 21) cannot run on stable CheerpJ**. Use **JRuby 9.4.x**
  (built for Java 8. Latest is 9.4.15.0, 2026-06-08, Ruby 3.1.7 compat).
- Runtime-reported versions: 1.8.0_492-internal, 11.0.31-internal, 17.0.19-internal (vm name "CheerpJ").

## APIs (all globals after loader.js. Everything is async)

- `await cheerpjInit(opts)` once per page. Useful options: `version`, `status:"none"|"splash"|"default"`,
  `javaProperties:["k=v"]` (= -D flags), `natives:{Java_pkg_Cls_method(lib, ...){}}` (implement JNI natives in JS),
  `preloadResources` + `preloadProgress` (startup optimisation, list from `cjGetRuntimeResources()`),
  `licenseKey`, `execCallback(cmd,args)` (intercepts Runtime.exec/ProcessBuilder), `enableDebug`, `hostName`.
- `await cheerpjRunMain(className, classPath /* ':'-separated /app/... */, ...args)` -> exit code.
- `await cheerpjRunJar("/app/x.jar", ...args)` -> exit code (uses the Main-Class from the manifest).
- `const lib = await cheerpjRunLibrary("/app/a.jar:/app/b.jar")` -> CJ3Library (library mode, Java from JS):
  `const C = await lib.org.jruby.Ruby; const o = await C.newInstance(); await o.evalScriptlet("1+1")`.
  Classes, static calls, `await new C()`, instance calls and fields all work. Every call returns a Promise.
  Conversions follow LiveConnect. JS strings map to java.lang.String. TypedArrays map to primitive arrays by reference.
  A Java exception becomes a JS rejection, and you can `await e.printStackTrace()` on the caught object.
  Prior art (Groovy, Scala) uses this mode for REPLs.
- `cheerpjCreateDisplay(w, h, parent)` is only needed for AWT/Swing. A headless REPL does not need it.
- `cheerpOSAddStringFile("/str/x.rb", stringOrUint8Array)` pushes data JS->Java (Java sees it read-only).
- `await cjFileBlob("/files/x" | "/app/x" | "/str/x")` reads a file Java wrote (JS side).

### stdout / stderr / stdin

- **Verified:** System.out and System.err both go into `<pre id="console">` if the page has such an
  element (they are interleaved and not distinguished). The JS console does not get them in that case.
  Capture output by snapshotting `#console.textContent` before and after each eval (that works, see below), or by
  watching it with a MutationObserver. A cleaner option for the REPL is to redirect the Ruby runtime's output from inside Java
  (`RubyInstanceConfig#setOutput(PrintStream)` with a ByteArrayOutputStream, or `$stdout = StringIO.new`
  inside the Ruby wrapper). That is what xuwei-k/cheerpj-scala does for scalac.
- stdin: there is no documented JS API to feed System.in. For a REPL, use library mode (one eval call per
  input line) and do not depend on stdin. (A `$stdin`-reading IRB would need a custom InputStream backed by a JS native.)

## Virtual filesystem

| mount | what | write |
|---|---|---|
| `/app/` | HTTP-backed, rooted at the **web-server root** (not the page dir). Read-only. 404 = ENOENT (404s in devtools are normal) | no |
| `/files/` | IndexedDB, persistent. `/files/uploads/` + `/files/downloads/` (4.3+) | Java only |
| `/str/` | in-memory, filled from JS via cheerpOSAddStringFile | JS only |

Jar paths must start with `/app/` (the most common mistake). You cannot use `file://` pages. The page must come over http(s).

## Server requirements

- **HTTP Range requests are mandatory** (jars are fetched in chunks, about 100 range requests to boot JRuby).
  The docs say `python3 -m http.server` does NOT work. `npx serve` and `npx http-server` work, and so does nginx.
- Correct MIME for `.js` (text/javascript) and `.wasm`. Do not gzip range responses for .js (Firefox
  "compressed partial data" error, `npx serve -u`).
- No COOP/COEP needed. The runtime loads from cjrtnc.leaningtech.com (CORS `*`).
- Testing trick used here: a Playwright `page.route('http://localhost:9/**')` handler that serves files
  and answers `Range: bytes=a-b` with 206 + Content-Range. No HTTP server and no port needed.
  See `research/probe/jprobe.js`.

## Licensing

- CheerpJ Community License: free for individuals and one-person companies (even with revenue), FOSS projects
  and technical evaluations. It requires "appropriate credits" and the CDN-hosted runtime (cjrtnc.leaningtech.com).
  A non-commercial message is shown unless you pass `licenseKey`.
- Commercial license (contact sales): any business use by companies with more than one person (internal apps
  included), self-hosting the runtime, redistribution and OEM. **Self-hosting the runtime needs a commercial
  license.** The runtime files must not be mirrored into the repo or onto the box.
- JRuby itself is EPL-2.0/GPL-2/LGPL-2.1, which is fine.

## Prior art

- No public JRuby-on-CheerpJ project found (GitHub, web search).
- Scala compiler: xuwei-k/cheerpj-scala (https://xuwei-k.github.io/cheerpj-scala/, CheerpJ 4.3, library
  mode). It is pinned to Scala 2.13.18 because "latest scala version does not work with CheerpJ"
  (MethodHandle/CallSite issues, cheerpj-meta #205).
- Groovy: jollytoad/groovy-in-browser (library mode, `new GroovyShell().parse(code).run()`).
- Kotlin compiler: F43nd1r/kotlin-compiler-cheerpj (2024, no README).
- JavaFiddle (leaningtech/javafiddle) runs javac in the browser on CheerpJ.
- Large apps: Minecraft (browsercraft.cheerpj.com). A Fabric loader hang is in #231 (ASM-heavy boot).
- I found no Jython, Rhino or Clojure demos.

## Known issues relevant to JRuby

- **`MutableCallSite` is broken** (cheerpj-meta #205, still open, reproduced on 4.3 for 8/11/17):
  `new MutableCallSite(type)` + `setTarget()` + `dynamicInvoker().invokeExact()` throws
  `IllegalStateException: uninitialized call site`. On native JDK 21 the same code prints `mcs-ok`.
  Lambdas (`LambdaMetafactory` indy) work. `SwitchPoint` was fixed in a nightly (2024-12).
  **JRuby impact:** with default settings JRuby compiles the `-e`/top-level script to JVM bytecode with indy
  call sites, and that fails with exactly this error (`RUBY$script at DashE ... linkToCallSite`).
  **Fix: run JRuby interpreter-only**: `-X-C` on the command line, or `javaProperties:["jruby.compile.mode=OFF"]`
  in library mode. With that, everything below works.
- Java 11/17 runtimes are missing the native `Java_jdk_internal_misc_Unsafe_fullFence` (JRuby
  AtomicVariableTable calls `sun.misc.Unsafe.fullFence`). You get `UnsatisfiedLinkError` during `Ruby.newInstance`.
  **Fix: provide no-op JS natives**:
  `natives:{Java_jdk_internal_misc_Unsafe_fullFence(){}, Java_jdk_internal_misc_Unsafe_loadFence(){}, Java_jdk_internal_misc_Unsafe_storeFence(){}}`.
  (A no-op is fine because the JS/wasm Java threads are green threads on one JS thread.) Java 8 does not need it.
- Harmless console log on every boot: `JIT failure - please report a bug: ... org/joni/ArrayCompiler.compileNonCECQuantifierNode`.
  CheerpJ's own JIT gives up on that method and it stays interpreted.
- Startup: the 34 MB jruby-complete jar is range-fetched lazily (about 17 MB transferred over about 100 requests).
  Boot is dominated by `Ruby.newInstance` (17-23 s headless). Use `preloadResources` and a ProGuard-shrunk jar
  (`cjGetProguardConfiguration()`) to cut this.
- In headless Playwright, `browser.close()` sometimes hung after CheerpJ runs. Wrap the run in `timeout` / `process.exit`.

## Measured results (headless Chromium via Playwright 1.60, CheerpJ 4.3, JRuby 9.4.15.0, cold cache, this box)

Ruby snippet: `puts RUBY_DESCRIPTION; puts [1,2,3].map { |x| x * 2 }.inspect; class Foo; def hi = "hi"; end; puts Foo.new.hi; require "set"; p Set[1,2]`

| mode | Java | result | timings |
|---|---|---|---|
| cheerpjRunMain org.jruby.Main -e (default JIT) | 8 | FAIL `IllegalStateException: uninitialized call site` | 23 s |
| cheerpjRunMain org.jruby.Main -X-C -e | 8 | OK, exit 0 | init 0.6 s, main 22.8 s |
| library: Ruby.newInstance + evalScriptlet x3, compile.mode=OFF | 8 | OK | init 0.6, runLibrary 2.2, class 2.7, newInstance 23.1 s, eval#1 203 ms, eval#2 10 ms, fib(20) 1.2 s |
| same | 11 (no natives) | FAIL UnsatisfiedLinkError Unsafe_fullFence | |
| same + fence natives | 11 | OK | newInstance 17.7 s, eval#1 128 ms, eval#2 7 ms (about 23 s total) |
| same + fence natives | 17 | OK | newInstance 17.4 s, eval#1 133 ms, eval#2 6 ms (about 23 s total) |
| version 21 | 21 | FAIL `Unsupported Java version: 21` | |

Captured output (Java 17): `jruby 9.4.15.0 (3.1.7) 2026-06-08 6114208a31 CheerpJ Unknown JVM version on 17.0.19-internal+0-adhoc..jdk17 [cheerpj-linux]`,
`[2, 4, 6]`, `hi`, `#<Set: {1, 2}>`. The second eval `puts Foo.new.hi * 2` printed `hihi`, so classes persist across evals and a REPL works.

## Recipe

```html
<script src="https://cjrtnc.leaningtech.com/4.3/loader.js"></script>
<pre id="console"></pre>
<script type="module">
await cheerpjInit({ version: 17, status: "none",
  javaProperties: ["jruby.compile.mode=OFF"],
  natives: { Java_jdk_internal_misc_Unsafe_fullFence(){}, Java_jdk_internal_misc_Unsafe_loadFence(){}, Java_jdk_internal_misc_Unsafe_storeFence(){} } });
const lib = await cheerpjRunLibrary("/app/jruby.jar");          // jruby-complete-9.4.15.0.jar at web root
const rt = await (await lib.org.jruby.Ruby).newInstance();
const v = await rt.evalScriptlet('puts RUBY_DESCRIPTION; 1+1'); // stdout lands in #console
console.log(await (await v.inspect()).toString());               // "2"
</script>
```
Serve with any Range-capable static server bound to 127.0.0.1 (`npx http-server -a 127.0.0.1 -p PORT`).

Probe files: `research/probe/` (Hello.java, www/index.html, www/jruby.html,
probe.js, jprobe.js). Jar: `jars/jruby-complete-9.4.15.0.jar` (sha1 matches Maven Central).
