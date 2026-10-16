#!/bin/sh
# JRuby in the browser via CheerpJ: one command.
#
#   ./run.sh            fetch the JRuby jar if missing, then serve on http://127.0.0.1:${PORT:-8017}/
#   ./run.sh test       fetch if missing, then run the headless Playwright test
#                       (test.mjs starts and stops its own server on a free 127.0.0.1 port)
#   ./run.sh test-demos [app]  real mouse/keyboard checks of the demo apps (apps/*.rb)
#   ./run.sh prepare    only fetch + verify the jars and build the overlays
#
# Remote box? Tunnel it: ssh -L 8017:127.0.0.1:8017 <host>, then open http://localhost:8017/
set -eu
cd "$(dirname "$0")"

V=9.4.15.0
JAR="jars/jruby-complete-$V.jar"
URL="https://repo1.maven.org/maven2/org/jruby/jruby-complete/$V/jruby-complete-$V.jar"

prepare() {
  fetch_jar
  # overlay that fixes Java constants under CheerpJ (needs a JDK; see patch/)
  [ -f jars/cheerpj-patch.jar ] && [ jars/cheerpj-patch.jar -nt patch/src/org/jruby/javasupport/binding/ConstantField.java ] || patch/build.sh "$JAR"
  # Processing core + its CheerpJ render fix (for sketches in the page)
  [ -f jars/processing-cheerpj-patch.jar ] && [ jars/processing-cheerpj-patch.jar -nt patch/processing/build.sh ] || patch/processing/build.sh
  # Glimmer DSL for Swing + its pure-Ruby gems, packed as a jar (require 'glimmer-cheerpj')
  [ -f jars/glimmer-swing-gems.jar ] && [ jars/glimmer-swing-gems.jar -nt patch/gems/build.sh ] || patch/glimmer/build.sh
  # Sequel (pure Ruby; bigdecimal is built into JRuby) for the SQL demo (require 'sequel-cheerpj')
  [ -f jars/sequel-gems.jar ] && [ jars/sequel-gems.jar -nt patch/gems/build.sh ] || patch/gems/build.sh sequel-gems sequel-cheerpj sequel 5.109.0 bigdecimal
  # Code editor + look-and-feel for the in-page Ruby IDE (?app=ide)
  fetch_maven com/fifesoft/rsyntaxtextarea/3.6.3/rsyntaxtextarea-3.6.3.jar
  fetch_maven com/formdev/flatlaf/3.7.2/flatlaf-3.7.2.jar
  # Java libraries used by the demos (apps/*.rb)
  fetch_maven com/google/zxing/core/3.5.4/core-3.5.4.jar
  fetch_maven com/google/zxing/javase/3.5.4/javase-3.5.4.jar
  fetch_maven org/jfree/jfreechart/1.5.6/jfreechart-1.5.6.jar
  fetch_maven com/h2database/h2/2.5.252/h2-2.5.252.jar
  fetch_maven org/dyn4j/dyn4j/6.0.0/dyn4j-6.0.0.jar
  fetch_maven org/mozilla/rhino/1.9.1/rhino-1.9.1.jar
  fetch_maven org/scilab/forge/jlatexmath/1.0.7/jlatexmath-1.0.7.jar
}

fetch_maven() {  # fetch_maven <path under maven2/> -> jars/<basename>, verified against Maven's .sha1
  f="jars/$(basename "$1")"
  [ -f "$f" ] && return 0
  u="https://repo1.maven.org/maven2/$1"
  sha1=$(curl -fsSL "$u.sha1" | cut -c1-40)
  curl -fsSL -o "$f.part" "$u"
  echo "$sha1  $f.part" | sha1sum -c --quiet - || { echo "SHA1 mismatch for $u" >&2; rm -f "$f.part"; exit 1; }
  mv "$f.part" "$f"
  echo "verified $f"
}

fetch_jar() {
  [ -f "$JAR" ] && return 0
  mkdir -p jars
  echo "downloading $URL"
  # checksums come from Maven Central itself, next to the artifact
  sha1=$(curl -fsSL "$URL.sha1" | cut -c1-40)
  sha256=$(curl -fsSL "$URL.sha256" | cut -c1-64)
  curl -fL --progress-bar -o "$JAR.part" "$URL"
  echo "$sha1  $JAR.part" | sha1sum -c --quiet - || { echo "SHA1 mismatch" >&2; rm -f "$JAR.part"; exit 1; }
  echo "$sha256  $JAR.part" | sha256sum -c --quiet - || { echo "SHA256 mismatch" >&2; rm -f "$JAR.part"; exit 1; }
  mv "$JAR.part" "$JAR"
  echo "verified $JAR (sha1 $sha1, sha256 $sha256)"
}

case "${1:-serve}" in
  prepare)
    prepare ;;
  serve)
    prepare
    echo "open http://127.0.0.1:${PORT:-8017}/  (Ctrl+C stops the server)"
    exec python3 -I serve.py --port "${PORT:-8017}" --bind 127.0.0.1 --quiet ;;
  test)
    prepare
    shift
    NODE_PATH="${NODE_PATH:-$(npm root -g)}" exec node test.mjs "$@" ;;
  test-demos)
    prepare
    shift
    NODE_PATH="${NODE_PATH:-$(npm root -g)}" exec node test-demos.mjs "$@" ;;
  *)
    echo "usage: $0 [serve|test|test-demos|prepare]" >&2; exit 2 ;;
esac
