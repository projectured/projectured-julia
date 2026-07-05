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

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..TextModule: TextText, TextString
import ..ReferenceModule: Reference, ReferencePath

export ConversationDocument, thinking_part

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

# ── ConversationThinking ──────────────────────────────────────────────────────

"""
    ConversationThinking(text; signature = "", redacted = false, data = "")

A content document for an extended-thinking ("reasoning") block. Wrapped in a
`ConversationPart` like any other content type — what makes it special is that
`signature` / `redacted` / `data` are Anthropic API protocol metadata that must
survive re-serialization back to the API (parallel to `EvaluatorForm.tool_use_id`),
so the tool-use round-trip is not broken.

Fields:

- `text::Document`     — the reasoning text (`TextText`; empty when `display` is
                         `"omitted"` or for redacted blocks).
- `signature::String`  — the opaque signature from `signature_delta` (`""` until
                         one arrives; redacted blocks have none).
- `redacted::Bool`     — `true` for a `redacted_thinking` block.
- `data::String`       — the opaque payload for a redacted block (`""` otherwise).
"""
@document struct ConversationThinking <: ConversationDocument
    text::Document
    signature::String
    redacted::Bool
    data::String
    selection::Reference
end

ConversationThinking(text::Document;
                     signature::AbstractString = "",
                     redacted::Bool = false,
                     data::AbstractString = "") =
    ConversationThinking(Cell(text), Cell(String(signature)),
                         Cell(redacted), Cell(String(data)), Cell(nothing))
ConversationThinking(text::AbstractString = "";
                     signature::AbstractString = "",
                     redacted::Bool = false,
                     data::AbstractString = "") =
    ConversationThinking(TextText(TextString(String(text)));
                         signature = signature, redacted = redacted, data = data)

# Convenience: a thinking part. Collapsed by default — reasoning is verbose and
# secondary (see Stage 5 of the conversation-thinking plan).
thinking_part(text = ""; collapsed::Bool = true, kwargs...) =
    ConversationPart(ConversationThinking(text; kwargs...); collapsed = collapsed)

# Accessor mirroring EvaluatorModule.result_text / _eval_*.
_thinking_text(t::ConversationThinking) = t.text

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
    turns::CellVector = CellVector()
    selection::Reference = nothing
end
ConversationConversation(turns::Vector) =
    ConversationConversation(CellVector(Cell[Cell(t) for t in turns]), Cell(nothing))

# ── ConversationDraft ─────────────────────────────────────────────────────────

"""
    ConversationDraft(parts = [], assistant = nothing)

The user message currently being composed. The draft is **always** a user turn,
so it carries its `parts` directly (rather than wrapping a `ConversationTurn`)
and renders without a role/avatar header. It exists as its own document type only
so the composer can dispatch on it: without a distinct type, a
`ConversationTurn => composer` projection entry would also turn the history turns
into editable composers. The `parts` are mutated in place by the composer
operations; `assistant` back-links the owning `WorkbenchAssistant` (or `nothing`
when standalone) so ENTER can submit the draft into the conversation.
"""
@document struct ConversationDraft <: ConversationDocument
    parts::CellVector
    assistant::Any        # the owning WorkbenchAssistant (or nothing, standalone)
    selection::Reference
end

ConversationDraft(parts::Vector = ConversationPart[], assistant = nothing) =
    ConversationDraft(CellVector(Cell[Cell(p) for p in parts]), Cell(assistant), Cell(nothing))

set_function!(d::ConversationDraft, f::Function) =
    (set_function!(getfield(d.parts, :elements), () -> Cell[Cell(x) for x in f()]); d)

# ── set_function! delegation (mirror Workbench panel pattern) ────────────────────────

set_function!(c::ConversationConversation, f::Function) =
    (set_function!(getfield(c.turns, :elements), () -> Cell[Cell(x) for x in f()]); c)

set_function!(t::ConversationTurn, f::Function) =
    (set_function!(getfield(t.parts, :elements), () -> Cell[Cell(x) for x in f()]); t)

end # module
