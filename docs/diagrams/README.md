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

The script creates a local venv pinned to **WireViz 0.4.1** and, after rendering,
deletes the `.html` and `.png` that WireViz also emits. Only `.svg` and `.bom.tsv`
are committed:

- The `.svg` is vector, renders inline on GitHub (verified — GitHub emits identical
  `<img>` markup for a repo-relative `.svg` and `.png`), and stays legible on wide
  harnesses. The equivalent `.png` is roughly 40x larger packed and barely
  delta-compresses, so every regeneration would add hundreds of KB to history.
- The `.html` is about 89% a byte-for-byte copy of the `.svg`, with the BOM appended
  as a table. Nothing links to it.

`classic.*` and `classicpro.*` predate the script and still have committed `.html`
and `.png`.

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
is either the missing pinlabels or a renumber, plus a regenerate. `classicpro.yml` is
unaffected and renders cleanly.
