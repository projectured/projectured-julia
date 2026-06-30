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

export LlmBackend, AnthropicLlm, FakeLlm, stream_turn,
       ScriptedLlm, scripted_turn, scripted_think, scripted_say, scripted_run

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

# The `stream_turn(::AnthropicLlm, …)` method calls `AnthropicModule.stream_message`
# (HTTP/JSON3) and therefore lives in `AnthropicModule` — the future LLM package
# extension — not here. This module stays dependency-free: it holds only the
# abstract `LlmBackend`, the `stream_turn` generic, the (dep-free) `AnthropicLlm`
# struct, and the in-process `FakeLlm`.

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

# ═══════════════════════════════════════════════════════════════════════
# ScriptedLlm — multi-round, timestamped, tool-capable
# ═══════════════════════════════════════════════════════════════════════

"""
    ScriptedLlm(scripts; delay = 0.0)

A multi-round scripted backend. `scripts` is a vector of *rounds*; each round is
a `Vector{NamedTuple}` of SSE events. Every call to `stream_turn` consumes the
next round (the agent loop calls `stream_turn` once per round — a round that ends
in `stop_reason = "tool_use"` is followed by a continuation round, so one logical
assistant turn typically spans several rounds).

Timing makes the stream feel real: after emitting each event the backend sleeps
for that event's `:delay` field, or for the backend-wide `delay` when the event
carries none. Build rounds with [`scripted_turn`](@ref) and the block helpers
[`scripted_think`](@ref) / [`scripted_say`](@ref) / [`scripted_run`](@ref), which
already spread prose across delayed deltas.

The older positional form `ScriptedLlm(scripts)` (no timing) keeps working.
"""
mutable struct ScriptedLlm <: LlmBackend
    scripts::Vector{Vector{NamedTuple}}
    cursor::Int
    delay::Float64
end

ScriptedLlm(scripts; delay::Real = 0.0) =
    ScriptedLlm([Vector{NamedTuple}(s) for s in scripts], 0, Float64(delay))

function stream_turn(b::ScriptedLlm,
                     _api_key::AbstractString,
                     _model::AbstractString,
                     _system::AbstractString,
                     _messages::AbstractVector,
                     _tools::AbstractVector;
                     on_event::Function,
                     thinking = nothing,
                     output_config = nothing)
    b.cursor += 1
    b.cursor > length(b.scripts) &&
        error("ScriptedLlm: exhausted at round $(b.cursor) (have $(length(b.scripts)))")
    for ev in b.scripts[b.cursor]
        on_event(ev)
        d = get(ev, :delay, b.delay)
        d > 0 && sleep(d)
    end
    nothing
end

# ── Scripted-round builders (dependency-free SSE NamedTuple factories) ──────────
#
# Each block builder returns a `Vector{NamedTuple}`; `scripted_turn` concatenates
# blocks and wraps them in the `message_start … message_stop` envelope with a
# `stop_reason`. The shapes match exactly what `_handle_sse_event!` consumes.

# One SSE event; carries an optional per-event `:delay` (seconds) the backend
# sleeps for after emitting it.
_sse(type::Symbol, data::Dict{Symbol,Any}) = (type = type, data = data)
_sse(type::Symbol, data::Dict{Symbol,Any}, delay::Real) =
    (type = type, data = data, delay = Float64(delay))

# Split prose into groups of `n` words (single-space rejoin, trailing space kept
# between chunks) so each chunk reveals a few words at a time.
function _word_chunks(text::AbstractString, n::Integer)
    n = max(1, Int(n))
    words = split(String(text), ' ')
    isempty(words) && return String[String(text)]
    chunks = String[]
    i = 1
    while i <= length(words)
        j = min(i + n - 1, length(words))
        chunk = join(@view(words[i:j]), ' ')
        j < length(words) && (chunk *= " ")
        push!(chunks, chunk)
        i = j + 1
    end
    chunks
end

# Minimal JSON string literal (quotes included) for a tool-call argument. The
# agent loop re-parses this with the project's `jsonparse`, which decodes the
# standard backslash escapes, so a multi-line code block round-trips intact.
function _json_string(s::AbstractString)
    io = IOBuffer()
    print(io, '"')
    for c in s
        if     c == '"';  print(io, "\\\"")
        elseif c == '\\'; print(io, "\\\\")
        elseif c == '\n'; print(io, "\\n")
        elseif c == '\r'; print(io, "\\r")
        elseif c == '\t'; print(io, "\\t")
        elseif c < ' ';   print(io, "\\u", lpad(string(UInt32(c); base = 16), 4, '0'))
        else;             print(io, c)
        end
    end
    print(io, '"')
    String(take!(io))
