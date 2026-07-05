"""
Per-layer test suite for the kernel `cell/` layer.

Runnable via `Pkg.test("ProjecturedKernel"; test_args=["cell"])` or directly:
`julia --project=. package/kernel/test/cell/runtests.jl`.

Rule (statically enforced by the top-level layer guard): tests under
`test/cell/` may reference ProjecturedKernel modules from the cell layer only.
Higher-layer references are a static error.
"""

using Test
using ProjecturedKernel

@testset "cell layer smoke" begin
    # The three cell kinds are wired up and the reactive counters bump on read.
    @test ProjecturedKernel.CellModule.Cell(1)[] == 1
    @test ProjecturedKernel.CellModule.ImmutableCell{Int}(1)[] == 1
    @test ProjecturedKernel.CellModule.MutableCell{Int}(1)[] == 1
end
