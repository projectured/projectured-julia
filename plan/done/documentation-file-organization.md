# Documentation file organization

## Goal

Move each documentation file to where it belongs — per-package reference guides
into the package they document, cross-cutting guides kept at the top level —
while eliminating duplication, merging fragments that describe one thing in two
places, splitting the one file that carries two audiences, and giving every
file a single clear role, audience, and message.

This is a reorganization of *prose*, not code. No `.jl` changes except the two
runtime couplings called out in [§6](#6-code-couplings-that-must-move-with-the-docs).

## The perspective that shapes everything

There are **two documentation trees today**, and they are not redundant — they
are a *deliberate split by audience that has drifted into fragmentation*:

- **`documentation/`** — 40 files, ~9,000 lines. Read by newcomers, evaluators,
  the human contributor, and **the AI agent** (see coupling below). Mixes
  whole-system concepts, how-to guides, and per-domain reference.
- **`package/<pkg>/doc/`** — 14 files, ~1,500 lines. Per-package *internal
  structure* guides (layers, slices, module inventory). Read only by a
  contributor already working inside that package. Kernel has a full set (9
  layer guides + `naming.md` + `architecture.md`); base/visual/domain each
  collapse to a single `architecture.md` (base adds one).

The current contract — *top-level = concepts + whole-system + how-to; package
`doc/` = per-package structure* — is real and mostly honored: every kernel
layer guide names a top-level companion it refuses to duplicate
(`cell.md`→`reactive-cells.md`, `operation.md`→`operations.md`,
`reference.md`→`editor/reference.md`, …). **That pairing is itself the
duplication to collapse.** For each kernel layer we currently ship two half-docs
— a "what modules exist" doc in the package and a "how to use it" doc at the top
level — that cross-reference each other instead of being one guide.

So the reorg is not "move everything into packages." It is:

1. **Merge each layer's structure-doc + how-to-doc into one guide, in the
   package.** (kernel gains the real weight here.)
2. **Move per-domain reference into the package that owns the domain.**
3. **Keep genuinely cross-cutting docs at the top level** — concepts, vision,
   the whole-system architecture, terminology/rules, onboarding, and the
   repo-wide tooling guides (testing/debugging). These serve newcomers,
   evaluators, and the AI, and they span all four packages; burying them in one
   package would be wrong.
4. **Remove one redirect stub and one piece of vaporware** that are not guides.

## The central constraint: two runtime couplings read `documentation/`

Any move must reckon with two pieces of live code that read the doc tree by
path. **This is the single most important fact in this plan** — it is why
"move docs into packages" is not free.

### Coupling A — the MCP guide catalogue (`package/kernel/main/agent/Mcp.jl`)

Three `walkdir` loops hardcode `joinpath(@__DIR__, "../../../../documentation")`
and expose every `.md` under it to the AI agent as `resource://guide/<name>`,
plus `list_guides()` / `read_guide()` / full-text `search_documentation()`.
The guide name is the path relative to `documentation/` (so today the agent
sees `editor/reference`, `document/json`, …). **Move a guide out of
`documentation/` and the AI loses it** — and the AI is a first-class audience
per the project's vision.

→ This forces the pivotal decision in [§7](#7-the-one-decision-that-must-be-made-first).

### Coupling B — the screenshot injector (`package/projectured/example/Examples.jl`)

`update_guide_screenshots()` injects example images into specific files by path:
- `_update_examples_tour(".../documentation/examples-tour.md")`
- `_update_domain_guides(".../documentation/document")` driven by
  `_DOMAIN_GUIDE_EXAMPLE` (`json.md`→`json`, `xml.md`→`xml`, `text.md`,
  `syntax.md`, `graphics.md`, `widget.md`, `workbench.md`, `collection.md`)
- a `walkdir(documentation/)` pass that width-pins every `<img>` in every `.md`.

→ If the `document/*.md` guides move into packages, this map and these paths
must move with them.

## 1. Target tree (top level)

Everything here stays top-level because it is **cross-cutting, onboarding, or
evaluator/AI-facing**, spanning all four packages:

| File | Role | Action |
|---|---|---|
| `README.md` (index) | 3-track reading guide | Rework links to new locations |
| `concepts.md` | Canonical plain-English mental model | Keep; make it the single owner of the "what/why" narrative |
| `vision.md` | Strategy + "compared to…" | Keep; trim the mechanics it re-argues, link to `concepts.md` |
| `roadmap.md` | Delivered / in-progress / planned | Keep; cross-ref instead of restating design-decisions & requirements |
| `requirements.md` | Behavior/capability spec | Keep (roadmap tracks against it) |
| `terminology.md` | package/layer/slice/module vocabulary | Keep — the naming contract all docs cite |
| `architecture.md` | **Whole-system** pipeline, package chain, inventory | Keep; de-stale (still shows old single-package paths); hand the projection taxonomy to `projection-system.md` |
| `architecture-rules.md` | Where-does-code-go decision rules | Keep |
| `design-decisions.md` | Cross-package "why" rationale | Keep |
| `getting-started.md` | Setup + REPL helpers | Keep; becomes the single home for the `run_example` block |
| `examples-tour.md` | Guided example gallery | Keep (Coupling B) |
| `debugging.md` | Repo-wide REPL debugging tooling | Keep |
| `testing.md` | Repo-wide test tooling | Keep; reference (not restate) the recursion contract |
| `tutorial-new-domain.md` | Integrative onboarding (spans all layers) | Keep; slim to lean on canonical docs |
| `orientation.md` | AI/dev concept→symbol search index | Keep — cross-package AI entry point |
| `projectured-overview.md` + `presentations.md` | Marp slide deck + its README | Keep as a `presentations/` subgroup (own audience) |

**Delete:** `design.md` — a 24-line redirect stub; its pointers belong in the
README/architecture index. **Remove from docs:** `editor/annotation.md` — an
"aspirational / not yet implemented" API sketch whose brainstorming twin already
lives at `plan/tentative/annotation.md`. Fold anything worth keeping into that
file; delete the docs copy. It is not a domain guide.

## 2. Move into `kernel/` (the projection/editor engine)

Kernel owns the reactive cells, the projection interface, references, selection,
operations, the editor loop, devices/backends, and the agent. Each move **merges
the existing kernel structure-guide with the top-level how-to** into one guide:

| New file | Merge of | Note |
|---|---|---|
| `kernel/doc/cell.md` | existing `cell.md` (structure) + `reactive-cells.md` (how-to) | One reactive-engine guide |
| `kernel/doc/macros.md` | `macros.md` | `@document`/`@projection`/`@iomap` are kernel codegen |
| `kernel/doc/operation.md` | existing `operation.md` + `operations.md` | Structure + reader flow in one |
| `kernel/doc/reference.md` | existing `reference.md` + `editor/reference.md` + `selection-deep-dive.md` §1/§9 | The reference-grammar guide |
| `kernel/doc/selection.md` (new) | `editor/selection.md` + `selection-deep-dive.md` §2–8 | The selection-mechanism guide |
| `kernel/doc/finding-and-selecting.md` | `editor/finding-and-selecting.md` | The task-oriented how-to (least redundant of the four selection docs) |
| `kernel/doc/editor.md` | existing `editor.md` (structure) + top-level `editor.md` (how-to) | The read-eval-print guide |
| `kernel/doc/projection-system.md` (new) | `projection-system.md` | **Becomes the single owner of the projection taxonomy** |
| `kernel/doc/higher-order-projections.md` (new) | `higher-order-projections.md` | Links to taxonomy owner; base cross-link for compound combinators |
| `kernel/doc/generic-projections.md` (new) | `generic-projections.md` | Nine `projection/generic/` projections |
| `kernel/doc/devices-and-backends.md` | existing `device.md` + `backend.md` + top `devices-and-backends.md` | Interface here; concrete backends live in sdl/web/visual — link out |

Unchanged kernel structure guides that have no top-level twin stay as-is:
`document.md`, `agent.md`, `naming.md`, `architecture.md`.

**The four reference/selection docs collapse from 4 → 3**: one reference
grammar, one selection mechanism, one finding-and-selecting how-to.
`selection-deep-dive.md` is dissolved into the first two.

## 3. Move into `visual/` (rendering substrate)

| New file | From |
|---|---|
| `visual/doc/text.md` | `document/text.md` |
| `visual/doc/syntax.md` | `document/syntax.md` |
| `visual/doc/graphics.md` | `document/graphics.md` |
| `visual/doc/widget.md` | `document/widget.md` |

These are visual slices (`visual/main/{text,syntax,graphics,widget}/`).
`visual/doc/architecture.md` already indexes the slices — link them from it.

## 4. Move into `base/` (domain-independent vocabulary)

| New file | From |
|---|---|
| `base/doc/collection.md` | `document/collection.md` (+ fold in `base/doc/document.md`'s Collection/Primitive structure) |

`Collection.jl` lives at `base/main/document/Collection.jl` (its in-doc link is
already stale, pointing at the old `kernel/…` path — fix on move).
`base/doc/document.md` is largely a subset of `base/doc/architecture.md`; merge
the unique Collection/Primitive material into `base/doc/collection.md` and the
membership rule into `base/doc/architecture.md`, then delete `document.md`.

## 5. Move into `domain/` (concrete domains)

| New file | From |
|---|---|
| `domain/doc/json.md` | `document/json.md` |
| `domain/doc/xml.md` | `document/xml.md` |
| `domain/doc/workbench.md` | `document/workbench.md` |
| `domain/doc/versioning.md` | `document/versioning.md` |

`domain/doc/architecture.md` already indexes the slices — link these from it.

After steps 2–5, `documentation/document/` and `documentation/editor/` are empty
and get removed.

## 6. Duplication to eliminate (independent of the moves)

These are the concrete "one thing, said twice" fixes. Do them **in the merged
file** as part of each move where possible:

1. **Projection taxonomy** — listed in full in `architecture.md`,
   `projection-system.md`, `higher-order-projections.md`, and
   `generic-projections.md`. → `projection-system.md` owns the full tables;
   the other three link to it; `architecture.md` keeps only the 4-stage pipeline
   and a one-line pointer.
2. **Recursion contract** — stated normatively in `projection-system.md`,
   re-explained in `higher-order-projections.md`, re-derived in `testing.md`.
   → normative statement in `projection-system.md`; the others reference it.
3. **Transparent-cell / `@document` mechanic** — split across
   `reactive-cells.md`, `macros.md`, `projection-system.md`. → canonical in
   `cell.md` + `macros.md`; others link.
4. **Evaluator narrative** — `concepts.md`, `vision.md`, `projectured-overview.md`
   all re-tell "text-as-strings → model-is-truth → composable bidirectional
   projections → lazy engine → AI/MCP." → `concepts.md` is canonical prose;
   `vision.md` keeps only strategy + comparisons; the deck stays slides but
   trims to headlines. `requirements.md` §1–3 links rather than re-argues.
5. **`run_example`/`print_example`/`write_example_*` block** — duplicated in
   `getting-started.md` and `examples-tour.md`. → single home in
   `getting-started.md`; the tour links.
6. **MCP/AI workflow** — duplicated across `getting-started.md`,
   `orientation.md`, `vision.md`. → `orientation.md` owns the how-to; others link.
7. **EventEnvelope / ScreenDocument placement rationale** — repeated in
   `kernel/doc/device.md`, `base/doc/document.md`, `base/doc/architecture.md`,
   `visual/doc/architecture.md`. → one canonical statement in
   `kernel/doc/devices-and-backends.md` (or `device` section); others cross-ref.
8. **Per-package `architecture.md` vs top-level `architecture.md`** — each
   package doc restates its own rows from the (partly stale) top-level inventory.
   → top-level keeps the whole-system view + pipeline status; each package's
   detailed inventory lives only in its own `architecture.md`; de-stale the
   top-level module paths.

## 7. Code couplings that must move with the docs

1. **`Examples.jl`** — update `_DOMAIN_GUIDE_EXAMPLE` and the
   `_update_domain_guides` directory arg from `documentation/document` to the new
   per-package `doc/` locations (json/xml/workbench→domain, text/syntax/graphics/
   widget→visual, collection→base). Keep `_update_examples_tour` pointed at
   `documentation/examples-tour.md` (stays top-level). Update the width-pin
   `walkdir` to also cover `package/*/doc/`.
2. **`Mcp.jl`** — the three `walkdir(documentation/)` loops — see §8.
3. **Link sweep** — `README.md` (~30 links), `CONTRIBUTING.md`, `CLAUDE.md`,
   `documentation/README.md`, `architecture.md`'s kernel-doc link block, and all
   cross-links inside moved files. Historical `plan/done/*` references may stay
   stale; fix `plan/pending/*` references that point at moved files.

## 8. The one decision that must be made first

**Does the AI agent keep seeing the guides that move into packages?** Three
options; the plan above assumes **Option B**.

- **Option A — Keep AI-facing guides in `documentation/`; move only
  contributor-internal structure docs.** Minimal `Mcp.jl` change, but it barely
  moves anything (structure docs are already in packages) and does not meet the
  stated goal.
- **Option B (recommended) — Move guides into packages *and* teach `Mcp.jl` to
  also walk `package/*/doc/`.** Point the three loops at both roots; namespace
  package guides (e.g. `kernel/reference`, `visual/widget`). Fully realizes
  "docs live with the code," AI keeps every guide. Cost: guide `resource://`
  names change (acceptable — they are not a stable external API), and one
  ~15-line change repeated across the three loops (factor into a
  `guide_roots()` helper).
- **Option C — Hybrid.** Thin top-level `documentation/` (concepts + onboarding +
  tooling + index) that links into package `doc/`; `Mcp.jl` walks both. Same
  code change as B; differs only in how much narrative stays top-level. The §1–§5
  split above is already essentially this hybrid.

**Recommendation: Option B/C** (they share the same `Mcp.jl` change). It is the
only path that satisfies "move docs into their packages" without blinding the AI
agent.

## 9. Execution order (each a separate commit, kept green)

1. **Prep, no moves** — de-stale `architecture.md` paths; delete `design.md`
   (fold pointers into README); fold `documentation/editor/annotation.md` into
   `plan/tentative/annotation.md` and delete the docs copy.
2. **`Mcp.jl` first** (Option B/C) — teach the three loops to walk
   `documentation/` + `package/*/doc/` via a shared helper, *before* moving
   files, so nothing is ever invisible mid-reorg. Verify with `list_guides()`.
3. **Move + merge per package**, one package per commit: kernel (§2), then
   visual (§3), base (§4), domain (§5). Do the §6 dedup inside each merged file
   as you touch it. Use `git mv` to preserve history.
4. **`Examples.jl`** — update the domain-guide map/paths; run
   `update_guide_screenshots()`; confirm idempotent (no diff on re-run).
5. **Link sweep** — README, CONTRIBUTING, CLAUDE.md, documentation/README,
   inter-doc links. Grep for `documentation/document/`, `documentation/editor/`,
   `reactive-cells.md`, `operations.md`, etc. and fix.
6. **Remove** emptied `documentation/document/` and `documentation/editor/`.

## 10. End state — who reads what

- **Newcomer / evaluator / AI**: `documentation/` — concepts, vision, roadmap,
  requirements, getting-started, examples-tour, tutorial, orientation, the
  whole-system architecture + terminology + rules + design-decisions, the
  repo-wide testing/debugging tooling, and the slide deck. One flat, curated set.
- **Contributor inside a package**: that package's `doc/` — its architecture
  plus the per-layer / per-slice / per-domain reference guides, each now a single
  merged guide (structure + how-to), living next to the code it describes.
- **Every guide has one role, one audience, one message, and one home.** The
  reference/selection cluster goes 4→3; the per-layer structure/how-to pairs go
  2→1; `design.md` and the annotation vaporware leave the docs tree entirely.
```
