# Atomize the test harness: stop re-deriving coverage through composed examples

## Problem

The suite spends most of its wall-clock running a handful of **generic,
example-enumeration suites over the whole `examples` registry** (~88 composed
`(document, projection)` pairs, see
[`package/example/src/Examples.jl`](../../package/example/src/Examples.jl)).
Each example's `projection` is a *full pipeline* — e.g. the JSON example is
`JsonToSyntax → SyntaxToText → TextToGraphics`
([`example/src/projection/Json.jl:1`](../../package/example/src/projection/Json.jl)) —
so every sweep re-runs the entire stack (including the expensive TrueType
`TextToGraphics` layout) for every example.

The cross-cutting suites that loop the registry, from `test_all()`
([`ProjecturedTest.jl:225`](../../package/test/src/ProjecturedTest.jl)):
`test_printers`, `test_readers`, `test_repls`, `test_typeins`,
`test_text_navigations`, `test_text_navigations_complete`, `test_mouse_clicks`,
`test_click_roundtrips`, `test_text_nav_invariants_all`,
`test_json_content_clicks_clean_all`, `test_tree_navigations`,
`test_tree_navigations_complete`. Most are **generic walkers**
(`_walk!` in [`PrinterTest.jl:45`](../../package/test/src/editor/PrinterTest.jl))
that assert "no cell throws / navigation doesn't get stuck" — they carry **no
domain- or projection-specific knowledge**. They give crash/smoke coverage at
O(examples × events × cells × full-pipeline-cost).

Two structural symptoms confirm the redundancy the request points at:

1. **The registry is mostly one projection with many documents.** ~38 of the 88
   examples are widget examples (`widget_label` … `widget_focus`) that **all share
   `make_widget_projection_example`** and differ only in their document. Running
   the 12-suite sweep over all 38 re-exercises the *identical* pipeline 38 times;
   the only discriminating fact each adds is "this widget document prints" — one
   printer assertion, not a full reader/repl/typein/nav/click sweep. Same pattern
   for the collection family (`collection`/`reversing`/`filtering`/`searching`/
   `sorting` share `make_collection_document_example`) and the
   `make_json_document_example` reuse (json / json_sorted / json_widget /
   graphics_image).

2. **"Which examples are meaningful for me" is re-derived, ad hoc, in every
   suite.** `test_text_navigations` skips widgets/layout/workbench/assistant/SQL
   with inline name-prefix heuristics
   ([`TextNavigationTest.jl:142-168`](../../package/test/src/editor/TextNavigationTest.jl));
   `test_mouse_clicks` and `test_click_roundtrips` skip non-`TextToGraphics`
   pipelines the same way
   ([`MouseClickTest.jl:304`](../../package/test/src/editor/MouseClickTest.jl),
   [`ClickRoundtripTest.jl:194`](../../package/test/src/editor/ClickRoundtripTest.jl)).
   These fragile, duplicated skip-lists are a smell that the registry is doing
   double duty: a **screenshot gallery** (every widget kind needs a picture, see
   `generate_example_screenshots`, [`ExampleTest.jl:791`](../../package/test/src/editor/ExampleTest.jl))
   *and* a **test-fixture matrix** — and the second job is mostly redundant with
   the atomic tests that already exist.

The good news: the atomic layer the request asks for **already exists and is the
better-factored half of the suite.** `test_json()`
([`JsonTest.jl`](../../package/test/src/document/JsonTest.jl)) exercises the JSON
domain directly; `test_json_to_syntax()`
([`JsonToSyntaxTest.jl:1`](../../package/test/src/projection/JsonToSyntaxTest.jl))
prints `JsonToSyntax` on bare `JsonNull()`/`JsonBool(true)`/… with **no pipeline
below it**, and `test_json_to_syntax_reader()` drives the reader on minimal
documents. These are fast, precise, and name the failing unit. The plan is to
**make the atomic layer the primary coverage and demote the registry sweep to a
thin, representative smoke tier** — not to delete coverage, but to stop paying
for the same coverage ~40× through the slowest path.

