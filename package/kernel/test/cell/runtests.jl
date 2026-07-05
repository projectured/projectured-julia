"""
Per-layer test suite for the kernel `cell/` layer.

Runnable via `Pkg.test("ProjecturedKernel"; test_args=["cell"])` or directly:
`julia --project=. package/kernel/test/cell/runtests.jl`.

Rule (statically enforced by the top-level layer guard): tests under
`test/cell/` may reference ProjecturedKernel modules from the cell layer only.
Higher-layer references are a static error.

Files:
- `CellTest.jl`               — the reactive engine + typed/Mutable/Immutable kinds
                                (migrated from ProjecturedTest/common/CellTest.jl).
- `PerformanceCounterTest.jl` — the process-global counter store.
- `TimeTest.jl`               — the sample/subscribe split on the editor clock.
"""

using Test

@testset "cell" begin
    include("CellTest.jl")
    include("PerformanceCounterTest.jl")
    include("TimeTest.jl")
end
