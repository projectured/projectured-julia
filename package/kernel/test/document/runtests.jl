"""
Per-layer test suite for the kernel `document/` layer.

Runnable via `Pkg.test("ProjecturedKernel"; test_args=["document"])` or
directly: `julia --project=. package/kernel/test/document/runtests.jl`.

Rule (statically enforced by the top-level layer guard): tests here may
reference ProjecturedKernel modules from the cell + document layers only.

Files:
- `DocumentContractTest.jl` — the contract exercised through a test-local
                              `ToyNode`; the concrete engine documents (Collection,
                              Primitive, ScreenDocument) are deliberately NOT
                              imported, so the interface has to stand on its own.
"""

using Test

@testset "document" begin
    include("DocumentContractTest.jl")
end
