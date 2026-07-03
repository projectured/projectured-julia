# Check (and enforce) printer locality

> **Goal.** A printer should produce the **smallest possible change in its
> output for any given change in its input.** A minimal input edit must touch a
> minimal slice of the output: the reactive cells it recomputes, the output
> objects it replaces, and the selection cells it invalidates should all be as
> few as the projection's semantics allow. Anything broader is a locality
> violation and must either be fixed or **justified** as a documented exception.
>
> This is especially true for **selection handling**: moving the caret /
> changing `document.selection` should invalidate **only** selection cells —
> never an output value or structure cell.

This is a *checking* plan first: build the measurement, run it across every
example, classify what passes, what fails, and what is a justified exception.
The fixes follow from what the measurement finds; the plan scopes them but the
audit decides which land.

## Why locality matters here

The reactive engine
([package/kernel/src/reactive/Reactive.jl](../../package/kernel/src/reactive/Reactive.jl))
is **pull-based and write-driven with no equality check** (see
[documentation/reactive-cells.md](../../documentation/reactive-cells.md), the
"Propagation is write-driven, not value-driven" invariant): writing a cell
unconditionally invalidates the transitive closure of its dependents, and a
thunk that recomputes to an unchanged value does **not** stop propagation. So
the only lever for "smallest possible change" is the **shape of the dependency
graph the printer builds** — a printer achieves locality by making a minimal
input write reach a minimal set of output cells, and by preserving the
*identity* of output objects whose inputs did not change so downstream
projections (SyntaxToText → TextToGraphics → layout) don't re-do work.

The editor reprints every frame and resets `perf_counters()` each loop
([package/kernel/src/editor/Editor.jl](../../package/kernel/src/editor/Editor.jl)),
so over-invalidation is paid on every keystroke and is directly measurable.

## The three locality dimensions

For a printer `proj` over document `doc`, print once and force every reachable
cell, then apply one **minimal** input mutation and measure what changed.

### A. Selection isolation (the strict one)
A pure selection move — `set_selection!(doc, p)` / `clear_selection!(doc)`, no
structural or value change — must invalidate **only selection cells** along the
old and new selection paths.

- **Must hold:** no output value cell, no output structure cell (children
  vectors, span lists, layout geometry) is invalidated.
- **Must hold:** every output *object* is identity-preserved (`out === out′`
  field by field, except the `selection` cells).
