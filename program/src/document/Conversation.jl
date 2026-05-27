"""
    ConversationModule

The conversation document domain models a live AI chat session inside the
editor. The whole conversation, including in-flight streaming, is a real
ProjecturEd domain so selection, projections, and editing all compose with
the rest of the editor.

Top-level type: `ConversationConversation` — a sequence of messages.

Message subtypes (`ConversationMessage`):
- `ConversationUserMessage`        — user prose (a `TextText`).
- `ConversationAssistantMessage`   — assistant response composed of blocks.
- `ConversationToolUseMessage`     — record that the assistant requested a tool call.
- `ConversationToolResultMessage`  — output of a tool call.
- `ConversationJuliaInputMessage`  — user-evaluated Julia code (a `JuliaDocument`).
- `ConversationJuliaResultMessage` — output of a user-evaluated Julia run.

Block subtypes (`ConversationBlock`) live inside `ConversationAssistantMessage`:
- `ConversationTextBlock`     — prose paragraph (a `TextText`).
- `ConversationCodeBlock`     — fenced code; `body` is `JuliaDocument` for julia, `TextText` otherwise.
- `ConversationHeadingBlock`  — heading at a given level.
- `ConversationListBlock`     — bulleted list of `TextText`s.
- `ConversationToolUseBlock`  — inline record of a tool_use content block.

Status of an assistant turn is held by `ConversationAssistantMessage.stop_reason`.
"""
module ConversationModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..TextModule: TextText, TextString
import ..JuliaModule: JuliaDocument
import ..ReferenceModule: Reference, ReferencePath

export ConversationDocument, ConversationConversation,
       ConversationMessage,
       ConversationUserMessage, ConversationAssistantMessage,
       ConversationToolUseMessage, ConversationToolResultMessage,
       ConversationJuliaInputMessage, ConversationJuliaResultMessage,
       ConversationBlock,
       ConversationTextBlock, ConversationCodeBlock,
       ConversationHeadingBlock, ConversationListBlock,
       ConversationToolUseBlock,
       IConversationConversation,
       IConversationUserMessage, IConversationAssistantMessage,
       IConversationToolUseMessage, IConversationToolResultMessage,
       IConversationJuliaInputMessage, IConversationJuliaResultMessage,
       IConversationTextBlock, IConversationCodeBlock,
       IConversationHeadingBlock, IConversationListBlock,
       IConversationToolUseBlock

# ── Abstract bases ──────────────────────────────────────────────────────────

abstract type ConversationDocument <: Document end
abstract type ConversationMessage  <: ConversationDocument end
abstract type ConversationBlock    <: ConversationDocument end

# ── Blocks ──────────────────────────────────────────────────────────────────

"""
    ConversationTextBlock(text::TextText)

A paragraph of prose inside an assistant message.
"""
@document struct ConversationTextBlock <: ConversationBlock
    text::TextText
    selection::Reference
end

ConversationTextBlock() = ConversationTextBlock(Cell(TextText()), Cell(nothing))
ConversationTextBlock(text::TextText) = ConversationTextBlock(Cell(text), Cell(nothing))
ConversationTextBlock(s::AbstractString) =
    ConversationTextBlock(Cell(TextText(TextString(String(s)))), Cell(nothing))

"""
    ConversationCodeBlock(language::String, body)

A fenced code block. `body` is a `JuliaDocument` if `language == "julia"`,
otherwise a `TextText` rendered monospace.
"""
@document struct ConversationCodeBlock <: ConversationBlock
    language::String
    body::Document
    selection::Reference
end

ConversationCodeBlock(language::AbstractString, body::Document) =
    ConversationCodeBlock(Cell(String(language)), Cell(body), Cell(nothing))

"""
    ConversationHeadingBlock(level::Int, text::TextText)

A markdown heading; `level ∈ 1:6`.
"""
@document struct ConversationHeadingBlock <: ConversationBlock
    level::Int
    text::TextText
    selection::Reference
end

ConversationHeadingBlock(level::Int, text::TextText) =
    ConversationHeadingBlock(Cell(level), Cell(text), Cell(nothing))
ConversationHeadingBlock(level::Int, s::AbstractString) =
    ConversationHeadingBlock(Cell(level), Cell(TextText(TextString(String(s)))), Cell(nothing))

"""
    ConversationListBlock(items::CellVector{TextText})

A bulleted list. Items are `TextText` values.
"""
@document struct ConversationListBlock <: ConversationBlock
    items::CellVector
    selection::Reference
