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
`chunk_size` characters per `content_block_delta` event. `delay` (in
seconds) sleeps between deltas so the reactive streaming-render path can
be exercised by tests.

When `thinking` is non-empty, a synthetic thinking block is streamed
*before* the text block: `content_block_start{type:"thinking"}`, one or
more `thinking_delta`s, a single `signature_delta{signature:"sig_fake"}`,
then `content_block_stop` — so the whole thinking capture/round-trip path
is exercisable offline.
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

function stream_turn(b::FakeLlm,
                     _api_key::AbstractString,
                     _model::AbstractString,
                     _system::AbstractString,
                     _messages::AbstractVector,
                     _tools::AbstractVector;
                     on_event::Function,
                     thinking = nothing,
                     output_config = nothing)
    on_event((type = :message_start, data = Dict{Symbol,Any}()))
    # Synthetic thinking block first, when scripted.
    if !isempty(b.thinking)
        on_event((type = :content_block_start,
                  data = Dict{Symbol,Any}(:content_block =>
                                           Dict{Symbol,Any}(:type => "thinking"))))
        tchars = collect(b.thinking)
        tn = length(tchars)
        ti = 1
        while ti <= tn
            tj = min(ti + b.chunk_size - 1, tn)
            on_event((type = :content_block_delta,
                      data = Dict{Symbol,Any}(:delta =>
                                                Dict{Symbol,Any}(:type     => "thinking_delta",
                                                                  :thinking => String(tchars[ti:tj])))))
            b.delay > 0 && sleep(b.delay)
            ti = tj + 1
        end
        on_event((type = :content_block_delta,
                  data = Dict{Symbol,Any}(:delta =>
                                            Dict{Symbol,Any}(:type      => "signature_delta",
                                                              :signature => "sig_fake"))))
        on_event((type = :content_block_stop, data = Dict{Symbol,Any}()))
    end
    on_event((type = :content_block_start,
              data = Dict{Symbol,Any}(:content_block =>
                                       Dict{Symbol,Any}(:type => "text"))))
    # Chunk by character, not byte: `b.reply[i:j]` indexes bytes and throws on
    # any multi-byte character (e.g. an em dash or emoji), so collect to a Char
    # vector and slice that.
    chars = collect(b.reply)
    n = length(chars)
    i = 1
    while i <= n
        j = min(i + b.chunk_size - 1, n)
        on_event((type = :content_block_delta,
                  data = Dict{Symbol,Any}(:delta =>
                                            Dict{Symbol,Any}(:type => "text_delta",
                                                              :text => String(chars[i:j])))))
        b.delay > 0 && sleep(b.delay)
        i = j + 1
    end
    on_event((type = :content_block_stop, data = Dict{Symbol,Any}()))
    on_event((type = :message_delta,
              data = Dict{Symbol,Any}(:delta =>
                                        Dict{Symbol,Any}(:stop_reason => "end_turn"))))
    on_event((type = :message_stop, data = Dict{Symbol,Any}()))
    nothing
end
