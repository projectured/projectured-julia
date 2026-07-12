"""
    LlmModule

Pluggable LLM backend for the WorkbenchAssistant chat surface. The agent
loop (see `WorkbenchAssistantModule._run_agent_loop!`) drives a single
function — `stream_turn(backend, api_key, model, system, messages, tools;
on_event)` — and the backend decides how to materialise the SSE event
stream that `_handle_sse_event!` already consumes.

This module is the **seam only** — the abstract `Llm` supertype and the
`stream_turn` generic. It defines no concrete backend and stays
dependency-free:

- The real-Claude backend (`AnthropicLlm`) lives entirely in the opt-in
  `ProjecturedLlm` package (`package/llm`).
- The test-double backends (`FakeLlm`, `ScriptedLlm`) are fakes and so live
  in `ProjecturedKernelExample` (`package/kernel/example`), never in `main` —
  no fake is reachable from a production build. See architecture requirement
  #68 (no test doubles in `main` packages).
"""
module LlmModule

import ..DocumentModule: is_opaque

export Llm, stream_turn

"""
    Llm

Abstract supertype for chat backends. Each concrete subtype defines a
method on `stream_turn` that takes the assistant's current context
(`api_key`, `model`, `system`, prior `messages`, available `tools`) and
emits SSE-shaped events through `on_event`. Events follow Anthropic's
streaming spec — `message_start`, `content_block_start`,
`content_block_delta`, `content_block_stop`, `message_delta`,
`message_stop` — so the same event handler works for all backends.
"""
abstract type Llm end

# Assistant configuration, not addressable document content (it may hold large
# scripted event payloads / API config) — opaque to reflection walkers, so
# `search_references` / `search_documents` never descend into it.
is_opaque(::Llm) = true

"""
    stream_turn(backend, api_key, model, system, messages, tools; on_event)

Drive a single chat turn. `on_event(ev::NamedTuple)` is called for each
event; `ev` has at least `:type` (`Symbol`) and `:data` (the event
payload). Errors propagate to the caller.
"""
function stream_turn end

end # module
