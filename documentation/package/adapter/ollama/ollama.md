# The Ollama model backend

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../../kernel/agent.md), [assistant.md](../../platform/assistant/assistant.md)

`ProjecturedOllama` is an `Llm` backend that runs a model on this machine through a local Ollama server. It is an opt-in package that implements the `llm` layer of the kernel. This document says how the adapter translates the wire format of Ollama into the events of the kernel, how the backend registers itself, and what it does not do. The other backend is in [anthropic.md](../anthropic/anthropic.md).

## How it works

The kernel declares the seam in `source/kernel/llm/LlmInterface.jl`, and [agent.md](../../kernel/agent.md) describes it: `stream_turn(llm, request; on_event)`, `render_tool_schema(llm, tools)`, `make_llm(kind; api_key, model, context)`, `get_default_llm_model(kind)`, and the three optional functions of a meaning model. The adapter translates the protocol of Ollama into the `LlmMessage` and `LlmEvent` types of the kernel, so no caller reads a wire format. The table in [agent.md](../../kernel/agent.md#what-each-adapter-must-answer-for-itself) compares what each adapter does below the seam.

| | `ProjecturedOllama` |
| --- | --- |
| Source | `source/adapter/ollama/OllamaLlm.jl` |
| Backend type | `OllamaLlm` |
| `make_llm` key | `:ollama` |
| Where the model runs | this machine, at `http://localhost:11434` by default |
| Credential | none |
| Default model | `"qwen3.8:27b"` |
| Keyword it ignores | `api_key` |
| Meaning vectors | `/api/embed`, with `"nomic-embed-text"` by default |

**The registration is a method.** The package adds `make_llm(::Val{:ollama}; …)` and `get_default_llm_model` for the same key. It has no `__init__`. `get_llm_backend_names()` reads the loaded backends from the method table of `make_llm`, so the backend exists exactly while its package is loaded.

`OllamaLlm` holds `model`, `base_url`, `max_tokens`, `context`, `thinking`, `temperature`, `seed` and `meaning_model`. `base_url` is the server, not one endpoint, because the adapter uses `/api/chat`, `/api/show`, `/api/embed` and `/api/tags`. A `context` of `0` sends no `num_ctx`, so the server sets the size of the window. `temperature` and `seed` are `nothing` by default and keep the sampling of the server; a repeatable run sets both.

Three rules of Ollama shape the messages. The system prompt is a message with the role `system`. A tool result is a message with the role `tool`, and it names the tool, not the call. `LlmToolResult` holds only the id of the call, so the adapter builds a map from id to name while it walks the history. A result whose id is not in the map goes as a user text message. A redacted thinking block has no Ollama form and is dropped.

Ollama sends one JSON object for each line, with no block framing. When `on_event` throws, as the assistant does after a stop, the adapter closes the connection before it passes the exception on, so the model stops at once; the close of an HTTP stream would read the rest of the answer first. `_line_handler` opens a text or thinking block when the kind of the delta changes, and closes the open block before a tool call and at the end. A tool call arrives whole in one line, so the adapter sends `LlmToolUseStart`, one `LlmToolInputDelta` with the whole arguments, and `LlmToolUseStop`. A call with no id gets `ollama_call_<n>`, because the result must pair with it. A stream that ends before the line with `done` throws.

**The adapter corrects the stop reason.** Ollama reports `done_reason: "stop"` on a round that made tool calls, and `run_turn!` runs the tools only when the round ends in `:tool_use`. So when any call arrived, `LlmTurnEnd` carries `:tool_use`, whatever the server said.

**The adapter reads from the server whether the model reasons.** With `thinking = nothing`, `_supports_thinking` posts `/api/show` once and looks for `thinking` in the capabilities of the model. It keeps the answer in `thinking_answer` on the instance, not in a module global, because one process can run many editors. A server that does not answer gives `false`, which costs the turn its reasoning and not the turn.

`compute_meaning_vectors` posts to `/api/embed` in batches of 64. It puts the prefix of the model family and the purpose, `:query` or `:document`, in front of each text: `nomic-embed-text` and `mxbai-embed-large` have one, and another model gets none. When the server does not have a model, the error lists the models it has and gives the `ollama pull` command.

## How it fits

The package depends on the kernel, `HTTP` and `JSON3`. The third-party dependencies are the reason that it is an opt-in package; see [package-rules.md](../../../rule/package-rules.md). It does not depend on `ProjecturedAnthropic`, and the assistant slice of `ProjecturedPlatform` does not depend on it.

`Assistant.backend` names a backend by its key, and the assistant builds it with `make_llm` at each turn; see [assistant.md](../../platform/assistant/assistant.md). `bind_meaning_model!` gives the meaning model of the backend to a tool set, which the assistant does at each turn. The test doubles `FakeLlm` and `ScriptedLlm` are in `ProjecturedKernelExample`, and never in a package of the main stack.

## Design decisions

- **The backend registers by a method of `make_llm`.** No dictionary must stay in step, and nothing runs at load time. `make_agent_server` for the MCP server has the same shape. See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The provider name marks the adapter.** The kernel keeps the neutral names `Llm` and `LlmModule`, and the adapter package carries the name of its provider. See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The backend takes the three keywords and uses the ones that apply to it.** A caller can then build a backend with no provider in mind. The comment on its `make_llm` method says that it ignores `api_key`, because a server on this machine needs no key.
- **The adapter reads the capabilities of the model, and does not guess from the model name.** Ollama answers HTTP 400 to the whole request when a model that can not reason gets a request to reason. So a guess from the name could stop the turn. The Anthropic adapter uses the model name; see [anthropic.md](../anthropic/anthropic.md). See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The meaning model is a keyword of `OllamaLlm`, and not a fourth keyword of the seam.** It belongs to one provider. See [plan/done/three-kinds-of-search.md](../../../../plan/done/three-kinds-of-search.md).

## Usage

```julia
using ProjecturedOllama
get_llm_backend_names()                        # [:ollama], with no other backend loaded
llm = make_llm(:ollama)                        # qwen3.8:27b at http://localhost:11434
llm = OllamaLlm(; model = "llama3.1:70b", context = 16384, temperature = 0.0, seed = 1)
request = LlmRequest(; system = "Answer in three words.",
                       messages = [LlmMessage(:user, "Say OK.")])
stream_turn(llm, request; on_event = println)
```

- Tests: `test_ollama()` runs the layering guard, `test_ollama_request()`, `test_ollama_stream()`, `test_ollama_backend()`, `test_ollama_meaning()` and the two live tests `test_ollama_live()` and `test_ollama_meaning_live()`.
- The package has no example of its own. `run_assistant_example(; backend = :ollama)` drives it through the assistant.

## Limits

- The live tests skip themselves. The chat test needs a server and uses only a chat model that the server already holds in memory, so that the suite never loads a model of several gigabytes. A change that only a live test would catch needs a real server.
- The adapter drops a redacted thinking block from the history.
- No test is marked `@test_broken`.
