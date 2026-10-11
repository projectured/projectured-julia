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

# ── ConversationSignInRequest ─────────────────────────────────────────────────

"""
    ConversationSignInRequest(message, methods; start = nothing, retry = nothing)

A part that says that an external agent needs a sign-in. `message` says how to
sign in, in words for a person. `methods` are the ways to sign in that this
editor can run, each an `AgentSignInMethod` with the command of a sign-in in a
terminal. The card shows a button for each method and a button that tries again.

`start` and `retry` are live functions and no data: `start(editor, method_id)`
runs the sign-in of a method, and `retry(editor)` starts the agent again.
`terminal` is the document in which the sign-in runs, `nothing` before one
started; the card shows it below its buttons, and it is the live field of the
part: a person types in it inside a transcript that is otherwise read.
`is_signing_in` says that a sign-in runs, and `state` says how the last one
went, in words for a person; the assistant writes both.

A `.pred` file keeps the message and the state, and no method, no live function
and no terminal: after a load, the next prompt gives a new request when the
agent still needs a sign-in.
"""
@document struct ConversationSignInRequest <: ConversationDocument
    message::String
    methods::Vector{AgentSignInMethod}
    state::String
    is_signing_in::Bool
    terminal::Any
    start::Any
    retry::Any
end

ConversationSignInRequest(message::AbstractString, methods::AbstractVector; start = nothing, retry = nothing) =
    ConversationSignInRequest(Cell(String(message)), Cell(CellVector{AgentSignInMethod}(collect(AgentSignInMethod, methods))),
                              Cell(""), Cell(false), Cell(nothing), Cell(start), Cell(retry), Cell(nothing))

pred_arguments(request::ConversationSignInRequest) = (), Pair{Symbol,Any}[
    :message => request.message,
    :state   => request.state,
]

