"""
`AgentModule` — the inbound agent-server seam.
"""

using Test
using ProjecturedKernel.AgentModule

# A test-local backend kind: the `Val`-keyed factory method registers `:toy`
# the same way a real transport package (llm/mcp) registers its kind. Julia
# only allows `struct` at the top level, so the fixture lives here rather than
# inside the testset.
struct ToyServer end
AgentModule.make_agent_server(::Val{:toy}, editor; kwargs...) = ToyServer()

function test_agent_seam()
@testset "Agent seam" begin

    @testset "unregistered kind raises a helpful error" begin
        @test_throws ErrorException make_agent_server(:definitely_not_registered, nothing)
        # The error lists the kinds whose servers are loaded.
        message = try
            make_agent_server(:definitely_not_registered, nothing)
            ""
        catch exception
            sprint(showerror, exception)
        end
        @test occursin(":toy", message)
    end

    @testset "a test-local Val method registers a factory" begin
        s = make_agent_server(:toy, nothing)
        @test s isa ToyServer
    end

end
end # test_agent_seam
