"""
    CellModule

The reactive cell and its kinds. A cell is a box of type `AbstractCell{T}` that
holds one value of type `T`. What a read and a write do depends on the kind of
the cell. A reactive cell records the cells that read it, and a write makes them
compute again on their next read. A cell computes only when it gets a
`Computation`, and it stores every other value as it is, a function too.

The layer imports only the performance counters, which the reactive kind counts
into. The guide `kernel/cell` explains the engine and the invariants that it
depends on.

The module lives in six fragments that share this namespace:

- [`CellInterface.jl`](CellInterface.jl) — `AbstractCell` and the generics that
  every kind answers.
- [`CellComputation.jl`](CellComputation.jl) — `Computation`, the marker of a
  computation, and `@computation`, which makes it for an expression.
- [`ReactiveCell.jl`](ReactiveCell.jl) — `ReactiveCell`, its alias `Cell`, and the
  engine that tracks the readers.
- [`MutableCell.jl`](MutableCell.jl) — a box that a write changes and that records
  no reader.
- [`ImmutableCell.jl`](ImmutableCell.jl) — a box that can not be written.
- [`CellDefaults.jl`](CellDefaults.jl) — the bodies of the generics of the
  interface, one method for each kind.
"""
module CellModule

using ..PerformanceModule

export AbstractCell, is_cell_up_to_date, unwrap_cell, get_cell_value_type,
       copy_cell_as, is_computed_cell, has_dependent_cells
export Computation, @computation
export ReactiveCell, Cell, set_cell_value!, set_cell_computation!
export MutableCell
export ImmutableCell

include("CellInterface.jl")
include("CellComputation.jl")
include("ReactiveCell.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")
include("CellDefaults.jl")

end # module
