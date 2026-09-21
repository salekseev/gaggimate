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
  echo "       dnf install graphviz | apt install graphviz | brew install graphviz" >&2
  exit 1
}

# Compare the version exactly. A substring test would accept 0.4.11 for a 0.4.1
# pin, and testing only for the binary's presence would let any pre-existing venv
# bypass the pin this script exists to enforce.
have_version() {
  [ -x "$VENV/bin/wireviz" ] || return 1
  local have
  have=$("$VENV/bin/wireviz" --version 2>/dev/null | awk '$1 == "WireViz" { print $2 }')
  [ "$have" = "$WIREVIZ_VERSION" ]
}

if ! have_version; then
  # Never rm -rf a path we cannot positively identify as a virtualenv: VENV is an
  # env override, and have_version() also fails for "exists but unreadable" and
  # "interpreter symlink broken by a Python upgrade".
  if [ -e "$VENV" ] && [ ! -f "$VENV/pyvenv.cfg" ]; then
    echo "error: $VENV exists but is not a virtualenv; refusing to delete it" >&2
    exit 1
  fi
  echo "installing wireviz $WIREVIZ_VERSION into $VENV (downloads ~40 MB)" >&2
  # Build beside the old one and swap, so a failed install does not leave the
  # caller with no venv at all.
  rm -rf -- "$VENV.new"
  python3 -m venv "$VENV.new"
  "$VENV.new/bin/pip" install --quiet "wireviz==$WIREVIZ_VERSION"
  rm -rf -- "$VENV"
  mv -- "$VENV.new" "$VENV"
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

# WireViz always emits .html and .png alongside .svg and .bom.tsv, plus a .tmp
# holding the graphviz source. For sources added since this script we keep only
# the .svg (vector, far smaller than the PNG, renders inline on GitHub) and the
# .bom.tsv. classic.* and classicpro.* predate that and have their .html/.png
# committed, so anything already tracked is left alone rather than deleted.
#
# "Not tracked" must mean exactly that. `git ls-files --error-unmatch` also fails
# when git is missing or this is not a checkout (a tarball export, a CI image
# without git), and deleting on "I cannot tell" is the wrong default.
if git rev-parse --git-dir >/dev/null 2>&1; then
  prune_untracked_extras() {
    local base="$1" ext f
    for ext in html png tmp; do
      f="$base.$ext"
      [ -e "$f" ] || continue
      git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || rm -f -- "$f"
    done
  }
else
  echo "warning: not a git checkout; leaving generated .html/.png/.tmp in place" >&2
  prune_untracked_extras() { :; }
fi

failed=()
for src in "${sources[@]}"; do
  echo "wireviz $src"
  base="${src%.yml}"
  bad=0

  # Don't let one bad source hide the rest: docs/diagrams/README.md records that
  # classic.yml does not currently render.
  if out=$("$VENV/bin/wireviz" "$src" 2>&1); then
    printf '%s\n' "$out"
    # WireViz exits 0 while warning that a connector appears in no connection
    # set -- and that connector is dropped from the .svg AND the .bom.tsv, so the
    # part silently never gets bought. Treat it as a failure.
    if grep -q '^Warning:' <<<"$out"; then
      echo "error: $src declares components not referenced in any connection set." >&2
      echo "       They are dropped from both the .svg and the .bom.tsv." >&2
      bad=1
    fi
    for want in "$base.svg" "$base.bom.tsv"; do
      [ -s "$want" ] || { echo "error: $src rendered but $want is missing" >&2; bad=1; }
    done
  else
    printf '%s\n' "$out" >&2
    bad=1
  fi

  # Prune on both paths: a failure partway through must not leave stale
  # .html/.png/.tmp behind for a later `git add -A` to commit.
  prune_untracked_extras "$base"
  [ "$bad" -eq 0 ] || failed+=("$src")
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo >&2
  echo "failed to render: ${failed[*]}" >&2
  echo "see the Known issue section of docs/diagrams/README.md" >&2
  exit 1
fi
