"""
    ConversationModule

The conversation document domain models a live AI chat session inside the
editor. The whole conversation, including in-flight streaming, is a real
ProjecturEd domain so selection, projections, and editing all compose with
the rest of the editor.

Uniform *turn / part* model:

- `ConversationConversation` — an ordered sequence of `ConversationTurn`s.
- `ConversationTurn`         — one message in the chat: a `role`
                               (`:user` / `:assistant`), an ordered list of
                               `ConversationPart`s, a `stop_reason`, and a
                               `collapsed` flag.
- `ConversationPart`         — one collapsible slot wrapping an arbitrary
                               `content::Document`. The content's own type
                               drives projection and serialization:
                                 * `TextText`     — prose
                                 * `JuliaDocument`— quoted code
                                 * `EvaluatorForm`— code + evaluation result
                                 * `JsonDocument` / `XmlDocument` / … — data
                                 * `DocumentInsertion` — being typed (composer)

There is exactly **one** part type; there is no part subtype hierarchy. Per-slot
state that is not in the content (`collapsed`, `selection`) lives on the part.
"""
module ConversationModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..TextModule: TextText, TextString
import ..ReferenceModule: Reference, ReferencePath

export ConversationDocument, ConversationConversation,
       ConversationTurn, ConversationPart,
       IConversationConversation, IConversationTurn, IConversationPart

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type ConversationDocument <: Document end

# ── ConversationPart ──────────────────────────────────────────────────────────

"""
    ConversationPart(content; collapsed = false)

A collapsible slot around an arbitrary content document.
"""
@document struct ConversationPart <: ConversationDocument
    content::Document
    collapsed::Bool
    selection::Reference
end

ConversationPart(content::Document; collapsed::Bool = false) =
    ConversationPart(Cell(content), Cell(collapsed), Cell(nothing))
ConversationPart(s::AbstractString; collapsed::Bool = false) =
    ConversationPart(Cell(TextText(TextString(String(s)))), Cell(collapsed), Cell(nothing))

# ── ConversationTurn ──────────────────────────────────────────────────────────

"""
    ConversationTurn(role; parts = [], stop_reason = :complete, collapsed = false)

One chat message: a `role` (`:user` / `:assistant`), an ordered list of parts,
a streaming `stop_reason`, and a `collapsed` flag.
"""
@document struct ConversationTurn <: ConversationDocument
    role::Symbol
    parts::CellVector
    stop_reason::Symbol
    collapsed::Bool
    selection::Reference
end

ConversationTurn(role::Symbol;
                 parts::Vector = ConversationPart[],
                 stop_reason::Symbol = :complete,
                 collapsed::Bool = false) =
    ConversationTurn(Cell(role),
                     CellVector(Cell[Cell(p) for p in parts]),
                     Cell(stop_reason), Cell(collapsed), Cell(nothing))

ConversationTurn(role::Symbol, parts::Vector; kwargs...) =
    ConversationTurn(role; parts = parts, kwargs...)

# Convenience: a user/assistant turn from a single string or content document.
user_turn(content) = ConversationTurn(:user, [ConversationPart(content)])
assistant_turn(content) = ConversationTurn(:assistant, [ConversationPart(content)])

# ── ConversationConversation ──────────────────────────────────────────────────

"""
    ConversationConversation(turns = [])

The whole chat history as an ordered sequence of `ConversationTurn`s.
"""
@document struct ConversationConversation <: ConversationDocument
    turns::CellVector
    selection::Reference
end

ConversationConversation() = ConversationConversation(CellVector(), Cell(nothing))
ConversationConversation(turns::Vector) =
    ConversationConversation(CellVector(Cell[Cell(t) for t in turns]), Cell(nothing))

# ── Element access on the conversation ────────────────────────────────────────

Base.length(c::ConversationConversation)  = length(c.turns)
Base.isempty(c::ConversationConversation) = isempty(c.turns)
Base.getindex(c::ConversationConversation, i::Integer) = c.turns[i]
Base.firstindex(::ConversationConversation) = 1
Base.lastindex(c::ConversationConversation) = length(c)
Base.iterate(c::ConversationConversation, s...) = iterate(c.turns, s...)
Base.eachindex(c::ConversationConversation) = eachindex(c.turns)

Base.push!(c::ConversationConversation, turns::ConversationTurn...) =
    (for t in turns; push!(c.turns, Cell(t)); end; c)

Base.deleteat!(c::ConversationConversation, i) = (deleteat!(c.turns, i); c)

# ── Element access on a turn's parts ──────────────────────────────────────────

Base.length(t::ConversationTurn)  = length(t.parts)
Base.isempty(t::ConversationTurn) = isempty(t.parts)
Base.getindex(t::ConversationTurn, i::Integer) = t.parts[i]
Base.firstindex(::ConversationTurn) = 1
Base.lastindex(t::ConversationTurn) = length(t)
Base.iterate(t::ConversationTurn, s...) = iterate(t.parts, s...)
Base.eachindex(t::ConversationTurn) = eachindex(t.parts)

Base.push!(t::ConversationTurn, parts::ConversationPart...) =
    (for p in parts; push!(t.parts, Cell(p)); end; t)

# ── setfn! delegation (mirror Workbench panel pattern) ────────────────────────

setfn!(c::ConversationConversation, f::Function) =
    (setfn!(getfield(c.turns, :elements), () -> Cell[Cell(x) for x in f()]); c)

setfn!(t::ConversationTurn, f::Function) =
    (setfn!(getfield(t.parts, :elements), () -> Cell[Cell(x) for x in f()]); t)

# ── Display ───────────────────────────────────────────────────────────────────

Base.show(io::IO, c::ConversationConversation) =
    print(io, "ConversationConversation(turns=", length(c), ")")

Base.show(io::IO, t::ConversationTurn) =
    print(io, "ConversationTurn(:", t.role, ", parts=", length(t), ")")

Base.show(io::IO, p::ConversationPart) =
    print(io, "ConversationPart(", typeof(p.content), ")")

end # module
