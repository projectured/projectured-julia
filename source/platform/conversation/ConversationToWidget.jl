# Fragment of `ConversationModule`.
#
# ConversationDocument → WidgetDocument projection — a vertical list of chat
# bubbles:
#
#     ConversationConversation → VerticalLayout of turn bands
#     ConversationTurn         → WidgetCard, quiet: title = [avatar(role) + role
#                                label], content = VerticalLayout of part widgets.
#                                The user's band is tinted and the model's is
#                                plain — neither draws a border.
#     ConversationPart         → the part's `content` document (recursed), bare.
#                                Code, a thinking block, an evaluation and a
#                                permission request each keep a quiet tinted panel
#                                with a one-line tag; every other kind draws no
#                                chrome at all.
#
# A turn is collapsible, and so is a part that kept a panel. Each is a
# `collapsible` card, which draws a chevron before its header and, while
# `collapsed`, the header and nothing else. The fold state lives on the domain
# node — `turn.collapsed`, `part.collapsed`, and the two section flags of an
# `EvaluatorForm` — and the card's own `collapsed` cell is a computed cell that
# reads it, because a turn's part cards are rebuilt whenever its part list
# changes and state held on a widget would reset while the model answers. A part
# with no panel has no header to click, so it does not fold — prose is what a
# person reads, and folding it hides the message.
#
# The turn/part *lists* are reactive (a `CellVector` thunk), so pushing a turn or a
# part updates the layout without re-running `print_document` (streaming).
# The badge on a part names the part's format, which the document itself
# answers; this file names no domain.


# ── Projection structs ──────────────────────────────────────────────────────
#
# No card width. A turn card and a part card take the width they are offered —
# the transcript says `child_width = Fill` and the card resolves it — so a
# conversation is as wide as the pane holding it.
#
# Each theme field it reads is documented on `ConversationTheme`, in
# `ConversationTheme.jl`.

@projection UntrackedCell struct ConversationConversationToWidgetComposite
    turn_gap::Int = get_conversation_style(nothing, :turn_gap)
end

@projection UntrackedCell struct ConversationTurnToWidgetComposite
    part_gap::Int = get_conversation_style(nothing, :part_gap)
    role_gap::Int = get_conversation_style(nothing, :role_gap)
    user_role_text::StyleText = get_conversation_style(nothing, :user_role_text)
    assistant_role_text::StyleText = get_conversation_style(nothing, :assistant_role_text)
    other_role_text::StyleText = get_conversation_style(nothing, :other_role_text)
    user_role_icon::StyleText = get_conversation_style(nothing, :user_role_icon)
    assistant_role_icon::StyleText = get_conversation_style(nothing, :assistant_role_icon)
    other_role_icon::StyleText = get_conversation_style(nothing, :other_role_icon)
end

@projection UntrackedCell struct ConversationPartToWidget
    kind_text::StyleText = get_conversation_style(nothing, :kind_text)
    picture_height::Int = get_conversation_style(nothing, :picture_height)
    section_text::StyleText = get_conversation_style(nothing, :section_text)
    error_text::StyleText = get_conversation_style(nothing, :error_text)
    section_gap::Int = get_conversation_style(nothing, :section_gap)
    # A section sits under the header of the card around it, indented by the
    # column that card's chevron takes: two half-sizes of the theme's chevron
    # and the title gap, so a section's own chevron starts where the header's
    # word starts.
    section_padding::Inset = get_conversation_style(nothing, :section_indent)
end

# The role's label, beside its glyph: smaller than the message it introduces —
# but it is still read, so it is not the size of a footnote. The role keeps its
# own color, because color is what tells a person who spoke.
_role_text(p, role::Symbol) =
    role === :user      ? p.user_role_text :
    role === :assistant ? p.assistant_role_text : p.other_role_text

# The mark beside a role. It is drawn as text and not as a `WidgetAvatar`,
# because an avatar is a disc with initials: at this size the disc is a pale ring
# behind a letter that overflows it, and a letter is not an icon. The glyph
# stands on its own, in the role's own color.
#
# The glyphs are icons of the Lucide font, the set every icon of the window comes
# from, so the mark beside a turn looks like the pictures of the toolbar. A mark
# must not read as a smudge beside the bold word: Lucide draws a stroke of a
# twelfth of its size, which at this size is as heavy as the stem of a letter.
_role_icon(p, role::Symbol) =
    role === :user      ? p.user_role_icon :
    role === :assistant ? p.assistant_role_icon : p.other_role_icon

# A person, a bot, and a dot for any other role. None is a letter, and none needs
# a legend.
_role_glyph(role::Symbol) =
    string(find_icon_character(role === :user ? :user : role === :assistant ? :bot : :dot))

"""
    FORMAT_LABELS, CODE_FORMATS

The decoration a part can carry, keyed by the format its document is written in.
A domain's insertion is a subtype of that domain's root, so one entry covers a
kind while it is typed and after it is committed.

`FORMAT_LABELS` holds the two formats whose key is an abbreviation of the
language's name; every other label is the key itself.

`CODE_FORMATS` is the set of formats that read as code. A part in one of them
gets a panel, because code between two paragraphs of prose must be told from
them; a part in any other format gets none. The decoration and this judgement
belong to this package; the kinds do not, and a format that names itself in
neither table is prose as far as this file is concerned.
"""
const FORMAT_LABELS = Dict(:jl => "julia", :md => "markdown")
const CODE_FORMATS  = Set([:jl, :json, :xml])

_is_code(content) = get_natural_format(typeof(content)) in CODE_FORMATS

# Per-part label, covering both editing states and committed content.
#
# A domain's insertion is a subtype of its own root, so one entry of the table
# covers a kind while it is typed and after it is committed. The transcript and
# the composer draw the same tag on a part of the same kind.
_kind_label(::PrimitiveString)      = "text"
_kind_label(::DocumentInsertion)    = "insert"
_kind_label(::ConversationThinking) = "thinking"
_kind_label(::TextBlock)            = "text"
_kind_label(f::EvaluatorForm)       = get_evaluation_title(f)
_kind_label(c)                      = _format_label(get_natural_format(typeof(c)))
_format_label(::Nothing)            = "doc"
_format_label(key::Symbol)          = get(FORMAT_LABELS, key, String(key))

