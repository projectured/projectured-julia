# The Anthropic model backend

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../../kernel/agent.md), [assistant.md](../../platform/assistant/assistant.md)

`ProjecturedAnthropic` is an `Llm` backend that runs a Claude model over the Anthropic API. It is an opt-in package that implements the `llm` layer of the kernel. This document says how the adapter translates the wire format of the Anthropic API into the events of the kernel, how the backend registers itself, and what it does not do. The other backend is in [ollama.md](../ollama/ollama.md).

## How it works

The kernel declares the seam in `source/kernel/llm/LlmInterface.jl`, and [agent.md](../../kernel/agent.md) describes it: `stream_turn(llm, request; on_event)`, `render_tool_schema(llm, tools)`, `make_llm(kind; api_key, model, context)`, `get_default_llm_model(kind)`, and the three optional functions of a meaning model. The adapter translates the protocol of the Anthropic API into the `LlmMessage` and `LlmEvent` types of the kernel, so no caller reads a wire format. The table in [agent.md](../../kernel/agent.md#what-each-adapter-must-answer-for-itself) compares what each adapter does below the seam.

| | `ProjecturedAnthropic` |
| --- | --- |
| Source | `source/adapter/anthropic/AnthropicLlm.jl` |
| Backend type | `AnthropicLlm` |
| `make_llm` key | `:anthropic` |
| Where the model runs | the servers of Anthropic |
| Credential | `api_key`, by default the `ANTHROPIC_API_KEY` environment variable at construction |
| Default model | the newest model that takes adaptive thinking, else `"claude-opus-5"` |
| Keyword it ignores | `context` |
| Meaning vectors | none |

**The registration is a method.** The package adds `make_llm(::Val{:anthropic}; …)` and `get_default_llm_model` for the same key. It has no `__init__`. `get_llm_backend_names()` reads the loaded backends from the method table of `make_llm`, so the backend exists exactly while its package is loaded.

`AnthropicLlm` holds `api_key`, `model`, `base_url` and `max_tokens`. An empty `model` calls `get_newest_anthropic_model(api_key)`. It reads `/v1/models` once in a process for each key and models URL, and keeps the first model, newest first, whose capabilities say that it takes adaptive thinking. With no key, or when the request fails, the answer is `"claude-opus-5"`. That name is an alias, not a dated identifier, so it names a model that exists after a new one comes out.

`stream_turn` posts a request with `stream = true` and reads the server-sent events in chunks with `readavailable`. A buffer holds an incomplete event until the next chunk. When `on_event` throws, as the assistant does after a stop, the adapter closes the connection before it passes the exception on. The close of an HTTP stream reads the rest of the answer first, so without that the model would write, and bill, all of it. `_translate_sse!` turns each named event into an `LlmEvent`:

- `content_block_start` opens a text, a thinking, a redacted thinking or a tool call block.
- `content_block_stop` does not name the kind of the block, so the adapter keeps the open block in a `Ref` and sends the matching stop event.
- The arguments of a tool call arrive as JSON fragments. The adapter joins them and parses them when the block stops, so `LlmToolUseStop` carries a `Dict`. A payload that does not parse gives no arguments, and the turn goes on.
- `message_start` gives the input tokens and `message_delta` the output tokens, and `LlmTurnEnd` carries both with the stop reason. The stop reasons `stop_sequence`, `refusal` and `pause_turn` give `:end_turn`.

When a request sets `thinking`, the adapter sends `{"type": "adaptive", "display": "summarized"}` for a model whose name contains `opus` or `sonnet`, and nothing for another model. A thinking block goes back to the provider with its signature unchanged. A thinking block with no signature, as one that a stop cut or one that another backend made, is left out, because the API answers a request that holds one with an error, and a message that is then empty is left out too. An HTTP status of 400 or more throws an error with the body of the answer. An error inside the stream arrives as `LlmFailure`. A stream that ends before its turn end throws, as a dead socket does.

## How it fits

The package depends on the kernel, `HTTP` and `JSON3`. The third-party dependencies are the reason that it is an opt-in package; see [package-rules.md](../../../rule/package-rules.md). It does not depend on `ProjecturedOllama`, and the assistant slice of `ProjecturedPlatform` does not depend on it.

`Assistant.backend` names a backend by its key, and the assistant builds it with `make_llm` at each turn; see [assistant.md](../../platform/assistant/assistant.md). The test doubles `FakeLlm` and `ScriptedLlm` are in `ProjecturedKernelExample`, and never in a package of the main stack.

## Design decisions

- **The backend registers by a method of `make_llm`.** No dictionary must stay in step, and nothing runs at load time. `make_agent_server` for the MCP server has the same shape. See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The provider name marks the adapter.** The kernel keeps the neutral names `Llm` and `LlmModule`, and the adapter package carries the name of its provider. See [plan/done/ollama-backend.md](../../../../plan/done/ollama-backend.md).
- **The backend takes the three keywords and uses the ones that apply to it.** A caller can then build a backend with no provider in mind. The comment on its `make_llm` method says that it ignores `context`, because the context window comes with the model.
- **The adapter chooses the thinking parameter from the model name.** The Ollama adapter asks its server instead, because there a wrong request stops the turn; see [ollama.md](../ollama/ollama.md).
- **The default model is read once in a process for each key and models URL.** The list changes when Anthropic releases a model, not during a session, so a request for each turn gives nothing.

## Usage

```julia
using ProjecturedAnthropic
get_llm_backend_names()                        # [:anthropic], with no other backend loaded
llm = make_llm(:anthropic; model = "")         # the newest model, the key from ANTHROPIC_API_KEY
request = LlmRequest(; system = "Answer in three words.",
                       messages = [LlmMessage(:user, "Say OK.")])
stream_turn(llm, request; on_event = println)
```

- Tests: `test_anthropic()` runs the layering guard, `test_anthropic_model()` against a recorded answer of the Models API, and `test_anthropic_stream()` against a stream body and a stand-in server.
- The package has no example of its own. `run_assistant_example(; backend = :anthropic)` drives it through the assistant.

## Limits

- The live test skips itself when `ANTHROPIC_API_KEY` is not set. A change that only a live test would catch needs a real key.
- `AnthropicLlm` has no meaning model. With only this backend, a search by description ranks by its words.
- A model whose name contains neither `opus` nor `sonnet` gets no thinking parameter.
- When the first request to the Models API fails, an empty `model` gives `"claude-opus-5"` for the rest of the process.
- No test is marked `@test_broken`.
