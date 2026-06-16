# SQL Selection Support

## Status

All projections in `SqlToSyntax.jl` now have full selection wiring. This file
records the **patterns** that emerged so future SQL constructs can be added
consistently.

### Completed ✅

| Projection | Type | Notes |
|---|---|---|
| `SqlAllColumnsToSyntaxLeaf` | Leaf | shared `doc.selection` |
| `SqlColumnReferenceToSyntaxLeaf` | Leaf | shared `doc.selection` |
| `SqlTableExpressionToSyntaxLeaf` | Leaf | shared `doc.selection` |
| `SqlScalarValueToSyntaxLeaf` | Leaf | shared `doc.selection` |
| `SqlJoinTypeToSyntaxLeaf` | Leaf | no `selection` field on input — `∅` only; display via `_join_type_display` (fully qualified: `INNER JOIN`, `LEFT OUTER JOIN`, …) |
| `SqlSelectStatementToSyntaxNode` | Node | reference impl (was already correct) |
| `SqlSelectClauseToSyntaxNode` | Node | items list through comma-body; dynamic body index (DISTINCT) |
| `SqlSelectItemToSyntaxNode` | Node | single child; optional AS/alias are proj-introduced |
| `SqlJoinedFromItemToSyntaxNode` | Node | two or three direct children (join_type, from_item, optional condition) |
| `SqlJoinOnConditionToSyntaxNode` | Node | `ON` keyword + expression inline (space-separated); expression at children[2] |
| `SqlWhereFilterConditionToSyntaxNode` | Node | transparent container; expression at children[1] (empty open/close/separator) |
| `SqlNotToSyntaxNode` | Node | keyword prefix; expression at children[2] |
| `SqlBooleanBinaryToSyntaxNode` | Node | keyword gap; left→[1], right→[3] |
| `SqlComparisonToSyntaxNode` | Node | same as BooleanBinary |
| `SqlWhereClauseToSyntaxNode` | Node | optional child; two-level path through newline-body |
| `SqlFromClauseToSyntaxNode` | Node | items list through comma-body; body always at pos 2 |
| `SqlSubqueryFromItemToSyntaxNode` | Node | subquery two-level deep through paren-node |
| `SqlFromItemToSyntaxNode` | Node | base + optional joins; index offset in child_iomaps |

---

## Patterns for new SQL projections

### Leaf projection (shared-cell trick)

Use when `doc` and `SyntaxLeaf` have the same selection semantics (∅ = whole
element, nothing = unselected). Pass `doc.selection` directly as the leaf's
`selection` argument — no mapper work required.

```julia
SimpleIoMap(p, doc, SyntaxLeaf(..., doc.selection))
```

Reference mappers: `∅ => @reference()` only; `projection_read` returns `nothing`.

If the input document has **no `selection` field** (e.g. enum-like types), use
`Cell(nothing)` for the leaf selection and keep the same stub mappers.

---

### Node projection — standard template

Every node projection follows this template, varying only the child_iomaps
construction and the mapper arms.

```julia
function projection_print(p::MyProjection, recursion, doc::MyDoc, ctx)
    # 1. Project children reactively
    child_im = Cell(() -> projection_print(recursion, recursion, doc.field,
                                           child_context(ctx, FieldReference("field"))))
    # ... more children as needed

    # 2. Build child_iomaps Cell (vector of iomaps, index = child_iomaps index)
    child_iomaps_cell = Cell(() -> Any[child_im[]])   # or Any[a[]; b_list[]; ...]

    # 3. Deferred-iomap trick
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    # 4. Full SyntaxNode constructor — pass sel as last arg
    node = SyntaxNode(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(" ", p.font, color_default),   # sep matches layout intent
        CellVector(() -> SyntaxDocument[...]),
        0, Cell(false), sel)

    # 5. Close the deferred loop
    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end
```

`projection_read` is always the same body:

```julia
function projection_read(p::MyProjection, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end
projection_read(::MyProjection, iomap::ChildrenIoMap, op) = nothing
```

---

### Reference mapper patterns

All `map_reference_forward` functions for node projections **must** start with
these two arms before any field arms:

```julia
∅ => @reference()
proj(^(p), _) => reference   # pass-through cursor/flat positions
```

The `proj` arm is required because `projection_read`'s `_syntax_to_flat`
fallback stores `ProjectionReference(p, PositionReference(flat))` in the input
doc's selection. The reactive `sel` cell calls `map_reference_forward` with
that path; without the `proj` arm it falls through to `nothing` and the cursor
disappears from the output. `JsonArrayToSyntaxNode` has this arm; all SQL
projections were initially missing it.

