# ── Cell layer (layer 1 — the DAG's dependency-free base) ──────────────────
# The ordered include list of the cell layer; a fragment of ProjecturedKernel.
# PerformanceCounter (leaf) before the cells, whose reactive kind bumps its
# counters on the hot path. CellModule is the aggregator; it includes the base
# type and the three kind files (AbstractCell/ReactiveCell/MutableCell/ImmutableCell).
# Time is the one global animation clock, a single `Cell` built on the engine
# above — it belongs beside cells, not with the editor loop that drives it.
include("PerformanceCounter.jl")
include("CellModule.jl")
include("Time.jl")