end

"""
    scripted_think(text; chunk_words = 4, delay = 0.05, signature = "sig_demo")

A thinking content block: `content_block_start{thinking}`, `thinking_delta`s (a
few words each, paced by `delay`), a `signature_delta`, then `content_block_stop`.
"""
function scripted_think(text::AbstractString; chunk_words::Integer = 4,
                        delay::Real = 0.05, signature::AbstractString = "sig_demo")
    evs = NamedTuple[_sse(:content_block_start,
        Dict{Symbol,Any}(:content_block => Dict{Symbol,Any}(:type => "thinking")))]
    for chunk in _word_chunks(text, chunk_words)
        push!(evs, _sse(:content_block_delta,
            Dict{Symbol,Any}(:delta => Dict{Symbol,Any}(:type => "thinking_delta",
                                                          :thinking => chunk)), delay))
    end
    push!(evs, _sse(:content_block_delta,
        Dict{Symbol,Any}(:delta => Dict{Symbol,Any}(:type => "signature_delta",
                                                      :signature => String(signature)))))
    push!(evs, _sse(:content_block_stop, Dict{Symbol,Any}()))
    evs
end

"""
    scripted_say(text; chunk_words = 3, delay = 0.05)

A text content block streamed a few words at a time so the prose types itself out.
"""
function scripted_say(text::AbstractString; chunk_words::Integer = 3, delay::Real = 0.05)
    evs = NamedTuple[_sse(:content_block_start,
        Dict{Symbol,Any}(:content_block => Dict{Symbol,Any}(:type => "text")))]
    for chunk in _word_chunks(text, chunk_words)
        push!(evs, _sse(:content_block_delta,
            Dict{Symbol,Any}(:delta => Dict{Symbol,Any}(:type => "text_delta",
                                                          :text => chunk)), delay))
    end
    push!(evs, _sse(:content_block_stop, Dict{Symbol,Any}()))
    evs
end

"""
    scripted_run(code; tool_id = "tu_…", tool_name = "execute_julia_code", delay = 0.0)

A `tool_use` content block carrying `{"code": code}` for `execute_julia_code` (or
another registered tool). A round containing one of these must declare
`stop_reason = "tool_use"` so the agent loop dispatches the tool and continues.
"""
function scripted_run(code::AbstractString;
                      tool_id::AbstractString = "tu_" * string(rand(UInt32); base = 16),
                      tool_name::AbstractString = "execute_julia_code",
                      delay::Real = 0.0)
    NamedTuple[
        _sse(:content_block_start,
            Dict{Symbol,Any}(:content_block => Dict{Symbol,Any}(
                :type => "tool_use", :id => String(tool_id), :name => String(tool_name)))),
        _sse(:content_block_delta,
            Dict{Symbol,Any}(:delta => Dict{Symbol,Any}(:type => "input_json_delta",
                :partial_json => "{\"code\":" * _json_string(code) * "}")), delay),
        _sse(:content_block_stop, Dict{Symbol,Any}()),
    ]
end

"""
    scripted_turn(blocks...; stop_reason = "end_turn") -> Vector{NamedTuple}

Wrap one or more content blocks (from `scripted_think` / `scripted_say` /
`scripted_run`) into a single streaming round: `message_start`, the blocks in
order, `message_delta{stop_reason}`, `message_stop`. Use `stop_reason = "tool_use"`
for a round that ends in a `scripted_run` block.
"""
function scripted_turn(blocks::Vector...; stop_reason::AbstractString = "end_turn")
    evs = NamedTuple[_sse(:message_start, Dict{Symbol,Any}())]
    for b in blocks
        append!(evs, b)
    end
    push!(evs, _sse(:message_delta,
        Dict{Symbol,Any}(:delta => Dict{Symbol,Any}(:stop_reason => String(stop_reason)))))
    push!(evs, _sse(:message_stop, Dict{Symbol,Any}()))
    evs
end

end # module
