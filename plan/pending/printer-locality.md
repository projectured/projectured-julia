# Check (and enforce) printer locality

> **Status (2026-08-12): IN PROGRESS.** The harness (Phase 1-2), the audit
> (Phase 3, partial), and both headline fixes (Phase 4) reached `main` —
> `package/projectured/test/editor/PrinterLocalityTest.jl` (561 lines) and the
> generic keyed-reconciliation engine `package/kernel/main/iomap/IoMapReconcile.jl`
> both exist and are exercised by `test_all()`. The branch name in
> [printer-locality-session-log.md](printer-locality-session-log.md),
> `claude/printer-locality-plan-rbzmq5`, no longer exists, but its work is on
> `main`. What remains: the full A/B sweep across all ~90 examples is written
> (`test_selection_localities`, `test_value_localities`) but not wired into
> `test_all` — it still fails wholesale on full-pipeline (graphics) examples, the
> "known scope gap" the plan predicted; keyed reconciliation covers `_node_print`
> only, not `_mixed_print`/`_sections_print`; and Phase 5's exception-list-as-data
> and `test_printer_locality` naming were not done. See the box-by-box notes below.
>
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
([package/kernel/main/cell/ReactiveCell.jl](../../source/kernel/cell/ReactiveCell.jl))
is **pull-based and write-driven with no equality check** (see
[package/kernel/doc/cell.md](../../documentation/package/kernel/cell.md), the
"Propagation is write-driven, not value-driven" invariant): writing a cell
unconditionally invalidates the transitive closure of its dependents, and a
thunk that recomputes to an unchanged value does **not** stop propagation. So
the only lever for "smallest possible change" is the **shape of the dependency
graph the printer builds** — a printer achieves locality by making a minimal
input write reach a minimal set of output cells, and by preserving the
*identity* of output objects whose inputs did not change so downstream
projections (SyntaxToText → TextToGraphics → layout) don't re-do work.

The editor reprints every frame and resets its performance counters each loop
([package/kernel/main/editor/Editor.jl](../../source/kernel/editor/Editor.jl)),
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
  as a `ComputedCell(() -> map_selection_forward(doc, path -> map_reference_forward(p, im, path)))`
  in each of `_node_print`/`_fixed_print`/`_mixed_print`/`_inline_print`/`_sections_print`
  ([package/kernel/main/projection/ProjectionTemplate.jl](../../source/kernel/projection/ProjectionTemplate.jl)
  — line numbers shifted with the rewrite; grep the file for `_with_selection`),
  which reads `doc.selection` **and**, through the deferred `iomap_cell`, the
  target child's iomap. Reading the child iomap makes the selection cell depend
  on the children *structure*; that is fine in the A→B direction (a structure
  change may invalidate the selection) but the audit must confirm the **reverse
  does not happen**: a selection write must not transitively reach any child
  output cell. **Confirmed clean** at the syntax layer: a direct run of
  `test_selection_locality` against `RecursiveProjection(JsonToSyntax())` passed
  160/160 (2026-08-12, see the status banner). The leaf fast path that *shares*
  the raw selection cell (`wiring.bound_field === :value` branch of the same
  file) is the gold standard — confirmed it stays that tight.

### B. Value-edit isolation
Editing one leaf's value (`leaf.value = …`, e.g. a `StringReplaceRangeOperation`
landing on one JSON string) must invalidate only that leaf's value/text cell and
the strictly-derived cells above it (the span that contains it, the line it lays
out on) — **not sibling leaves, not sibling subtrees.**