# ── Helpers ────────────────────────────────────────────────────────────────

# A header row: a role mark followed by the role, both in the role's color.
_role_header(p, role::Symbol) =
    HorizontalLayout(Any[
        WidgetLabel(_role_glyph(role); text_style = _role_icon(p, role)),
        WidgetLabel(String(role); text_style = _role_text(p, role)),
    ]; vertical_align = :center, gap = p.role_gap)

# A card that folds. Its `collapsed` cell reads the flag on the domain node,
# because the toggle reader re-targets every fold to that node and the kernel
# handler flips the flag there; the card only shows it. `read_flag` answers the
# flag, and a flag that was never set reads as open.
function _follow_fold!(card::WidgetCard, read_flag::Function)
    set_cell_computation!(getfield(card, :collapsed), () -> read_flag() === true)
    card
end

# A widget that follows the paths (the selection, the mouse target) of the node
# that printed it. Each path cell holds the node's path mapped forward, with the
# steps that lead from the printed output to the widget taken off, and nothing
# when the image does not pass through the widget. A container draws its
# selection ring from that cell, and routes keys by it, so it follows only a live
# selection. `lead` are those steps, without node types.
function _follow_selection!(widget, node, projection, iomap, lead::Vector)
    set_output_path_computations!(widget, node, path -> begin
        image = map_reference_forward(projection, iomap, path)
        image isa Reference || return nothing
        steps = get_reference_steps(strip_reference_types(image))
        length(steps) >= length(lead) || return nothing
        all(i -> steps[i] == lead[i], eachindex(lead)) || return nothing
        _from_steps(steps[(length(lead) + 1):end])
    end; dormant = false)
    widget
end

# ── print_document: conversation → vertical list of turn cards ──────────────

function print_document(projection::ConversationConversationToWidgetComposite,
                          recursion, c::ConversationConversation, ctx)
    rec = recursion
    # Cache the child turn iomaps (recomputed only when the turn list changes),
    # so the produced cards keep a stable identity that the toggle reader can
    # match against. The layout reads each iomap's `.output`.
    ioms = Cell(@computation(Any[
        print_document(rec, rec, c.turns[i], ctx)
        for i in eachindex(c.turns)
    ]))
    # Every turn fills the width it is given and grows with what it holds.
    layout = VerticalLayout(CellVector(@computation Any[im.output for im in ioms[]]),
                            Cell(:left), Cell(projection.turn_gap),
                            Cell(Fill), Cell(Content), Cell(nothing))
    iomap = ChildrenIoMap(projection, c, layout, ioms)
    _follow_selection!(layout, c, projection, iomap, Any[])
    iomap
end

# ── print_document: turn → card with avatar header + part stack ─────────────

function print_document(projection::ConversationTurnToWidgetComposite,
                          recursion, t::ConversationTurn, ctx)
    rec = recursion
    ioms = Cell(@computation(Any[
        print_document(rec, rec, t.parts[i], ctx)
        for i in eachindex(t.parts)
    ]))
    # And so does every part inside a turn.
    body = VerticalLayout(CellVector(@computation Any[im.output for im in ioms[]]),
                          Cell(:left), Cell(projection.part_gap),
                          Cell(Fill), Cell(Content), Cell(nothing))
    # A turn is a band and not a box. The user's band is tinted and the model's
    # is plain, which is what tells the two apart — the same job a border did,
    # done by a channel the content does not already use. It stays a card, so
    # its chevron still folds it and the collapse reader below still finds
    # the turn that a produced card came from.
    # A turn of notes is the editor speaking, not the person: it has the header
    # of no role of its own and no tint.
    editor = is_note_turn(t)
    card = WidgetCard(;
                      title = _role_header(projection, editor ? :editor : t.role),
                      content = body,
                      variant = t.role === :user && !editor ? :tinted : :plain,
                      collapsible = true)
    _follow_fold!(card, () -> t.collapsed)
    iomap = ChildrenIoMap(projection, t, card, ioms)
    _follow_selection!(card, t, projection, iomap, Any[])
    _follow_selection!(body, t, projection, iomap, Any[FieldReferenceStep("content")])
    iomap
end

# ── print_document: part → the content, and a chrome only where it is earned ─
#
# A part draws as its content, and takes a chrome only where it earns one. A card
# with a kind heading around whatever it holds is wrong twice. A frame does not
# say WHAT a part is — it only separates, and the content already says what it is:
# prose looks like prose and code looks like code. And a heading that names the
# kind repeats what the reader can see: `¶ text` over the words `hi there` tells
# nobody anything.
#
# So the default is no chrome at all. Three kinds keep one, because each has
# something a frame does that whitespace cannot:
#
# - code, which must be told apart from the prose it sits between;
# - a thinking block, which is secondary and folds away;
# - an evaluation, which is two documents (a form and its result) and needs to
#   say where one ends.

# The IO map of a part. `folds` lists the cards inside the part that fold on
# their own — the two sections of an evaluation — each with the domain operation
# its fold means, so the reader can say a chevron click back to the domain.
@iomap struct ConversationPartToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    folds::Any
end

