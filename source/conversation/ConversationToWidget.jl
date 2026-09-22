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
#                                Code, a thinking block and an evaluation each keep
#                                a quiet tinted panel with a one-line tag; every
#                                other kind draws no chrome at all.
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

struct ConversationConversationToWidgetComposite <: Projection end
struct ConversationTurnToWidgetComposite         <: Projection end
struct ConversationPartToWidget                  <: Projection end

# ── Constants / glyphs ────────────────────────────────────────────────────────

# No card width. A turn card and a part card take the width they are offered —
# the transcript says `child_width = Fill` and the card resolves it — so a
# conversation is as wide as the pane holding it.
const _GAP           = 8    # between the parts of one turn
# Between turns. A transcript is read by turn, so the eye needs the boundary to
# be louder than the one inside a turn. Each turn card already keeps its own
# padding above and below what it holds, so a small gap on top of that is what
# separates two turns without pushing them apart.
const _TURN_GAP      = 8
# Between the two sections of an evaluation, which are one thing read together.
const _SECTION_GAP   = 10
# A section sits under the header of the card around it, indented by the column
# that card's chevron takes: two half-sizes of the theme's chevron and the title
# gap, so a section's own chevron starts where the header's word starts.
const _SECTION_INDENT = 12

# The role line is metadata, and the message is the content, so it renders
# smaller than the body it introduces — but it is still read, so it is not the
# size of a footnote. It was bold 22, bigger than the words it labelled, which
# made a transcript read as a stack of headings; 14 answered that and went too
# far the other way. The role keeps its color, because color is what tells a
# person who spoke.
const _ROLE_FONT = font_ubuntu_bold_18
_role_color(role::Symbol) = role === :user      ? color_indigo_600 :
                            role === :assistant ? color_solarized_cyan : color_slate_600
_role_style(role::Symbol) = StyleText(_ROLE_FONT, _role_color(role))

# A part's tag names a kind, which is a smaller thing to say than who spoke, so
# it stays smaller and stays neutral. It is 16 and not 14: at 14 the word sat
# below the middle of the chevron beside it, and the two read as two rows.
const _KIND_STYLE = StyleText(font_ubuntu_bold_16, color_slate_600)
# A section of an evaluation is a smaller thing again, so its title is the same
# size and not bold. An error is the one section title that carries a color,
# because it is the one a reader must not miss.
const _SECTION_STYLE = StyleText(font_ubuntu_regular_16, color_slate_500)
const _ERROR_STYLE   = StyleText(font_ubuntu_bold_16, color_destructive)

# The mark beside a role. It is drawn as text and not as a `WidgetAvatar`,
# because an avatar is a disc with initials: at this size the disc is a pale ring
# behind a letter that overflows it, and a letter is not an icon. The glyph
# stands on its own, in the role's own color.
#
# The glyphs are icons of the Lucide font, the set every icon of the window comes
# from, so the mark beside a turn looks like the pictures of the toolbar. A mark
# must not read as a smudge beside the bold word: Lucide draws a stroke of a
# twelfth of its size, which at this size is as heavy as the stem of a letter.
const _ICON_FONT = font_lucide_icons_20
_icon_style(role::Symbol) = StyleText(_ICON_FONT, _role_color(role))

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
_role_header(role::Symbol) =
    HorizontalLayout(Any[
        WidgetLabel(Point2D(0, 0), _role_glyph(role); text_style = _icon_style(role)),
        WidgetLabel(Point2D(0, 0), String(role); text_style = _role_style(role)),
    ]; vertical_align = :center, gap = 10)

# A card that folds. Its `collapsed` cell reads the flag on the domain node,
# because the toggle reader re-targets every fold to that node and the kernel
# handler flips the flag there; the card only shows it. `read_flag` answers the
# flag, and a flag that was never set reads as open.
function _follow_fold!(card::WidgetCard, read_flag::Function)
    set_cell_function!(getfield(card, :collapsed), () -> read_flag() === true)
    card
end