All patterns use `child_i = s + 1` to convert 0-based `RangeReference.start`
to a 1-based Julia index. `@reference children[N]` builds
`FieldReference("children") + RangeReference(N-1, N)`.

#### Direct child at position N

```julia
# child_iomaps[][cim_idx] → output children[N]
field.rest... => begin
    child = iomap.child_iomaps[][cim_idx]
    inner = map_reference_forward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference children[N].^(inner)
end
# backward:
children[N].rest... => begin
    child = iomap.child_iomaps[][cim_idx]
    inner = map_reference_backward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference field.^(inner)
end
```

#### Proj-introduced keyword gap (e.g. operator at children[2])

No mapper arm needed — any path into a proj-introduced node returns `nothing`
and falls through to the `_syntax_to_flat` fallback in `projection_read`.

#### Items list through a body node (comma-body / newline-body)

Body node is at output `children[body_idx]`; items are its children.
`child_iomaps` is the item iomaps vector (length == number of items).

```julia
# forward:
items{s:_}.rest... => begin
    child_i = s + 1
    cims = iomap.child_iomaps[]
    1 <= child_i <= length(cims) || return nothing
    child = cims[child_i]
    inner = map_reference_forward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference children[body_idx].children[child_i].^(inner)
end
# backward (body_idx is fixed or computed from iomap.input):
children{outer_s:_}.children{t:u}.rest... => begin
    outer_s + 1 != body_idx && return nothing
    item_i = t + 1
    cims = iomap.child_iomaps[]
    1 <= item_i <= length(cims) || return nothing
    child = cims[item_i]
    inner = map_reference_backward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference items[item_i].^(inner)
end
```

When `body_idx` is **dynamic** (e.g. depends on `doc.distinct`), read it from
`iomap.input.distinct !== nothing ? 3 : 2`. When **fixed**, use a constant
guard: `outer_s != 1 && return nothing` (pos 2 → `outer_s == 1`).

#### Optional child (condition present or absent)

Two variants depending on whether the optional child is routed through a body
node (e.g. `SqlWhereClauseToSyntaxNode`) or appended directly to the children
list (e.g. `SqlJoinedFromItemToSyntaxNode`).

**Via body node** (keyword + newline-body wrapper, child appears at `children[body_idx].children[1]`):

```julia
child_iomaps_cell = Cell(() -> begin ci = cond_im[]; ci === nothing ? Any[] : Any[ci] end)

# forward:
condition.rest... => begin
    cims = iomap.child_iomaps[]
    isempty(cims) && return nothing
    child = cims[1]
    ...
end
# backward (two-level through body node):
children[body_idx].children[1].rest... => begin
    cims = iomap.child_iomaps[]
    isempty(cims) && return nothing
    ...
end
```

**Appended as trailing child** (child appears at `children[N]`; `child_iomaps`
grows from length N-1 to N):

```julia
# child_iomaps has 2 items without condition, 3 with:
child_iomaps_cell = Cell(() -> begin
    jt, fi, cond_im = projected[]
    cond_im === nothing ? Any[jt, fi] : Any[jt, fi, cond_im]
end)

# forward:
condition.rest... => begin
    cims = iomap.child_iomaps[]
    length(cims) < 3 && return nothing
    child = cims[3]
    inner = map_reference_forward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference children[3].^(inner)
end
# backward:
children[3].rest... => begin
    cims = iomap.child_iomaps[]
    length(cims) < 3 && return nothing
    child = cims[3]
    inner = map_reference_backward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference condition.^(inner)
end
```

#### Mixed base + variable-length list (index offset)

When `child_iomaps` packs `[base_im; join_ims...]`, the list items are offset
by 1. Reference into `joins` uses `cim_i = join_i + 1`.

```julia
child_iomaps_cell = Cell(() -> begin base, joins = projected[]; Any[base; joins] end)

# forward for joins:
joins{s:_}.rest... => begin
    join_i = s + 1
    cim_i  = join_i + 1          # skip base_im at index 1
    cims = iomap.child_iomaps[]
    1 <= cim_i <= length(cims) || return nothing
    ...
    @reference children[2].children[join_i].^(inner)
end
# backward for joins:
children{1:_}.children{t:u}.rest... => begin
    join_i = t + 1
    cim_i  = join_i + 1
    ...
    @reference joins[join_i].^(inner)
end
```

