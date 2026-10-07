# Fragment of `AgentModule` — the fallback behaviours of the external-agent
# contract. The contract is declared in `AgentConnectionInterface.jl`; the
# concrete connections live in opt-in packages.

# The `Symbol` entry every caller uses; a connection package answers the `Val`.
make_agent_connection(kind::Symbol; kwargs...) = make_agent_connection(Val(kind); kwargs...)

# A kind nothing answered: say which connections are loaded rather than raise a
# bare `MethodError`.
function make_agent_connection(::Val{K}; kwargs...) where {K}
    error("No agent connection registered for :$(K). Loaded connections: " *
          _format_kinds(get_agent_connection_names()) * ". " *
          "Load the opt-in package that provides :$(K).")
end

"""
    get_agent_connection_names() -> Vector{Symbol}

The kinds of the loaded agent connections, in alphabetical order, read from the
method table of `make_agent_connection`.
"""
get_agent_connection_names() = _collect_val_kinds(make_agent_connection)
