"""
    CellModule

The reactive cell and its kinds. A cell is a box of type `AbstractCell{T}` that
holds one value of type `T`. What a read and a write do depends on the kind of
the cell. A reactive cell records the cells that read it, and a write makes them
compute again on their next read. A cell computes only when it gets a
`Computation`, and it stores every other value as it is, a function too.

The layer imports the performance counters, which the reactive kind counts
into, and from the fault layer the test of an exception that no barrier takes.
The guide `kernel/cell` explains the engine and the invariants that it depends
on.

The module lives in eight fragments that share this namespace:

- [`CellInterface.jl`](CellInterface.jl) — `AbstractCell` and the generics that
  every kind answers.
- [`CellComputation.jl`](CellComputation.jl) — `Computation`, the marker of a
  computation, and `@computation`, which makes it for an expression.
- [`ReactiveCell.jl`](ReactiveCell.jl) — `ReactiveCell`, its alias `Cell`, and the
  engine that tracks the readers.
- [`CellFaultScope.jl`](CellFaultScope.jl) — the fault scope that a computation
  keeps, and the fault that it hands to the scope when it throws.
- [`MutableCell.jl`](MutableCell.jl) — a box that a write changes and that records
  no reader.
- [`ImmutableCell.jl`](ImmutableCell.jl) — a box that can not be written.
- [`UntrackedCell.jl`](UntrackedCell.jl) — a cell that computes at each read and
  records no reader.
- [`CellDefaults.jl`](CellDefaults.jl) — the bodies of the generics of the
  interface, one method for each kind.
"""
module CellModule

using Base.ScopedValues: ScopedValue, with
using ..PerformanceModule
using ..FaultModule

export AbstractCell, is_cell_up_to_date, unwrap_cell, get_cell_value_type,
       make_similar_cell, is_computed_cell, get_cell_computation, has_dependent_cells,
       run_untracked
export Computation, @computation
export ReactiveCell, Cell, set_cell_value!, set_cell_computation!
export run_in_fault_scope, record_computation_fault!, RecordedFaultException,
       get_fault_scope, find_fault_scope
export MutableCell
export ImmutableCell
export UntrackedCell

include("CellInterface.jl")
include("CellComputation.jl")
include("ReactiveCell.jl")
include("CellFaultScope.jl")
include("MutableCell.jl")
include("ImmutableCell.jl")
include("UntrackedCell.jl")
include("CellDefaults.jl")

end # module