function print_document(projection::ConversationPartToWidget,
                          recursion, part::ConversationPart, ctx)
    content = part.content
    folds = Pair{Any,Any}[]
    output = content isa EvaluatorForm        ? _eval_card(projection, content, part, folds) :
             content isa ConversationThinking ? _thinking_card(projection, content, part)    :
             content isa ConversationPermissionRequest ? _permission_card(projection, content, part) :
             content isa ConversationSignInRequest ? _sign_in_card(projection, content, part) :
             content isa ConversationQuestionRequest ? _question_card(projection, content, part) :
             content isa ConversationNote     ? _note_row(projection, content)               :
             content isa ImageFile            ? _picture_card(projection, content, part)     :
             _is_code(content)                ? _code_card(projection, content, part)        :
             content
    iomap = ConversationPartToWidgetIoMap(projection, part, output, folds)
    content isa EvaluatorForm && _follow_section_selection!(output, part, projection, iomap)
    content isa ConversationSignInRequest && _follow_sign_in_selection!(output, part, projection, iomap)
    content isa ConversationQuestionRequest && _follow_question_selection!(output, part, projection, iomap)
    iomap
end

# The selection of an evaluation's form or result draws a ring around that
# section's body. The card of the part, its body and the section card each follow
# the part's selection, so the section card's own selection names its content.
function _follow_section_selection!(card, part, projection, iomap)
    _follow_selection!(card, part, projection, iomap, Any[])
    body = card.content
    _follow_selection!(body, part, projection, iomap, Any[FieldReferenceStep("content")])
    for (_, index) in _PART_SECTIONS
        section = body.children[index]
        _follow_selection!(section, part, projection, iomap,
                           Any[FieldReferenceStep("content"), FieldReferenceStep("children"),
                               RangeReferenceStep(index - 1, index)])
    end
end

# The card of a sign-in and its body follow the part's selection, so a key that
# a person types in the terminal of the sign-in reaches it.
function _follow_sign_in_selection!(card, part, projection, iomap)
    _follow_selection!(card, part, projection, iomap, Any[])
    _follow_selection!(card.content, part, projection, iomap, Any[FieldReferenceStep("content")])
end

# A part's panel is MUTED and a turn's band is TINTED, because a part sits inside
# a turn: a code block in a user message would draw nothing if the two shared a
# color.
#
# A quiet tag: the one line a chromed part draws to name itself. No avatar — a
# glyph beside a word says the word twice.
_tag(p, label::AbstractString) =
    WidgetLabel(String(label); text_style = p.kind_text)

# The panel of a part: a muted card with a tag, that folds with the part.
_part_card(p, tag::AbstractString, body, part::ConversationPart) =
    _follow_fold!(WidgetCard(;
                             title = _tag(p, tag), content = body,
                             variant = :muted, collapsible = true),
                  () -> part.collapsed)

# Code is separated from the prose around it, and its language named, because a
# panel cannot say which language it holds.
_code_card(p, content, part::ConversationPart) =
    _part_card(p, _kind_label(content), content, part)

# A note is one quiet line, in the style of a tag, and the button of its action
# when it has one.
function _note_row(p, note::ConversationNote)
    children = Any[WidgetLabel(note.text; text_style = p.section_text)]
    action = note.action
    action === nothing || isempty(note.action_label) ||
        push!(children, WidgetButton(note.action_label; action))
    HorizontalLayout(children; vertical_align = :center, gap = p.section_gap)
end

# A picture, under the tag "picture".
_picture_card(p, image::ImageFile, part::ConversationPart) =
    _part_card(p, "picture", _make_picture_body(image, p.picture_height), part)

# The image of a picture, at most `height` high, in the shape of the picture. The
# view decodes the file for itself, so the part keeps only the name of the file,
# and a file that is gone, or a process with no backend to decode it, shows an
# empty box.
function _make_picture_body(image::ImageFile, height::Int)
    filename = image.filename
    raw = try
        decode_image(filename)
    catch exception
        is_fault_exception(exception) || rethrow()
        nothing
    end
    natural_width, natural_height = raw isa Tuple && length(raw) == 3 ?
        (max(1, Int(raw[2])), max(1, Int(raw[3]))) : (4 * height ÷ 3, height)
    shown_height = min(height, natural_height)
    shown_width = max(1, round(Int, natural_width * shown_height / natural_height))
    label = WidgetLabel(ImageFile(Cell(filename), Cell(raw)))
    HorizontalLayout(Any[LayoutConstraint(label; min_width = shown_width, preferred_width = shown_width,
                                          max_width = shown_width, min_height = shown_height,
                                          preferred_height = shown_height, max_height = shown_height)])
end

# Reasoning is secondary, so it starts folded, and folded it is the bare word.
# The tag is a word like every other tag.
_thinking_card(p, t::ConversationThinking, part::ConversationPart) =
    _part_card(p, "thinking", _thinking_body(t), part)

# A permission request is the question over one button for each answer. The
# buttons work while the agent waits, and the line under them says the answer
# once there is one.
function _permission_card(p, request::ConversationPermissionRequest, part::ConversationPart)
    buttons = Any[]
    for option in request.options
        button = WidgetButton(option.name; action = _ -> answer_permission_request!(request, option.id))
        set_cell_computation!(getfield(button, :enabled), () -> is_permission_request_open(request))
        push!(buttons, button)
    end
    status = WidgetLabel(""; text_style = p.section_text)
    set_cell_computation!(getfield(status, :content),
                          () -> (answer = request.answer; isempty(answer) ? "" : "Answer: " * answer))
    body = VerticalLayout(Any[WidgetLabel(request.title), HorizontalLayout(buttons; gap = p.section_gap), status];
                          gap = p.section_gap)
    _part_card(p, "permission", body, part)
end

