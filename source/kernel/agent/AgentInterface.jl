# Fragment of `AgentModule` — the agent-server **contract**: the seams of the
# inbound half, a channel that lets an agent *outside* this process inspect
# and manipulate a running editor — conceptually another device/backend,
# reading operations from an agent and writing document state back.
# Independent of the editor loop, which reaches it only through
# `make_agent_server`.
#
# The *outbound* half — the agent loop of `Agent.jl` and `AgentLoop.jl`, this
# editor driving a model — is the mirror image. Both spend the same currency,
# the editor's `ToolSet`: an agent server publishes it, an agent loop calls it.
#
# Concrete servers live in their own packages and register methods for these
# generics. The editor loop drives a server only through them, so it never
# names a concrete server type, which is what lets the implementation live in
# an optional package whose types cannot be referenced at load time. Nothing
# here carries a body — the fallback behaviours sit in `AgentDefaults.jl`.

"""
    make_agent_server(kind::Symbol, editor; kwargs...)

Construct an agent server of the given `kind` (e.g. `:mcp`) bound to `editor`.
A server package answers `make_agent_server(::Val{kind}, editor; kwargs...)`;
the `Symbol` entry redispatches, and a missing method (its optional package
not loaded) raises a helpful error — both in `AgentDefaults.jl`.
"""
function make_agent_server end

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
