"""
`AgentModule` — the agent control-surface seam. Kernel plan P9: renamed
from `AgentApiModule` and moved from `api/` into `agent/`.
"""

using Test
using ProjecturedKernel.AgentModule

@testset "Agent seam" begin

    @testset "unregistered kind raises a helpful error" begin
        @test_throws ErrorException make_agent_server(:definitely_not_registered, nothing)
    end

    @testset "a test-local Val method registers a factory" begin
        struct ToyServer end
        AgentModule.make_agent_server(::Val{:toy}, editor; kwargs...) = ToyServer()

        s = make_agent_server(:toy, nothing)
        @test s isa ToyServer
    end

end
