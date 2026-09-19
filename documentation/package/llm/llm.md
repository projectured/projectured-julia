# The two model backends

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [assistant.md](../assistant/assistant.md)

`ProjecturedAnthropic` and `ProjecturedOllama` are the two concrete `Llm`
backends: one runs a hosted Claude model over the Anthropic API, the other
runs a model on this machine through a local Ollama server. Both are opt-in
packages that implement the same seam the kernel's `LlmModule` declares, and
[assistant.md](../assistant/assistant.md) is what holds one and drives a
turn with it.

## What each package needs to run

| | `anthropic` | `ollama` |
| --- | --- | --- |
| Package | `ProjecturedAnthropic` | `ProjecturedOllama` |
| Source | `source/anthropic/Anthropic.jl` | `source/ollama/Ollama.jl` |
| Backend type | `AnthropicLlm` | `OllamaLlm` |
| `make_llm` key | `:anthropic` | `:ollama` |
| Where the model runs | Anthropic's servers | this machine, served by Ollama |
| Credential | `api_key`, defaulting to `ENV["ANTHROPIC_API_KEY"]` | none — a local server needs none |
| Default model | `"claude-opus-5"`, or the newest model the Models API reports supports adaptive thinking | `"qwen3.8:27b"` |
| Meaning vectors | not implemented | `compute_meaning_vectors`, through `/api/embed`, `"nomic-embed-text"` by default |

`AnthropicLlm`'s empty-model default asks `https://api.anthropic.com/v1/models`
once per process and keeps the answer, since the list changes only when
Anthropic releases a model. `OllamaLlm`'s `base_url` defaults to
`http://localhost:11434`; a model must be pulled on that server first
(`ollama pull <model>`), and a chat request against a model that is not
throws an error naming the models the server does have.

## The `Llm` interface both answer

`source/kernel/llm/LlmInterface.jl` declares the abstract `Llm` and the seam:

- `stream_turn(llm, request; on_event)` — run one turn, translating the
  provider's own streaming protocol (Anthropic's server-sent events,
  Ollama's newline-delimited JSON) into the project's own `LlmEvent`s:
  `LlmTextDelta`, `LlmThinkingDelta`, `LlmToolUseStart` / `LlmToolUseStop`,
  `LlmTurnEnd`, `LlmFailure`. No caller ever sees a provider's wire format.
- `render_tool_schema(llm, tools)` — render the editor's `Tool`s into the
  shape the provider's API wants: a JSON-Schema object under `input_schema`
  for Anthropic, a `{"type": "function", "function": {...}}` wrapper for
  Ollama.
- `has_meaning_model`, `get_meaning_model_name`, `compute_meaning_vectors` —
  optional; a backend with none keeps the `Llm` default of `false` and an
  error naming itself.

`make_llm(kind::Symbol; model, api_key, context, kwargs...)` builds a backend
by name without naming its type: `make_llm(:ollama)`. Every backend accepts
the same three keywords and uses only the ones that apply to it. An adapter
ignores a keyword it has no use for and says so in its own docstring. The
Anthropic adapter ignores `context`, since a hosted model fixes its context
window; the Ollama adapter ignores `api_key`, since a local server asks for
none. A `kind` whose package is not loaded raises an error that names the
backends that are; `get_llm_backend_names()` reads that list from the method
table of `make_llm` itself, so nothing needs to unregister a backend that
unloads.

## How it fits

`Assistant.backend` holds `:anthropic`, `:ollama` or `:none`; `AssistantTurn`
calls `stream_turn` on whichever `Llm` that resolves to. Neither backend
package depends on the other, and neither is a dependency of
`ProjecturedAssistant` — a session that never loads `ProjecturedAnthropic`
or `ProjecturedOllama` can still open the assistant pane with
`backend = :none`, which answers nothing. A tool call inside a turn goes
through the same `ToolSet` regardless of which backend is asking; only the
rendering of the tool list into the request, and the parsing of a tool call
out of the response, differ per backend.

## What to check when a change touches this slice

`test/anthropic/AnthropicTest.jl` reaches the network only in one test, which
skips itself with no `ANTHROPIC_API_KEY`; every other assertion — the model
choice, the request render, the backend registration — runs against a
recorded Models API answer. `test_ollama()`
(`test/ollama/OllamaSuite.jl`, `test/ollama/OllamaTest.jl`) is the same
shape: the request render and the stream translation run against recorded
data, and the one live turn and the one live meaning-vector test each skip
themselves, logging why, when no server or no model answers at
`http://localhost:11434`. A change to either backend that only the skipped
test would catch needs a real server or a real key to verify.
