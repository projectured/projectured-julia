# Fragment of `LlmModule` — the multi-round, timestamped, tool-capable
# `ScriptedLlm` backend and its dependency-free scripted-round builders
# (`make_scripted_turn` and the `make_scripted_think` / `make_scripted_say`
# / `make_scripted_run` block helpers).

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
carries none. Build rounds with [`make_scripted_turn`](@ref) and the block helpers
[`make_scripted_think`](@ref) / [`make_scripted_say`](@ref) / [`make_scripted_run`](@ref), which
already spread prose across delayed deltas.

The older positional form `ScriptedLlm(scripts)` (no timing) keeps working.
"""
mutable struct ScriptedLlm <: Llm
    scripts::Vector{Vector{NamedTuple}}
    cursor::Int
    delay::Float64
    jitter::Float64
end

ScriptedLlm(scripts; delay::Real = 0.0, jitter::Real = 0.0) =
    ScriptedLlm([Vector{NamedTuple}(s) for s in scripts], 0, Float64(delay), Float64(jitter))

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
        # Jitter each delay by a random factor in [1-jitter, 1+jitter] so the
        # streamed prose lands unevenly — like a real model, not a metronome.
        b.jitter > 0 && (d *= 1 + b.jitter * (2 * rand() - 1))
        d > 0 && sleep(d)
    end
    nothing
end

# ── Scripted-round builders (dependency-free SSE NamedTuple factories) ──────────
#
# Each block builder returns a `Vector{NamedTuple}`; `make_scripted_turn` concatenates
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
    make_scripted_think(text; chunk_words = 4, delay = 0.05, signature = "sig_demo")

A thinking content block: `content_block_start{thinking}`, `thinking_delta`s (a
few words each, paced by `delay`), a `signature_delta`, then `content_block_stop`.
"""
function make_scripted_think(text::AbstractString; chunk_words::Integer = 4,
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
    make_scripted_say(text; chunk_words = 3, delay = 0.05)

A text content block streamed a few words at a time so the prose types itself out.
"""
function make_scripted_say(text::AbstractString; chunk_words::Integer = 3, delay::Real = 0.05)
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
    make_scripted_run(code; tool_id = "tu_…", tool_name = "execute_julia_code", delay = 0.0)

A `tool_use` content block carrying `{"code": code}` for `execute_julia_code` (or
another registered tool). A round containing one of these must declare
`stop_reason = "tool_use"` so the agent loop dispatches the tool and continues.
"""
function make_scripted_run(code::AbstractString;
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
    make_scripted_turn(blocks...; stop_reason = "end_turn") -> Vector{NamedTuple}

Wrap one or more content blocks (from `make_scripted_think` / `make_scripted_say` /
`make_scripted_run`) into a single streaming round: `message_start`, the blocks in
order, `message_delta{stop_reason}`, `message_stop`. Use `stop_reason = "tool_use"`
for a round that ends in a `make_scripted_run` block.
"""
function make_scripted_turn(blocks::Vector...; stop_reason::AbstractString = "end_turn")
    evs = NamedTuple[_sse(:message_start, Dict{Symbol,Any}())]
    for b in blocks
        append!(evs, b)
    end
    push!(evs, _sse(:message_delta,
        Dict{Symbol,Any}(:delta => Dict{Symbol,Any}(:stop_reason => String(stop_reason)))))
    push!(evs, _sse(:message_stop, Dict{Symbol,Any}()))
    evs
end
