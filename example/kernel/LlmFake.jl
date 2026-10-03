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
    FakeLlm(reply = "Yes, sir!"; chunk_size = 1, delay = 0.0, thinking = "",
            meaning_model = "")

Deterministic backend that always replies with `reply`, emitting
`chunk_size` characters per `LlmTextDelta` event. `delay` (in
seconds) sleeps between deltas so the reactive streaming-render path can
be exercised by tests.

When `thinking` is non-empty, a synthetic thinking block is streamed
*before* the text block: `LlmThinkingStart`, one or more `LlmThinkingDelta`s,
a single `LlmThinkingSignature("sig_fake")`, then `LlmThinkingStop` — so the
whole thinking capture/round-trip path is exercisable offline.

When `meaning_model` is a name, the backend has a meaning model: it computes a
text's meaning vector as a bag of its words, so two texts that share words have
vectors that lie close. That is enough to drive a search by description offline.
Empty, the default, means no meaning model.
"""
struct FakeLlm <: Llm
    reply::String
    chunk_size::Int
    delay::Float64
    thinking::String
    meaning_model::String
end

# @optional: the reply stands first, as the content the backend returns; the rest is its chrome.
FakeLlm(reply::AbstractString = "Yes, sir!";
        chunk_size::Integer = 1,
        delay::Real = 0.0,
        thinking::AbstractString = "",
        meaning_model::AbstractString = "") =
    FakeLlm(String(reply), max(1, Int(chunk_size)), Float64(delay), String(thinking),
            String(meaning_model))

has_meaning_model(b::FakeLlm) = !isempty(b.meaning_model)

get_meaning_model_name(b::FakeLlm) =
    has_meaning_model(b) ? "fake/" * b.meaning_model : error("FakeLlm has no meaning model.")

# The length of a fake meaning vector.
const _FAKE_MEANING_SIZE = 64

function compute_meaning_vectors(b::FakeLlm, texts; purpose::Symbol = :document)
    has_meaning_model(b) || error("FakeLlm has no meaning model.")
    vectors = zeros(Float32, _FAKE_MEANING_SIZE, length(texts))
    for (column, text) in enumerate(texts)
        for word in split(lowercase(text), r"[^a-z0-9]+")
            length(word) >= 2 || continue
            vectors[_get_fake_meaning_place(word), column] += 1
        end
    end
    vectors
end

# The place a word adds to. FNV-1a over the bytes, so the place is the same in
# every Julia version and in every process.
function _get_fake_meaning_place(word::AbstractString)
    hash = UInt32(2166136261)
    for byte in codeunits(word)
        hash = (hash ⊻ byte) * UInt32(16777619)
    end
    Int(hash % _FAKE_MEANING_SIZE) + 1
end

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
