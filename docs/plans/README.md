# Design and build plans

Staged plans for work that does not exist in the tree yet — typically porting
GaggiMate onto a machine whose stock electronics need reverse engineering.

A plan is a working document, not a permanent record. It exists to be executed and
then largely deleted.

## Convention

- **One plan per machine or capability**, named `<vendor>-<machine>-<topic>.md`.
- **Open with a `**Status:**` line** stating plainly what does and does not exist yet,
  so a reader never has to guess whether the code is there.
- **Anchor claims to greppable symbols** — `MAX_SAFE_TEMP`,
  `ALT_RELAY_STEAM_BOILER`, `boiler.index = 0` — rather than paraphrasing behaviour, and
  rather than bare line numbers, which rot fastest. That is what makes drift detectable
  when the code moves underneath.
- **Split reference material out.** Wire formats, register maps and provenance tables
  outlive the plan that prompted them, so they belong in their own document that the
  plan links to. Evidence for a rejected approach likewise.
- **Machine-agnostic tooling knowledge does not belong here.** It ends up somewhere
  nobody looks. Toolchain notes go next to the tool or its output — e.g.
  `docs/diagrams/README.md`.

## Retirement

When a stage lands, delete what the code now carries and keep only what it cannot:

- Per-file responsibility tables become header comments or a README next to the code.
- **Safety invariants become named constants plus enforcing tests**, following
  `TemperatureSensor.h`'s `MAX_SAFE_TEMP`. A limit that lives only in prose is a limit
  that gets lost — any such statement in a plan is a placeholder for a constant and a
  test, not its final home.
- Rationale, machine facts and reverse-engineered protocol detail stay.

## Current plans

| Document | Machine | Status |
|---|---|---|
| [lelit-elizabeth-gaggimate.md](lelit-elizabeth-gaggimate.md) | Lelit Elizabeth PL92T-120 | Machine reference and bring-up notes; awaiting prototype hardware |
| [appendix-retained-gicar.md](appendix-retained-gicar.md) | Lelit Elizabeth PL92T-120 | **Superseded.** Kept for the record |

Supporting references: [lelit-lcc-protocol.md](lelit-lcc-protocol.md) (stock wire
format), [lelit-alternatives-considered.md](lelit-alternatives-considered.md) (evidence
log from the superseded investigation).

Worth noting as a worked example of the retirement rule above: the Elizabeth plan was
superseded mid-flight when upstream took a different approach. Rather than deleting it,
the machine facts and the constraints that bind *any* controller were kept in the live
document and the architecture-specific reasoning moved to a clearly-marked appendix.