end

ConversationListBlock() = ConversationListBlock(CellVector(), Cell(nothing))
ConversationListBlock(items::Vector) =
    ConversationListBlock(CellVector(Cell[Cell(x) for x in items]), Cell(nothing))

"""
    ConversationToolUseBlock(id, name, input)

Inline record of a Claude `tool_use` content block. `input` is the raw
arguments dict (kept as `Any` to avoid forcing JSON conversion here).
"""
@document struct ConversationToolUseBlock <: ConversationBlock
    id::String
    name::String
    input::Any
    selection::Reference
end

ConversationToolUseBlock(id::AbstractString, name::AbstractString, input) =
    ConversationToolUseBlock(Cell(String(id)), Cell(String(name)), Cell(input), Cell(nothing))

# ── Messages ────────────────────────────────────────────────────────────────

"""
    ConversationUserMessage(text::TextText)

A user prose turn.
"""
@document struct ConversationUserMessage <: ConversationMessage
    text::TextText
    selection::Reference
end

ConversationUserMessage() = ConversationUserMessage(Cell(TextText()), Cell(nothing))
ConversationUserMessage(text::TextText) = ConversationUserMessage(Cell(text), Cell(nothing))
ConversationUserMessage(s::AbstractString) =
    ConversationUserMessage(Cell(TextText(TextString(String(s)))), Cell(nothing))

"""
    ConversationAssistantMessage(; blocks=[], stop_reason=:streaming)

A streaming assistant response. `blocks` is a `CellVector` of
`ConversationBlock`s appended to as the SSE stream arrives.
`stop_reason` is a `Symbol`: `:streaming`, `:end_turn`, `:tool_use`,
`:max_tokens`, `:error`, ...
"""
@document struct ConversationAssistantMessage <: ConversationMessage
    blocks::CellVector
    stop_reason::Symbol
    selection::Reference
end

ConversationAssistantMessage(; blocks::Vector = ConversationBlock[],
                              stop_reason::Symbol = :streaming) =
    ConversationAssistantMessage(CellVector(Cell[Cell(b) for b in blocks]),
                                 Cell(stop_reason), Cell(nothing))

"""
    ConversationToolUseMessage(id, name, input; status=:pending)

Free-standing record that Claude requested a tool call. `status` is one
of `:pending`, `:running`, `:done`, `:error`.
"""
@document struct ConversationToolUseMessage <: ConversationMessage
    id::String
    name::String
    input::Any
    status::Symbol
    selection::Reference
end

ConversationToolUseMessage(id::AbstractString, name::AbstractString, input;
                           status::Symbol = :pending) =
    ConversationToolUseMessage(Cell(String(id)), Cell(String(name)),
                               Cell(input), Cell(status), Cell(nothing))

"""
    ConversationToolResultMessage(tool_use_id, content::TextText; is_error=false)

The textual result of a tool call. `tool_use_id` matches the
`ConversationToolUseMessage`/`ConversationToolUseBlock` it answers.
"""
@document struct ConversationToolResultMessage <: ConversationMessage
    tool_use_id::String
    content::TextText
    is_error::Bool
    selection::Reference
end

ConversationToolResultMessage(tool_use_id::AbstractString, content::TextText;
                              is_error::Bool = false) =
    ConversationToolResultMessage(Cell(String(tool_use_id)), Cell(content),
                                  Cell(is_error), Cell(nothing))

ConversationToolResultMessage(tool_use_id::AbstractString, s::AbstractString;
                              is_error::Bool = false) =
    ConversationToolResultMessage(Cell(String(tool_use_id)),
                                  Cell(TextText(TextString(String(s)))),
                                  Cell(is_error), Cell(nothing))

"""
    ConversationJuliaInputMessage(code::JuliaDocument)

A Julia evaluation initiated by the user (Alt+Enter).
"""
@document struct ConversationJuliaInputMessage <: ConversationMessage
    code::JuliaDocument
    selection::Reference
end

ConversationJuliaInputMessage(code::JuliaDocument) =
    ConversationJuliaInputMessage(Cell(code), Cell(nothing))

"""
    ConversationJuliaResultMessage(output::TextText; is_error=false)

The output (stdout / stderr / repr) of a user-initiated Julia evaluation.
"""
@document struct ConversationJuliaResultMessage <: ConversationMessage
    output::TextText
    is_error::Bool
    selection::Reference
end

