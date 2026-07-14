# Fragment of `LlmModule` — what streams back while the model answers.
#
# A model does not reply all at once: it opens a block, fills it in pieces, closes
# it, and eventually ends the turn. These events are that shape, in the project's
# own words. Every provider's stream maps onto them; no consumer downstream sees a
# provider's event names.

"""
    LlmEvent

One event in a streaming turn. A consumer that only wants the text can match
`LlmTextDelta` and ignore the rest; the agent loop needs the tool-use events and
the terminal `LlmTurnEnd`.
"""
abstract type LlmEvent end

"""
    LlmTextStart()

A prose block opens; `LlmTextDelta`s follow until `LlmTextStop`.
"""
struct LlmTextStart <: LlmEvent end

"""
    LlmTextDelta(text)

The next piece of the open prose block. Deltas are fragments, not whole words or
lines — a consumer appends them.
"""
struct LlmTextDelta <: LlmEvent
    text::String
end

"""
    LlmTextStop()

The open prose block is complete.
"""
struct LlmTextStop <: LlmEvent end

"""
    LlmThinkingStart()

A reasoning block opens.
"""
struct LlmThinkingStart <: LlmEvent end

"""
    LlmThinkingDelta(text)

The next piece of the open reasoning block.
"""
struct LlmThinkingDelta <: LlmEvent
    text::String
end

"""
    LlmThinkingSignature(signature)

The opaque signature for the open reasoning block, which arrives near its end and
must be kept with it (see [`LlmThinking`](@ref)).
"""
struct LlmThinkingSignature <: LlmEvent
    signature::String
end

"""
    LlmThinkingStop()

The open reasoning block is complete.
"""
struct LlmThinkingStop <: LlmEvent end

"""
    LlmRedactedThinkingBlock(data)

A whole withheld-reasoning block, complete in one event — there is nothing to
stream, only an opaque payload to keep.
"""
struct LlmRedactedThinkingBlock <: LlmEvent
    data::String
end

"""
    LlmToolUseStart(id, name)

The model begins asking for a tool call; its arguments stream in as
`LlmToolInputDelta`s.
"""
struct LlmToolUseStart <: LlmEvent
    id::String
    name::String
end

"""
    LlmToolInputDelta(json)

The next fragment of the open tool call's argument JSON. Fragments are not
individually valid JSON — a consumer concatenates them and parses once at
`LlmToolUseStop`.
"""
struct LlmToolInputDelta <: LlmEvent
    json::String
end

"""
    LlmToolUseStop()

The open tool call's arguments are complete and may now be parsed.
"""
struct LlmToolUseStop <: LlmEvent end

"""
    LlmTurnEnd(stop_reason)

The turn is over. `stop_reason` is normalised across providers:

- `:end_turn`   — the model finished speaking.
- `:tool_use`   — it is waiting on the tool calls it just made; the loop runs them
                  and goes again.
- `:max_tokens` — it ran out of budget mid-answer.
- `:error`      — the turn failed (an `LlmFailure` carries the message).
"""
struct LlmTurnEnd <: LlmEvent
    stop_reason::Symbol
end

"""
    LlmFailure(message)

The provider reported an error *inside* the stream. A transport failure — a dead
socket, a 401 — is thrown instead; this is for the case where the model's own
stream says something went wrong.
"""
struct LlmFailure <: LlmEvent
    message::String
end