# A widget that follows the selection of the node that printed it. Its selection
# cell holds the node's selection mapped forward, with the steps that lead from
# the printed output to the widget taken off, and nothing when the image does
# not pass through the widget. A container draws its selection ring from that
# cell. `lead` are those steps, without node types.
function _follow_selection!(widget, node, projection, iomap, lead::Vector)
    set_cell_function!(getfield(widget, :selection), () -> begin
        selection = node.selection
        selection === nothing && return nothing
        image = map_reference_forward(projection, iomap, selection)
        image isa Reference || return nothing
        steps = get_reference_steps(strip_reference_types(image))
        length(steps) >= length(lead) || return nothing
        all(i -> steps[i] == lead[i], eachindex(lead)) || return nothing
        _from_steps(steps[(length(lead) + 1):end])
    end)
    widget
end

# ── print_document: conversation → vertical list of turn cards ──────────────

function print_document(projection::ConversationConversationToWidgetComposite,
                          recursion, c::ConversationConversation, ctx)
    rec, ref = recursion, ctx.reference
    # Cache the child turn iomaps (recomputed only when the turn list changes),
    # so the produced cards keep a stable identity that the toggle reader can
    # match against. The layout reads each iomap's `.output`.
    ioms = ComputedCell(() -> Any[
        print_document(rec, rec, c.turns[i], make_child_context(ctx, ref))
        for i in eachindex(c.turns)
    ])
    # Every turn fills the width it is given and grows with what it holds.
    layout = VerticalLayout(ComputedCellVector(() -> Any[im.output for im in ioms[]]),
                            Cell(:left), Cell(_TURN_GAP),
                            Cell(Fill), Cell(Content), Cell(nothing))
    iomap = ChildrenIoMap(projection, c, layout, ioms)
    _follow_selection!(layout, c, projection, iomap, Any[])
    iomap
end

# ── print_document: turn → card with avatar header + part stack ─────────────

