# Collection Domain

<img width="240" alt="Collection example" src="../../image/example/collection.png">

The collection domain provides four generic, reactive container types used
everywhere in ProjecturEd. They are defined in
[program/src/document/Collection.jl](../../package/kernel/src/document/Collection.jl)
and subtype `Document` so they participate in the selection mechanism. This guide
covers the two most common ones, `CellVector` and `ListNode`; `CellMatrix`
(2-D) and `CellTable` (rows of `CellVector`s) follow the same reactive-cell design.

```julia
const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}
```

## CellVector

```julia
@document struct CellVector <: Document
    elements::Vector{Cell}
    selection::Reference
end
```

A growable indexed vector where **each slot is a reactive `Cell`**. A
write to one slot invalidates only the dependents that read *that* slot —
not the whole container — which is the key to scalable updates.

Construction:

```julia
CellVector()                       # empty
CellVector(cells::Vector{Cell})    # adopt these cells
CellVector(items::AbstractVector)  # wrap each item in a Cell
CellVector(n::Integer)             # n empty slots
CellVector(items...)               # wrap each positional arg in a Cell
CellVector(f::Function)            # computed slots — thunk returns Vector
```

The last form is what enables lazy children:

```julia
SyntaxNode("[", "]", ", ",
    CellVector(() -> [project_child(c) for c in input.children]))
```

The function is wrapped via `setfn!` and re-runs whenever its reactive
dependencies invalidate.

### Access patterns

- `cv[i]` — returns the *value* stored at slot `i` (1-based).
- `cell_at(cv, i)` — returns the raw `Cell` at slot `i` (escape hatch).
- `cv[i] = val` — writes the value into the cell.
- `cv[i] = cell` (where `cell isa Cell`) — replaces the slot itself.
- `push!`, `pop!`, `insert!`, `deleteat!`, `sort`, `reverse` — standard
  vector operations, all updating the underlying `elements` cell.
- `length`, `firstindex`, `lastindex`, `iterate`, `eachindex`, `isempty` —
  standard.

### Reference semantics

The selection mechanism treats a `CellVector` as a sequence:

- `ElementReference(i)` (or `[i]` in the `@reference` DSL) → slot `i` (1-based).
- `PositionReference(i)` (or `{i}`) → cursor *between* slots (0-based).

## ListNode

```julia
@document struct ListNode <: Document
    value::Any
    prev::Union{ListNode, Nothing}
    next::Union{ListNode, Nothing}
    selection::Reference
end
```

A doubly-linked list where the node you hold is the **middle** — `prev`
and `next` are two tails growing outward in opposite directions. The
design is deliberately asymmetric in *use* but symmetric in *structure*:
both directions can be lazy.

- `head[1]` is the head itself
- `head[2]`, `head[3]`, … walk `next`
- `head[0]`, `head[-1]`, … walk `prev`

`push!(head, v)` appends to the right tail, `pushfirst!(head, v)`
prepends to the left tail. `left_tail(node)` and `right_tail(node)` walk
to the far end of the respective direction.

### Laziness

Because `prev` and `next` are `Cell` fields, they can be backed by
computations. `CopyingProjection` exploits this: when it projects a
`ListNode`, only the head is computed eagerly; the directions are
re-projected on demand. The result is that copying an *infinite* list is
still O(1) at construction time — extra nodes are materialised when
something reads them.

### Iteration

```julia
for n in head_node
    println(n.value)
end
```

Iteration starts from `left_tail(head_node)` and walks rightward through
`next`, yielding the whole reachable list. `Base.IteratorSize(ListNode) =
SizeUnknown()` because the right tail may be unbounded.

### `take_first_n` helpers

```julia
take_first_n(node, n)                 # n values walking :next
take_first_n(node, n, :prev)          # n values walking :prev
take_first_n(node, n_prev, n_next)    # window centred on node
```

Useful when projecting a slice of a potentially infinite list to a
finite-area widget.

## When to use which

- **CellVector** — for finite, bounded collections (JSON arrays, JSON
  object entries, syntax-tree children, file-system directory listings,
  widget children). The structure is finite and you have an index to
  address slots.
- **ListNode** — for sequences where the natural addressing is "the node
  in front of / behind this one" and where either direction may extend
  indefinitely. Used in the graphics module for lazy lines/elements and
  by `CopyingProjection`'s lazy traversal.

## Reactivity rules of thumb

1. **Reading one slot** registers a dependency on that slot only. A write
   to another slot does *not* invalidate readers of unaffected slots.
2. **Structural changes** (push/pop/insert/delete) update the outer
   `elements` cell, which invalidates anything that depends on the
   *shape* of the vector (e.g. layout code reading `length(cv)`), while
   leaving per-slot readers alone unless the slot they observe was
   actually moved.
3. **`CellVector(f::Function)`** is the way to make a computed collection
   — recreate the whole thing reactively from upstream cells.
