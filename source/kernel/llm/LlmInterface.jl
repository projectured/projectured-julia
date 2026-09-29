# Fragment of `LlmModule` — the provider **contract**: the abstract `Llm` type
# and the open generics a provider package answers with a method for its own
# type. Nothing here carries a body — the fallback behaviours for the parts that a
# provider can leave out sit in `LlmDefaults.jl`.

"""
    Llm

Abstract supertype for language-model backends. A concrete subtype carries that
provider's *configuration* — its API key, model name, endpoint, token budget —
and implements two methods:

- `stream_turn(llm, request; on_event)` — run one turn, emitting `LlmEvent`s.
- `render_tool_schema(llm, tools)` — render `Tool`s into the provider-specific
  tool list that the API of this provider takes.

A backend that also has a meaning model implements three more:
`has_meaning_model`, `get_meaning_model_name` and `compute_meaning_vectors`.

Configuration lives on the struct rather than in the call because it is not
universal: a local model has no API key, a hosted one may need a region, and the
model name is the backend's identity, not a parameter of "have a conversation".
"""
abstract type Llm end

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
    render_tool_schema(llm::Llm, tools::AbstractVector{Tool})

Render `tools` into the provider-specific tool list that the API of this provider
takes, such as a `Vector{Dict}` in the form of a JSON Schema.

The provider adapter does this. A `Tool` describes its parameters abstractly and
holds no wire format.
"""
function render_tool_schema end

"""
    has_meaning_model(llm::Llm) -> Bool

Whether `llm` can compute meaning vectors, the vectors a search by description
ranks with — see `MeaningModel`. A backend that can not keeps the default,
`false`.
"""
function has_meaning_model end

"""
    get_meaning_model_name(llm::Llm) -> String

Which model computes the meaning vectors of `llm`, as `"ollama/nomic-embed-text"`.
The vectors of two models can not be compared, so the name keeps them apart.
"""
function get_meaning_model_name end

"""
    compute_meaning_vectors(llm::Llm, texts; purpose = :document) -> Matrix{Float32}

The meaning vectors of `texts`, one column per text. `purpose` is `:query` for
the text a search looks for and `:document` for the texts it looks in; a model
that reads the two differently is told which by its adapter.

Throws when the vectors can not be computed, with a message that says why — a
server that does not answer, or a model that is not installed.
"""
function compute_meaning_vectors end

"""
    make_llm(kind::Symbol; model, api_key, context, kwargs...) -> Llm

Construct the backend that its package registered under the symbol `kind`.

**Every backend accepts the same three keywords, and uses the ones that apply to
it.** They are what a caller can hold without knowing which provider will answer:

- `model`   — the model to talk to; empty means the backend's own default.
- `api_key` — the key, where there is one. A server on this machine asks for none,
              and its adapter ignores this.
- `context` — how many tokens of the conversation the model may see; `0` leaves it
              to the provider. A hosted provider fixes the window with the model
              and cannot be told, and its adapter ignores this.

A backend that ignores a keyword says so in its own documentation. That is the
price of a seam a caller can use without a provider in mind, and it is a smaller
price than a caller that must know.

A backend lives in an opt-in package, so nothing here can name its type. The
factory is keyed by symbol and dispatched on `Val`: each opt-in package adds one
method, and the method table IS the registry — there is no dictionary to keep in
step, and no process-global state. A missing method — its opt-in package is not
loaded — raises an error that lists the backends that are (`LlmDefaults.jl`).
"""
function make_llm end

"""
    get_default_llm_model(kind::Symbol) -> String

The model that the backend registered under `kind` falls back to. It belongs to the
backend, not to a caller: a Claude model id means nothing to a local server, so a
caller that holds one model name for every provider holds the wrong name for all but
one.

A backend can choose another model when `make_llm` gets an empty `model`. The
Anthropic adapter first asks the Models API for the newest model, and it uses this
model only when it has no key or when that request fails.
"""
function get_default_llm_model end
