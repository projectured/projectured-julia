# Navigation reaches all possible selections

Rename the text-selection navigation suite and extend both navigation suites so
they no longer just check "navigation never errors", but also **pre-collect the
complete set of possible selections directly from the editor's document** and
assert that **navigation can reach all of them**.

## Context

Two BFS-based suites today explore selection states by pressing navigation keys
from a seed and asserting only that *no reader/printer errors occur*:

- [test/src/editor/SelectionTest.jl](../../test/src/editor/SelectionTest.jl) —
  `explore_selections` / `test_selection` / `test_selections`. Plain arrows +
  Home/End + Ctrl+Home/End, reaching **text caret** selections
  (`…value{k}` positions).
- [test/src/editor/SyntaxTreeNavigationTest.jl](../../test/src/editor/SyntaxTreeNavigationTest.jl) —
  `explore_tree_selections` / `test_tree_navigation` / `test_tree_navigations`.
  Ctrl+Alt+Home seed + Alt+arrows, reaching **structural / whole-element**
  selections (`∅` at each node).

Neither verifies *coverage*: a navigation bug that makes some positions
unreachable would pass today. [TableNavigationTest.jl](../../test/src/projection/TableNavigationTest.jl)
already pairs enumeration with navigation in spirit; this plan brings the same
idea to the generic text and syntax suites.

