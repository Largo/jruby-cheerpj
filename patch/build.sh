#!/bin/sh
# Builds jars/cheerpj-patch.jar: overlay classes put BEFORE the JRuby jar on the CheerpJ classpath.
set -eu
cd "$(dirname "$0")/.."
JRUBY_JAR=${1:-jars/jruby-complete-9.4.15.0.jar}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
javac -nowarn --release 8 -cp "$JRUBY_JAR" -d "$out" $(find patch/src -name '*.java')
jar --create --file jars/cheerpj-patch.jar --date=2026-01-01T00:00:00Z -C "$out" .
echo "built jars/cheerpj-patch.jar"