## Coverage model: separate the axes

Today one mechanism (enumerate the registry, run a generic walker) is asked to
cover four independent axes at once. Name them and cover each at its cheapest
level:

| Axis | Question | Cheapest home | Today |
|---|---|---|---|
| **A. Document** | Does a domain's data model behave (construct, mutate, react)? | `test_<domain>()` on bare structs | ✅ exists (`test_json`, `test_syntax`, …) |
| **B. Stage** | Does one projection print/read correctly in isolation? | `test_<proj>()` printing the stage on a *minimal* document, no pipeline below | ✅ partial (`test_json_to_syntax`, `test_syntax_to_text`, …); gaps below |
| **C. Composition** | Do stages wire together (references map end-to-end, selection forwards, recursion delegates)? | One representative example per *distinct pipeline shape* | ⚠️ done by sweeping **all** 88, not the ~12 distinct shapes |
| **D. Invariants** | Crash-free cell forcing, navigation reachability, click round-trip | Representative example per shape + the existing curated completeness subsets | ⚠️ run over the whole registry via fragile skip-lists |

The waste is entirely in **C** and **D** being run per-example instead of
per-pipeline-shape. A/B are already atomic and should *absorb* the
discriminating coverage that C/D currently get by accident.

## Strategy

1. **Tag the registry with coverage metadata instead of re-deriving it.** Give
   `Example` (struct at [`ExampleTest.jl:1`](../../package/test/src/editor/ExampleTest.jl), via `Examples.jl`)
   two new fields:
   - `shape::Symbol` — the pipeline shape it represents (`:text_graphics`,
     `:widget_graphics`, `:syntax_text`, `:collection`, `:read_only`, …). All ~38
     widget examples share `shape = :widget_graphics`.
   - `coverage::Vector{Symbol}` — which cross-cutting suites are *meaningful*
     (e.g. a static widget screenshot example is `[:printer]`; the canonical
     editable JSON example is `[:printer, :reader, :repl, :navigation, :typein, :click]`).

   Drive every enumeration suite off `coverage`/`shape` and **delete the inline
   skip-lists** in TextNavigationTest/MouseClickTest/ClickRoundtripTest. The skip
   logic becomes one declaration per example, in one place, instead of N fragile
   name-prefix heuristics.

2. **Pick one representative example per `shape` for the heavy C/D sweep.** The
   full read/repl/typein/nav/click suites run only over the representatives
   (~12 pipeline shapes), not all 88. This is the bulk of the time saving and
   loses no *pipeline-wiring* coverage, because non-representative examples of a
   shape exercise the same wiring.

