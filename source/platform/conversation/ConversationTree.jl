# Fragment of `ConversationModule` — the nodes of a conversation in a tree: a turn
# has its parts as children, and a part has the children of its content. A turn
# and a part of text are known by the first line of their text, and a thinking, a
# tool call and a request of an agent by what they are.

# ── A turn ───────────────────────────────────────────────────────────────────

get_tree_children_steps(::ConversationTurn) = ((FieldReferenceStep("parts"),),)

# The role, and the first line of the first part that has a text.
function format_tree_node_label(turn::ConversationTurn)
    role = _describe_turn_role(turn.role)
    for part in turn.parts
        _has_content_text(part.content) || continue
        line = _find_content_line(part.content)
        line === nothing || return role * " · " * line
    end
    role
end

_describe_turn_role(role::Symbol) =
    role === :user ? "You" : role === :assistant ? "Assistant" : uppercasefirst(String(role))

# A turn says its role as its icon, and while it runs, that it runs. Its detail
# is the count of its parts and the time when it started, if it is known. It
# reads no clock.
function get_document_decoration(turn::ConversationTurn)
    count = length(turn.parts)
    words = String[count == 1 ? "1 part" : string(count, " parts")]
    turn.start_time == 0.0 || push!(words, Libc.strftime("%H:%M:%S", turn.start_time))
    detail = join(words, " · ")
    tooltip = () -> _make_turn_note(turn)
    _is_turn_running(turn) &&
        return DocumentDecoration(; icon = :loader, conditions = [DocumentCondition(:running)], detail,
                                  work_item = true, tooltip)
    DocumentDecoration(; icon = turn.role === :user ? :user : :bot, detail, tooltip)
end

# What a row of a turn says when the pointer rests on it: its role, when it
# started, how long it ran, its parts and why it stopped.
function _make_turn_note(turn::ConversationTurn)
    facts = Pair{String,Any}["Role" => _describe_turn_role(turn.role)]
    if turn.start_time != 0.0
        push!(facts, "Started" => Libc.strftime("%H:%M:%S", turn.start_time))
        seconds = (turn.finish_time == 0.0 ? time() : turn.finish_time) - turn.start_time
        push!(facts, "Duration" => string(round(seconds; digits = 1), " s"))
    end
    push!(facts, "Parts" => string(length(turn.parts)))
    push!(facts, "Stop reason" => replace(string(turn.stop_reason), '_' => ' '))
    TooltipNote(; title = "Turn", facts)
end

# A turn runs from its start to its finish. A turn whose start is not known, such
# as a turn of a file that kept no times, does not run.
_is_turn_running(turn::ConversationTurn) = turn.start_time != 0.0 && turn.finish_time == 0.0

# ── A part ───────────────────────────────────────────────────────────────────

# A part is the node of its content: the children of the content are its
# children, below the step `content`.
get_tree_children_steps(part::ConversationPart) =
    map(steps -> (FieldReferenceStep("content"), steps...), get_tree_children_steps(part.content))

# A part of text is known by the first line of its text, and the mark of a
# paragraph. Any other part is known as its content is.
function format_tree_node_label(part::ConversationPart)
    content = part.content
    _has_content_text(content) || return format_tree_node_label(content)
    something(_find_content_line(content), format_tree_node_label(content))
end

get_document_decoration(part::ConversationPart) =
    _has_content_text(part.content) ?
        DocumentDecoration(; icon = :pilcrow, tooltip = () -> _make_part_note(part)) :
        get_document_decoration(part.content)

# What a row of a part of text says when the pointer rests on it: the whole of
# its first line, which the label cuts.
function _make_part_note(part::ConversationPart)
    TooltipNote(; title = "Text", text = _find_whole_line(_get_content_string(part.content)))
end

_get_content_string(text::TextBlock) = get_flat_string(text)
_get_content_string(content) = print_natural_text(content)

# Whether a content is a text: a text block, or a document with a natural
# notation that is not a document of the conversation, such as the Markdown of an
# answer or the code of a fenced block.
_has_content_text(::TextBlock) = true
_has_content_text(::Union{ConversationDocument,EvaluatorDocument}) = false
_has_content_text(content) = make_natural_projection(content, :string) !== nothing

# The first line of the text of a content, or `nothing` when every line is blank.
_find_content_line(content) = _find_first_line(_get_content_string(content))

# The first line of `text` that is not blank, with no blanks at its ends, or
# `nothing` when every line is blank.
function _find_whole_line(text::AbstractString)
    for line in eachsplit(text, '\n')
        stripped = strip(line)
        isempty(stripped) || return String(stripped)
    end
    nothing
end

# That line cut at the length of a label.
function _find_first_line(text::AbstractString)
    line = _find_whole_line(text)
    (line === nothing || length(line) <= _TREE_LABEL_LENGTH) && return line
    first(line, _TREE_LABEL_LENGTH - 1) * "…"
end

# The count of characters of the label of a node, with its "…".
const _TREE_LABEL_LENGTH = 80

# ── The contents of a part ───────────────────────────────────────────────────

format_tree_node_label(::ConversationThinking) = "Thinking"
get_document_decoration(::ConversationThinking) = DocumentDecoration(; icon = :circle_dashed)

# A tool call is known by its header. It says that it runs, and that it failed.
format_tree_node_label(form::EvaluatorForm) = get_evaluation_title(form)

function get_document_decoration(form::EvaluatorForm)
    conditions = DocumentCondition[]
    form.is_running && push!(conditions, DocumentCondition(:running))
    form.is_error && push!(conditions, DocumentCondition(:failed))
    DocumentDecoration(; icon = get_evaluation_kind_label(form) == "eval" ? :lambda : :terminal, conditions,
                       tooltip = () -> _make_form_note(form))
end

# What a row of a tool call says when the pointer rests on it: its header, the
# tool, and whether it runs, failed or ended.
_make_form_note(form::EvaluatorForm) =
    TooltipNote(; title = get_evaluation_title(form),
                facts = ["Tool" => get_evaluation_kind_label(form),
                         "State" => form.is_running ? "running" : form.is_error ? "failed" : "done"])

# A request of an agent is known by its first line, and says that it waits while
# the person did not answer it.
format_tree_node_label(request::ConversationPermissionRequest) =
    something(_find_first_line(request.title), "Permission")
get_document_decoration(request::ConversationPermissionRequest) =
    _make_request_decoration(is_permission_request_open(request), "Permission", request.title)

format_tree_node_label(request::ConversationQuestionRequest) =
    something(_find_first_line(request.message), "Question")
get_document_decoration(request::ConversationQuestionRequest) =
    _make_request_decoration(is_question_request_open(request), "Question", request.message)

format_tree_node_label(request::ConversationSignInRequest) =
    something(_find_first_line(request.message), "Sign in")
get_document_decoration(request::ConversationSignInRequest) =
    DocumentDecoration(; icon = :lock, tooltip = () -> _make_request_note("Sign in", request.message))

_make_request_decoration(is_open::Bool, title::String, text) =
    DocumentDecoration(; icon = :circle_help,
                       conditions = is_open ? [DocumentCondition(:waiting; count = 1)] : DocumentCondition[],
                       tooltip = () -> _make_request_note(title, text))

# What a row of a request says when the pointer rests on it: what the agent asks.
_make_request_note(title::String, text) =
    TooltipNote(; title, text = isempty(strip(string(text))) ? nothing : strip(string(text)))
