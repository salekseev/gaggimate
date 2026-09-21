#!/usr/bin/env bash
# Regenerate the WireViz wiring harness diagrams in docs/diagrams/.
#
# Pinned to 0.4.1 deliberately: the committed .yml files are written against its
# behaviour, and the graphviz label constraints noted in docs/diagrams/README.md
# are version-sensitive.
#
# Usage:
#   scripts/make_wiring_diagrams.sh                       # all sources
#   scripts/make_wiring_diagrams.sh docs/diagrams/foo.yml # just one
set -euo pipefail

WIREVIZ_VERSION="0.4.1"
VENV="${VENV:-.wireviz-venv}"

if [ ! -x "$VENV/bin/wireviz" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "wireviz==$WIREVIZ_VERSION"
fi

if [ "$#" -gt 0 ]; then
  sources=("$@")
else
  sources=(docs/diagrams/*.yml)
fi

for src in "${sources[@]}"; do
  echo "wireviz $src"
  "$VENV/bin/wireviz" "$src"
done

# WireViz always emits .html and .png alongside .svg and .bom.tsv. We keep the .svg
# (vector, ~40x smaller than the PNG, renders inline on GitHub) and the .bom.tsv.
# The .html is ~89% a byte-for-byte copy of the .svg and nothing links to it.
for src in "${sources[@]}"; do
  base="${src%.yml}"
  rm -f -- "$base.html" "$base.png"
done
