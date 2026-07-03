"""
    CellModule

The cell layer — **Layer 0**, the dependency-free base of the whole system. A
cell is a typed box `AbstractCell{T}` holding a value; the *kind* of the cell
decides its behavior:

- **`ReactiveCell{T}`** — the pull-based reactive engine. Wraps either a plain
  value or a zero-argument thunk. Reading a cell while another reactive cell's
  thunk is evaluating registers a dependency edge. Writing a primitive cell
  eagerly marks all transitive dependents as stale; recomputation is lazy — it
  happens on the next read. `Cell` is a `const` alias for the **concrete**
  `ReactiveCell{Any}`, the untyped reactive cell (see the alias docstring for why
  concrete matters).
- **`MutableCell{T}`** — a plain mutable box: read/write, **no** reactive
  bookkeeping. Reading it inside a reactive thunk registers *nothing*; writing
  it invalidates *nothing*. This is the high-frequency-mutation kind (simulation
  state); a sync step copies changes into a reactive shadow when observation is
  wanted.
- **`ImmutableCell{T}`** — a plain immutable wrapper: read-only, zero-cost (an
  immutable struct with a concrete field inlines into its parent). This is the
  derived/display-content kind.

The base type and the three kinds live in one file each —
[`AbstractCell.jl`](AbstractCell.jl), [`ReactiveCell.jl`](ReactiveCell.jl),
[`MutableCell.jl`](MutableCell.jl), [`ImmutableCell.jl`](ImmutableCell.jl) —
included below; this file (`CellModule.jl`) is just the module aggregator: imports,
exports, and the include list.

The module exposes:
- **Cell kinds**: `AbstractCell`, `ReactiveCell` (= `Cell`), `MutableCell`,
  `ImmutableCell`
- **Functions**: `set_value!`, `set_function!`, `is_up_to_date`, `peek` (reactive
  kind only, except the shared read protocol `c[]`)

The instrumentation counters (`PerformanceCounterModule`,
`cell/PerformanceCounter.jl`, whose `_perf` dict `ReactiveCell` bumps inline on the
hot path) count **reactive** cell traffic only: `MutableCell`/`ImmutableCell`
reads cost a pointer load, so they are deliberately not counted. Anything *built
on* cells rather than part of the engine — an animation clock that samples time,
say — belongs in a higher layer, not here.

Dependency tracking is automatic: when a computed reactive cell evaluates its
thunk, every `ReactiveCell` read via `c[]` is recorded as a dependency. When any
upstream cell changes, all downstream dependents are invalidated and will
recompute on next read.

# Invariants (unchecked — see documentation/reactive-cells.md)
- **Acyclic graph.** A thunk must never transitively read its own cell;
  `recompute!` would recurse forever. Only *direct* self-edges are skipped.
- **Monotone invalidation.** `_invalidate_walk!` stops at already-invalid
  dependents, trusting they propagated when first invalidated. Always walk the
  full closure on write; never hand-set `valid` or partially invalidate.
- **Write-driven propagation.** Writes invalidate dependents unconditionally —
  there is no value-equality short-circuit, so writing a cell its current value
  still recomputes downstream.
- **Pure thunks.** A thunk may run 0/1/many times and is cached until
  invalidation, so it must be side-effect-free and depend only on cells it reads.
"""
module CellModule

export Cell, AbstractCell, ReactiveCell, MutableCell, ImmutableCell,
       set_value!, set_function!, is_up_to_date

# ── the base type + the three kinds (one file each) ────────────────────────
# AbstractCell first (it also holds the cross-kind protocol fallbacks); the
# concrete kinds subtype it.
include("AbstractCell.jl")
include("ReactiveCell.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")

end # module
