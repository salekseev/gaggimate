# Wiring harness diagrams

Wiring harnesses in this directory are [WireViz](https://github.com/wireviz/WireViz)
sources. Each `<name>.yml` is the source of truth; the `.svg` and `.bom.tsv` beside it
are generated and committed so they can be linked from documentation without a build
step.

Board *pinout* diagrams are a separate toolchain — see `scripts/pinout_diagram.py`
and `scripts/make_pcb_preview.sh`.

## Regenerating

```sh
scripts/make_wiring_diagrams.sh                              # all sources
scripts/make_wiring_diagrams.sh docs/diagrams/<name>.yml     # one source
```

The script creates a local venv pinned to **WireViz 0.4.1** (checking the version, so
a pre-existing venv cannot silently bypass the pin) and, after rendering, deletes the
`.html` and `.png` that WireViz also emits — but only when they are untracked, so the
committed `classic`/`classicpro` artifacts are never removed. Only `.svg` and
`.bom.tsv` are committed for sources added since:

- The `.svg` is vector, renders inline on GitHub (verified — GitHub emits identical
  `<img>` markup for a repo-relative `.svg` and `.png`), and stays legible on wide
  harnesses. The equivalent `.png` is 30-40x larger compressed (measured: 33x and 36x
  for the two lelit diagrams, 40-43x for classic and classicpro) and barely
  delta-compresses, so every regeneration would add hundreds of KB to history.
- The `.html` is 75-90 % a byte-for-byte copy of the `.svg` depending on diagram size,
  with the BOM appended as a table. Nothing links to it.

`classic.*` and `classicpro.*` predate the script and still have committed `.html` and
`.png`; `classicpro` additionally has no committed `.bom.tsv`, so the source-plus-two-
artifacts rule above describes the new diagrams rather than the directory as a whole.

**Pass the source you are working on.** With no arguments the script renders every
source, which has two pre-existing consequences: `classic.yml` fails (see below, and
the script reports it and exits non-zero rather than masking it), and `classicpro`'s
committed artifacts were produced by graphviz 12.2.0, so a modern graphviz
regenerates them byte-differently and dirties three tracked files.

## Gotchas

The version pin is not cosmetic. WireViz renders through graphviz, and these bite:

- **No `<`, `>` or `->` in `notes:` or `description:`.** Graphviz HTML-like labels are
  `<`-delimited, so a bare `>` truncates the label and the render dies with a syntax
  error. Write "gives" or "to" instead of "->".
- **No `3.0V`-style number-letter without a space.** Graphviz warns "badly delimited
  number" and then errors. Write `3.0 V`.
- **A connector absent from `connections:` is silently not drawn** — you get a warning,
  not an error, and the connector vanishes from the diagram. If a part matters but has
  no wires (an abandoned terminal, say), put it in a `notes:` field on a connector that
  *is* wired.
- **`subtype:` and `type:` are BOM grouping keys.** Putting a board name, a position
  count or a warning in `subtype:` fragments the BOM. Keep `subtype:` for gender and
  form factor, matching `classic.yml`, and put everything else in `notes:`.
- **`ignore_in_bom: true`** is the way to draw something that is not a purchasable
  connector — e.g. a resistor network that exists in the harness but whose parts belong
  in `additional_bom_items`.

## Known issue

`classic.yml` does not render on WireViz 0.4.1:

```
Exception: POWER_SWITCH:4 not found.
```

It declares `POWER_SWITCH` with two pins (line 41) and then wires pin 4 (line 122), so
the committed `classic.svg` is **not reproducible from its committed source**. The fix
is either the missing pinlabels or a renumber, plus a regenerate.

`classicpro.yml` renders cleanly, with no errors or warnings — but its committed `.svg`
is not byte-reproducible either (regenerates ~110.6 kB against the committed 105.1 kB),
because it was produced by an older graphviz. By contrast the two `lelit-*` `.svg` and
`.bom.tsv` files **are** byte-identical to a fresh render under the pinned 0.4.1, which
is the property the pin exists to give you.
