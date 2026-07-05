"""
Per-layer test suite for the kernel `device/` layer.

Runnable via `Pkg.test("ProjecturedKernel"; test_args=["device"])` or directly.
"""

using Test

@testset "device" begin
    include("GestureModuleTest.jl")
end