3. **Push discriminating per-example facts down to axis A/B.** For each widget
   kind that today only earns coverage by being swept, add (or confirm) a cheap
   assertion in the widget document/stage test that the kind constructs and
   prints — a single `@test` next to `test_object_to_widget` / `test_syntax_to_widget`,
   not a registry entry that triggers 12 sweeps. The widget *screenshot* entry
   stays (it's a gallery artifact, `coverage = [:printer]`), but it no longer
   pulls the full matrix.

4. **Fill the B-axis gaps** so demoting C/D is safe. Audit the projection stages
   that have **no standalone `test_<proj>()`** and only get touched through
   examples (candidates from the registry: the per-widget projections, the
   graphics/layout stages reached only via `*_graphics`). Each gap gets a
   minimal-document stage test in the `JsonToSyntaxTest` style.

5. **Tier the entry points** so the dev-loop default is the fast atomic layer and
   the registry sweep is opt-in / CI-only:
   - `test_atomic()` — documents (A) + stages (B) + primitives/cells/references.
     Fast; the default per-change loop. (CLAUDE.md already pushes "smallest test
     that covers the change"; this gives it a named home.)
   - `test_smoke()` — `test_printer` over the per-`shape` representatives only (C
     wiring + D crash, cheap).
   - `test_all()` — unchanged surface, still the full registry sweep, for CI.

   No public function is removed; `test_all()` stays a superset.

## Phases (each independently shippable, suite stays green)

- **Phase 0 — measure.** Record per-suite timings from one `test_all()` run
  (wrap each `test_*` in `@elapsed`/`@info`). This is the baseline the plan is
  judged against and tells us which sweeps actually dominate (hypothesis:
  `test_repls` + `test_click_roundtrips` + the `*_navigations`, all ×88).

- **Phase 1 — metadata, no behavior change.** Add `shape` + `coverage` to
  `Example` with defaults that reproduce *exactly today's* skip behavior, then
  rewrite the three suites with inline skip-lists to read the metadata. Net
  coverage identical; the skip logic is now declarative. (Safe, mechanical,
  high-confidence.)

- **Phase 2 — B-axis gap audit.** List projection stages with no standalone
  test; add minimal-document stage tests for each. Gate the rest of the plan on
  this — we only demote a sweep once the stage it covered has an atomic test.

- **Phase 3 — representatives.** Introduce `test_smoke()` and switch the heavy
  C/D suites to iterate representatives by `shape` instead of the full registry.
  Keep the curated completeness subsets (`_text_navigation_complete_examples`,
  the tree-nav curation) — those are already representative by design.

- **Phase 4 — retier & document.** Add `test_atomic()`; update
  [`documentation/testing.md`](../../documentation/testing.md) and `CLAUDE.md`'s
  "Testing a change" section to point at `test_atomic` / single-stage tests as
  the default and `test_all` as the CI sweep. Re-measure against Phase 0.

## What explicitly does NOT change

- **The `examples` registry stays complete** — every widget kind keeps its entry
  so `generate_example_screenshots` still produces the gallery. Atomization is
  about *which suites run over which examples*, not deleting examples.
- **`test_all()` stays a full sweep.** CI still gets exhaustive crash coverage;
  the win is that the *dev loop* and the *common case* stop paying for it.
- **Lazy/stateful exclusions are unaffected** — `lazy_example`,
  `clipboard_example`, `versioning_example` are already kept out of the registry
  for documented reasons ([`Examples.jl:93-142`](../../package/example/src/Examples.jl));
  the `coverage` field just makes that kind of exclusion uniform.

## Risks / open questions

- **Lost crash coverage on non-representative examples.** Mitigated by keeping
  `test_printer` (the cheapest sweep) over *all* examples in `test_smoke`/`test_all`
  — only the expensive reader/repl/nav/click/typein sweeps drop to representatives.
  A bug that only manifests in, say, `widget_accordion`'s reader but not the
  `:widget_graphics` representative would be caught by `test_all` in CI, not the
  dev loop — an acceptable trade given those readers share one pipeline.
- **Reactive-incrementality coverage.** The generic `_walk!` forces every cell;
  some examples may be the only thing forcing a particular cell graph. Phase 2's
  gap audit must check that each stage's atomic test forces its own cells (the
  `JsonToSyntaxTest` "value change propagates" assertions are the model).
- **Choosing representatives.** "One per shape" needs the shape taxonomy to be
  honest — two examples that look like the same shape but wire references
  differently must be different shapes, or C-axis coverage silently narrows. The
  taxonomy should be derived from the actual projection *composition*, not the
  example name.

## Progress

- [ ] Phase 0 — per-suite timing baseline captured
- [ ] Phase 1 — `shape`/`coverage` metadata on `Example`; inline skip-lists in
      TextNavigation/MouseClick/ClickRoundtrip replaced by metadata reads
- [ ] Phase 2 — projection-stage gap audit + minimal-document stage tests for
      every stage lacking a standalone `test_<proj>()`
- [ ] Phase 3 — `test_smoke()`; heavy C/D suites iterate per-`shape`
      representatives
- [ ] Phase 4 — `test_atomic()`; docs/CLAUDE.md retiered; re-measured vs Phase 0
