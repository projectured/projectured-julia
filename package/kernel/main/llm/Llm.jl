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
is_walk_opaque(::Llm) = true

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
