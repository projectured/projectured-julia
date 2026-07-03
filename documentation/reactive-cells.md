# Working with Reactive Cells

The reactive cell system is the foundation of ProjecturEd's incrementality. It is a
lightweight pull-based reactive engine that replaces the original Common Lisp
ProjecturEd's `hu.dwim.computed-class`. It lives entirely in
[package/kernel/src/reactive/Reactive.jl](../package/kernel/src/reactive/Reactive.jl) and has no
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
set_value!(c, v)     # same as c[] = v
set_function!(c, thunk)  # switch c to a computed cell; previous deps detached
is_up_to_date(c)     # has the cached value been invalidated since last compute?
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

- `c[] = v` or `set_function!(c, f)` walks the transitive set of `c.dependents` and
  marks them invalid (`valid = false`). The actual recomputation does NOT run.
- The next `c[]` on an invalid cell calls `recompute!(c)`, which detaches old
  upstream links, evaluates the thunk under tracking, and refreshes the value.

This is the pull-based / lazy strategy. It is essential to how the projection
printer stays incremental: invisible parts of the output don't recompute even
when their inputs change, because nothing pulls on them.

## Invariants the engine relies on

These hold by construction in the current code, but nothing checks them — break
one and you get a hang, a stale render, or a stack overflow rather than an error.

- **The dependency graph must be acyclic.** `recompute!` evaluates a thunk while
  its cell sits on the `_computing` stack; if that thunk (transitively) reads its
  own cell, recomputation recurses forever. The engine only skips a *direct*
  self-edge (`observer !== c`) — it does **not** detect multi-cell cycles. A
  computed cell must never depend on itself through any chain.
- **Invalidation is monotone: invalid ⟹ all transitive dependents are already
  invalid.** `_invalidate_walk!` stops descending the moment it meets an
  already-invalid dependent, trusting that that cell propagated its own
  invalidation when it first became invalid. This holds only because every write
  walks the *full* transitive closure and `recompute!` is the only thing that
  re-validates. Never hand-set `valid`, and never partially invalidate a subset
  of dependents — either breaks the early-stop and leaves cells stale forever.
- **Propagation is write-driven, not value-driven.** Writing a cell invalidates
  its dependents unconditionally, with **no equality check** — setting a cell to
  the value it already holds still recomputes everything downstream, and a thunk
  that recomputes to an unchanged value does *not* stop propagation (the engine
  is not glitch-free / not value-stabilising). So `c[] = c[]` is not free; a
  printer that rewrites `selection` every frame pays for the whole subtree it
  feeds. See [the design-decisions note](design-decisions.md#10-propagation-is-write-driven-not-value-driven).
- **Thunks must be pure and deterministic in their cell inputs.** A thunk may run
  zero, one, or many times for a single logical change, and its cached result is
  reused until invalidation. It must therefore have no side effects and depend
  only on the cells it reads (no clocks, RNG, or external mutable state) — or the
  cache is wrong. This is a correctness requirement, not a style preference.
- **Invalidation recurses on the call stack**, so its depth is bounded by the
  longest dependency chain (≈ document tree depth). Pathologically deep documents
  can overflow the stack; in practice trees stay shallow enough that this is a
  theoretical limit, noted here so it isn't a surprise.

## Performance counters

```julia
perf_counters()  # Dict{Symbol,Int} with :reads :computes :invalidations :writes
perf_reset!()    # zero them
```

The editor's main loop resets and reports these every frame (see
[Editor.run!](../package/kernel/src/editor/Editor.jl)), which is the easiest way to
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
even though every field is reactive. See [the macros guide](macros.md) for details.

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
- **`set_function!(getfield(obj, :field), () -> …)`** — used to lazily attach a
  computation to a field after construction; common in
  `CellVector(f::Function)` and child-element generators.

## Best practices

- Wrap document fields in Cells via the `@document` macro rather than hand-rolling.
- Use computed cells for derived state so the system can invalidate it.
- Never side-effect inside a thunk — the thunk may run zero, one, or many times.
- Don't read a cell during construction of a struct that hasn't finished its
  iomap wiring — use `Cell(() -> ...)` to defer the read.