Both BFS loops already key visited states by `string(path)` and return
`(state_count, errors)`. Selection descent in
[Operation.jl:367](../../program/src/common/Operation.jl#L367) (`set_selection!`)
and [Reference.jl:422](../../program/src/reference/Reference.jl#L422)
(`evaluate_reference`) descends a node by exactly two moves:
`FieldReference` → `getfield`/unwrap-`Cell`; `RangeReference` →
`document[idx]` (requires `length`/`getindex`, i.e. `CellVector` or a `String`).
The new enumerators must mirror **only** these two moves so their generated path
strings are byte-identical to what `projection_read` returns.

## Decisions (confirmed)

- **Check direction: subset.** Assert `enumerated ⊆ reachable` — navigation must
  reach *at least* every enumerated selection. Extra reachable states
  (projection-introduced delimiter positions via `ProjectionReference`, etc.) are
  allowed.
- **Scope: a curated subset per kind**, not every example. Keep the existing
  no-error BFS over the full example list; add the completeness assertion only to
  representative examples known to expose all their content.
- **Numbers: ignored in phase 1.** Enumerate caret positions only over `String`
  leaves. Numeric leaves are skipped for now (revisit later: caret positions over
  the printed numeric representation).
- **Text selections = carets only.** For each navigable `String` leaf of length
  `n`, enumerate `PositionReference` cursors `{0}…{n}`. No character ranges
  (plain-arrow navigation produces carets, not ranges, so ranges could never
  satisfy the subset check).
- **Structural selections = whole-element `∅` at every document node.** Per
  [[whole-element-selection]], a whole-element selection is just the path
  terminating *at* the node (no marker step).

## Phase 1: Rename SelectionTest.jl → TextNavigationTest.jl

Pure rename + call-site churn, no behavior change yet. (Only the former file is
renamed; `SyntaxTreeNavigationTest.jl` keeps its name.)

- `git mv test/src/editor/SelectionTest.jl test/src/editor/TextNavigationTest.jl`.
- Rename internal functions to mirror the `Table*` naming
  (`explore_table_selections` / `test_table_navigation` / `test_table_navigations`):
  - `explore_selections` → `explore_text_selections`
  - `test_selection`      → `test_text_navigation`
  - `test_selections`     → `test_text_navigations`
- Update the file header comment to the new names/filename.
- Update call sites and exports:
  - [ProjecturedTest.jl](../../test/src/ProjecturedTest.jl):
    `include(...)` (line 53), `test_selections()` in `test_all` (line 124), and
    the exports (lines 158–160).
  - [ExampleTest.jl:6](../../test/src/editor/ExampleTest.jl#L6) —
    `test_selection(example)` inside `test_example`.
- Update docs that name these functions:
  [CLAUDE.md](../../CLAUDE.md) (lines 27, 40, 43, 45),
  [guide/testing.md](../../guide/testing.md) (lines 44, 58, 73, 89, 93, 102, 136,
  146), [guide/debugging.md:217](../../guide/debugging.md#L217),
  [guide/getting-started.md:87](../../guide/getting-started.md#L87).
  The comment at [JuliaToSyntax.jl:949](../../program/src/projection/primitive/JuliaToSyntax.jl#L949)
  mentions `test_selection(julia_example)` — update for accuracy.

Verify the rename compiles/loads (`test_text_navigation(text_example)`) before
moving on.

## Phase 2: Ground-truth enumerators

Add a small shared recursive walker that descends a document using *only* the
two canonical selection moves, so generated paths match navigation output. Place
it in a shared test helper (e.g. a new `test/src/editor/SelectionEnumeration.jl`
included before both nav-test files) and export the two public functions.

### Descent rule (shared)

For a node reached at `path`:

1. **Sequence containers** (`node isa CellVector`, and `String` leaves — the only
   types reached by `RangeReference` in `set_selection!`): index by element.
   - For a `CellVector`: for `i in 1:length(node)`, recurse into `node[i]` with
     `append_reference(path, RangeReference(i-1, i))` (`[i]`).
   - A `String` is handled by its *parent field* (see below), not descended into.
2. **Record structs** (everything else with `Cell` fields): for each field `f`
   that is a `Cell` (skip `:selection`), unwrap `v = cell[]` and:
   - `v isa AbstractString` → it's a text leaf at `path.f`;
   - `v isa Number` → skip (phase 1);
   - otherwise (a sub-document / container) → recurse with
     `append_reference(path, FieldReference(string(f)))`.

This distinguishes the `CellVector`-indexing case (`.elements[i]`) from the
record-descent case (`.elements` → `CellVector`), which is exactly why the
generic `_search_document` walker in
[Reference.jl:594](../../program/src/reference/Reference.jl#L594) is *not* reused
(it double-descends into a `CellVector`'s internal `elements` field and produces
non-canonical paths).

### `collect_text_selections(document) -> Vector{ReferencePath}`

Walk with the rule above. At every text leaf (`String` cell at `path.f`), emit
`append_reference(path, FieldReference(f), PositionReference(k))` for
`k in 0:length(string)` — the `{0}…{n}` carets.

### `collect_tree_selections(document) -> Vector{ReferencePath}`

Walk with the rule above. At every node where `hasproperty(node, :selection)`
(the `Document` predicate used by `set_selection!`), emit `path` itself — the
whole-element `∅` selection at that node (root included → `EmptyReferencePath()`).

### Safety net

Filter every emitted candidate through the document-aware
`is_valid_reference(document, path)`
([Reference.jl:506](../../program/src/reference/Reference.jl#L506)) so a
structurally-broken candidate never enters the ground-truth set. (Validity is
necessary but not sufficient for reachability — see Phase 4.)

## Phase 3: Wire enumeration into the completeness assertions

Both BFS explorers must expose the *set of visited path strings* (today they
return only `state_count`). Add a `visited` field to the returned NamedTuple
(`(state_count, errors, visited)`), where `visited::Set{String}` is the existing
local set.

Add a completeness helper used by both suites:

```
function _assert_reaches_all(label, enumerated, visited)
    missing = [string(p) for p in enumerated if !(string(p) in visited)]
    isempty(missing) || @warn "[$label] unreached" missing
    @test isempty(missing)
end
```

### Text suite (TextNavigationTest.jl)

Add `test_text_navigation_complete(example)`:
1. `result = explore_text_selections(doc, proj)`
2. `enumerated = collect_text_selections(doc)`
3. `_assert_reaches_all(example.name, enumerated, result.visited)` plus the
   existing no-error assertions.

Wire a `@testset` over a **curated subset** — start with `text_example`,
`json_example`, `xml_example`, `syntax_example`. Add a
`test_text_navigations_complete()` runner; call it from `test_all` (alongside or
in place of the broad `test_text_navigations()`).

### Syntax suite (SyntaxTreeNavigationTest.jl)

Add `test_tree_navigation_complete(example)` mirroring the above with
`explore_tree_selections` + `collect_tree_selections`, over the syntax-capable
curated subset (e.g. `json_example`, `xml_example`, `syntax_example`,
`math_example`) — drawing from the set already not skipped by
`test_tree_navigations`. Add a `test_tree_navigations_complete()` runner and call
it from `test_all`.

## Phase 4: Reconcile enumeration with navigation

The subset assertion will surface real discrepancies — for each, triage whether
it is an **enumeration bug** (we listed a position navigation legitimately can't
reach) or a **navigation gap** (a position that *should* be reachable but isn't).

Likely cases to expect and decide on:

- **Empty delimiters / zero-length strings** (e.g. a `SyntaxLeaf` `open`/`close`
  of length 0): enumeration yields a lone `{0}`; navigation may never land an
  independent caret there. If genuinely non-navigable, exclude such fields from
  the text enumerator (document the reason inline).
- **Projection-hidden or reordered content** (why filtering/sorting/word-wrapping
  examples are kept out of the curated set): if a curated example trips this,
  either narrow the enumerator or drop the example from the completeness set with
  a comment.
- **Structural nodes that are not independently selectable** in tree navigation:
  if a `hasproperty(:selection)` node is never reached by Alt+arrows, confirm
  whether that is a navigation gap worth filing or an enumeration over-reach.

Record the outcome of each discrepancy inline in the test (a comment naming why a
field/example is excluded) so the curated set's boundaries are self-documenting.
A genuine navigation gap should be noted here in the plan as a follow-up rather
than silently excluded.

## Testing

Per repo convention, run the narrowest scope:

- Phase 1: `test_text_navigation(text_example)` (load + rename sanity).
- Phases 2–4: `test_text_navigation_complete(text_example)` and
  `test_tree_navigation_complete(syntax_example)`, expanding to each curated
  example. Use the `explore_*` / `collect_*` return values directly in the REPL
  to inspect the `missing` set while reconciling.
- Final sweep: `test_text_navigations_complete()` + `test_tree_navigations_complete()`.

## Out of scope (later phases)

- Numeric-leaf caret enumeration.
- Character-range selections (would require shift-select navigation keys).
- Extending the completeness assertion to the full example list (filtering /
  sorting / word-wrapping / collapse projections).
