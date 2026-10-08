# Fragment of `ConversationModule`.
#
# The conversation documents — an AI chat session (including in-flight
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
# @optional: the text stands first, as the content of the part; the rest is its chrome.
make_conversation_thinking_part(text = ""; collapsed::Bool = true, kwargs...) =
    ConversationPart(ConversationThinking(text; kwargs...); collapsed = collapsed)

# Accessor mirroring ConversationModule.make_evaluator_result_text / _eval_*.
_thinking_text(t::ConversationThinking) = t.text

# ── ConversationPermissionRequest ─────────────────────────────────────────────

"""
    ConversationPermissionRequest(title, options; reply = nothing)

An external agent asks a person whether it can run a tool, and waits for the
answer. `title` says what the tool does. `options` are the answers that the
agent offers, each an `AgentPermissionOption`. `answer` is the name of the
option that the person chose, `"Cancelled"` when the turn ended first, and empty
while the agent waits.

`reply` sends the chosen option to the agent. It is a live function and no data:
the duplicate of a request has none, and a request with none can not be
answered. [`answer_permission_request!`](@ref) answers a request.

A `.pred` file keeps the title, the options and the answer, and no `reply`. A
request that waits when it is saved reads back as `"Cancelled"`, because nobody
can answer it after the load.
"""
@document struct ConversationPermissionRequest <: ConversationDocument
    title::String
    options::Vector{AgentPermissionOption}
    answer::String
    reply::Any
end

ConversationPermissionRequest(title::AbstractString, options::AbstractVector; reply = nothing) =
    ConversationPermissionRequest(Cell(String(title)), Cell(CellVector{AgentPermissionOption}(collect(AgentPermissionOption, options))),
                                  Cell(""), Cell(reply), Cell(nothing))

# An option is a group of named values in a file, so the kernel type of an
# option needs no place among the types that a file may build.
pred_arguments(request::ConversationPermissionRequest) = (), Pair{Symbol,Any}[
    :title   => request.title,
    :options => [(id = option.id, name = option.name, kind = option.kind) for option in request.options],
    :answer  => isempty(request.answer) ? "Cancelled" : request.answer,
]

function make_pred_document(::Type{<:ConversationPermissionRequest}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    options = AgentPermissionOption[AgentPermissionOption(String(option.id), String(option.name), option.kind)
                                    for option in values[:options]]
    request = ConversationPermissionRequest(values[:title], options)
    request.answer = String(get(values, :answer, "Cancelled"))
    request
end

"""
    is_permission_request_open(request) -> Bool

Whether the agent still waits for the answer of a person to `request`.
"""
is_permission_request_open(request::ConversationPermissionRequest) =
    isempty(request.answer) && request.reply !== nothing

"""
    answer_permission_request!(request, option_id)

Answer `request` with the option whose id is `option_id`, or as cancelled with
`nothing`. The first answer goes to the agent, and a later one does nothing. A
`reply` that answers `false` says that the agent had its answer already, from a
cancel of the turn, and the request then shows `"Cancelled"`.
"""
function answer_permission_request!(request::ConversationPermissionRequest,
                                     option_id::Union{Nothing,AbstractString})
    is_permission_request_open(request) || return nothing
    index = option_id === nothing ? nothing : findfirst(option -> option.id == option_id, request.options)
    reply = request.reply
    request.reply = nothing
    is_delivered = reply(index === nothing ? nothing : String(option_id)) !== false
    request.answer = index === nothing || !is_delivered ? "Cancelled" : request.options[index].name
    nothing
end

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

# A draft keeps its caret when the focus leaves it, dormant: still stored, not
# drawn and not acted on, and live again when the focus comes back. A person who
# leaves the draft finds the caret where it was.
has_dormant_selection(::ConversationDraft) = true

# ── The duplicate ─────────────────────────────────────────────────────────────

# A conversation is what a person said and read, so its duplicate is a copy of it.
has_document_duplicate(::ConversationDocument) = true

# The reply of a request goes to the agent that asked, and a copy did not ask.
copy_document(policy::DuplicatePolicy, request::ConversationPermissionRequest) =
    copy_document_fields(policy, request; reply = nothing)

# The assistant a draft links back to is not the draft's own, so the duplicate of
# a draft keeps the link. The duplicate of an assistant puts its own link there.
copy_document(policy::DuplicatePolicy, draft::ConversationDraft) =
    copy_document_fields(policy, draft; assistant = draft.assistant)

set_cell_computation!(d::ConversationDraft, f::Function) =
    (set_cell_computation!(getfield(d.parts, :elements), () -> Cell[Cell(x) for x in f()]); d)

# ── set_cell_computation! delegation ───────────────────────────────────────

set_cell_computation!(c::ConversationConversation, f::Function) =
    (set_cell_computation!(getfield(c.turns, :elements), () -> Cell[Cell(x) for x in f()]); c)

set_cell_computation!(t::ConversationTurn, f::Function) =
    (set_cell_computation!(getfield(t.parts, :elements), () -> Cell[Cell(x) for x in f()]); t)

# The history of a conversation is a record of what was said. A paste replaces
# nothing in it, and puts no text into it.
accepts_pasted_document(::ConversationConversation) = false
accepts_pasted_text(::ConversationConversation) = false
