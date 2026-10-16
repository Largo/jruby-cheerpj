// jruby.js: boot JRuby 9.4 inside CheerpJ and evaluate Ruby from JavaScript.
//
//   <script src="https://cjrtnc.leaningtech.com/4.3/loader.js"></script>
//   <script type="module">
//     import { bootJRuby } from "./jruby.js";
//     const ruby = await bootJRuby({ jar: "jars/jruby-complete-9.4.15.0.jar" });
//     const r = await ruby.eval('puts "hi"; 1 + 1');   // { ok, out: "hi\n", result: "=> 2", ms }
//   </script>
//
// The page must be served by a server that answers HTTP Range requests (run.sh does).
// One JVM and one Ruby runtime stay alive. Every eval runs in TOPLEVEL_BINDING, so locals,
// methods, classes and requires persist; $stdout/$stderr are captured per eval.

export const JRUBY_VERSION = "9.4.15.0";
export const DEFAULT_JAR = `jars/jruby-complete-${JRUBY_VERSION}.jar`;
// Overlay classes that go before the JRuby jar on the classpath (built by patch/build.sh).
// It patches JRuby's ConstantField so classes with static final char/short/float constants
// (Character, Locale, every Swing/AWT component) can be used. Missing jar = skipped.
export const DEFAULT_PATCH_JAR = "jars/cheerpj-patch.jar";

// CheerpJ runtime chunks a Java 17 boot of JRuby touches (from cjGetRuntimeResources()).
// Passed as preloadResources so CheerpJ fetches them in parallel at init instead of on demand.
const CDN_PRELOAD_17 = {"/lt/17/lib/modules":[0,131072,1179648,5898240,6029312,6291456,6422528,7208960,7602176,7733248,7864320,8388608,9437184,9699328,9830400,10092544,19005440,19136512,19791872,19922944,28049408,28311552,28442624,28573696,37617664,38273024],"/lt/etc/users":[0,131072],"/lt/etc/localtime":[],"/lt/17/jre/lib/cheerpj-handlers.jar":[0,131072],"/lt/17/jre/lib/cheerpj-awt.jar":[0,131072],"/lt/17/jre/lib/cheerpj-jsobject.jar":[0,131072],"/lt/17/conf/security/java.security":[0,131072],"/lt/17/conf/logging.properties":[0,131072],"/lt/17/lib/tzdb.dat":[0,131072],"/lt/17/bin/java":[],"/lt/17/jre/bin/java":[]};

// Ruby side of the REPL. Input arrives base64-encoded (no quoting or #{} issues); the reply
// is one string "ok \0 captured-output \0 result-or-error" so each eval is one JS->Java call.
const HARNESS = String.raw`
require 'stringio'
# Ruby files at the root of any classpath jar become requirable (e.g. require 'glimmer-cheerpj').
$LOAD_PATH.push('uri:classloader:/') unless $LOAD_PATH.include?('uri:classloader:/')
module CheerpREPL
  B = TOPLEVEL_BINDING
  def self.run(b64)
    src = b64.unpack1('m').force_encoding('UTF-8')
    buf = StringIO.new
    so, se = $stdout, $stderr
    $stdout = $stderr = buf
    begin
      res = "=> " + B.eval(src, '(irb)', 1).inspect
      ok = "1"
    rescue Exception => e
      bt = (e.backtrace || []).reject { |l| l =~ /<script>|\.java:|\Aorg\/jruby\// }.first(6)
      res = "#{e.class}: #{e.message}" + bt.map { |l| "\n  from #{l}" }.join
      ok = "0"
    ensure
      $stdout, $stderr = so, se
    end
    ok + "\0" + buf.string + "\0" + res
  end
end
nil`;

// Warm-up (found in the slim-jar experiment, docs/research/attempt-c-slim-jar.md): CheerpJ's JIT appears to specialise JRuby's interpreter methods on
// the first types it sees and not to re-specialise, so with RubyGems off the FIRST evalScriptlet
// after Ruby.newInstance decides the speed of every later eval. It must run before the harness.
// Measured with this stock jar, Java 17: fib(24) 1.3-1.7 s with it vs 4-6 s without; 300k
// `times` 2.0-2.4 s vs 10-13 s. Costs about 1.3 s of boot.
const WARMUP = String.raw`
require 'optparse'
class CheerpjWarmup; attr_reader :x; def initialize(x) = @x = x; end
Array.new(300) { |i| CheerpjWarmup.new(i) }.sum(&:x)
Object.send(:remove_const, :CheerpjWarmup)
nil`;

