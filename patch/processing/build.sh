#!/bin/sh
# Fetches Processing core (LGPL-2.1) from Maven Central and builds jars/processing-cheerpj-patch.jar,
# an overlay that goes BEFORE the Processing jar on the CheerpJ classpath.
#
# Patch: PSurfaceAWT.render() blits through canvas.createBufferStrategy(2); CheerpJ 4.3's
# FlipBufferStrategy.getDrawGraphics() throws NullPointerException, so sketches open an empty
# window. We draw the frame straight onto the canvas's Graphics instead.
set -eu
cd "$(dirname "$0")/../.."
V=${PROCESSING_VERSION:-4.5.7}
JAR=jars/processing-core-$V.jar
URL=https://repo1.maven.org/maven2/org/processing/core/$V/core-$V

fetch() {  # fetch <url> <dest>, verified against Maven Central's .sha1
  [ -f "$2" ] && return 0
  sha1=$(curl -fsSL "$1.sha1" | cut -c1-40)
  curl -fsSL -o "$2.part" "$1"
  echo "$sha1  $2.part" | sha1sum -c --quiet - || { echo "SHA1 mismatch for $1" >&2; rm -f "$2.part"; exit 1; }
  mv "$2.part" "$2"
}
mkdir -p jars
fetch "$URL.jar" "$JAR"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fetch "$URL-sources.jar" "$work/src.jar"
(cd "$work" && unzip -q src.jar processing/awt/PSurfaceAWT.java)
python3 -I - "$work/processing/awt/PSurfaceAWT.java" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
start = s.index("  protected void render() {")
end = s.index("  @Override\n  public void selectInput(", start)
s = s[:start] + """  protected void render() {
    // CheerpJ: no BufferStrategy (FlipBufferStrategy.getDrawGraphics NPEs); paint directly.
    if (canvas.isDisplayable() && graphics.image != null) {
      Graphics draw = canvas.getGraphics();
      if (draw != null) {
        draw.drawImage(graphics.image, 0, 0, sketchWidth, sketchHeight, null);
        draw.dispose();
      }
    }
  }


""" + s[end:]
open(p, "w").write(s)
PY
mkdir "$work/out"
javac -nowarn --release 17 -cp "$JAR" -d "$work/out" "$work/processing/awt/PSurfaceAWT.java"
jar --create --file jars/processing-cheerpj-patch.jar --date=2026-01-01T00:00:00Z -C "$work/out" .
echo "built jars/processing-cheerpj-patch.jar for Processing $V"