ConversationJuliaResultMessage(output::TextText; is_error::Bool = false) =
    ConversationJuliaResultMessage(Cell(output), Cell(is_error), Cell(nothing))

ConversationJuliaResultMessage(s::AbstractString; is_error::Bool = false) =
    ConversationJuliaResultMessage(Cell(TextText(TextString(String(s)))),
                                   Cell(is_error), Cell(nothing))

# ── Top-level conversation ──────────────────────────────────────────────────

"""
    ConversationConversation(messages = [])

The whole chat history as an ordered `CellVector` of
`ConversationMessage`s.
"""
@document struct ConversationConversation <: ConversationDocument
    messages::CellVector
    selection::Reference
end

ConversationConversation() = ConversationConversation(CellVector(), Cell(nothing))

ConversationConversation(messages::Vector) =
    ConversationConversation(CellVector(Cell[Cell(m) for m in messages]), Cell(nothing))

# ── Element access on ConversationConversation ───────────────────────────────

Base.length(c::ConversationConversation)  = length(c.messages)
Base.isempty(c::ConversationConversation) = isempty(c.messages)
Base.getindex(c::ConversationConversation, i::Integer) = c.messages[i]
Base.firstindex(::ConversationConversation) = 1
Base.lastindex(c::ConversationConversation) = length(c)
Base.iterate(c::ConversationConversation, s...) = iterate(c.messages, s...)
Base.eachindex(c::ConversationConversation) = eachindex(c.messages)

Base.push!(c::ConversationConversation, msgs::ConversationMessage...) =
    (for m in msgs; push!(c.messages, Cell(m)); end; c)

Base.deleteat!(c::ConversationConversation, i) =
    (deleteat!(c.messages, i); c)

# ── Element access on assistant message blocks ──────────────────────────────

Base.length(m::ConversationAssistantMessage)  = length(m.blocks)
Base.isempty(m::ConversationAssistantMessage) = isempty(m.blocks)
Base.getindex(m::ConversationAssistantMessage, i::Integer) = m.blocks[i]

Base.push!(m::ConversationAssistantMessage, bs::ConversationBlock...) =
    (for b in bs; push!(m.blocks, Cell(b)); end; m)

# ── setfn! delegation (mirror Workbench panel pattern) ──────────────────────

setfn!(c::ConversationConversation, f::Function) =
    (setfn!(getfield(c.messages, :elements), () -> Cell[Cell(x) for x in f()]); c)

setfn!(m::ConversationAssistantMessage, f::Function) =
    (setfn!(getfield(m.blocks, :elements), () -> Cell[Cell(x) for x in f()]); m)

# ── Display ─────────────────────────────────────────────────────────────────

Base.show(io::IO, c::ConversationConversation) =
    print(io, "ConversationConversation(messages=", length(c), ")")

Base.show(io::IO, m::ConversationUserMessage) =
    print(io, "ConversationUserMessage(text=", m.text, ")")

Base.show(io::IO, m::ConversationAssistantMessage) =
    print(io, "ConversationAssistantMessage(blocks=", length(m), ", stop_reason=:", m.stop_reason, ")")

Base.show(io::IO, m::ConversationToolUseMessage) =
    print(io, "ConversationToolUseMessage(name=", repr(m.name), ", status=:", m.status, ")")

Base.show(io::IO, m::ConversationToolResultMessage) =
    print(io, "ConversationToolResultMessage(tool_use_id=", repr(m.tool_use_id), ", is_error=", m.is_error, ")")

Base.show(io::IO, m::ConversationJuliaInputMessage) =
    print(io, "ConversationJuliaInputMessage(code=", m.code, ")")

Base.show(io::IO, m::ConversationJuliaResultMessage) =
    print(io, "ConversationJuliaResultMessage(is_error=", m.is_error, ")")

Base.show(io::IO, b::ConversationTextBlock) =
    print(io, "ConversationTextBlock(", b.text, ")")

Base.show(io::IO, b::ConversationCodeBlock) =
    print(io, "ConversationCodeBlock(language=", repr(b.language), ")")

Base.show(io::IO, b::ConversationHeadingBlock) =
    print(io, "ConversationHeadingBlock(level=", b.level, ")")

Base.show(io::IO, b::ConversationListBlock) =
    print(io, "ConversationListBlock(items=", length(b.items), ")")

Base.show(io::IO, b::ConversationToolUseBlock) =
    print(io, "ConversationToolUseBlock(name=", repr(b.name), ")")

end # module
