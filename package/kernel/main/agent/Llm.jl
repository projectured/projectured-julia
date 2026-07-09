"""
    LlmModule

Pluggable LLM backend for the WorkbenchAssistant chat surface. The agent
loop (see `WorkbenchAssistantModule._run_agent_loop!`) drives a single
function — `stream_turn(backend, api_key, model, system, messages, tools;
on_event)` — and the backend decides how to materialise the SSE event
stream that `_handle_sse_event!` already consumes.

This module is the **seam only** — the abstract `Llm` supertype and the
`stream_turn` generic (in `LlmApi.jl`). It defines no concrete backend and
stays dependency-free:

- The real-Claude backend (`AnthropicLlm`) lives entirely in the opt-in
  `ProjecturedLlm` package (`package/llm`).
- The test-double backends (`FakeLlm`, `ScriptedLlm`) are fakes and so live
  in `ProjecturedKernelExample` (`package/kernel/example`), never in `main` —
  no fake is reachable from a production build. See architecture requirement
  #68 (no test doubles in `main` packages).
"""
module LlmModule

export Llm, stream_turn

include("LlmApi.jl") # abstract Llm + stream_turn generic (the seam)

end # module
