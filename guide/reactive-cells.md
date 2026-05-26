# Working with Reactive Cells

The reactive cell system is the foundation of ProjecturEd's incrementality. It is a
lightweight pull-based reactive engine that replaces the original Common Lisp
ProjecturEd's `hu.dwim.computed-class`. It lives entirely in
[program/src/common/Reactive.jl](../program/src/common/Reactive.jl) and has no
dependencies on the rest of the codebase — every other layer is built on top of it.

## Cell

A `Cell` is the only reactive primitive. It is either *primitive* (holds a value)
or *computed* (holds a zero-arg thunk):

```julia
c = Cell(42)                      # primitive
c = Cell(() -> upstream[] + 1)    # computed
```

The struct also tracks `valid`, the set of cells it reads from (`deps`), and the
set of cells that read it (`dependents`).

### Reading and writing

```julia
c[]               # read  — triggers recompute if invalid; returns the value
c[] = v           # write — converts c to a primitive, invalidates dependents
setval!(c, v)     # same as c[] = v
setfn!(c, thunk)  # switch c to a computed cell; previous deps detached
isuptodate(c)     # has the cached value been invalidated since last compute?
```

## Dependency tracking

Tracking is automatic via a global `_computing` stack:

1. When a computed cell starts evaluating, it pushes itself onto the stack.
2. Every `c[]` that happens during evaluation registers an edge `observer ← c`
   (the observing computed cell becomes a downstream dependent of `c`).
3. When the thunk returns, the cell pops off the stack and is marked valid.

Therefore, no part of the code needs to declare dependencies explicitly — they
arise as a side effect of reading.

## Invalidation

Invalidation propagates eagerly, recomputation is lazy:

- `c[] = v` or `setfn!(c, f)` walks the transitive set of `c.dependents` and
  marks them invalid (`valid = false`). The actual recomputation does NOT run.
- The next `c[]` on an invalid cell calls `recompute!(c)`, which detaches old
  upstream links, evaluates the thunk under tracking, and refreshes the value.

This is the pull-based / lazy strategy. It is essential to how the projection
printer stays incremental: invisible parts of the output don't recompute even
when their inputs change, because nothing pulls on them.

## Performance counters

```julia
perf_counters()  # Dict{Symbol,Int} with :reads :computes :invalidations :writes
perf_reset!()    # zero them
```

The editor's main loop resets and reports these every frame (see
[Editor.run!](../program/src/editor/Editor.jl)), which is the easiest way to
profile what work a particular edit actually triggered.

## How the cell appears in the rest of the codebase

Cells are *not* normally accessed directly in domain code. Every
`@document`, `@projection`, and `@iomap` macro generates a struct whose fields
are stored as `Cell` but are read and written *transparently* via
`getproperty` / `setproperty!`:

```julia
@document struct JsonString <: JsonDocument
    value::String          # stored as Cell internally
    selection::Reference   # stored as Cell internally
end

s = JsonString("hello")
s.value           # → "hello" (calls c[] on the underlying Cell)
s.value = "world" # → assigns via c[] = "world"
getfield(s, :value)  # → the raw Cell, escape hatch when you need it
```

This is why the bulk of the code reads like ordinary Julia struct manipulation
even though every field is reactive. See [macros.md](macros.md) for details.

## Idioms you will encounter

- **Computed cell sharing a primitive cell** — selection cells are passed
  through unchanged between domain and projection (e.g. `JsonString.selection`
  is the very same Cell as the produced `SyntaxLeaf.selection`), so a single
  write at the document level instantly invalidates the rendered cursor.
- **`Cell(() -> ...)` for derived values** — projections wire a computed cell
  that reads upstream cells, often to translate a path from one domain to
  another (e.g. `map_reference_forward(p, nothing, j.selection)`).
- **`Cell(Cell[...])` inside `CellVector`** — the outer cell tracks the
  *structure* (the vector itself); each inner cell tracks one *element*. A
  structural change invalidates the outer cell; a value change invalidates
  only that slot, which is how the editor avoids re-rendering siblings.
- **`setfn!(getfield(obj, :field), () -> …)`** — used to lazily attach a
  computation to a field after construction; common in
  `CellVector(f::Function)` and child-element generators.

## Best practices

- Wrap document fields in Cells via the `@document` macro rather than hand-rolling.
- Use computed cells for derived state so the system can invalidate it.
- Never side-effect inside a thunk — the thunk may run zero, one, or many times.
- Don't read a cell during construction of a struct that hasn't finished its
  iomap wiring — use `Cell(() -> ...)` to defer the read.