# A sign-in request is the message over one button for each way to sign in and a
# button that tries again, the line that says how the last sign-in went, and the
# terminal of the sign-in once one started. The buttons work while the request
# has its live functions, which a request that a file read back has not; a
# method waits while a sign-in runs.
function _sign_in_card(p, request::ConversationSignInRequest, part::ConversationPart)
    buttons = Any[]
    for method in request.methods
        button = WidgetButton(method.name; tooltip = isempty(method.description) ? nothing : method.description,
                              action = editor -> (start = request.start; start === nothing || start(editor, method.id)))
        set_cell_computation!(getfield(button, :enabled), () -> request.start !== nothing && !request.is_signing_in)
        push!(buttons, button)
    end
    retry = WidgetButton("Try again"; tooltip = "Start the agent again.",
                         action = editor -> (try_again = request.retry; try_again === nothing || try_again(editor)))
    set_cell_computation!(getfield(retry, :enabled), () -> request.retry !== nothing)
    push!(buttons, retry)
    status = WidgetLabel(""; text_style = p.section_text)
    set_cell_computation!(getfield(status, :content), () -> request.state)
    fixed = Any[WidgetLabel(request.message), HorizontalLayout(buttons; gap = p.section_gap), status]
    body = VerticalLayout(copy(fixed); gap = p.section_gap, child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        terminal = request.terminal
        Cell[Cell(child) for child in (terminal === nothing ? fixed : vcat(fixed, Any[terminal]))]
    end)
    _part_card(p, "sign-in", body, part)
end

# A question is its message, then a block for each field with its title, its
# description and its control, then the Send and Decline buttons and the line
# that says the answer, or what the form still needs. The form is the live field
# of the part, where a person picks and types. The controls work while the agent
# waits.
function _question_card(p, request::ConversationQuestionRequest, part::ConversationPart)
    is_open() = is_question_request_open(request)
    children = Any[WidgetLabel(request.message)]
    for (index, field) in enumerate(request.fields)
        block = Any[WidgetLabel(field.title * (field.is_required ? " *" : ""))]
        isempty(field.description) || push!(block, WidgetLabel(field.description; text_style = p.section_text))
        push!(block, _make_question_control(p, field, request.form.values[index], is_open))
        push!(children, VerticalLayout(block; gap = p.section_gap, child_width = Fill))
    end
    send = WidgetButton("Send"; action = _ -> (values = find_question_values(request);
                                               values isa AbstractDict && answer_question_request!(request, values)))
    set_cell_computation!(getfield(send, :enabled), () -> is_open() && find_question_values(request) isa AbstractDict)
    decline = WidgetButton("Decline"; action = _ -> answer_question_request!(request, nothing))
    set_cell_computation!(getfield(decline, :enabled), is_open)
    status = WidgetLabel(""; text_style = p.section_text)
    set_cell_computation!(getfield(status, :content), () -> !isempty(request.answer) ? request.answer :
                          (values = find_question_values(request); values isa AbstractString ? values : ""))
    push!(children, HorizontalLayout(Any[send, decline]; gap = p.section_gap), status)
    _part_card(p, "question", VerticalLayout(children; gap = p.section_gap, child_width = Fill), part)
end

# The control of one field, which writes the `PrimitiveString` of its value: a
# toggle group for one choice and for yes or no, a button for each option of a
# choice of several, which adds or removes the option, and a text field for a
# text and a number.
function _make_question_control(p, field::AgentQuestionField, value::PrimitiveString, is_open::Function)
    if field.kind in (:choice, :boolean)
        options = field.kind === :boolean ? AgentOptionValue[AgentOptionValue("true", "Yes", ""),
                                                             AgentOptionValue("false", "No", "")] : field.options
        described = [option.name * ": " * option.description for option in options if !isempty(option.description)]
        group = WidgetToggleGroup(Any[option.name for option in options]; values = Any[option.value for option in options],
                                  target = value, field = "value",
                                  tooltip = isempty(described) ? nothing : join(described, "\n"))
        set_cell_computation!(getfield(group, :selected),
                              () -> something(findfirst(option -> option.value == value.value, options), 0))
        set_cell_computation!(getfield(group, :enabled), is_open)
        return group
    elseif field.kind === :choices
        buttons = Any[]
        for option in field.options
            is_chosen() = option.value in split(something(value.value, ""), '\n')
            button = WidgetButton(option.name; tooltip = isempty(option.description) ? nothing : option.description,
                                  action = _ -> (value.value = _toggle_question_choice(something(value.value, ""), option.value)))
            set_cell_computation!(button, () -> (is_chosen() ? "✓ " : "") * option.name)
            set_cell_computation!(getfield(button, :enabled), is_open)
            push!(buttons, button)
        end
        return HorizontalLayout(buttons; gap = p.section_gap)
    end
    text = WidgetText(value)
    set_cell_computation!(getfield(text, :enabled), is_open)
    text
end

# The chosen values, one a line, with `choice` added or removed.
function _toggle_question_choice(text::AbstractString, choice::AbstractString)
    chosen = [String(line) for line in split(text, '\n') if !isempty(line)]
    join(choice in chosen ? filter(!=(choice), chosen) : vcat(chosen, String(choice)), '\n')
end

# The steps from the card of a question to the text field of the field `index`,
# and the field whose text field a path names; `nothing` for a field with no text
# field. The body holds the message, then a block for each field, whose control
# follows its title and its description, when it has one.
function _get_question_text_steps(request::ConversationQuestionRequest, index::Int)
    field = request.fields[index]
    field.kind in (:text, :number, :integer) || return nothing
    control = isempty(field.description) ? 2 : 3
    Any[FieldReferenceStep("content"), FieldReferenceStep("children"), RangeReferenceStep(index, index + 1),
        FieldReferenceStep("children"), RangeReferenceStep(control - 1, control), FieldReferenceStep("content")]
end

function _map_question_forward(request::ConversationQuestionRequest, reference)
    steps = _steps(reference)
    (steps !== nothing && length(steps) >= 4 && _is_field_step(steps[1], "content") &&
     _is_field_step(steps[2], "form") && _is_field_step(steps[3], "values") && steps[4] isa RangeReferenceStep) ||
        return EmptyReference()
    index = steps[4].stop
    1 <= index <= length(request.fields) || return EmptyReference()
    prefix = _get_question_text_steps(request, index)
    prefix === nothing ? EmptyReference() : _from_steps(vcat(prefix, steps[5:end]))
end

