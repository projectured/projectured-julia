# Fragment of `AgentModule` — the fallback behaviours the agent-server
# contract supplies itself. The contract is declared in `AgentInterface.jl`;
# the concrete servers live in opt-in packages.

# The `Symbol` entry every caller uses; a server package answers the `Val`.
make_agent_server(kind::Symbol, editor; kwargs...) =
    make_agent_server(Val(kind), editor; kwargs...)

# A kind nothing answered: say which package is missing rather than raise a
# bare `MethodError`.
make_agent_server(::Val{K}, editor; kwargs...) where {K} = error(
    "No agent server registered for :$(K). Is the package/extension that " *
    "provides it loaded?")
