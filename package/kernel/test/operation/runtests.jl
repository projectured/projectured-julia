"""
Per-layer test suite for the kernel `operation/` layer.

Runnable via `Pkg.test("ProjecturedKernel"; test_args=["operation"])` or
directly.

Files:
- `RerootingTest.jl` — the open reroot_operation seam: base methods on
                       kernel operations + a test-local Operation type adds
                       its own method.
- `TraversalTest.jl` — the open child_reference_steps seam: default
                       fieldnames-walk + a test-local override.
"""

using Test

@testset "operation" begin
    include("RerootingTest.jl")
    include("TraversalTest.jl")
end