function _map_question_backward(request::ConversationQuestionRequest, reference)
    steps = _steps(reference)
    steps === nothing && return EmptyReference()
    for index in eachindex(request.fields)
        prefix = _get_question_text_steps(request, index)
        prefix === nothing && continue
        length(steps) >= length(prefix) && steps[1:length(prefix)] == prefix || continue
        return _from_steps(vcat(Any[FieldReferenceStep("content"), FieldReferenceStep("form"),
                                    FieldReferenceStep("values"), RangeReferenceStep(index - 1, index)],
                                steps[(length(prefix) + 1):end]))
    end
    EmptyReference()
end

# The card of a question, its body, and the block and the text field of each
# field follow the part's selection, so a key that a person types reaches the
# text field.
function _follow_question_selection!(card, part, projection, iomap)
    _follow_selection!(card, part, projection, iomap, Any[])
    _follow_selection!(card.content, part, projection, iomap, Any[FieldReferenceStep("content")])
    request = part.content
    for index in eachindex(request.fields)
        prefix = _get_question_text_steps(request, index)
        prefix === nothing && continue
        block = card.content.children[index + 1]
        _follow_selection!(block, part, projection, iomap, prefix[1:3])
        _follow_selection!(block.children[prefix[5].stop], part, projection, iomap, prefix[1:5])
    end
end

# Where the terminal of a sign-in sits in the card of its part: the fourth child
# of the body.
const _SIGN_IN_TERMINAL_PREFIX = Any[FieldReferenceStep("content"), FieldReferenceStep("children"),
                                     RangeReferenceStep(3, 4)]

# The field of the content of a part in which a person works, inside a transcript
# that is otherwise read: the terminal of a sign-in. `nothing` for a content
# that has none.
_find_live_field(content) = nothing
_find_live_field(::ConversationSignInRequest) = "terminal"
_find_live_field(::ConversationQuestionRequest) = "form"

# Whether `document` is, or is inside, the live field of the content of a part
# under `node`, a conversation, a turn or a part.
function _is_live_document(node, document)
    parts = node isa ConversationConversation ? (part for turn in node.turns for part in turn.parts) :
            node isa ConversationTurn ? node.parts : node isa ConversationPart ? (node,) : ()
    for part in parts
        field = _find_live_field(part.content)
        field === nothing && continue
        live = getproperty(part.content, Symbol(field))
        live === document && return true
        live isa Document && !isempty(search_references(live, found -> found === document)) && return true
    end
    false
end

# Whether `steps`, from `node` (a conversation, a turn or a part), go into the
# live field of the content of a part.
function _is_live_path(node, steps)
    length(steps) >= 2 || return false
    if node isa Union{ConversationConversation,ConversationTurn}
        name = node isa ConversationConversation ? "turns" : "parts"
        children = getproperty(node, Symbol(name))
        (_is_field_step(steps[1], name) && steps[2] isa RangeReferenceStep &&
         1 <= steps[2].stop <= length(children)) || return false
        return _is_live_path(children[steps[2].stop], steps[3:end])
    elseif node isa ConversationPart
        field = _find_live_field(node.content)
        return field !== nothing && _is_field_step(steps[1], "content") && _is_field_step(steps[2], field)
    end
    false
end

# Whether the operation `op`, which reached the IO map `iomap` of `p`, goes into
# the live field of a part: by its path, or by the document that it names, such
# as the value that a toggle group of a question form writes.
function _is_live_operation(p, iomap, op)
    op isa ReplaceReferencedValueOperation && op.document !== nothing &&
        return _is_live_document(iomap.input, op.document)
    reference = operation_reference(op)
    reference isa Reference || return false
    mapped = map_reference_backward(p, iomap, reference)
    steps = mapped isa Reference ? _steps(strip_reference_types(mapped)) : nothing
    steps !== nothing && _is_live_path(iomap.input, steps)
end

# An evaluation is its header over its two sections. The header names the tool
# or the resource, and the part folds as a whole; each section folds on its own.
_eval_card(p, ef::EvaluatorForm, part::ConversationPart, folds) =
    _part_card(p, get_evaluation_title(ef), _eval_sections(p, ef, folds), part)

# The two sections of a form: its code (or its arguments) over its result. Each
# is a bare card with a small title, indented under the panel's header and with
# no other padding of its own, because the panel around them already keeps one. The form (a JuliaDocument) and the result
# (a TextBlock) are embedded as the sections' bodies, so each is recursed through
# its own projection chain and sizes to its content.
#
# With `folds`, each section folds on its own, and `folds` receives what a fold
# on each card means, so the reader can say it back to the domain. With no
# `folds` the sections do not fold — the composer draws a draft that way.
#
# `p` is a projection that holds `section_text`, `error_text`, `section_gap`
# and `section_padding`: `ConversationPartToWidget` in a transcript, and
# `ConversationComposerToWidget` for the committed evaluation of a draft.
function _eval_sections(p, ef::EvaluatorForm, folds)
    form_label, result_label = get_evaluation_section_labels(ef)
    foldable = folds !== nothing
    form_card   = _section_card(form_label, ef.form, p.section_text, p.section_padding, foldable)
    result_card = _section_card(result_label, ef.result,
                                ef.is_error === true ? p.error_text : p.section_text,
                                p.section_padding, foldable)
    if foldable
        _follow_fold!(form_card,   () -> ef.form_collapsed)
        _follow_fold!(result_card, () -> ef.result_collapsed)
        push!(folds, form_card   => ToggleEvaluatorSectionOperation(ef, :form))
        push!(folds, result_card => ToggleEvaluatorSectionOperation(ef, :result))
    end
    VerticalLayout(Any[form_card, result_card]; gap = p.section_gap)
end

_section_card(label::AbstractString, body, style::StyleText, padding::Inset, foldable::Bool) =
    WidgetCard(;
               title = WidgetLabel(String(label); text_style = style),
               content = body, variant = :plain, collapsible = foldable,
               padding = padding)

