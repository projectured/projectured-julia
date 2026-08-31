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
- [`graphlayoutbench`](@ref) — what each graph layout engine costs and what it
  draws at 10, 60 and 300 vertices. Backs the threshold at which the engine that
  decides late turns from the advanced layouter to the fast one.
"""
module ProjecturedBench

using Projectured
using ProjecturedExample
using Statistics
using Projectured: ReactiveCell, ImmutableCell, MutableCell, AbstractCell, Cell

# The bodies are measurements, not code that ships, so they live under `test/`
# with every other thing a person runs to check the system.
const _BENCH_DIR = normpath(joinpath(@__DIR__, "..", "..", "..", "test", "bench"))
include(joinpath(_BENCH_DIR, "colorbench.jl"))
include(joinpath(_BENCH_DIR, "fanout.jl"))
include(joinpath(_BENCH_DIR, "graphlayoutbench.jl"))

export colorbench, fanout_report, walk_cells, graphlayoutbench

end # module ProjecturedBench
