"""
Per-layer test suite for the kernel `reference/` layer.

Runnable via `Pkg.test("ProjecturedKernel"; test_args=["reference"])` or
directly: `julia --project=. package/kernel/test/reference/runtests.jl`.

Files:
- `ReferenceBuilderTest.jl` — the @reference / @step / @reference_case DSLs.
- `ReferenceEvalTest.jl`    — evaluate_reference on a test-local ToyBranch tree.
"""

using Test

@testset "reference" begin
    include("ReferenceBuilderTest.jl")
    include("ReferenceEvalTest.jl")
end