# A thinking part's body is its reasoning text, recursed like any other text
# content. Redacted blocks (and `display: "omitted"`, which yields empty text)
# render an elided placeholder rather than an empty card.
function _thinking_body(t::ConversationThinking)
    t.redacted && return make_text_block("[redacted thinking]")
    txt = t.text
    txt isa TextBlock && _text_is_empty(txt) &&
        return make_text_block("[no thinking summary]")
    txt
end

# True when a TextBlock has no non-empty span content (e.g. `display: "omitted"`).
# A text is empty when it holds no character but the breaks between its lines.
_text_is_empty(t::TextBlock) = all(==('\n'), get_flat_string(t))

# ── Reference mapping / reader ───────────────────────────────────────────────
#
# A transcript is READ, not written, and a person reading one still has to be
# able to point at a message and take a copy of it. So a plain click names the
# PART it landed in — `turns[i].parts[j]` — and an Alt+click names the innermost
# object under the pointer: a message, a part, or the form or the result of an
# evaluation. The reader below declines every operation that would change what a
# turn says.
#
# Naming the part is a translation, and each level does its own step of it. The
# widget layer hands up a path in ITS domain,
# `children[i].content.children[j].content.…`, because a turn prints as a card in
# a layout and a part prints inside that card. Each level strips the steps it
# printed and delegates the rest to the child that printed them (School A: talk
# to the child IoMap, never re-walk the tree by type).
#
# Answering `EmptyReference()` at every level would say "somewhere in me" and
# could not say where. Worse, an operation from below would pass through
# untranslated, so a click in a text part would put a WIDGET path — `children[2].
# content.children[1].content⌶{3}` — on a conversation document, where no such
# field exists.

# The child IoMaps a composite kept, in print order.
_children(iomap) = getfield(iomap, :child_iomaps)[]::Vector

# Split `[Field(name), Range(i-1, i), rest...]` into `(i, rest)`, or nothing when
# the path does not start that way.
function _indexed(steps, name::AbstractString)
    length(steps) >= 2 || return nothing
    h = steps[1]
    (h isa FieldReferenceStep && h.name == name) || return nothing
    r = steps[2]
    r isa RangeReferenceStep || return nothing
    (r.stop, steps[3:end])
end

_steps(reference) = reference isa Reference ? get_reference_steps(reference) : nothing

# Rebuild a reference from a step list, innermost last, ending in `tail`.
_from_steps(steps, tail = EmptyReference()) =
    foldr((step, rest) -> ConcreteReference(step, rest), steps; init = tail)

# One level of the walk down: strip this level's steps, ask the child that
# printed the rest what the rest means, and put this level's own step back on.
# `skip` is how many `content` steps this level printed above its layout; a path
# that leaves the layout by another field, such as a card's `title`, names this
# level's own node.
function _backward_level(iomap, reference, out_name::AbstractString,
                         in_name::AbstractString, skip::Int)
    steps = _steps(reference)
    steps === nothing && return EmptyReference()
    length(steps) >= skip || return EmptyReference()
    all(k -> _is_field_step(steps[k], "content"), 1:skip) || return EmptyReference()
    found = _indexed(steps[(skip + 1):end], out_name)
    found === nothing && return EmptyReference()
    (i, rest) = found
    children = _children(iomap)
    (1 <= i <= length(children)) || return EmptyReference()
    child = children[i]
    inner = map_reference_backward(child.projection, child, _from_steps(rest))
    inner === nothing && (inner = EmptyReference())
    ConcreteReference(FieldReferenceStep(in_name),
        ConcreteReference(RangeReferenceStep(i - 1, i), inner))
end

# And one level of the walk up: strip this level's own step, ask the child to
# place the rest, and put back the widget steps this level printed.
function _forward_level(iomap, reference, in_name::AbstractString,
                        prefix::Vector, out_name::AbstractString)
    steps = _steps(reference)
    steps === nothing && return nothing
    found = _indexed(steps, in_name)
    found === nothing && return nothing
    (i, rest) = found
    children = _children(iomap)
    (1 <= i <= length(children)) || return nothing
    child = children[i]
    inner = isempty(rest) ? EmptyReference() :
            map_reference_forward(child.projection, child, _from_steps(rest))
    inner === nothing && return nothing
    _from_steps(vcat(prefix, Any[FieldReferenceStep(out_name),
                                 RangeReferenceStep(i - 1, i)]), inner)
end

# `turns[i].<rest>` ↔ `children[i].<rest>`
map_reference_backward(::ConversationConversationToWidgetComposite, iomap, reference) =
    _backward_level(iomap, reference, "children", "turns", 0)
map_reference_forward(::ConversationConversationToWidgetComposite, iomap, reference) =
    _forward_level(iomap, reference, "turns", Any[], "children")

# `parts[j].<rest>` ↔ `content.children[j].<rest>`. The card's body sits behind
# its `content` slot, which is the one step this level prints above the layout.
map_reference_backward(::ConversationTurnToWidgetComposite, iomap, reference) =
    _backward_level(iomap, reference, "children", "parts", 1)
map_reference_forward(::ConversationTurnToWidgetComposite, iomap, reference) =
    _forward_level(iomap, reference, "parts",
                   Any[FieldReferenceStep("content")], "children")

# A part is the floor, except for the two sections of an evaluation. Whatever was
# clicked inside a part names the part — a transcript is read as messages, not as
# characters — and whatever was clicked inside a section of an evaluation names
# that section's document, its form or its result, as a whole. The section's
# place in the part's card is `content.children[k].content`.
const _PART_SECTIONS = (("form", 1), ("result", 2))

_is_field_step(step, name::AbstractString) = step isa FieldReferenceStep && step.name == name