function make_pred_document(::Type{<:ConversationSignInRequest}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    request = ConversationSignInRequest(values[:message], AgentSignInMethod[])
    request.state = String(get(values, :state, ""))
    request
end

# ── ConversationQuestionRequest ───────────────────────────────────────────────

"""
    ConversationQuestionForm(values)

The values of a question form, one `PrimitiveString` for each field, in the
order of the fields: the value of the chosen option, the values of the chosen
options one a line, or the text that a person typed.
"""
@document struct ConversationQuestionForm <: ConversationDocument
    values::CellVector
end

"""
    ConversationQuestionRequest(message, fields; reply = nothing)

A question of an external agent that a person answers in a form. `message` says
what the agent asks, `fields` are the `AgentQuestionField`s, and `form` holds
the values that the person fills in; it is the live field of the part, where a
person works inside a transcript that is otherwise read. `answer` says what the
person answered, and is empty while the agent waits. `reply` sends the values
to the agent; it is a live function and no data, so the duplicate of a request
has none. [`answer_question_request!`](@ref) answers a request.

A `.pred` file keeps the message, the fields and the answer, and no `reply`: a
request that waits when it is saved reads back as `"Cancelled"`.
"""
@document struct ConversationQuestionRequest <: ConversationDocument
    message::String
    fields::Vector{AgentQuestionField}
    form::ConversationQuestionForm
    answer::String
    reply::Any
end

function ConversationQuestionRequest(message::AbstractString, fields::AbstractVector; reply = nothing)
    form = ConversationQuestionForm(Cell(CellVector(Cell[Cell(PrimitiveString("")) for _ in fields])), Cell(nothing))
    ConversationQuestionRequest(Cell(String(message)), Cell(CellVector{AgentQuestionField}(collect(AgentQuestionField, fields))),
                                Cell(form), Cell(""), Cell(reply), Cell(nothing))
end

# A field is a group of named values in a file, as an option of a permission is.
pred_arguments(request::ConversationQuestionRequest) = (), Pair{Symbol,Any}[
    :message => request.message,
    :fields  => [(name = field.name, title = field.title, description = field.description, kind = field.kind,
                  options = [(value = option.value, name = option.name, description = option.description)
                             for option in field.options],
                  is_required = field.is_required) for field in request.fields],
    :answer  => isempty(request.answer) ? "Cancelled" : request.answer,
]

function make_pred_document(::Type{<:ConversationQuestionRequest}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    fields = AgentQuestionField[
        AgentQuestionField(String(field.name), String(field.title), String(field.description), field.kind,
                           AgentOptionValue[AgentOptionValue(String(option.value), String(option.name),
                                                             String(option.description)) for option in field.options],
                           field.is_required) for field in values[:fields]]
    request = ConversationQuestionRequest(values[:message], fields)
    request.answer = String(get(values, :answer, "Cancelled"))
    request
end

"""
    is_question_request_open(request) -> Bool

Whether the agent still waits for the answer of a person to `request`.
"""
is_question_request_open(request::ConversationQuestionRequest) =
    isempty(request.answer) && request.reply !== nothing

"""
    find_question_values(request) -> Union{Dict{String,Any},String}

The values of the form of `request`, as the reply takes them: a `String` for a
choice or a text, a `Vector{String}` for choices, a number, or a `Bool`, for
each field that has a value. A `String` in place of the values says what the
form still needs, such as a required field or a number.
"""
function find_question_values(request::ConversationQuestionRequest)
    values = Dict{String,Any}()
    for (field, text) in zip(request.fields, (value.value for value in request.form.values))
        text = strip(something(text, ""))
        if isempty(text)
            field.is_required && return "Fill in: " * field.title
            continue
        end
        value = field.kind === :choices ? String[String(line) for line in split(text, '\n') if !isempty(line)] :
                field.kind === :number ? tryparse(Float64, text) :
                field.kind === :integer ? tryparse(Int, text) :
                field.kind === :boolean ? text == "true" : String(text)
        value === nothing && return field.title * " needs " * (field.kind === :integer ? "a whole number" : "a number")
        values[field.name] = value
    end
    values
end

"""
    answer_question_request!(request, values)

Answer `request` with `values`, the values of its form, or as declined with
`nothing`. The first answer goes to the agent, and a later one does nothing. A
`reply` that answers `false` says that the agent had its answer already, from a
cancel of the turn, and the request then shows `"Cancelled"`.
"""
function answer_question_request!(request::ConversationQuestionRequest, values::Union{Nothing,AbstractDict})
    is_question_request_open(request) || return nothing
    reply = request.reply
    request.reply = nothing
    is_delivered = reply(values) !== false
    request.answer = !is_delivered ? "Cancelled" : values === nothing ? "Declined" :
                     _format_question_answer(request, values)
    nothing
end

# The answer as a person reads it: each answered field with the names of its
# options or its text.
function _format_question_answer(request::ConversationQuestionRequest, values::AbstractDict)
    parts = String[]
    for field in request.fields
        haskey(values, field.name) || continue
        value = values[field.name]
        text = value isa AbstractVector ? join((_find_option_name(field, String(item)) for item in value), ", ") :
               value isa Bool ? (value ? "yes" : "no") :
               value isa AbstractString ? _find_option_name(field, String(value)) : string(value)
        push!(parts, field.title * ": " * text)
    end
    isempty(parts) ? "Answered" : "Answered: " * join(parts, "; ")
end

# The name of the option of `field` whose value is `value`, or `value` itself.
function _find_option_name(field::AgentQuestionField, value::String)
    index = findfirst(option -> option.value == value, field.options)
    index === nothing ? value : field.options[index].name
end

# ── ConversationTurn ──────────────────────────────────────────────────────────

"""
    ConversationTurn(role; parts = [], stop_reason = :complete, collapsed = false,
                     start_time = 0.0, finish_time = 0.0)

One chat message: a `role` (`:user` / `:assistant`), an ordered list of parts,
a streaming `stop_reason`, a `collapsed` flag, and the times at which the turn
started and finished, in seconds of `time()`. A time of `0.0` is not known: a
turn of a file that kept no times, a turn of a test, or a turn that runs and
has not finished.
"""
@document struct ConversationTurn <: ConversationDocument
    role::Symbol
    parts::CellVector
    stop_reason::Symbol
    collapsed::Bool
    start_time::Float64
    finish_time::Float64
end

ConversationTurn(role::Symbol;
                 parts::Vector = ConversationPart[],
                 stop_reason::Symbol = :complete,
                 collapsed::Bool = false,
                 start_time::Real = 0.0,
                 finish_time::Real = 0.0) =
    ConversationTurn(Cell(role),
                     CellVector(Cell[Cell(p) for p in parts]),
                     Cell(stop_reason), Cell(collapsed),
                     Cell(Float64(start_time)), Cell(Float64(finish_time)), Cell(nothing))

# A file that kept no times builds a turn whose times are not known.
function make_pred_document(::Type{<:ConversationTurn}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    ConversationTurn(values[:role]; parts = collect(values[:parts]),
                     stop_reason = get(values, :stop_reason, :complete),
                     collapsed = get(values, :collapsed, false),
                     start_time = get(values, :start_time, 0.0),
                     finish_time = get(values, :finish_time, 0.0))
end

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

# The reply of a question goes to the agent that asked, and a copy did not ask.
copy_document(policy::DuplicatePolicy, request::ConversationQuestionRequest) =
    copy_document_fields(policy, request; reply = nothing)

# A sign-in goes to the agent of the assistant that needed it, which a copy has
# not, and its program runs once.
copy_document(policy::DuplicatePolicy, request::ConversationSignInRequest) =
    copy_document_fields(policy, request; is_signing_in = false, terminal = nothing, start = nothing,
                         retry = nothing)

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
