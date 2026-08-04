"""
    ProjecturedBench

Development-only measurements that back design decisions elsewhere in the
repository. Each is a function, so a session can run several and compare:

    using ProjecturedBench
    colorbench()                                  # colour representation costs
    fanout_report("workbench"); fanout_report("json")   # cell fanout, side by side

- [`colorbench`](@ref) — what a colour costs as a plain struct, as a bare
  `@document`, as a non-selectable `@document`, and as a reactive selectable one.
  Backs the selection-parameter design.
- [`fanout_report`](@ref) — a cell-kind census of a live example pipeline plus the
  `dependents` fanout distribution, attributed to the struct field that holds each
  cell. Backs the immutable-style work.
- [`walk_cells`](@ref) — the underlying traversal: every cell reachable from a
  value, with its owning `(struct, field)`.
"""
module ProjecturedBench

using Projectured
using ProjecturedExample
using Statistics
using Projectured: ReactiveCell, ImmutableCell, MutableCell, AbstractCell, Cell

include(joinpath(@__DIR__, "colorbench.jl"))
include(joinpath(@__DIR__, "fanout.jl"))

export colorbench, fanout_report, walk_cells

end # module ProjecturedBench
