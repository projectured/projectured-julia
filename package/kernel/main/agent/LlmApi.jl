# Fragment of `LlmModule` — the LLM backend contract: the abstract `Llm`
# supertype and the `stream_turn` generic every concrete backend adds a
# method for. The concrete backends live one-per-file alongside this one:
# `LlmAnthropic.jl` (`AnthropicLlm`), `LlmFake.jl` (`FakeLlm`), and
# `LlmScripted.jl` (`ScriptedLlm` + its scripted-round builders).

# ═══════════════════════════════════════════════════════════════════════
# Interface
# ═══════════════════════════════════════════════════════════════════════

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

"""
    stream_turn(backend, api_key, model, system, messages, tools; on_event)

Drive a single chat turn. `on_event(ev::NamedTuple)` is called for each
event; `ev` has at least `:type` (`Symbol`) and `:data` (the event
payload). Errors propagate to the caller.
"""
function stream_turn end
