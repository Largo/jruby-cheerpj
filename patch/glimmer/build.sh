#!/bin/sh
# Builds jars/glimmer-swing-gems.jar (require 'glimmer-cheerpj'): Glimmer DSL for Swing and its
# pure-Ruby dependencies. jruby-win32ole is Windows-only and never required off Windows.
exec "$(dirname "$0")/../gems/build.sh" glimmer-swing-gems glimmer-cheerpj \
  "${GLIMMER_GEM:-glimmer-dsl-swing}" "${GLIMMER_VERSION:-0.0.5}" jruby-win32ole
