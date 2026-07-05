"""
Per-layer test suite for the kernel `agent/` layer.
"""

using Test

@testset "agent" begin
    include("AgentSeamTest.jl")
end
