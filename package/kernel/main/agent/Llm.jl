"""
    LlmModule

Pluggable LLM backend for the WorkbenchAssistant chat surface. The agent
loop (see `WorkbenchAssistantModule._run_agent_loop!`) drives a single
function — `stream_turn(backend, api_key, model, system, messages, tools;
on_event)` — and the backend decides how to materialise the SSE event
stream that `_handle_sse_event!` already consumes.

The in-process backends live here:

- `FakeLlm` — canned-reply backend that synthesises the SSE event shapes
  in-process. Useful for offline development, deterministic tests, and
  exercising the streaming-render path without a network call.
- `ScriptedLlm` — multi-round, tool-capable scripted backend.

The real-Claude backend (`AnthropicLlm`) lives entirely in the opt-in
`ProjecturedLlm` package (`package/llm`), so this module stays
dependency-free and names no concrete network backend.

This module aggregates three fragments — the interface (`LlmApi.jl`: the
abstract `Llm` supertype and the `stream_turn` generic) and one file per
in-process backend (`LlmFake.jl`, `LlmScripted.jl`) — since they are only
ever imported together. The files remain as fragments sharing this
namespace.
"""
module LlmModule

export Llm, FakeLlm, stream_turn,
       ScriptedLlm, make_scripted_turn, make_scripted_think, make_scripted_say, make_scripted_run

include("LlmApi.jl")      # abstract Llm + stream_turn generic (the seam)
include("LlmFake.jl")     # FakeLlm (in-process canned reply)
include("LlmScripted.jl") # ScriptedLlm + scripted-round builders

end # module
