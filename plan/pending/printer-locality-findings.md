# Printer locality — static audit findings (Phase 3, partial)

> **Status.** These findings are from **reading the code**, not from running the
> Phase 1 harness — the environment this was authored in had no Julia toolchain,
> so the dynamic sweep over `examples` (the full Phase 3 audit table) is still
> pending. Each finding is anchored to file:line so it can be confirmed by
> running `printer_locality_report` / `report_structural_locality` against the
> named example. Treat the dimension verdicts as **predictions to confirm**.

The central object is the template engine
[ProjectionTemplate.jl](../../package/domain/src/projection/ProjectionTemplate.jl),
which backs almost every printer (`@projection_template`): Json/Xml/Math/Book/Sql
→ Syntax, the generic `CopyingProjection`/`SortingProjection`, etc. Its locality
properties are inherited by all of them, so it dominates the audit.

## Finding 1 — Dimension A (selection isolation): engine is **clean** (predicted PASS)

A selection move writes input `:selection` cells (`set_selection!`,
[Operation.jl:423](../../package/kernel/src/common/Operation.jl#L423)). For the
template engine to be dimension-A clean, **no content cell may read
`doc.selection`.** Reading the builders confirms it:

- **Value cells** read only the bound field: `bound(:value, …, TextString(() ->
  string(doc.value), …))` and `hinted_text(() -> …, () -> isempty(doc.value), …)`
  ([JsonToSyntax.jl:61-77](../../package/domain/src/projection/primitive/JsonToSyntax.jl#L61)).
  The thunks close over `doc.value`, never `doc.selection`.
- **Children cells** read the element documents through `child_iomaps[]`
  ([ProjectionTemplate.jl:283-303](../../package/domain/src/projection/ProjectionTemplate.jl#L283));
  the recursion reads each element's own fields, not the parent's selection.
- **Selection cells** are the only ones that read `doc.selection`
  ([ProjectionTemplate.jl:296,371,428,474,507](../../package/domain/src/projection/ProjectionTemplate.jl#L296))
  and are tagged `:selection`.

So a selection write invalidates only `:selection`-tagged output cells →
`explore_selection_locality` should report **no** non-selection cells for every
`@projection_template` projection whose output carries selection as a
`:selection` field (Json→Syntax, Xml→Syntax, …). The leaf fast path that
*shares* the raw input selection cell
([ProjectionTemplate.jl:271](../../package/domain/src/projection/ProjectionTemplate.jl#L271),
`bound_field === :value`) is the tightest possible and the gold standard.

**Confirm with:** `test_selection_locality(json_example)`,
`test_selection_locality(xml_example)`, `test_selection_locality(math_example)`.

**Known scope gap (not a violation):** a full pipeline to graphics
(`… → SyntaxToText → TextToGraphics`) lowers the caret into geometry cells that
are not named `:selection`, so the generic check will over-report on those
examples until a cursor-field allow-list is added. The structural-layer
projections above are the clean, in-scope cases.

## Finding 2 — Dimension C (structural minimality): engine is **non-local** (predicted FAIL, central)

This is the headline violation. When a collection's structure cell invalidates
(any insert/remove/reorder of an input element), the engine rebuilds the
**entire** children vector and re-projects **every** sibling:

- `child_iomaps = Cell(() -> [projection_printer_recurse(recursion, x, …) for x in coll])`
  ([ProjectionTemplate.jl:283](../../package/domain/src/projection/ProjectionTemplate.jl#L283))
  re-runs the whole comprehension, producing a **fresh iomap (and fresh output
  object) for every sibling**, not just the changed one.
- `children = CellVector(() -> [im.output for im in child_iomaps[]])`
  ([ProjectionTemplate.jl:303](../../package/domain/src/projection/ProjectionTemplate.jl#L303))
  routes through `CellVector(f::Function)`
  ([Collection.jl:46-50](../../package/kernel/src/document/Collection.jl#L46)),
  whose `elements` thunk is `() -> Cell[Cell(x) for x in f()]` — so **every slot
  cell is a brand-new `Cell`** on each recompute, even for unchanged siblings.

Both effects are *identity* churn, not *invalidation* — the old sibling objects
are orphaned, not marked invalid — which is exactly why the harness measures
dimension C by `lost_objects` (identity diff), not by the invalidation set.
`_mixed_print` ([:425](../../package/domain/src/projection/ProjectionTemplate.jl#L425))
and `_sections_print` ([:504](../../package/domain/src/projection/ProjectionTemplate.jl#L504))
have the same `CellVector(() -> …)` shape and the same defect.

The irony: the **document** side already has per-slot incrementality — a manual
`push!`/`insert!` on an input `CellVector` keeps every existing slot cell and
only reassigns `.elements`
([Collection.jl invariants](../../package/kernel/src/document/Collection.jl#L10-L21)),
so editing one element invalidates only that slot. The **output** side discards
that win by regenerating the whole vector from a single computed thunk.

**Confirm with:** `report_structural_locality(json_example)` — predict
`lost ≈ total` (nearly all output objects rebuilt) when one array element /
object entry is appended.

**Candidate fix (Phase 4):** keyed reconciliation — key child iomaps by the
element document `objectid` (stable across edits to *other* elements; see the
"incremental write" assertions at
[JsonToSyntaxTest.jl:101](../../package/test/src/projection/JsonToSyntaxTest.jl#L101)),
reuse the existing child iomap + slot cell when the same element reappears, and
project only genuinely new elements. Implement once in `_node_print` /
`_mixed_print` / `_sections_print` so every template projection inherits it.

## Finding 3 — `tokens(...)` inline nodes rebuild all leaves per recompute (predicted FAIL, narrow)

`_inline_print`'s children cell is `CellVector(() -> begin leaves = thunk(); …
strip markers …; leaves end)`
([ProjectionTemplate.jl:459-471](../../package/domain/src/projection/ProjectionTemplate.jl#L459)).
The `thunk()` rebuilds the whole token-leaf vector on every recompute, so any
dependency change regenerates all decorative + bound leaves (fresh objects).
Narrower than Finding 2 (token nodes are small and few), but the same identity
churn. Decide in Phase 4 whether it is worth keying or is a justified exception
(token sets are tiny and recomputed wholesale by design).

## Finding 4 — Justified-exception candidates (predicted, by design)

Dimension-C non-locality is *correct* where the output geometry is a pure
function of the whole sibling set — these should be marked dimension-C-exempt
with the reason recorded, and still held to dimensions A and B:

- `WordWrapping`, table column-width fitting, constraint / anchored layout, graph
  layout — a change to one element legitimately re-flows the rest.
- `SyntaxNodeToText` flattening — a separately-tracked structural defect
  ([syntaxtotext-delegation.md](syntaxtotext-delegation.md)); its delegation
  refactor is a prerequisite for SyntaxToText structural locality. Reference it
  rather than duplicating the fix here.

## What still needs a runtime (the rest of Phase 3)

- Run `explore_selection_locality` over all ~90 `examples` and record the
  pass/fail/exception table (Finding 1 predicts the structural layers pass; the
  graphics pipelines need the allow-list).
- Run `report_structural_locality` over all collections and record the
  `lost/total` ratios (Finding 2 predicts ≈100% churn engine-wide).
- Add the dimension-B (value-edit) driver and confirm sibling isolation
  (Finding 1's value-cell reading predicts it is already local).
- Build the cursor-field allow-list so dimension A is exact for graphics
  pipelines.
</content>
