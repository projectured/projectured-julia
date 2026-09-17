# Fragment of `ConversationModule`.
#
# The conversation document domain — an AI chat session (including in-flight
# streaming) as a `Document`, so selection/projections/editing compose with the
# rest of the editor. `ConversationConversation` holds `ConversationTurn`s; each
# turn has a role + a list of `ConversationPart`s wrapping arbitrary content.
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
end

ConversationPart(content::Document; collapsed::Bool = false) =
    ConversationPart(Cell(content), Cell(collapsed), Cell(nothing))
ConversationPart(s::AbstractString; collapsed::Bool = false) =
    ConversationPart(Cell(TextBlock(TextString(String(s)))), Cell(collapsed), Cell(nothing))

# ── ConversationThinking ──────────────────────────────────────────────────────

"""
An extended-thinking block. Wrapped in a `ConversationPart` like any content.
`signature`/`redacted`/`data` are Anthropic API metadata that must survive
re-serialization back to the API.
"""
@document struct ConversationThinking <: ConversationDocument
    text::Document
    signature::String
    redacted::Bool
    data::String
end

ConversationThinking(text::Document;
                     signature::AbstractString = "",
                     redacted::Bool = false,
                     data::AbstractString = "") =
    ConversationThinking(Cell(text), Cell(String(signature)),
                         Cell(redacted), Cell(String(data)), Cell(nothing))
ConversationThinking(text::AbstractString;
                     signature::AbstractString = "",
                     redacted::Bool = false,
                     data::AbstractString = "") =
    ConversationThinking(TextBlock(TextString(String(text)));
                         signature = signature, redacted = redacted, data = data)

# Convenience: a thinking part. Collapsed by default — reasoning is verbose and
# secondary (see Stage 5 of the conversation-thinking plan).
make_conversation_thinking_part(text = ""; collapsed::Bool = true, kwargs...) =
    ConversationPart(ConversationThinking(text; kwargs...); collapsed = collapsed)

# Accessor mirroring ConversationModule.make_evaluator_result_text / _eval_*.
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
end

# ── ConversationDraft ─────────────────────────────────────────────────────────

"""
    ConversationDraft(parts = [], assistant = nothing)

The user message currently being composed. The draft is **always** a user turn,
so it carries its `parts` directly (rather than wrapping a `ConversationTurn`)
and renders without a role/avatar header. It exists as its own document type only
so the composer can dispatch on it: without a distinct type, a
`ConversationTurn => composer` projection entry would also turn the history turns
into editable composers. The `parts` are mutated in place by the composer
operations; `assistant` back-links the owning `Assistant` (or `nothing`
when standalone) so ENTER can submit the draft into the conversation.
"""
@document struct ConversationDraft <: ConversationDocument
    parts::CellVector
    assistant::Any        # the owning Assistant (or nothing, standalone)
end

ConversationDraft(parts::Vector, assistant = nothing) =
    ConversationDraft(CellVector(Cell[Cell(p) for p in parts]), Cell(assistant), Cell(nothing))

# ── The duplicate ─────────────────────────────────────────────────────────────

# A conversation is what a person said and read, so its duplicate is a copy of it.
has_document_duplicate(::ConversationDocument) = true

# The assistant a draft links back to is not the draft's own, so the duplicate of
# a draft keeps the link. The duplicate of an assistant puts its own link there.
copy_document(policy::DuplicatePolicy, draft::ConversationDraft) =
    copy_document_fields(policy, draft; assistant = draft.assistant)

set_cell_function!(d::ConversationDraft, f::Function) =
    (set_cell_function!(getfield(d.parts, :elements), () -> Cell[Cell(x) for x in f()]); d)

# ── set_cell_function! delegation (mirror Workbench panel pattern) ────────────────────────

set_cell_function!(c::ConversationConversation, f::Function) =
    (set_cell_function!(getfield(c.turns, :elements), () -> Cell[Cell(x) for x in f()]); c)

set_cell_function!(t::ConversationTurn, f::Function) =
    (set_cell_function!(getfield(t.parts, :elements), () -> Cell[Cell(x) for x in f()]); t)

# The history of a conversation is a record of what was said. A paste replaces
# nothing in it, and puts no text into it.
accepts_pasted_document(::ConversationConversation) = false
accepts_pasted_text(::ConversationConversation) = false