- This is the load-bearing case the user singled out. Today selection is wired
  as `Cell(() -> map_reference_forward(p, im, doc.selection))`
  ([ProjectionTemplate.jl:296,371,428,474,507](../../package/domain/src/projection/ProjectionTemplate.jl#L296)),
  which reads `doc.selection` **and** `iomap.child_iomaps[]`. Reading
  `child_iomaps` makes the selection cell depend on the children *structure*;
  that is fine in the A→B direction (a structure change may invalidate the
  selection) but the audit must confirm the **reverse does not happen**: a
  selection write must not transitively reach any child output cell. The
  leaf fast path that *shares* the raw selection cell
  ([ProjectionTemplate.jl:271](../../package/domain/src/projection/ProjectionTemplate.jl#L271),
  `bound_field === :value`) is the gold standard — verify it stays that tight.

### B. Value-edit isolation
Editing one leaf's value (`leaf.value = …`, e.g. a `StringReplaceRangeOperation`
landing on one JSON string) must invalidate only that leaf's value/text cell and
the strictly-derived cells above it (the span that contains it, the line it lays
out on) — **not sibling leaves, not sibling subtrees.**

- Model already verified for SyntaxToText:
  [SyntaxToTextTest.jl:20-28](../../package/test/src/projection/SyntaxToTextTest.jl#L20)
  asserts the spans-structure cell stays `isuptodate` across a value change.
  Generalise that assertion to every leaf in every example.

### C. Structural-edit minimality (the hard one)
Inserting / removing / reordering **one** element of a collection must:

- rebuild the changed slot and the structural envelope (open/sep/close, indices
  that genuinely shifted), and
- **preserve the output objects of the unaffected siblings** (cell identity), so
  downstream layout reuses them.

- **Suspected central violation.** The template engine builds children as
  `child_iomaps = Cell(() -> [projection_printer_recurse(recursion, x, …) for x in coll])`
  and `children = CellVector(() -> [im.output for im in child_iomaps[]])`
  ([ProjectionTemplate.jl:283-303](../../package/domain/src/projection/ProjectionTemplate.jl#L283)).
  When the collection's structure cell invalidates (any insert/remove/reorder),
  the **whole** `child_iomaps` thunk re-runs and re-projects **every** sibling
  from scratch — new iomaps, new output objects — so all siblings lose identity
  even though their inputs are unchanged. `_mixed_print` and `_sections_print`
  ([ProjectionTemplate.jl:421,492](../../package/domain/src/projection/ProjectionTemplate.jl#L421))
  have the same shape. This is the most likely place "smallest possible change"
  is not met, and the audit's primary target. (Whether it is *fixable* vs. a
  justified exception is decided in Phase 4 — keyed-reconciliation against the
  element document objects is the candidate fix.)

## Phase 1 — Measurement harness

Add a locality walker beside the existing test walkers (sibling of
`walk_printer_output` in
[package/test/src/editor/PrinterTest.jl](../../package/test/src/editor/PrinterTest.jl);
see [documentation/testing.md](../../documentation/testing.md) "walker helpers").

- [ ] `printer_locality_report(doc, proj, mutate!; expect)` that:
  1. prints (`projection_print(proj, doc)`), reflexively forces every reachable
     `Cell` (reuse `_walk!`), and snapshots, per cell, `objectid` →
     `isuptodate`; also snapshot output-object identities (`objectid` of every
     reachable `@document` struct).
  2. runs `perf_reset!()`, applies `mutate!(doc)` (a selection / value /
     structural edit), forces every reachable cell again.
  3. returns a report: the set of cells that recomputed, the set of output
     objects whose identity changed, and the `perf_counters()` delta
     (`:computes`, `:invalidations`).
- [ ] Express expectations as predicates over the report (`expect`): e.g.
  `only_selection_cells_changed`, `siblings_identity_preserved(i)`,
  `no_structure_cells_invalidated`. Return `(ok, message)` per check, in the
  `Vector{String}`-of-errors style the other walkers use so it runs in the REPL
  and keeps going on failure.
- [ ] To classify a recomputed cell as "selection vs. value vs. structure",
  tag cells by the field they back. The `@document`/`@iomap` getproperty layer
  already routes through named fields; have the walker record the field name and
  owning struct type when it forces `getfield(obj, :selection)` vs. other
  fields, so a report can say *which* cells moved.

## Phase 2 — Mutation generators

Reuse the selection enumerators already in the suite
([SelectionEnumeration.jl](../../package/test/src/editor/SelectionEnumeration.jl):
`collect_text_selections`, `collect_tree_selections`) to drive dimension A
exhaustively, and derive value/structural edits from the document structure.

- [ ] **A (selection):** for each enumerated selection, `set_selection!` to it
  from a different selection and assert dimension-A expectations. Also the
  `clear → set` and `set → clear` transitions.
- [ ] **B (value):** for each reachable leaf with an editable bound field
  (reuse `walk_typein`'s reachability,
  [TypeinTest.jl](../../package/test/src/editor/TypeinTest.jl)), write a new
  value and assert only that leaf's cell + strict ancestors moved.
- [ ] **C (structural):** for each reachable collection, generate
  insert-at-end, insert-in-middle, remove, and swap-two edits; assert the
  unaffected siblings keep identity.

## Phase 3 — Audit sweep and classification

- [ ] Run the harness over every entry in `examples` (~90; see
  [package/example/src/Examples.jl](../../package/example/src/Examples.jl)),
  three dimensions each. Produce a table: example × dimension × {pass, fail,
  exception-candidate} with the offending cell/object named on failure.
- [ ] Bucket failures by **root cause**, not by example — most will trace to a
  handful of shared mechanisms (the `CellVector(() -> […])` whole-vector rebuild
  in the template engine; any projection that re-derives all siblings; selection
  cells that pull on structure they shouldn't). Fixing one mechanism clears many
  examples, exactly as in
  [plan/pending/test-suite-green.md](test-suite-green.md).
- [ ] Cross-check the central engine directly with unit tests on
  `ProjectionTemplate` (dimensions A/B/C against a small synthetic node), since
  it backs almost every printer.

## Phase 4 — Fixes vs. justified exceptions

For each root-cause bucket decide: **fix** (tighten the dependency graph) or
**document as a justified exception**.

Likely **fixes**:
- [ ] **Selection isolation (A).** Anywhere a selection write transitively
  invalidates a value/structure cell, sever the dependency: a node's selection
  cell should depend on `doc.selection` and on the *minimum* of `child_iomaps`
  needed to resolve the path (ideally only the targeted child's selection cell),
  not the whole children vector. This is the highest-priority fix — it is the
  case the user named and the one with the clearest "must hold".
- [ ] **Structural minimality (C).** Replace the whole-vector rebuild with
  **keyed reconciliation**: key child iomaps by the element document object
  (`objectid` of the `@document` struct, which survives an edit to a *different*
  element) and reuse the existing child iomap when the same element object
  reappears, projecting only genuinely new elements. Implement once in
  `_node_print` / `_mixed_print` / `_sections_print` so every template projection
  inherits it. Guard the engine invariant that child iomaps are stored in a
  single shared `Cell` (selection deep dive §8).

Likely **justified exceptions** (must be written down, with the reason):
- [ ] **Layout that genuinely depends on all siblings.** `WordWrapping`,
  table column-width fitting, constraint/anchored layout, and graph layout
  recompute globally *by definition* — a change to one element legitimately
  re-flows the rest. Mark these dimension-C-exempt and record *why* (the output
  geometry is a function of the whole sibling set), and still hold them to
  dimensions A and B.
- [ ] **`SyntaxNodeToText` flattening.** Its non-local rebuild is a known,
  separately-tracked structural defect — see
  [plan/pending/syntaxtotext-delegation.md](syntaxtotext-delegation.md). Note the
  overlap; the delegation refactor there is a prerequisite for SyntaxToText
  structural locality, so reference it rather than duplicating the fix.
- [ ] Any other exception requires a one-line justification in the audit table.
  "It's simpler" is not a justification; "the output is a pure function of all
  siblings" is.

## Phase 5 — Lock it in

- [ ] Promote the passing checks into the suite as `test_printer_locality(ex)` /
  `test_printer_localities()`, mirroring `test_printer` / `test_printers`
  ([documentation/testing.md](../../documentation/testing.md)), emitting one
  `@test` per (example, dimension, mutation) unit so the pass count reflects the
  work and a regression names the offending cell.
- [ ] Encode the **exception list** as data the test consults (example +
  dimension → justification string), so a newly non-local printer fails unless
  it is explicitly justified — the check defends locality going forward.
- [ ] Document the principle in
  [documentation/projection-system.md](../../documentation/projection-system.md)
  (a "Locality: smallest possible output change" subsection next to the
  recursion principle) and in the `projection_print` docstring
  ([package/kernel/src/api/ProjectionApi.jl](../../package/kernel/src/api/ProjectionApi.jl)):
  state the selection-isolation rule, the keyed-reconciliation expectation for
  collections, and that exceptions must be justified.

## Verification (run the narrowest covering test, never `test_all`)

- [ ] `test_cell()` first — the harness leans on `isuptodate` / `perf_counters`.
- [ ] Build the harness against one example by hand
  (`printer_locality_report(json_example.document, json_example.projection, …)`)
  before sweeping.
- [ ] Per-fix: the targeted projection test (`test_json_to_syntax()`,
  `test_syntax_to_text()`, `test_copying_projection()`, …) plus
  `test_printer_locality(<that example>)`.
- [ ] After the engine fix (C): `test_example(json_example)` and
  `test_example(xml_example)` (printer + reader + nav + repl) to confirm keyed
  reconciliation did not change *behavior*, only locality, and a
  `test_text_navigation(…; check_reaches_all=true)` to confirm every caret is
  still reachable.
- [ ] Only after the targeted tests pass, a broad `test_printer_localities()`
  sweep for regressions.

## Risks / open questions

- **Identity vs. value.** Dimension C asks output *objects* to survive an edit
  elsewhere. Confirm downstream projections actually key off object identity
  (cell reuse) and not value, or the identity-preservation win is invisible.
- **Selection cell ↔ structure coupling.** Tightening A (selection cell must not
  pull on the whole children vector) without breaking the forward-map's ability
  to resolve a path into a child is the subtle part — the dependency must be on
  the *target child's* selection, resolved lazily, not the vector.
- **Write-driven engine.** Because there is no equality check, even a "minimal"
  recompute that lands on an unchanged value still propagates. Locality is about
  *graph shape*, not value diffing; do not expect value-stabilisation to save a
  badly-shaped dependency.
- **Keyed reconciliation correctness.** Keying by element `objectid` assumes the
  document mutates elements in place (it does — see the "incremental write"
  assertions in
  [JsonToSyntaxTest.jl:101](../../package/test/src/projection/JsonToSyntaxTest.jl#L101)
  and [XmlToSyntaxTest.jl:83](../../package/test/src/projection/XmlToSyntaxTest.jl#L83)).
  Verify operations never replace an unchanged element with a fresh equal object,
  which would defeat the key.
</content>
</invoke>
