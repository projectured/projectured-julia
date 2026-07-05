"""
Per-layer test suite for the kernel `backend/` layer.
"""

using Test

@testset "backend" begin
    include("HeadlessBackendTest.jl")
end
