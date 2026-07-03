"""
    AgentApiModule

Abstract agent control-surface interface. An *agent server* is a channel that
lets an external AI agent inspect and manipulate a running editor — conceptually
another device/backend that reads operations from an agent and writes document
state back.

Concrete servers (e.g. the MCP server) live in their own modules / package
extensions and register methods for `make_agent_server` / `start_agent_server!`
/ `stop_agent_server!`. The editor loop drives an agent server only through
these generics, so it never names a concrete server type — letting the
implementation move into an optional extension whose type cannot be referenced
at load time.
"""
module AgentApiModule

export make_agent_server, start_agent_server!, stop_agent_server!

"""
    make_agent_server(kind::Symbol, editor; kwargs...)

Construct an agent server of the given `kind` (e.g. `:mcp`) bound to `editor`.
A missing method (its optional dependency not loaded) raises a helpful error.
"""
make_agent_server(kind::Symbol, editor; kwargs...) =
    make_agent_server(Val(kind), editor; kwargs...)
make_agent_server(::Val{K}, editor; kwargs...) where {K} = error(
    "No agent server registered for :$(K). Is the package/extension that " *
    "provides it loaded?")

"""
    start_agent_server!(server)

Start the agent server (begin processing in the background).
"""
function start_agent_server! end

"""
    stop_agent_server!(server)

Stop the agent server and release its resources.
"""
function stop_agent_server! end

end # module
