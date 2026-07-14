# Fragment of `ProjecturedKernelExample` — the in-process `FakeLlm`
# backend: a canned reply (optionally preceded by a synthetic thinking
# block) streamed as SSE events, no network. A test double for the kernel's
# `LlmModule.Llm` seam; it lives in the example package (never in `main`)
# so no fake reaches a production build. Useful for offline development,
# deterministic tests, and exercising the streaming-render path.

# ═══════════════════════════════════════════════════════════════════════
# FakeLlm — canned reply, no network
# ═══════════════════════════════════════════════════════════════════════

"""
    FakeLlm(reply = "Yes, sir!"; chunk_size = 1, delay = 0.0, thinking = "")

Deterministic backend that always replies with `reply`, emitting
`chunk_size` characters per `LlmTextDelta` event. `delay` (in
seconds) sleeps between deltas so the reactive streaming-render path can
be exercised by tests.

When `thinking` is non-empty, a synthetic thinking block is streamed
*before* the text block: `LlmThinkingStart`, one or more `LlmThinkingDelta`s,
a single `LlmThinkingSignature("sig_fake")`, then `LlmThinkingStop` — so the
whole thinking capture/round-trip path is exercisable offline.
"""
struct FakeLlm <: Llm
    reply::String
    chunk_size::Int
    delay::Float64
    thinking::String
end

FakeLlm(reply::AbstractString = "Yes, sir!";
        chunk_size::Integer = 1,
        delay::Real = 0.0,
        thinking::AbstractString = "") =
    FakeLlm(String(reply), max(1, Int(chunk_size)), Float64(delay), String(thinking))

function stream_turn(b::FakeLlm, _request::LlmRequest; on_event::Function)
    # Synthetic thinking block first, when scripted.
    if !isempty(b.thinking)
        on_event(LlmThinkingStart())
        tchars = collect(b.thinking)
        tn = length(tchars)
        ti = 1
        while ti <= tn
            tj = min(ti + b.chunk_size - 1, tn)
            on_event(LlmThinkingDelta(String(tchars[ti:tj])))
            b.delay > 0 && sleep(b.delay)
            ti = tj + 1
        end
        on_event(LlmThinkingSignature("sig_fake"))
        on_event(LlmThinkingStop())
    end
    on_event(LlmTextStart())
    # Chunk by character, not byte: `b.reply[i:j]` indexes bytes and throws on
    # any multi-byte character (e.g. an em dash or emoji), so collect to a Char
    # vector and slice that.
    chars = collect(b.reply)
    n = length(chars)
    i = 1
    while i <= n
        j = min(i + b.chunk_size - 1, n)
        on_event(LlmTextDelta(String(chars[i:j])))
        b.delay > 0 && sleep(b.delay)
        i = j + 1
    end
    on_event(LlmTextStop())
    on_event(LlmTurnEnd(:end_turn))
    nothing
end
