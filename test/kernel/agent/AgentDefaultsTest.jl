"""
`AgentModule` — the fallbacks of the inbound agent-server seam and of the
external-agent seam: the error for a kind that no package answers, and a
factory that a `Val` method registers.
"""

using Test
using ProjecturedKernel.AgentModule

# A test-local backend kind: the `Val`-keyed factory method registers `:toy`
# the same way a real transport package (llm/mcp) registers its kind. Julia
# only allows `struct` at the top level, so the fixture lives here rather than
# inside the testset.
struct ToyServer end
AgentModule.make_agent_server(::Val{:toy}, editor; kwargs...) = ToyServer()
struct ToyConnection end
AgentModule.make_agent_connection(::Val{:toy}; kwargs...) = ToyConnection()

function test_agent_defaults()
@testset "Agent defaults" begin

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
        @test :toy in get_agent_server_names()
    end

    @testset "an unregistered connection kind raises a helpful error" begin
        message = try
            make_agent_connection(:definitely_not_registered)
            ""
        catch exception
            sprint(showerror, exception)
        end
        @test occursin("No agent connection registered for :definitely_not_registered", message)
        @test occursin(":toy", message)
    end

    @testset "a test-local Val method registers a connection" begin
        @test make_agent_connection(:toy) isa ToyConnection
        @test get_agent_connection_names() == sort!(unique!(Symbol[get_agent_connection_names()...]))
        @test :toy in get_agent_connection_names()
    end

    @testset "a tool call update keeps what it does not name" begin
        update = AgentToolCallUpdate("call-1"; status = :completed)
        @test update.id == "call-1"
        @test update.status === :completed
        @test update.title === nothing && update.input === nothing && update.output === nothing
    end

end
end # test_agent_defaults
