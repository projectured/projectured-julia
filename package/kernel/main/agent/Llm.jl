"""
    LlmModule

Pluggable LLM backend for the WorkbenchAssistant chat surface. The agent
loop (see `WorkbenchAssistantModule._run_agent_loop!`) drives a single
function — `stream_turn(backend, api_key, model, system, messages, tools;
on_event)` — and the backend decides how to materialise the SSE event
stream that `_handle_sse_event!` already consumes.

Two concrete backends:

- `AnthropicLlm` — real Claude over HTTP+SSE; thin wrapper around
  `ProjecturedLlm.stream_message` (the opt-in `ProjecturedLlm` package,
  `package/llm`).
- `FakeLlm` — canned-reply backend that synthesises the SSE event shapes
  in-process. Useful for offline development, deterministic tests, and
  exercising the streaming-render path without a network call.

This module aggregates four fragments — the interface (`LlmApi.jl`: the
abstract `Llm` supertype and the `stream_turn` generic) and one file per
concrete backend (`LlmAnthropic.jl`, `LlmFake.jl`, `LlmScripted.jl`) —
since they are only ever imported together. The files remain as fragments
sharing this namespace.
"""
module LlmModule

export Llm, AnthropicLlm, FakeLlm, stream_turn,
       ScriptedLlm, make_scripted_turn, make_scripted_think, make_scripted_say, make_scripted_run

include("LlmApi.jl")       # abstract Llm + stream_turn generic (the seam)
include("LlmAnthropic.jl") # AnthropicLlm (real-Claude struct; method in ProjecturedLlm)
include("LlmFake.jl")      # FakeLlm (in-process canned reply)
include("LlmScripted.jl")  # ScriptedLlm + scripted-round builders

end # module