function map_reference_backward(::ConversationPartToWidget, iomap, reference)
    iomap.input.content isa ConversationSignInRequest && return _map_sign_in_backward(reference)
    iomap.input.content isa ConversationQuestionRequest && return _map_question_backward(iomap.input.content, reference)
    iomap.input.content isa EvaluatorForm || return EmptyReference()
    steps = _steps(reference)
    (steps !== nothing && length(steps) >= 4 && _is_field_step(steps[1], "content") &&
     _is_field_step(steps[2], "children") && steps[3] isa RangeReferenceStep &&
     _is_field_step(steps[4], "content")) || return EmptyReference()
    for (name, index) in _PART_SECTIONS
        steps[3].stop == index &&
            return _from_steps(Any[FieldReferenceStep("content"), FieldReferenceStep(name)])
    end
    EmptyReference()
end

# And the floor going up: the part itself, wherever the caret is said to be
# inside it, or the body of the section its selection names. A part with no
# chrome prints its content directly, so there is no step of this level's own to
# add.
function map_reference_forward(::ConversationPartToWidget, iomap, reference)
    iomap.input.content isa ConversationSignInRequest && return _map_sign_in_forward(reference)
    iomap.input.content isa ConversationQuestionRequest && return _map_question_forward(iomap.input.content, reference)
    iomap.input.content isa EvaluatorForm || return EmptyReference()
    steps = _steps(reference)
    (steps !== nothing && length(steps) >= 2 && _is_field_step(steps[1], "content")) ||
        return EmptyReference()
    for (name, index) in _PART_SECTIONS
        _is_field_step(steps[2], name) &&
            return _from_steps(Any[FieldReferenceStep("content"), FieldReferenceStep("children"),
                                   RangeReferenceStep(index - 1, index), FieldReferenceStep("content")])
    end
    EmptyReference()
end

# The terminal of a sign-in and back: `content.terminal.<rest>` is the fourth
# child of the body of the card, and `<rest>` in it. Any other place in the card
# is the part.
function _map_sign_in_forward(reference)
    steps = _steps(reference)
    (steps !== nothing && length(steps) >= 2 && _is_field_step(steps[1], "content") &&
     _is_field_step(steps[2], "terminal")) || return EmptyReference()
    _from_steps(vcat(_SIGN_IN_TERMINAL_PREFIX, steps[3:end]))
end

function _map_sign_in_backward(reference)
    steps = _steps(reference)
    prefix = _SIGN_IN_TERMINAL_PREFIX
    (steps !== nothing && length(steps) >= length(prefix) && steps[1:length(prefix)] == prefix) ||
        return EmptyReference()
    _from_steps(vcat(Any[FieldReferenceStep("content"), FieldReferenceStep("terminal")],
                     steps[(length(prefix) + 1):end]))
end

for P in (ConversationConversationToWidgetComposite,
          ConversationTurnToWidgetComposite,
          ConversationPartToWidget)
    # A left click that named nothing still landed here, and this node is what it
    # can honestly claim. Another button moves no selection.
    @eval read_intent(::$P, iomap, click::MouseClick) =
        click.button === :left ? ReplaceSelectionOperation(EmptyReference()) : nothing
    # A click that DID name something: say which part it named. The widget path
    # comes up from below and goes down the walk above.
    @eval function read_intent(p::$P, iomap, op::ReplacePathOperation)
        inner = map_reference_backward(p, iomap, op.path)
        make_path_operation(op, inner === nothing ? EmptyReference() : inner)
    end
    # A transcript is READ. An edit that reaches it is declined by its exact
    # type, so an operation this file does not know about still travels. An edit
    # in the live field of a part, such as the terminal of a sign-in, is the work
    # of a person there, and goes on.
    for O in (:ReplaceReferencedValueOperation, :ReplaceStringRangeOperation,
              :ReplaceNumberRangeOperation)
        @eval read_intent(p::$P, iomap, op::$O) =
            _is_live_operation(p, iomap, op) ? invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, op) : nothing
    end
    # A compound says each of its parts onward, and a path in it says which part
    # it named, as a path alone does; so the start of a drag in a compound names
    # its part, and the drag comes back to it.
    @eval read_intent(p::$P, iomap, op::CompoundOperation) =
        CompoundOperation(Any[o isa Union{ReplacePathOperation,CompoundOperation} ? read_intent(p, iomap, o) : o
                              for o in op.operations])
    # Anything else an operation says, it says onward.
    @eval read_intent(::$P, iomap, op::Operation) = op
    # A raw gesture is not an intent. Answering one would claim it, and the level
    # above could not tell the two apart.
    @eval read_intent(::$P, iomap, op) = nothing
end

# The WidgetCard chevron-click reader emits `ToggleCollapseOperation(card)` where
# `card` is the produced widget. Say what that fold means in the conversation
# domain by walking the iomap tree: a card that is the output of an iomap folds
# the node that iomap printed, and a card a part listed among its `folds` means
# the operation the part said. A card this walk does not find is not the
# transcript's, and its operation travels unchanged.
function _find_fold_operation(iomap, card)
    iomap = get_content_iomap(iomap)
    if iomap isa ConversationPartToWidgetIoMap
        for (folded, operation) in iomap.folds
            folded === card && return operation
        end
    end
    iomap.output === card && return ToggleCollapseOperation(iomap.input)
    if iomap isa ChildrenIoMap
        for entry in getfield(iomap, :child_iomaps)[]
            cim = entry isa Tuple ? entry[end] : entry
            operation = _find_fold_operation(cim, card)
            operation !== nothing && return operation
        end
    end
    nothing
end

# A turn or a part folds from its chevron wherever it is the root of what is
# drawn: in a transcript, or alone in a tab.
for P in (ConversationConversationToWidgetComposite,
          ConversationTurnToWidgetComposite,
          ConversationPartToWidget)
    @eval function read_intent(::$P, iomap, op::ToggleCollapseOperation)
        op.target === nothing && return op
        operation = _find_fold_operation(iomap, op.target)
        operation === nothing ? op : operation
    end
end

