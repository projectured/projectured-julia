# Fragment of `ProjecturedKernelExample` — the multi-round, timestamped,
# tool-capable `ScriptedLlm` backend and its dependency-free scripted-round
# builders (`make_scripted_turn` and the `make_scripted_think` /
# `make_scripted_say` / `make_scripted_run` block helpers). A test double
# for the kernel's `LlmModule.Llm` seam; it lives in the example package
# (never in `main`) so no fake reaches a production build.

# ═══════════════════════════════════════════════════════════════════════
# ScriptedLlm — multi-round, timestamped, tool-capable
# ═══════════════════════════════════════════════════════════════════════

"""
    ScriptedLlm(scripts; delay = 0.0)

A multi-round scripted backend. `scripts` is a vector of *rounds*; each round is
a `Vector{<:NamedTuple}` of `(event::LlmEvent, delay::Float64)` entries. Every call
to `stream_turn` consumes the next round (the agent loop calls `stream_turn` once
per round — a round that ends in `LlmTurnEnd(:tool_use)` is followed by a
continuation round, so one logical assistant turn typically spans several rounds).

Timing makes the stream feel real: after emitting each event the backend sleeps
for that entry's `delay`, or for the backend-wide `delay` when the entry's is
zero. Build rounds with [`make_scripted_turn`](@ref) and the block helpers
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

function stream_turn(b::ScriptedLlm, _request::LlmRequest; on_event::Function)
    b.cursor += 1
    b.cursor > length(b.scripts) &&
        error("ScriptedLlm: exhausted at round $(b.cursor) (have $(length(b.scripts)))")
    for e in b.scripts[b.cursor]
        on_event(e.event)
        d = e.delay > 0 ? e.delay : b.delay
        # Jitter each delay by a random factor in [1-jitter, 1+jitter] so the
        # streamed prose lands unevenly — like a real model, not a metronome.
        b.jitter > 0 && (d *= 1 + b.jitter * (2 * rand() - 1))
        d > 0 && sleep(d)
    end
    nothing
end

# ── Scripted-round builders (dependency-free LlmEvent factories) ────────────
#
# Each block builder returns a `Vector{<:NamedTuple}` of `(event, delay)` entries;
# `make_scripted_turn` concatenates blocks and appends the terminal `LlmTurnEnd`.
# The shapes match exactly what `ScriptedLlm.stream_turn` consumes.

# One scripted entry: an `LlmEvent` and the delay (seconds) the backend sleeps
# for after emitting it (0.0 defers to the backend-wide `delay`).
_ev(event::LlmEvent, delay::Real = 0.0) = (event = event, delay = Float64(delay))

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
# agent loop re-parses this with the project's `parse_json`, which decodes the
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

A thinking content block: `LlmThinkingStart`, `LlmThinkingDelta`s (a few words
each, paced by `delay`), an `LlmThinkingSignature`, then `LlmThinkingStop`.
"""
function make_scripted_think(text::AbstractString; chunk_words::Integer = 4,
                        delay::Real = 0.05, signature::AbstractString = "sig_demo")
    evs = NamedTuple[_ev(LlmThinkingStart())]
    for chunk in _word_chunks(text, chunk_words)
        push!(evs, _ev(LlmThinkingDelta(chunk), delay))
    end
    push!(evs, _ev(LlmThinkingSignature(String(signature))))
    push!(evs, _ev(LlmThinkingStop()))
    evs
end

"""
    make_scripted_say(text; chunk_words = 3, delay = 0.05)

A text content block streamed a few words at a time so the prose types itself out.
"""
function make_scripted_say(text::AbstractString; chunk_words::Integer = 3, delay::Real = 0.05)
    evs = NamedTuple[_ev(LlmTextStart())]
    for chunk in _word_chunks(text, chunk_words)
        push!(evs, _ev(LlmTextDelta(chunk), delay))
    end
    push!(evs, _ev(LlmTextStop()))
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
        _ev(LlmToolUseStart(String(tool_id), String(tool_name))),
        # The arguments stream as JSON fragments (what a UI would show), and the
        # finished call arrives parsed — which is what a real adapter delivers, and
        # what the agent loop dispatches on.
        _ev(LlmToolInputDelta("{\"code\":" * _json_string(code) * "}"), delay),
        _ev(LlmToolUseStop(LlmToolUse(String(tool_id), String(tool_name),
                                      Dict{String,Any}("code" => String(code))))),
    ]
end

"""
    make_scripted_turn(blocks...; stop_reason = "end_turn") -> Vector{NamedTuple}

Wrap one or more content blocks (from `make_scripted_think` / `make_scripted_say` /
`make_scripted_run`) into a single streaming round: the blocks in order, then the
terminal `LlmTurnEnd(stop_reason)`. Use `stop_reason = "tool_use"` for a round
that ends in a `make_scripted_run` block. `stop_reason` accepts a `String` for
source compatibility with existing call sites.
"""
function make_scripted_turn(blocks::Vector...; stop_reason::AbstractString = "end_turn")
    evs = NamedTuple[]
    for b in blocks
        append!(evs, b)
    end
    push!(evs, _ev(LlmTurnEnd(Symbol(stop_reason))))
    evs
end
