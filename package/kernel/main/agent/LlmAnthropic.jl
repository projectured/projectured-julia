# Fragment of `LlmModule` — the real-Claude backend struct. Only the
# (dependency-free) `AnthropicLlm` type lives here; its `stream_turn`
# method calls `ProjecturedLlm.stream_message` (HTTP/JSON3) and therefore
# lives in the opt-in `ProjecturedLlm` package (`package/llm`), keeping
# `LlmModule` dependency-free.

# ═══════════════════════════════════════════════════════════════════════
# AnthropicLlm — real Claude
# ═══════════════════════════════════════════════════════════════════════

"""
    AnthropicLlm(; base_url, max_tokens)

Real Claude backend. Requires `api_key` to be set on the assistant
(typically from `ENV["ANTHROPIC_API_KEY"]`).
"""
struct AnthropicLlm <: Llm
    base_url::String
    max_tokens::Int
end

AnthropicLlm(; base_url::AbstractString = "https://api.anthropic.com/v1/messages",
               max_tokens::Integer = 4096) =
    AnthropicLlm(String(base_url), Int(max_tokens))

# The `stream_turn(::AnthropicLlm, …)` method calls `ProjecturedLlm.stream_message`
# (HTTP/JSON3) and therefore lives in the standalone `ProjecturedLlm` package
# (package/llm) — not here. This module stays dependency-free: it holds only the
# abstract `Llm`, the `stream_turn` generic, the (dep-free) `AnthropicLlm`
# struct, and the in-process `FakeLlm` / `ScriptedLlm`.