---

## Testing

### Concept

Selection correctness is verified by `explore_selections` (BFS over all
reachable selection states). It fires every nav key (`←`, `→`, `↑`, `↓`,
`Home`, `End`, `Ctrl+Home`, `Ctrl+End`) at every reachable state, catches any
thrown exception, and asserts zero errors. The top-level entry point is
`test_selection(label, document, projection)` which wraps this in a
`@testset`.

The pipeline used must go all the way to `TextToGraphics` because keyboard
navigation is dispatched by that layer. In the test suite SDL is unavailable,
so use a deterministic dummy measure:

```julia
measure = (text, font) -> (length(text) * 10, 18)
proj = SequentialProjection(
    RecursiveProjection(SqlToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=measure))
```

### Current coverage

`test_sql_to_syntax_selection()` in
`test/src/projection/SqlToSyntaxTest.jl` runs against the nested SQL document
(`make_sql_nested_document_example`), which exercises every projection type
that was fixed:

- outer `SqlSelectStatementToSyntaxNode`
- `SqlSelectClauseToSyntaxNode` / `SqlSelectItemToSyntaxNode` (aliased columns)
- `SqlSubqueryFromItemToSyntaxNode` (subquery two levels deep)
- `SqlFromClauseToSyntaxNode` / `SqlFromItemToSyntaxNode`
- inner `SqlSelectStatementToSyntaxNode` (subquery body)
- `SqlWhereClauseToSyntaxNode` / `SqlComparisonToSyntaxNode` (outer + inner)
- `SqlColumnReferenceToSyntaxLeaf` / `SqlTableExpressionToSyntaxLeaf` / `SqlScalarValueToSyntaxLeaf`

Registered in `test/src/ProjecturedTest.jl` under `test_projections()`.

### Rule: new SQL projection → must add to selection test

Whenever a new SQL node projection is added to `SqlToSyntax.jl`:

1. Ensure the **nested document** in `test_sql_to_syntax_selection()` exercises
   the new construct. If it does not, extend the document or add a second
   `test_selection(...)` call with a targeted document.
2. If a new example document is added to `example/src/document/Sql.jl`, also
   remove it from the skip list in `test/src/editor/SelectionTest.jl`
   (`test_selections()` currently skips `"sql_syntax"`, `"sql_nested_syntax"`,
   and `"sql_table"` — un-skip any that now have full selection wiring).

---

## Adding a new SQL node projection checklist

1. Read the input `@document struct` to identify which fields have `selection`
   (all `@document` structs do) and which hold child documents.
2. Sketch the output shape: which output children correspond to input fields
   and which are proj-introduced (keywords, delimiters, wrappers).
3. Build `child_iomaps_cell` covering only the **children with input
   pre-images**; proj-introduced nodes are not tracked.
4. Use the standard node template above.
5. Write `map_reference_forward` with one arm per input field that has a child
   iomap. Proj-introduced positions need no arm — `_syntax_to_flat` handles
   them.
6. Write `map_reference_backward` mirroring each forward arm, using the
   multi-step pattern (`children[A].children[B].rest...`) for nodes nested
   inside structural wrappers.
7. Use `children[N]` (literal) when the position is fixed; use
   `children{s:_}` + guard when it depends on runtime document state.

## Open / future work

- `SqlDistinct` — if it becomes a projectable document instead of a flag,
  add `SqlDistinctToSyntaxLeaf` (leaf, shared selection).
- `HAVING`, `GROUP BY`, `ORDER BY`, `LIMIT` clauses — each follows the
  `SqlWhereClauseToSyntaxNode` pattern (keyword + optional/required body node).
- `CASE WHEN` expressions — multi-branch; use items-list-through-body-node
  pattern with a fixed body position.
- `IN (subquery / list)`, `BETWEEN`, `EXISTS` — add as leaf or node depending
  on whether the subparts are separate documents.
- `SqlJoinTypeToSyntaxLeaf` — no `selection` field on join-type enum variants;
  left as `∅`-only. The `_join_type_display` helper provides fully qualified
  display names (`INNER JOIN`, `LEFT OUTER JOIN`, …) independently of the projection pipeline.
- `SqlJoinUsingCondition` — no projection yet; add `SqlJoinUsingConditionToSyntaxNode`
  following the `SqlJoinOnConditionToSyntaxNode` pattern (USING keyword + column list).
