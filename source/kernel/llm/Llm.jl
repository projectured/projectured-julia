# Fragment of `LlmModule` — the seam a provider implements.

"""
    Llm

Abstract supertype for language-model backends. A concrete subtype carries that
provider's *configuration* — its API key, model name, endpoint, token budget —
and implements two methods:

- `stream_turn(llm, request; on_event)` — run one turn, emitting `LlmEvent`s.
- `tool_schema(llm, tools)` — render `Tool`s into whatever shape this provider's
  API wants for them.

Configuration lives on the struct rather than in the call because it is not
universal: a local model has no API key, a hosted one may need a region, and the
model name is the backend's identity, not a parameter of "have a conversation".
"""
abstract type Llm end

# A backend is configuration, not addressable document content (it may hold an API
# key or a large scripted payload) — opaque to the reflection walk, so
# `search_references` / `search_documents` never descend into it.
DocumentModule.is_walk_opaque(::Llm) = true

"""
    stream_turn(llm::Llm, request::LlmRequest; on_event)

Run a single turn against `llm` and call `on_event(ev::LlmEvent)` for every event
as it arrives. Returns when the turn's stream is exhausted; the last event is an
`LlmTurnEnd` carrying the stop reason (or an `LlmFailure`). Errors that are not
part of the protocol — a dead socket, a 401 — are thrown, not reported as events.

The adapter's job is translation: it renders `request` into its own wire format
and its own stream back into `LlmEvent`s. No caller ever sees the provider's
protocol.
"""
function stream_turn end

"""
    tool_schema(llm::Llm, tools::AbstractVector{Tool})

Render `tools` into the shape this provider's API expects (for Anthropic, a
JSON-Schema-shaped `Vector{Dict}`).

This is the provider adapter's job. A `Tool` itself describes its parameters
abstractly and knows no wire format at all.
"""
function tool_schema end

# ── Selecting a backend by name ──────────────────────────────────────────────
# A backend lives in an opt-in package, so nothing here can name its type. The
# factory is keyed by symbol and dispatched on `Val`, exactly as
# `make_agent_server(:mcp, editor)` is: each opt-in package adds one method, and
# the method table IS the registry — there is no dictionary to keep in step, and
# no process-global state.

"""
    make_llm(kind::Symbol; kwargs...) -> Llm

Construct the backend registered under `kind` (`:anthropic`, `:ollama`). The
keyword arguments are that backend's own configuration; each one documents what it
takes. A missing method — its opt-in package is not loaded — raises an error that
lists the backends that are.
"""
make_llm(kind::Symbol; kwargs...) = make_llm(Val(kind); kwargs...)

make_llm(::Val{K}; kwargs...) where {K} = error(
    "No LLM backend registered for :$(K). Loaded backends: " *
    (isempty(llm_backend_names()) ? "none" :
     join(map(n -> ":" * String(n), llm_backend_names()), ", ")) *
    ". Load the opt-in package that provides :$(K).")

"""
    default_llm_model(kind::Symbol) -> String

The model this backend talks to when nobody names one. It belongs to the backend,
not to a caller: a Claude model id means nothing to a local server, so a caller
that holds one model name for every provider holds the wrong name for all but one.
"""
default_llm_model(kind::Symbol) = default_llm_model(Val(kind))

default_llm_model(::Val{K}) where {K} = error(
    "No LLM backend registered for :$(K); it has no default model.")

"""
    llm_backend_names() -> Vector{Symbol}

The backends whose packages are loaded, in alphabetical order. Read from the
method table of `make_llm`, so a backend counts as available exactly when it can
be built — there is nothing to register and nothing to forget to unregister.
"""
function llm_backend_names()
    out = Symbol[]
    for m in methods(make_llm)
        # The first argument type of a registered method is `Val{:name}`; the two
        # generic methods above take `Symbol` and `Val{K} where K`, and neither is
        # a backend.
        sig = m.sig
        sig isa UnionAll && continue
        length(sig.parameters) >= 2 || continue
        T = sig.parameters[2]
        T isa DataType && T <: Val || continue
        p = T.parameters[1]
        p isa Symbol && push!(out, p)
    end
    sort!(unique!(out))
end
