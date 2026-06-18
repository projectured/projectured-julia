"""
    LlmModule

Pluggable LLM backend for the WorkbenchAssistant chat surface. The agent
loop (see `WorkbenchAssistantModule._run_agent_loop!`) drives a single
function — `stream_turn(backend, api_key, model, system, messages, tools;
on_event)` — and the backend decides how to materialise the SSE event
stream that `_handle_sse_event!` already consumes.

Two concrete backends:

- `AnthropicLlm` — real Claude over HTTP+SSE; thin wrapper around
  `AnthropicModule.stream_message`.
- `FakeLlm` — canned-reply backend that synthesises the SSE event shapes
  in-process. Useful for offline development, deterministic tests, and
  exercising the streaming-render path without a network call.
"""
module LlmModule

import ..AnthropicModule: stream_message

export LlmBackend, AnthropicLlm, FakeLlm, stream_turn

# ═══════════════════════════════════════════════════════════════════════
# Interface
# ═══════════════════════════════════════════════════════════════════════

"""
    LlmBackend

Abstract supertype for chat backends. Each concrete subtype defines a
method on `stream_turn` that takes the assistant's current context
(`api_key`, `model`, `system`, prior `messages`, available `tools`) and
emits SSE-shaped events through `on_event`. Events follow Anthropic's
streaming spec — `message_start`, `content_block_start`,
`content_block_delta`, `content_block_stop`, `message_delta`,
`message_stop` — so the same event handler works for all backends.
"""
abstract type LlmBackend end

"""
    stream_turn(backend, api_key, model, system, messages, tools; on_event)

Drive a single chat turn. `on_event(ev::NamedTuple)` is called for each
event; `ev` has at least `:type` (`Symbol`) and `:data` (the event
payload). Errors propagate to the caller.
"""
function stream_turn end

# ═══════════════════════════════════════════════════════════════════════
# AnthropicLlm — real Claude
# ═══════════════════════════════════════════════════════════════════════

"""
    AnthropicLlm(; base_url, max_tokens)

Real Claude backend. Requires `api_key` to be set on the assistant
(typically from `ENV["ANTHROPIC_API_KEY"]`).
"""
struct AnthropicLlm <: LlmBackend
    base_url::String
    max_tokens::Int
end

AnthropicLlm(; base_url::AbstractString = "https://api.anthropic.com/v1/messages",
               max_tokens::Integer = 4096) =
    AnthropicLlm(String(base_url), Int(max_tokens))

function stream_turn(b::AnthropicLlm,
                     api_key::AbstractString,
                     model::AbstractString,
                     system::AbstractString,
                     messages::AbstractVector,
                     tools::AbstractVector;
                     on_event::Function,
                     thinking = nothing,
                     output_config = nothing)
    stream_message(api_key, model, system, messages, tools;
                   on_event      = on_event,
                   max_tokens    = b.max_tokens,
                   base_url      = b.base_url,
                   thinking      = thinking,
                   output_config = output_config)
end

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
struct FakeLlm <: LlmBackend
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

end # module