function b64utf8(s) {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

async function javaErrorText(e) {
  try { if (e && typeof e.toString === "function") return String(await e.toString()); } catch (_) {}
  try { return String(e); } catch (_) { return "unknown error"; }
}

/**
 * Boot CheerpJ + JRuby. Options (all optional):
 *   jar      URL of jruby-complete jar, relative to the page (same origin). Default DEFAULT_JAR.
 *   java     CheerpJ Java runtime: 17 (default, fastest), 11 or 8.
 *   gems     true loads RubyGems at boot (+8-10 s). Default false; `require 'rubygems'` works later.
 *   warmup   run the interpreter warm-up at boot (default: true unless gems, which warms up
 *            the same way). A string is used as custom warm-up Ruby code.
 *   preload  pass the CDN preload list to cheerpjInit (default true; Java 17 only). An object
 *            is merged in as extra preloadResources entries.
 *   props    extra Java system properties, e.g. ["jruby.debug.fullTrace=true"].
 *   display  element (or CSS selector) where CheerpJ draws AWT/Swing windows (JFrame etc.).
 *            Without it, Java GUI code only works offscreen (BufferedImage).
 *   classpath extra jar URLs (same origin), appended to the JRuby jar on the classpath,
 *            e.g. ["jars/processing-core.jar"]. Classes are then reachable as Java::...
 *   patchJar overlay jar placed first on the classpath (default DEFAULT_PATCH_JAR; false = none).
 *   onStatus (text, percent) progress callback.
 *   skipInit true if the page already called cheerpjInit itself.
 * Resolves to { eval(code) -> Promise<{ok, out, result, ms}>, timings, runtime }.
 */
export async function bootJRuby(opts = {}) {
  const java = +(opts.java || 17);
  const jarUrl = new URL(opts.jar || DEFAULT_JAR, location.href);
  const status = opts.onStatus || (() => {});
  const T = {};
  const t0 = performance.now();
  let t = t0;
  const lap = (k) => { const n = performance.now(); T[k] = Math.round(n - t); t = n; };

  if (!opts.skipInit) {
    status(`Starting CheerpJ (Java ${java})...`, 5);
    const init = {
      version: java,
      status: "none",
      javaProperties: [
        "jruby.compile.mode=OFF",              // required: CheerpJ's MutableCallSite is broken (cheerpj-meta #205)
        "jruby.compile.invokedynamic=false",
        "jruby.native.enabled=false",          // no JNI/FFI in the browser; must be a property, not -X
        "jruby.cli.did_you_mean.enable=false",
        ...(opts.props || []),
      ],
      // Java 11/17 runtimes lack these JNI natives, which JRuby reaches via Unsafe on boot.
      // No-ops are safe: CheerpJ runs all Java threads on the one JS thread.
      natives: {
        Java_jdk_internal_misc_Unsafe_fullFence() {},
        Java_jdk_internal_misc_Unsafe_loadFence() {},
        Java_jdk_internal_misc_Unsafe_storeFence() {},
      },
    };
    if (opts.preload !== false && java === 17) {
      init.preloadResources = { ...CDN_PRELOAD_17, ...(typeof opts.preload === "object" ? opts.preload : {}) };
      init.preloadProgress = (done, total) => status(`Downloading the Java runtime... ${done}/${total}`, 5 + Math.round(30 * done / total));
    }
    await cheerpjInit(init);
    lap("cheerpjInit");
  }

  if (opts.display) {
    // CheerpJ renders every AWT/Swing top-level window into this element.
    const el = typeof opts.display === "string" ? document.querySelector(opts.display) : opts.display;
    cheerpjCreateDisplay(-1, -1, el);   // -1, -1: size it to the element
  }

  status("Loading the JRuby jar...", 40);
  const patch = opts.patchJar === false ? [] : [new URL(opts.patchJar || DEFAULT_PATCH_JAR, location.href)];
  const cp = [...patch, jarUrl, ...(opts.classpath || []).map((j) => new URL(j, location.href))];
  const lib = await cheerpjRunLibrary(cp.map((u) => "/app" + u.pathname).join(":"));
  lap("cheerpjRunLibrary");
  const Ruby = await lib.org.jruby.Ruby;
  const Config = await lib.org.jruby.RubyInstanceConfig;
  const cfg = await new Config();
  if (!opts.gems) await cfg.setDisableGems(true);   // halves Ruby.newInstance
  lap("loadClasses");

  status("Booting the Ruby runtime (the slow part)...", 50);
  const runtime = await Ruby.newInstance(cfg);
  lap("rubyNewInstance");

  status("Warming up the interpreter...", 90);
  const warmup = opts.warmup ?? !opts.gems;
  if (warmup) await runtime.evalScriptlet(typeof warmup === "string" ? warmup : WARMUP);
  await runtime.evalScriptlet(HARNESS);
  lap("harnessAndWarmup");
  T.bootTotal = Math.round(performance.now() - t0);
  status(`Ready in ${(T.bootTotal / 1000).toFixed(1)} s`, 100);

  let queue = Promise.resolve();
  async function evalOnce(code) {
    const ts = performance.now();
    let ok = false, out = "", result = "";
    try {
      const v = await runtime.evalScriptlet(`CheerpREPL.run('${b64utf8(code)}')`);
      const s = String(await v.toString());
      const i = s.indexOf("\0"), j = s.indexOf("\0", i + 1);
      ok = s.slice(0, i) === "1"; out = s.slice(i + 1, j); result = s.slice(j + 1);
    } catch (e) {
      result = "Java exception: " + await javaErrorText(e);
    }
    return { ok, out, result, ms: Math.round(performance.now() - ts) };
  }
  // Calls are serialised: the Ruby runtime is single-threaded from JS's point of view.
  function evalRuby(code) {
    const p = queue.then(() => evalOnce(String(code)));
    queue = p.catch(() => {});
    return p;
  }
  return { eval: evalRuby, timings: T, runtime, java, jar: jarUrl.pathname };
}

export { javaErrorText };
