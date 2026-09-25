# The two model backends

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../kernel/agent.md), [assistant.md](../assistant/assistant.md)

`ProjecturedAnthropic` and `ProjecturedOllama` are the two `Llm` backends: one runs a Claude model over the Anthropic API, and the other runs a model on this machine through a local Ollama server. Both are opt-in packages that implement the `llm` layer of the kernel. This document says how each adapter translates its wire format into the events of the kernel, how a backend registers itself, and what each one does not do.

## How it works

The kernel declares the seam in `source/kernel/llm/LlmInterface.jl`, and [agent.md](../kernel/agent.md) describes it: `stream_turn(llm, request; on_event)`, `render_tool_schema(llm, tools)`, `make_llm(kind; api_key, model, context)`, `default_llm_model(kind)`, and the three optional functions of a meaning model. An adapter translates its own protocol into the `LlmMessage` and `LlmEvent` types of the kernel, so no caller reads a wire format. The table in [agent.md](../kernel/agent.md#what-each-adapter-must-answer-for-itself) compares what each adapter does below the seam.

| | `ProjecturedAnthropic` | `ProjecturedOllama` |
| --- | --- | --- |
| Source | `source/anthropic/Anthropic.jl` | `source/ollama/Ollama.jl` |
| Backend type | `AnthropicLlm` | `OllamaLlm` |
| `make_llm` key | `:anthropic` | `:ollama` |
| Where the model runs | the servers of Anthropic | this machine, at `http://localhost:11434` by default |
| Credential | `api_key`, by default the `ANTHROPIC_API_KEY` environment variable at construction | none |
| Default model | the newest model that takes adaptive thinking, else `"claude-opus-5"` | `"qwen3.8:27b"` |
| Keyword it ignores | `context` | `api_key` |
| Meaning vectors | none | `/api/embed`, with `"nomic-embed-text"` by default |

**The registration is a method.** Each package adds `make_llm(::Val{:anthropic}; …)` or `make_llm(::Val{:ollama}; …)`, and `default_llm_model` for the same key. Neither package has an `__init__`. `get_llm_backend_names()` reads the loaded backends from the method table of `make_llm`, so a backend exists exactly while its package is loaded.

### ProjecturedAnthropic

`AnthropicLlm` holds `api_key`, `model`, `base_url` and `max_tokens`. An empty `model` calls `get_newest_anthropic_model(api_key)`. It reads `/v1/models` once in a process and keeps the first model, newest first, whose capabilities say that it takes adaptive thinking. With no key, or when the request fails, the answer is `"claude-opus-5"`. That name is an alias, not a dated identifier, so it names a model that exists after a new one comes out.

`stream_turn` posts a request with `stream = true` and reads the server-sent events in chunks with `readavailable`. A buffer holds an incomplete event until the next chunk. `_translate_sse!` turns each named event into an `LlmEvent`:

- `content_block_start` opens a text, a thinking, a redacted thinking or a tool call block.
- `content_block_stop` does not name the kind of the block, so the adapter keeps the open block in a `Ref` and sends the matching stop event.
- The arguments of a tool call arrive as JSON fragments. The adapter joins them and parses them when the block stops, so `LlmToolUseStop` carries a `Dict`. A payload that does not parse gives no arguments, and the turn goes on.
- `message_start` gives the input tokens and `message_delta` the output tokens, and `LlmTurnEnd` carries both with the stop reason.

When a request sets `thinking`, the adapter sends `{"type": "adaptive", "display": "summarized"}` for a model whose name contains `opus` or `sonnet`, and nothing for another model. A thinking block goes back to the provider with its signature unchanged. An HTTP status of 400 or more throws an error with the body of the answer. An error inside the stream arrives as `LlmFailure`.

### ProjecturedOllama

`OllamaLlm` holds `model`, `base_url`, `max_tokens`, `context`, `thinking`, `temperature`, `seed` and `meaning_model`. `base_url` is the server, not one endpoint, because the adapter uses `/api/chat`, `/api/show`, `/api/embed` and `/api/tags`. A `context` of `0` sends no `num_ctx`, so the server sets the size of the window. `temperature` and `seed` are `nothing` by default and keep the sampling of the server; a repeatable run sets both.

Three rules of Ollama shape the messages. The system prompt is a message with the role `system`. A tool result is a message with the role `tool`, and it names the tool, not the call. `LlmToolResult` holds only the id of the call, so the adapter builds a map from id to name while it walks the history. A result whose id is not in the map goes as a user text message. A redacted thinking block has no Ollama form and is dropped.

Ollama sends one JSON object for each line, with no block framing. `_line_handler` opens a text or thinking block when the kind of the delta changes, and closes the open block before a tool call and at the end. A tool call arrives whole in one line, so the adapter sends `LlmToolUseStart`, one `LlmToolInputDelta` with the whole arguments, and `LlmToolUseStop`. A call with no id gets `ollama_call_<n>`, because the result must pair with it.

**The adapter corrects the stop reason.** Ollama reports `done_reason: "stop"` on a round that made tool calls, and `run_turn!` runs the tools only when the round ends in `:tool_use`. So when any call arrived, `LlmTurnEnd` carries `:tool_use`, whatever the server said.

**The adapter reads from the server whether the model reasons.** With `thinking = nothing`, `_supports_thinking` posts `/api/show` once and looks for `thinking` in the capabilities of the model. It keeps the answer in `thinking_answer` on the instance, not in a module global, because one process can run many editors. A server that does not answer gives `false`, which costs the turn its reasoning and not the turn.

`compute_meaning_vectors` posts to `/api/embed` in batches of 64. It puts the prefix of the model family and the purpose, `:query` or `:document`, in front of each text: `nomic-embed-text` and `mxbai-embed-large` have one, and another model gets none. When the server does not have a model, the error lists the models it has and gives the `ollama pull` command.

## How it fits

Each package depends on the kernel, `HTTP` and `JSON3`. The third-party dependencies are the reason that both are opt-in packages; see [package-rules.md](../../rule/package-rules.md). Neither depends on the other, and `ProjecturedAssistant` depends on neither.

`Assistant.backend` names a backend by its key, and the assistant builds it with `make_llm` at each turn; see [assistant.md](../assistant/assistant.md). `bind_meaning_model!` gives the meaning model of a backend to a tool set, which the assistant does at each turn. The test doubles `FakeLlm` and `ScriptedLlm` are in `ProjecturedKernelExample`, and never in a package of the main stack.

## Design decisions

- **A backend registers by a method of `make_llm`.** No dictionary must stay in step, and nothing runs at load time. `make_agent_server` for the MCP server has the same shape. See [plan/done/ollama-backend.md](../../../plan/done/ollama-backend.md).
- **The provider name marks the adapter.** The kernel keeps the neutral names `Llm` and `LlmModule`, and each adapter package carries the name of its provider. See [plan/done/ollama-backend.md](../../../plan/done/ollama-backend.md).
- **A backend takes the three keywords and uses the ones that apply to it.** A caller can then build a backend with no provider in mind. Each adapter says in its docstring which keyword it ignores.
- **The Ollama adapter reads the capabilities of the model, and the Anthropic adapter uses the model name.** Ollama answers HTTP 400 to the whole request when a model that can not reason gets a request to reason. So a guess from the name could stop the turn. See [plan/done/ollama-backend.md](../../../plan/done/ollama-backend.md).
- **The meaning model is a keyword of `OllamaLlm`, and not a fourth keyword of the seam.** It belongs to one provider. See [plan/done/three-kinds-of-search.md](../../../plan/done/three-kinds-of-search.md).
- **The Anthropic default model is read once in a process.** The list changes when Anthropic releases a model, not during a session, so a request for each turn gives nothing.

## Usage

```julia
using ProjecturedOllama, ProjecturedAnthropic
get_llm_backend_names()                        # [:anthropic, :ollama]
llm = make_llm(:ollama)                        # qwen3.8:27b at http://localhost:11434
llm = OllamaLlm(; model = "llama3.1:70b", context = 16384, temperature = 0.0, seed = 1)
llm = make_llm(:anthropic; model = "")         # the newest model, the key from ANTHROPIC_API_KEY
request = LlmRequest(; system = "Answer in three words.",
                       messages = [LlmMessage(:user, "Say OK.")])
stream_turn(llm, request; on_event = println)
```

- Tests: `test_anthropic()` runs the layering guard and `test_anthropic_model()`, against a recorded answer of the Models API. `test_ollama()` runs the layering guard, `test_ollama_request()`, `test_ollama_stream()`, `test_ollama_backend()`, `test_ollama_meaning()` and the two live tests `test_ollama_live()` and `test_ollama_meaning_live()`.
- Neither package has an example of its own. `run_assistant_example(; backend = :ollama)` or `backend = :anthropic` drives one through the assistant.

## Limits

- The live tests skip themselves. The Anthropic test needs `ANTHROPIC_API_KEY`. The Ollama chat test needs a server and uses only a chat model that the server already holds in memory, so that the suite never loads a model of several gigabytes. A change that only a live test would catch needs a real server or a real key.
- `AnthropicLlm` has no meaning model. With only this backend, a search by description ranks by its words.
- A model whose name contains neither `opus` nor `sonnet` gets no thinking parameter from the Anthropic adapter.
- When the first request to the Models API fails, an empty `model` gives `"claude-opus-5"` for the rest of the process.
- The Ollama adapter drops a redacted thinking block from the history.
- No test is marked `@test_broken`.