# ── The two gestures a transcript reads itself ──────────────────────────────
#
# A plain click names at most a part, so a click in a result selects the part
# that holds it, as a click always did. An Alt+click keeps the innermost object
# the maps named. And Alt with an arrow walks the objects: a message, its parts,
# and the form and the result of an evaluation. The transcript is read, so no
# widget inside it has a use for these keys, and the walk answers them whatever
# a widget said.
function read_intent(p::ConversationConversationToWidgetComposite, recursion,
                     change::Intent, iomap)
    gesture = change.gesture
    direction = get_selection_walk_direction(gesture)
    if direction !== nothing
        path = compute_transcript_walk(iomap.input, iomap.input.selection, direction)
        return Intent(gesture, path === nothing ? nothing : ReplaceSelectionOperation(path))
    end
    payload = change.operation === nothing ? gesture : change.operation
    answer = read_intent(p, iomap, payload)
    if answer isa ReplaceSelectionOperation && gesture isa MouseClick &&
       !is_whole_selection_press(gesture)
        steps = _steps(strip_reference_types(answer.path))
        # A press in the live field of a part keeps its place, as the caret of
        # a person who types there.
        (steps !== nothing && _is_live_path(iomap.input, steps)) ||
            (answer = ReplaceSelectionOperation(_get_part_prefix(answer.path)))
    end
    Intent(gesture, answer)
end

# `turns[i].parts[j]` when `path` goes into a part, else `path` itself.
function _get_part_prefix(path)
    steps = _steps(path)
    (steps !== nothing && length(steps) > 4 && _is_field_step(steps[3], "parts")) || return path
    _from_steps(steps[1:4])
end

"""
    compute_transcript_walk(conversation, selection, direction) -> Reference | Nothing

One step of the Alt + arrow walk over the objects of a transcript, as a path
from `conversation`. The objects are the messages (`turns[i]`), their parts
(`turns[i].parts[j]`), and the form and the result of an evaluation
(`turns[i].parts[j].content.form`, `….result`).

Up is the enclosing object, and the conversation as a whole above a message;
down is the first object inside, and an object with nothing inside keeps the
selection; left and right are the neighbouring objects of the same kind, and
the first and the last keep the selection. `nothing` when the selection is not
in the conversation, or when up has nowhere to go.
"""
function compute_transcript_walk(c::ConversationConversation, selection, direction::Symbol)
    selection === nothing && return nothing
    steps = _steps(strip_reference_types(selection))
    steps === nothing && return nothing
    i = _walk_index(steps, 1, "turns")
    (i === nothing || 1 <= i <= length(c.turns)) || return nothing
    j = i === nothing ? nothing : _walk_index(steps, 3, "parts")
    (j === nothing || 1 <= j <= length(c.turns[i].parts)) || return nothing
    section = j === nothing ? nothing : _walk_section(steps)
    turn(i) = Any[FieldReferenceStep("turns"), RangeReferenceStep(i - 1, i)]
    part(i, j) = vcat(turn(i), Any[FieldReferenceStep("parts"), RangeReferenceStep(j - 1, j)])
    form(i, j, name) = vcat(part(i, j), Any[FieldReferenceStep("content"), FieldReferenceStep(name)])
    evaluation(i, j) = c.turns[i].parts[j].content isa EvaluatorForm
    step(k, n, offset) = clamp(k + offset, 1, n)
    offset = direction === :left ? -1 : 1
    path = if i === nothing
        # The conversation as a whole: down is the first message.
        direction === :down && !isempty(c.turns) ? turn(1) : nothing
    elseif j === nothing
        n = length(c.turns[i].parts)
        direction === :up ? Any[] :
        direction === :down ? (n > 0 ? part(i, 1) : turn(i)) :
        turn(step(i, length(c.turns), offset))
    elseif section === nothing
        direction === :up ? turn(i) :
        direction === :down ? (evaluation(i, j) ? form(i, j, "form") : part(i, j)) :
        part(i, step(j, length(c.turns[i].parts), offset))
    else
        direction === :up ? part(i, j) :
        direction === :down ? form(i, j, section) :
        form(i, j, direction === :left ? "form" : "result")
    end
    path === nothing ? nothing : _from_steps(path)
end

# The 1-based index at `steps[at + 1]` when `steps[at]` is the field `name`.
function _walk_index(steps, at::Int, name::AbstractString)
    length(steps) >= at + 1 || return nothing
    _is_field_step(steps[at], name) || return nothing
    steps[at + 1] isa RangeReferenceStep || return nothing
    steps[at + 1].stop
end

# `"form"` or `"result"` when the steps go into that section of a part.
function _walk_section(steps)
    length(steps) >= 6 && _is_field_step(steps[5], "content") || return nothing
    for (name, _) in _PART_SECTIONS
        _is_field_step(steps[6], name) && return name
    end
    nothing
end

# ── Factory ──────────────────────────────────────────────────────────────────

"""
    ConversationToWidget(; theme = nothing)

Type-dispatching projection over the conversation document types. Wrap in
`RecursiveProjection` at the call site. It gives each projection its styles from
`theme`, a `ConversationTheme` scaled or not, or the default values for `nothing`.
"""
function ConversationToWidget(; theme = nothing)
    get_style(name) = get_conversation_style(theme, name)
    TypeDispatchingProjection(
        ConversationConversation => ConversationConversationToWidgetComposite(; turn_gap = get_style(:turn_gap)),
        ConversationTurn         => ConversationTurnToWidgetComposite(;
            part_gap = get_style(:part_gap), role_gap = get_style(:role_gap),
            user_role_text = get_style(:user_role_text),
            assistant_role_text = get_style(:assistant_role_text),
            other_role_text = get_style(:other_role_text),
            user_role_icon = get_style(:user_role_icon),
            assistant_role_icon = get_style(:assistant_role_icon),
            other_role_icon = get_style(:other_role_icon)),
        ConversationPart         => ConversationPartToWidget(;
            kind_text = get_style(:kind_text), section_text = get_style(:section_text),
            error_text = get_style(:error_text), section_gap = get_style(:section_gap),
            section_padding = get_style(:section_indent)),
    )
end