- Model already verified for SyntaxToText:
  [SyntaxToTextTest.jl:24-27](../../test/substrate/projection/SyntaxToTextTest.jl#L24)
  asserts the spans-structure cell stays `is_cell_up_to_date` across a value
  change. Generalised to every leaf in every example by
  `explore_value_locality`/`test_value_locality` in
  `package/projectured/test/editor/PrinterLocalityTest.jl` — confirmed as an
  **assertion** (`lost_objects == 0`), not just a report, matching the "predicted
  CLEAN" call below.

### C. Structural-edit minimality (the hard one)
Inserting / removing / reordering **one** element of a collection must:

- rebuild the changed slot and the structural envelope (open/sep/close, indices
  that genuinely shifted), and
- **preserve the output objects of the unaffected siblings** (cell identity), so
  downstream layout reuses them.

- **Central violation — fixed for `_node_print`, still open for two siblings.**
  The template engine used to build children as
  `child_iomaps = Cell(() -> [projection_printer_recurse(recursion, x, …) for x in coll])`
  and `children = CellVector(() -> [im.output for im in child_iomaps[]])`, so any
  structural edit re-projected **every** sibling from scratch. **As of
  2026-08-12**, `_node_print`
  ([ProjectionTemplate.jl:440-467](../../source/kernel/projection/ProjectionTemplate.jl#L440))
  calls `reconcile_child_iomaps`
  ([IoMapReconcile.jl](../../source/kernel/iomap/IoMapReconcile.jl)), which
  keys the cache by `(objectid(element), index)` and reuses the prior child iomap
  for every unchanged sibling — confirmed by `test_template_structural_locality()`
  (JSON collections orphan ≈1% of output objects on insert, down from ≈97%).
  **`_mixed_print`** ([:593-637](../../source/kernel/projection/ProjectionTemplate.jl#L593))
  and **`_sections_print`** ([:696-720](../../source/kernel/projection/ProjectionTemplate.jl#L696))
  still build their `coll_iomaps` / `section_iomaps` with a plain
  `ComputedCell(() -> [… for … in …])` comprehension — **not** reconciled — so
  they retain the original defect. This is the highest-value remaining Phase 4
  item.

## Phase 1 — Measurement harness

Add a locality walker beside the existing test walkers (sibling of
`walk_printer_output` in
[package/kernel/test/editor/PrinterTest.jl](../../test/kernel/editor/PrinterTest.jl);
see [documentation/testing.md](../../documentation/testing.md) "walker helpers").

**Landed** as `package/projectured/test/editor/PrinterLocalityTest.jl` (561 lines).
The signature and internals differ from the sketch below in ways that still meet
the intent — noted inline.

- [x] `printer_locality_report(doc, proj, mutate!; expect)` that:
  1. prints (`projection_print(proj, doc)`), reflexively forces every reachable
     `Cell` (reuse `_walk!`), and snapshots, per cell, `objectid` →
     `isuptodate`; also snapshot output-object identities (`objectid` of every
     reachable `@document` struct).
  2. runs `perf_reset!()`, applies `mutate!(doc)` (a selection / value /
     structural edit), forces every reachable cell again.
  3. returns a report: the set of cells that recomputed, the set of output
     objects whose identity changed, and the `perf_counters()` delta
     (`:computes`, `:invalidations`).

  Built as `printer_locality_report(document, projection, mutate!)` — no `expect`
  kwarg; each dimension has its own `explore_*`/`test_*` driver instead (see
  Phase 2). Uses `with_performance_counters() do … end` scoping rather than a
  global `perf_reset!()`. All three numbered sub-steps are present:
  `_collect_locality!` reflexively forces every cell and snapshots identity;
  `mutate!` runs inside the scoped counters; the returned `LocalityReport` carries
  invalidated cells, `preserved_objects`/`lost_objects`, and the `perf` delta.
- [x] Express expectations as predicates over the report (`expect`): e.g.
  `only_selection_cells_changed`, `siblings_identity_preserved(i)`,
  `no_structure_cells_invalidated`. Return `(ok, message)` per check, in the
  `Vector{String}`-of-errors style the other walkers use so it runs in the REPL
  and keeps going on failure.

  Built as per-dimension predicates (`is_selection_cell`,
  `_is_selection_overlay_cell`, `_is_router_rebuild_cell`) filtered inside each
  `explore_*` function, not a single named `expect` library, but the same
  `(ok, message)` / `Vector{String}`-of-errors shape is there.
- [x] To classify a recomputed cell as "selection vs. value vs. structure",
  tag cells by the field they back. The `@document`/`@iomap` getproperty layer
  already routes through named fields; have the walker record the field name and
  owning struct type when it forces `getfield(obj, :selection)` vs. other
  fields, so a report can say *which* cells moved.

  `struct LocalityCell` carries `cell`, `owner` (the struct type), and `field`
  exactly as specified.

## Phase 2 — Mutation generators

Reuse the selection enumerators already in the suite
([SelectionEnumeration.jl](../../test/substrate/document/SelectionEnumeration.jl):
`collect_position_selections`, `collect_tree_selections` — the actual names;
there is no `collect_text_selections`) to drive dimension A exhaustively, and
derive value/structural edits from the document structure.

- [x] **A (selection):** for each enumerated selection, `set_selection!` to it
  from a different selection and assert dimension-A expectations. Also the
  `clear → set` and `set → clear` transitions.

  Built as `explore_selection_locality`, driving `collect_position_selections`
  and mutating with `replace_selection!` — the editor's real caret-move fast
  path — rather than `set_selection!` (a deliberate choice recorded in the
  function's docstring: `set_selection!` is a from-scratch re-walk that never
  happens on a real caret move, so measuring it would flag unchanged routing
  ancestors as false positives). Does not separately drive `clear ↔ set`
  transitions.
- [x] **B (value):** for each reachable leaf with an editable bound field
  (reuse `walk_typein`'s reachability,
  [TypeinTest.jl](../../test/substrate/editor/TypeinTest.jl)), write a
  new value and assert only that leaf's cell + strict ancestors moved.

  Built as `explore_value_locality` / `_find_input_value_leaves` — its own
  walker (String/Real/Bool `:value` fields), not a reuse of `walk_typein` — and
  asserts the stronger, cleaner invariant `lost_objects == 0` (no output object
  rebuilt) rather than enumerating which ancestors are allowed to move.
- [ ] **C (structural):** for each reachable collection, generate
  insert-at-end, insert-in-middle, remove, and swap-two edits; assert the
  unaffected siblings keep identity.

  Built as `explore_structural_locality` / `_find_input_collections`, but only
  the insert-at-end mutation (`push!(cv, cv[1])`, restored after) — no
  insert-in-middle, remove, or swap-two generators exist yet. It reports
  `lost`/`preserved`/`total` rather than asserting per-sibling identity
  directly; `test_template_structural_locality`/`test_graphics_structural_locality`
  turn that report into a `< 5%` / `< 20%` threshold assertion (see Phase 5).

## Phase 3 — Audit sweep and classification

- [ ] Run the harness over every entry in `examples` (~90; see
  [package/projectured/example/Examples.jl](../../example/projectured/Examples.jl)),
  three dimensions each. Produce a table: example × dimension × {pass, fail,
  exception-candidate} with the offending cell/object named on failure.

  `test_selection_localities()` / `test_value_localities()` (in
  `PrinterLocalityTest.jl`) already loop over the full `examples` registry and
  would produce exactly this, but **running them today fails wholesale**: a
  direct run against `json_example` (the full `JsonToSyntax → SyntaxToText →
  WordWrapping → TextToGraphics` pipeline, confirmed 2026-08-12) gives 0/176
  pass on both dimensions — the documented "known scope gap" (caret lowered into
  un-tagged `Graphics*` geometry cells). No audit table has been produced; these
  two functions are not wired into `test_all` for this reason. Confirmed clean at
  the syntax layer alone (`RecursiveProjection(JsonToSyntax())`): 160/160 (A),
  15/16 (B, one violation found and not yet triaged).
- [ ] Bucket failures by **root cause**, not by example — most will trace to a
  handful of shared mechanisms (the `CellVector(() -> […])` whole-vector rebuild
  in the template engine; any projection that re-derives all siblings; selection
  cells that pull on structure they shouldn't). Fixing one mechanism clears many
  examples, exactly as in
  [plan/pending/test-suite-green.md](test-suite-green.md).
- [x] Cross-check the central engine directly with unit tests on
  `ProjectionTemplate` (dimensions A/B/C against a small synthetic node), since
  it backs almost every printer.

  Done for dimension C: `test_template_structural_locality()` measures
  `RecursiveProjection(JsonToSyntax())` directly (not a synthetic node, a real
  JSON example, to isolate the template engine from downstream render layers) and
  is wired into `test_all` via `test_projections()`. Dimensions A/B are exercised
  against the template engine only via the ad hoc syntax-layer run noted above,
  not as a standing test.

## Phase 4 — Fixes vs. justified exceptions

For each root-cause bucket decide: **fix** (tighten the dependency graph) or
**document as a justified exception**.

Likely **fixes**:
- [x] **Selection isolation (A).** Anywhere a selection write transitively
  invalidates a value/structure cell, sever the dependency: a node's selection
  cell should depend on `doc.selection` and on the *minimum* of `child_iomaps`
  needed to resolve the path (ideally only the targeted child's selection cell),
  not the whole children vector. This is the highest-priority fix — it is the
  case the user named and the one with the clearest "must hold".

  The template engine itself was already clean here (Finding 1, confirmed
  160/160 above); the real violations were in the **widget layer**, and both
  landed: `fix(widget): WidgetTabPage Document so tabbed-pane selection is
  locality-clean` (commit `0c2423c6`) and `fix(widget): table & tree selection
  highlight as a persistent overlay` (commit `29b04eef`, which records "Widget
  selection-locality violations: 109 -> 7").
- [ ] **Structural minimality (C).** Replace the whole-vector rebuild with
  **keyed reconciliation**: key child iomaps by the element document object
  (`objectid` of the `@document` struct, which survives an edit to a *different*
  element) and reuse the existing child iomap when the same element object
  reappears, projecting only genuinely new elements. Implement once in
  `_node_print` / `_mixed_print` / `_sections_print` so every template projection
  inherits it. Guard the engine invariant that child iomaps are stored in a
  single shared `Cell` (selection deep dive §8).

  Landed as the generic `reconcile_child_iomaps`/`reconcile_child_iomap` in
  `package/kernel/main/iomap/IoMapReconcile.jl`, used well beyond the template
  engine (also `package/clipboard`, `package/pane`, `package/dragging`,
  `package/projection` Sorting/Copying, `package/syntax`, `package/workbench`,
  `package/screen`, `package/widget`). Inside `ProjectionTemplate.jl` it is wired
  into **`_node_print` only**; `_mixed_print` and `_sections_print` still use a
  plain `ComputedCell` comprehension and were not converted — this checkbox is
  therefore only partially done.

Likely **justified exceptions** (must be written down, with the reason):
- [ ] **Layout that genuinely depends on all siblings.** `WordWrapping`,
  table column-width fitting, constraint/anchored layout, and graph layout
  recompute globally *by definition* — a change to one element legitimately
  re-flows the rest. Mark these dimension-C-exempt and record *why* (the output
  geometry is a function of the whole sibling set), and still hold them to
  dimensions A and B.

  Not written down anywhere yet — no `dimension-C-exempt` marker or comment found
  near `WordWrapping.jl` or the layout/graph-layout packages.
- [x] **`SyntaxNodeToText` flattening.** Its non-local rebuild is a known,
  separately-tracked structural defect — see
  [plan/pending/syntaxtotext-delegation.md](../done/syntaxtotext-delegation.md). Note the
  overlap; the delegation refactor there is a prerequisite for SyntaxToText
  structural locality, so reference it rather than duplicating the fix.

  That plan is DONE and moved to
  [plan/done/syntaxtotext-delegation.md](../done/syntaxtotext-delegation.md):
  `SyntaxNodeToText`/`SyntaxListToText` now delegate every child through
  `print_child` (commit `03c72774`, "printer delegates children via recursion,
  splices element lists") instead of walking the input subtree. This directly
  feeds `test_graphics_structural_locality`'s "the text layer shares decorative
  whitespace spans" result.
- [ ] Any other exception requires a one-line justification in the audit table.
  "It's simpler" is not a justification; "the output is a pure function of all
  siblings" is.

  No such audit table exists yet (see Phase 3/5).

## Phase 5 — Lock it in

- [ ] Promote the passing checks into the suite as `test_printer_locality(ex)` /
  `test_printer_localities()`, mirroring `test_printer` / `test_printers`
  ([documentation/testing.md](../../documentation/testing.md)), emitting one
  `@test` per (example, dimension, mutation) unit so the pass count reflects the
  work and a regression names the offending cell.

  Partially done under different names, and only for dimension C. `test_selection_locality`
  / `test_value_locality` (one `@test` per caret/leaf) exist and are correctly
  shaped, but are not wired into `test_all` (Phase 3 scope gap above).
  `test_template_structural_locality()` / `test_graphics_structural_locality()`
  **are** wired into `test_all` (via `test_projections()` in
  `package/projectured/test/ProjecturedTest.jl`) and pass (22/22 assertions,
  confirmed 2026-08-12) — but as a per-collection `< 5%`/`< 20%` loss-ratio
  threshold, not a strict "zero lost siblings" assertion, and scoped to the JSON
  example rather than every example. No function named `test_printer_locality`
  exists.
- [ ] Encode the **exception list** as data the test consults (example +
  dimension → justification string), so a newly non-local printer fails unless
  it is explicitly justified — the check defends locality going forward.

  Not done. The exceptions that exist today (`_is_selection_overlay_cell`,
  `_is_router_rebuild_cell` in `PrinterLocalityTest.jl`) are hard-coded predicate
  functions, not a data table with per-example/per-dimension justification
  strings.
- [ ] Document the principle in
  [documentation/projection-system.md](../../documentation/package/kernel/projection-system.md)
  (a "Locality: smallest possible output change" subsection next to the
  recursion principle) and in the `projection_print` docstring
  ([package/kernel/src/api/ProjectionApi.jl](../../package/kernel/src/api/ProjectionApi.jl)):
  state the selection-isolation rule, the keyed-reconciliation expectation for
  collections, and that exceptions must be justified.

  Partially done, in different places than planned. There is no standalone
  "Locality" subsection in
  [package/kernel/doc/projection-system.md](../../documentation/package/kernel/projection-system.md)
  (the function is now called `print_document`, not `projection_print`, and its
  docstring lives in
  [package/kernel/main/projection/ProjectionApi.jl](../../source/kernel/projection/ProjectionApi.jl)),
  but `projection-system.md`'s "Purity" section covers reconciliation, and
  [documentation/architecture-requirements.md](../../documentation/architecture-requirements.md)
  states the rule formally as **PAR-STABLE-IOMAP-IDENTITY** ("its children
  reconcile by identity... goes through the shared reconciler... `reconcile_child_iomaps`
  (in the iomap layer)") and **PAR-SHARED-CHILDREN-IOMAP**. The exceptions-must-be-justified
  rule is not written down anywhere yet.

## Verification (run the narrowest covering test, never `test_all`)

- [x] `test_cell()` first — the harness leans on `is_cell_up_to_date` /
  performance counters. (`package/kernel/test/cell/CellTest.jl`.)
- [x] Build the harness against one example by hand
  (`printer_locality_report(json_example.document, json_example.projection, …)`)
  before sweeping. Done during this audit (2026-08-12): confirms the 176/176
  full-pipeline failure and the 160/160 (A) + 15/16 (B) syntax-layer result
  quoted above.
- [ ] Per-fix: the targeted projection test (`test_json_to_syntax()`,
  `test_syntax_to_text()`, `test_copying_projection()`, …) plus
  `test_printer_locality(<that example>)`. (No `test_printer_locality` function
  exists — see Phase 5.)
- [ ] After the engine fix (C): `test_example(json_example)` and
  `test_example(xml_example)` (printer + reader + nav + repl) to confirm keyed
  reconciliation did not change *behavior*, only locality, and a
  `test_position_navigation(…; check_reaches_all=true)` — the real function name;
  the plan's `test_text_navigation` does not exist — to confirm every caret is
  still reachable. Not run as part of this audit.
- [ ] Only after the targeted tests pass, a broad `test_printer_localities()`
  sweep for regressions. Cannot pass today — see the Phase 3 scope-gap note.

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
  [JsonToSyntaxTest.jl:101](../../test/json/projection/JsonToSyntaxTest.jl#L101)
  and [XmlToSyntaxTest.jl:83](../../test/xml/projection/XmlToSyntaxTest.jl#L83)).
  Verify operations never replace an unchanged element with a fresh equal object,
  which would defeat the key. This is exactly the assumption `reconcile_child_iomaps`
  now relies on in production (`package/kernel/main/iomap/IoMapReconcile.jl`).
</content>
</invoke>