function print_document(projection::ConversationTurnToWidgetComposite,
                          recursion, t::ConversationTurn, ctx)
    rec, ref = recursion, ctx.reference
    ioms = ComputedCell(() -> Any[
        print_document(rec, rec, t.parts[i], make_child_context(ctx, ref))
        for i in eachindex(t.parts)
    ])
    # And so does every part inside a turn.
    body = VerticalLayout(ComputedCellVector(() -> Any[im.output for im in ioms[]]),
                          Cell(:left), Cell(_GAP),
                          Cell(Fill), Cell(Content), Cell(nothing))
    # A turn is a band and not a box. The user's band is tinted and the model's
    # is plain, which is what tells the two apart — the same job a border did,
    # done by a channel the content does not already use. It stays a card, so
    # its chevron still folds it and the collapse reader below still finds
    # the turn that a produced card came from.
    card = WidgetCard(Point2D(0, 0);
                      title = _role_header(t.role),
                      content = body,
                      variant = t.role === :user ? :tinted : :plain,
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
    output = content isa EvaluatorForm        ? _eval_card(content, part, folds) :
             content isa ConversationThinking ? _thinking_card(content, part)    :
             _is_code(content)                ? _code_card(content, part)        :
             content
    iomap = ConversationPartToWidgetIoMap(projection, part, output, folds)
    content isa EvaluatorForm && _follow_section_selection!(output, part, projection, iomap)
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

# A part's panel is MUTED and a turn's band is TINTED, because a part sits inside
# a turn: a code block in a user message would draw nothing if the two shared a
# color.
#
# A quiet tag: the one line a chromed part draws to name itself. No avatar — a
# glyph beside a word says the word twice.
_tag(label::AbstractString) =
    WidgetLabel(Point2D(0, 0), String(label); text_style = _KIND_STYLE)

# The panel of a part: a muted card with a tag, that folds with the part.
_part_card(tag::AbstractString, body, part::ConversationPart) =
    _follow_fold!(WidgetCard(Point2D(0, 0);
                             title = _tag(tag), content = body,
                             variant = :muted, collapsible = true),
                  () -> part.collapsed)

# Code is separated from the prose around it, and its language named, because a
# panel cannot say which language it holds.
_code_card(content, part::ConversationPart) =
    _part_card(_kind_label(content), content, part)

# Reasoning is secondary, so it starts folded, and folded it is the bare word.
# The tag is a word like every other tag.
_thinking_card(t::ConversationThinking, part::ConversationPart) =
    _part_card("thinking", _thinking_body(t), part)

# An evaluation is its header over its two sections. The header names the tool
# or the resource, and the part folds as a whole; each section folds on its own.
_eval_card(ef::EvaluatorForm, part::ConversationPart, folds) =
    _part_card(get_evaluation_title(ef), _eval_sections(ef, folds), part)

# The two sections of a form: its code (or its arguments) over its result. Each
# is a bare card with a small title, indented under the panel's header and with
# no other padding of its own, because the panel around them already keeps one. The form (a JuliaDocument) and the result
# (a TextBlock) are embedded as the sections' bodies, so each is recursed through
# its own projection chain and sizes to its content.
#
# With `folds`, each section folds on its own, and `folds` receives what a fold
# on each card means, so the reader can say it back to the domain. With no
# `folds` the sections do not fold — the composer draws a draft that way.
function _eval_sections(ef::EvaluatorForm, folds)
    form_label, result_label = get_evaluation_section_labels(ef)
    foldable = folds !== nothing
    form_card   = _section_card(form_label, ef.form, _SECTION_STYLE, foldable)
    result_card = _section_card(result_label, ef.result,
                                ef.is_error === true ? _ERROR_STYLE : _SECTION_STYLE,
                                foldable)
    if foldable
        _follow_fold!(form_card,   () -> ef.form_collapsed)
        _follow_fold!(result_card, () -> ef.result_collapsed)
        push!(folds, form_card   => ToggleEvaluatorSectionOperation(ef, :form))
        push!(folds, result_card => ToggleEvaluatorSectionOperation(ef, :result))
    end
    VerticalLayout(Any[form_card, result_card]; gap = _SECTION_GAP)
end

_section_card(label::AbstractString, body, style::StyleText, foldable::Bool) =
    WidgetCard(Point2D(0, 0);
               title = WidgetLabel(Point2D(0, 0), String(label); text_style = style),
               content = body, variant = :plain, collapsible = foldable,
               padding = Inset(0, 0, _SECTION_INDENT, 0))

# A thinking part's body is its reasoning text, recursed like any other text
# content. Redacted blocks (and `display: "omitted"`, which yields empty text)
# render an elided placeholder rather than an empty card.
function _thinking_body(t::ConversationThinking)
    t.redacted && return TextBlock(TextString("[redacted thinking]"))
    txt = t.text
    txt isa TextBlock && _text_is_empty(txt) &&
        return TextBlock(TextString("[no thinking summary]"))
    txt
end

# True when a TextBlock has no non-empty span content (e.g. `display: "omitted"`).
function _text_is_empty(t::TextBlock)
    for span in t.elements
        hasproperty(span, :content) || continue
        c = span.content
        c isa AbstractString && !isempty(c) && return false
    end
    true
end

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

for P in (ConversationConversationToWidgetComposite,
          ConversationTurnToWidgetComposite,
          ConversationPartToWidget)
    # A click that named nothing still landed here, and this node is what it can
    # honestly claim.
    @eval read_intent(::$P, iomap, ::MousePress) =
        ReplaceSelectionOperation(EmptyReference())
    # A click that DID name something: say which part it named. The widget path
    # comes up from below and goes down the walk above.
    @eval function read_intent(p::$P, iomap, op::ReplaceSelectionOperation)
        inner = map_reference_backward(p, iomap, op.path)
        ReplaceSelectionOperation(inner === nothing ? EmptyReference() : inner)
    end
    # A transcript is READ. An edit that reaches it is declined by its exact
    # type, so an operation this file does not know about still travels.
    for O in (:ReplaceReferencedValueOperation, :ReplaceStringRangeOperation,
              :ReplaceNumberRangeOperation)
        @eval read_intent(::$P, iomap, op::$O) = nothing
    end
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
    if answer isa ReplaceSelectionOperation && gesture isa MousePress &&
       !is_whole_selection_press(gesture)
        answer = ReplaceSelectionOperation(_get_part_prefix(answer.path))
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
    ConversationToWidget()

Type-dispatching projection over the conversation document types. Wrap in
`RecursiveProjection` at the call site.
"""
function ConversationToWidget()
    TypeDispatchingProjection(
        ConversationConversation => ConversationConversationToWidgetComposite(),
        ConversationTurn         => ConversationTurnToWidgetComposite(),
        ConversationPart         => ConversationPartToWidget(),
    )
end
