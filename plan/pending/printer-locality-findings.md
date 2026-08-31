# Printer locality — static audit findings (Phase 3, partial)

> **Status (2026-08-12): IN PROGRESS.** These findings were originally from
> **reading the code only** (no Julia toolchain in that session). A Julia
> toolchain is available now, and this audit confirmed both headline
> predictions with real runs: Finding 1 (dimension A clean at the syntax layer)
> — 160/160 selection-locality checks pass against
> `RecursiveProjection(JsonToSyntax())`; Finding 2 (dimension C non-local) — was
> true, and is now **fixed for `_node_print`** by keyed reconciliation
> (`reconcile_child_iomaps`, `test_template_structural_locality()` passes,
> ≈1% loss instead of ≈97%), but **still open for `_mixed_print` /
> `_sections_print`**, which were never converted. See
> [printer-locality.md](printer-locality.md) for the full status. The dynamic
> sweep over all ~90 `examples` (the full Phase 3 audit table this document was
> meant to seed) is still pending — it currently fails wholesale on full-pipeline
> examples, so it is not run as a matter of course.

The central object is the template engine
[ProjectionTemplate.jl](../../source/kernel/projection/ProjectionTemplate.jl),
which backs almost every printer (`@projection_template`): Json/Xml/Math/Book/Sql
→ Syntax, the generic `CopyingProjection`/`SortingProjection`, etc. Its locality
properties are inherited by all of them, so it dominates the audit.

## Finding 1 — Dimension A (selection isolation): engine is **clean** (CONFIRMED PASS, 2026-08-12)

