# Fragment of `AgentModule` — the fallback behaviours the agent-server
# contract supplies itself. The contract is declared in `AgentInterface.jl`;
# the concrete servers live in opt-in packages.

# The `Symbol` entry every caller uses; a server package answers the `Val`.
make_agent_server(kind::Symbol, editor; kwargs...) =
    make_agent_server(Val(kind), editor; kwargs...)

# A kind nothing answered: say which servers are loaded rather than raise a
# bare `MethodError`.
function make_agent_server(::Val{K}, editor; kwargs...) where {K}
    error("No agent server registered for :$(K). Loaded servers: " *
          _format_kinds(get_agent_server_names()) * ". " *
          "Load the opt-in package that provides :$(K).")
end

"""
    get_agent_server_names() -> Vector{Symbol}

The kinds of the loaded agent servers, in alphabetical order, read from the
method table of `make_agent_server` as `get_llm_backend_names` reads the
backends.
"""
get_agent_server_names() = _collect_val_kinds(make_agent_server)

# The kinds that the `Val` methods of `function_` answer, in alphabetical order.
# A kind method takes `Val{:kind}` first. The `Symbol` entry and the `Val{K}
# where K` fallback take a `Symbol` and a `UnionAll`, and neither is a kind.
function _collect_val_kinds(function_)
    names = Symbol[]
    for method in methods(function_)
        signature = method.sig
        signature isa UnionAll && continue
        length(signature.parameters) >= 2 || continue
        kind = signature.parameters[2]
        kind isa DataType && kind <: Val || continue
        name = kind.parameters[1]
        name isa Symbol && push!(names, name)
    end
    sort!(unique!(names))
end

_format_kinds(names) = isempty(names) ? "none" : join(map(name -> ":" * String(name), names), ", ")

# A target that nothing runs a loop for has no other task to wait for.
run_on_editor_task!(function_, target; wait::Bool = true) =
    wait ? function_() : (function_(); nothing)
