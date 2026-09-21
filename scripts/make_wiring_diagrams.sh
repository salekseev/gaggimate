#!/usr/bin/env bash
# Regenerate the WireViz wiring harness diagrams in docs/diagrams/.
#
# Pinned to a known WireViz version deliberately: the committed .yml files are
# written against its behaviour, and the graphviz label constraints noted in
# docs/diagrams/README.md are version-sensitive.
#
# Usage:
#   scripts/make_wiring_diagrams.sh                       # every source
#   scripts/make_wiring_diagrams.sh docs/diagrams/foo.yml # just one
set -euo pipefail
shopt -s nullglob

cd "$(dirname "$0")/.."

WIREVIZ_VERSION="0.4.1"
VENV="${VENV:-.wireviz-venv}"

# WireViz renders through graphviz, which pip cannot install for us.
command -v dot >/dev/null || {
  echo "error: graphviz not found (need the 'dot' binary)" >&2
  exit 1
}

# Check the version, not just presence — an existing venv holding some other
# WireViz would otherwise silently bypass the pin this script exists to enforce.
if ! "$VENV/bin/wireviz" --version 2>/dev/null | grep -qF "$WIREVIZ_VERSION"; then
  rm -rf -- "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "wireviz==$WIREVIZ_VERSION"
fi

if [ "$#" -gt 0 ]; then
  sources=("$@")
else
  sources=(docs/diagrams/*.yml)
fi

if [ "${#sources[@]}" -eq 0 ]; then
  echo "error: no .yml sources found in docs/diagrams/" >&2
  exit 1
fi

# WireViz always emits .html and .png alongside .svg and .bom.tsv. For sources
# added since this script, we keep only the .svg (vector, ~30x smaller compressed than the
# PNG, renders inline on GitHub) and the .bom.tsv. classic.* and classicpro.*
# predate that and have their .html/.png committed, so anything already tracked
# is left alone rather than silently deleted.
prune_untracked_extras() {
  local base="$1" ext f
  for ext in html png; do
    f="$base.$ext"
    [ -e "$f" ] || continue
    git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || rm -f -- "$f"
  done
}

failed=()
for src in "${sources[@]}"; do
  echo "wireviz $src"
  # Don't let one bad source hide the rest: docs/diagrams/README.md records that
  # classic.yml does not currently render.
  if "$VENV/bin/wireviz" "$src"; then
    base="${src%.yml}"
    prune_untracked_extras "$base"
    for want in "$base.svg" "$base.bom.tsv"; do
      [ -s "$want" ] || { echo "error: $src rendered but $want is missing" >&2; failed+=("$src"); }
    done
  else
    failed+=("$src")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo >&2
  echo "failed to render: ${failed[*]}" >&2
  echo "see the Known issue section of docs/diagrams/README.md" >&2
  exit 1
fi