A selection move writes input `:selection` cells (`set_selection!`,
[SelectionDefaults.jl:182](../../source/kernel/selection/SelectionDefaults.jl#L182)).
For the template engine to be dimension-A clean, **no content cell may read
`doc.selection`.** Reading the builders confirms it:

- **Value cells** read only the bound field: `bound(:value, …, hinted_text(() ->
  …, () -> …, …))` ([JsonToSyntax.jl:61-77](../../source/json/JsonToSyntax.jl#L61)).
  The thunks close over `doc.value`, never `doc.selection`.
- **Children cells** read the element documents through `child_iomaps[]`
  ([ProjectionTemplate.jl `_node_print`](../../source/kernel/projection/ProjectionTemplate.jl));
  the recursion reads each element's own fields, not the parent's selection.
- **Selection cells** are the only ones that read `doc.selection`, via
  `_with_selection(out, ComputedCell(() -> map_selection_forward(doc, …)))` in each
  of `_node_print`/`_fixed_print`/`_mixed_print`/`_inline_print`/`_sections_print`
  (`ProjectionTemplate.jl`) and are tagged `:selection`.

So a selection write invalidates only `:selection`-tagged output cells →
`explore_selection_locality` should report **no** non-selection cells for every
`@projection_template` projection whose output carries selection as a
`:selection` field (Json→Syntax, Xml→Syntax, …). The leaf fast path that
*shares* the raw input selection cell (`wiring.bound_field === :value` branch of
`ProjectionTemplate.jl`) is the tightest possible and the gold standard.

**Confirmed with:** a direct run (2026-08-12) of `test_selection_locality`
against `RecursiveProjection(JsonToSyntax())` — 160/160 pass, zero non-selection
cells invalidated. `test_selection_locality(json_example)` (the full pipeline,
not the syntax layer alone) does **not** pass — see the scope gap below, now
itself confirmed by measurement (0/176 on `json_example`, 2026-08-12).

**Known scope gap (not a violation):** a full pipeline to graphics
(`… → SyntaxToText → TextToGraphics`) lowers the caret into geometry cells that
are not named `:selection`, so the generic check will over-report on those
examples until a cursor-field allow-list is added. The structural-layer
projections above are the clean, in-scope cases. This gap is why
`test_selection_localities()`/`test_value_localities()` are still not wired
into `test_all` (see [printer-locality.md](printer-locality.md)).

## Finding 2 — Dimension C (structural minimality): engine was **non-local** (CONFIRMED, then fixed for `_node_print`; `_mixed_print`/`_sections_print` still open)

This was the headline violation. Before the fix, when a collection's structure
cell invalidated (any insert/remove/reorder of an input element), the engine
rebuilt the **entire** children vector and re-projected **every** sibling:

- `child_iomaps = Cell(() -> [projection_printer_recurse(recursion, x, …) for x in coll])`
  re-ran the whole comprehension, producing a **fresh iomap (and fresh output
  object) for every sibling**, not just the changed one.
- `children = CellVector(() -> [im.output for im in child_iomaps[]])`
  routed through the collection module's function-backed `CellVector`, whose
  `elements` thunk built a fresh `Cell` per element — so **every slot cell was a
  brand-new `Cell`** on each recompute, even for unchanged siblings.

Both effects are *identity* churn, not *invalidation* — the old sibling objects
are orphaned, not marked invalid — which is exactly why the harness measures
dimension C by `lost_objects` (identity diff), not by the invalidation set.
`_mixed_print` and `_sections_print`
([ProjectionTemplate.jl:593-720](../../source/kernel/projection/ProjectionTemplate.jl#L593))
still have the same `ComputedCell(() -> …)` shape and the same defect — they
were not converted when `_node_print` was fixed (see below).

The irony: the **document** side already has per-slot incrementality — a manual
`push!`/`insert!` on an input `CellVector` keeps every existing slot cell and
only reassigns `.elements`
([Collection.jl invariants](../../source/collection/Collection.jl#L11-L19)),
so editing one element invalidates only that slot. The **output** side used to
discard that win by regenerating the whole vector from a single computed thunk —
now fixed for `_node_print`, per below.

**Confirmed with:** `test_template_structural_locality()` (JSON, syntax layer):
before the fix, `lost ≈ total` (nearly all output objects rebuilt) when one array
element / object entry was appended; after the fix, `lost < 5%` — passes 22/22
(2026-08-12).

**Fix landed (Phase 4), partially:** keyed reconciliation — key child iomaps by
the element document `objectid` (stable across edits to *other* elements; see the
"incremental write" assertions at
[JsonToSyntaxTest.jl:101](../../test/json/projection/JsonToSyntaxTest.jl#L101)),
reuse the existing child iomap + slot cell when the same element reappears, and
project only genuinely new elements. Implemented as the generic
`reconcile_child_iomaps`/`reconcile_child_iomap` in
`package/kernel/main/iomap/IoMapReconcile.jl`, wired into **`_node_print` only**.
`_mixed_print` and `_sections_print` were not converted — every template
projection does **not yet** inherit the fix.

## Finding 3 — `tokens(...)` inline nodes rebuild all leaves per recompute (CONFIRMED, still open, narrow)

`_inline_print`'s children cell is `make_children_container(() -> begin
map(thunk()) do leaf … end end)`
([ProjectionTemplate.jl:649-681](../../source/kernel/projection/ProjectionTemplate.jl#L649)).
The `thunk()` still rebuilds the whole token-leaf vector on every recompute, so
any dependency change regenerates all decorative + bound leaves (fresh objects).
Narrower than Finding 2 (token nodes are small and few), but the same identity
churn. Not converted to keyed reconciliation — left as-is, matching the
"justified exception" reading (token sets are tiny and recomputed wholesale by
design), but that reading is not written down anywhere as a recorded exception.

## Finding 4 — Justified-exception candidates (still not written down)

Dimension-C non-locality is *correct* where the output geometry is a pure
function of the whole sibling set — these should be marked dimension-C-exempt
with the reason recorded, and still held to dimensions A and B:

- `WordWrapping`, table column-width fitting, constraint / anchored layout, graph
  layout — a change to one element legitimately re-flows the rest. No
  dimension-C-exempt marker found near any of these (2026-08-12 grep).
- `SyntaxNodeToText` flattening — was a separately-tracked structural defect;
  now **fixed and moved to done**: see
  [plan/done/syntaxtotext-delegation.md](../done/syntaxtotext-delegation.md).
  `SyntaxNodeToText`/`SyntaxListToText` now delegate every child through
  `print_child` (commit `03c72774`) instead of walking the input subtree.

## What still needs doing (the rest of Phase 3 and Phase 4)

A Julia toolchain is now available, so these are runnable, not blocked — the
remaining work is doing them and recording the results, plus the two
implementation gaps found:

- Run `explore_selection_locality` over all ~90 `examples` and record the
  pass/fail/exception table. Finding 1 is confirmed for the structural layers
  (160/160 at the syntax layer); the graphics pipelines fail wholesale (0/176 on
  `json_example`) until the cursor-field allow-list exists.
- Run `report_structural_locality` over all collections and record the
  `lost/total` ratios. Finding 2 is confirmed fixed for `_node_print`
  (`test_template_structural_locality` / `test_graphics_structural_locality`,
  22/22) but still ≈100% churn for any projection routed through `_mixed_print`
  or `_sections_print`.
- The dimension-B (value-edit) driver exists (`explore_value_locality`) and is
  mostly clean at the syntax layer (15/16 on `json_example`'s syntax layer,
  2026-08-12) — the one failure is untriaged.
- Build the cursor-field allow-list so dimension A is exact for graphics
  pipelines.
- Convert `_mixed_print` / `_sections_print` to `reconcile_child_iomaps`, the
  remaining half of Finding 2's fix.
</content>
