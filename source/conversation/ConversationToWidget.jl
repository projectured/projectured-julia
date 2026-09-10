"""
    ConversationToWidgetModule

ConversationDocument → WidgetDocument projection — a vertical list of chat
bubbles:

    ConversationConversation → VerticalLayout of turn bands
    ConversationTurn         → WidgetCard, quiet: title = [avatar(role) + role
                               label], content = VerticalLayout of part widgets.
                               The user's band is tinted and the model's is
                               plain — neither draws a border.
    ConversationPart         → the part's `content` document (recursed), bare.
                               Code, a thinking block and an evaluation each keep
                               a quiet tinted panel with a one-line tag; every
                               other kind draws no chrome at all.

A turn is collapsible, and so is a part that kept a panel: when `collapsed` is
set, the body is wrapped in a `WidgetScrollPane` clipped to a few lines (a
graphics-viewport clip). A part with no panel has no header to click, so it does
not fold — prose is what a person reads, and folding it hides the message.
The richer first-line collapse (`TextFirstLine`) is a later refinement.

The turn/part *lists* are reactive (a `CellVector` thunk), so pushing a turn or a
part updates the layout without re-running `print_document` (streaming). The
`collapsed` state is read at print time.
"""
module ConversationToWidgetModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..DocumentModule: Document
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationTurn, ConversationPart, ConversationThinking
import ..EvaluatorModule: EvaluatorForm, eval_kind_label
# The badge on a part names the part's format, which the document itself
# answers; this file names no domain.
import ..NaturalNotationModule: get_natural_format
import ..WidgetModule: WidgetDocument, WidgetCard, WidgetLabel,
                       WidgetScrollPane, Point2D, Inset, inset_default
import ..LayoutModule: VerticalLayout, HorizontalLayout, LayoutConstraint, Fill, Content, Fixed
import ..TextModule: TextBlock, TextString
import ..StyleTextModule: StyleText
import ..FontModule: font_ubuntu_bold_14, font_ubuntu_bold_18,
                     font_dejavu_monospace_bold_20
import ..ColorModule: color_indigo_600, color_solarized_cyan, color_slate_600
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference,
                          FieldReferenceStep, RangeReferenceStep, get_reference_steps
import ..OperationModule: ToggleCollapseOperation, Operation, ReplaceSelectionOperation,
                          ReplaceReferencedValueOperation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..EventModule: MousePress
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..PrinterContextModule: make_child_context

export ConversationConversationToWidgetComposite,
       ConversationTurnToWidgetComposite,
       ConversationPartToWidget,
       ConversationToWidget

# ── Projection structs ──────────────────────────────────────────────────────

struct ConversationConversationToWidgetComposite <: Projection end
struct ConversationTurnToWidgetComposite         <: Projection end
struct ConversationPartToWidget                  <: Projection end

# ── Constants / glyphs ────────────────────────────────────────────────────────

# No card width. A turn card and a part card take the width they are offered —
# the transcript says `child_width = Fill` and the card resolves it — so a
# conversation is as wide as the pane holding it.
const _COLLAPSED_H   = 30   # clipped viewport height (≈ one row) when collapsed
const _GAP           = 8    # between the parts of one turn
# Between turns. A transcript is read by turn, so the eye needs the boundary to
# be louder than the one inside a turn. A gap says it; a border would say it
# again.
const _TURN_GAP      = 28
# Mirrors the WidgetCard padding configured in the WidgetToGraphics theme builder
# (the source of truth). Used to size a collapsed body's clip to the card's
# *interior* width so the clipped viewport never widens the card past its
# authored width.
const _CARD_PADDING  = 16

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
# it stays smaller and stays neutral.
const _KIND_STYLE = StyleText(font_ubuntu_bold_14, color_slate_600)

# The mark beside a role. It is drawn as text and not as a `WidgetAvatar`,
# because an avatar is a disc with initials: at this size the disc is a pale ring
# behind a letter that overflows it, and a letter is not an icon. The glyph
# stands on its own, in the role's own color.
#
# Both glyphs come from DejaVu, which the chrome font does not cover. Each was
# checked by rendering it at the size it is drawn at, twice over: the font has no
# fallback, so a glyph it lacks draws as an empty box — which is how `∴` was found
# and dropped from the thinking tag — and a glyph it draws as a thin OUTLINE
# disappears beside a bold word. `👤` and `✦` are both in the font and both are
# outlines; at 18 px they read as smudges. The pair below is solid at this size.
#
# Bold, because the word beside it is bold and a regular mark reads as a mistake.
const _ICON_FONT = font_dejavu_monospace_bold_20
_icon_style(role::Symbol) = StyleText(_ICON_FONT, _role_color(role))

# A face and a spark. Neither is a letter, and neither needs a legend.
#
# The spark is ONE mark and not the three of `✨`: a cluster's ink runs wider than
# the box the font advances by, so it ate the gap after it and sat against the
# word. A mark that fits its own advance keeps the row spaced the way the layout
# says.
_role_glyph(role::Symbol) = role === :user ? "☻" : role === :assistant ? "✱" : "●"

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

function _kind_label(content)
    content isa EvaluatorForm      && return eval_kind_label(content)
    content isa ConversationThinking && return "thinking"
    content isa TextBlock           && return "text"
    key = get_natural_format(typeof(content))
    key === nothing && return "doc"
    get(FORMAT_LABELS, key, String(key))
end

# ── Helpers ────────────────────────────────────────────────────────────────

# A header row: a role mark followed by the role, both in the role's color.
_role_header(role::Symbol) =
    HorizontalLayout(Any[
        WidgetLabel(Point2D(0, 0), _role_glyph(role); text_style = _icon_style(role)),
        WidgetLabel(Point2D(0, 0), String(role); text_style = _role_style(role)),
    ]; vertical_align = :center, gap = 10)

# A collapsed card shows one row of its body. Saying so is a constraint on the
# body's height; the card builds the viewport, because the card is what knows its
# own inner width and this does not.
_maybe_clip(body, collapsed::Bool) =
    collapsed ? LayoutConstraint(body; height = Fixed(_COLLAPSED_H)) : body

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
    ChildrenIoMap(projection, c, layout, ioms)
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
    # the header click still folds it and the collapse reader below still finds
    # the turn that a produced card came from.
    card = WidgetCard(Point2D(0, 0);
                      title = _role_header(t.role),
                      content = _maybe_clip(body, t.collapsed === true),
                      variant = t.role === :user ? :tinted : :plain)
    ChildrenIoMap(projection, t, card, ioms)
end

# ── print_document: part → the content, and a chrome only where it is earned ─
#
# A part used to be a card with a kind heading, whatever it held. Two things
# were wrong with that. A frame does not say WHAT a part is — it only separates,
# and the content already says what it is: prose looks like prose and code looks
# like code. And a heading that names the kind repeats what the reader can see:
# `¶ text` over the words `hi there` tells nobody anything.
#
# So the default is no chrome at all. Three kinds keep one, because each has
# something a frame does that whitespace cannot:
#
# - code, which must be told apart from the prose it sits between;
# - a thinking block, which is secondary and folds away;
# - an evaluation, which is two documents (a form and its result) and needs to
#   say where one ends.

function print_document(projection::ConversationPartToWidget,
                          recursion, part::ConversationPart, ctx)
    content = part.content
    collapsed = part.collapsed === true
    output = content isa EvaluatorForm        ? _eval_card(content, collapsed)     :
             content isa ConversationThinking ? _thinking_card(content, collapsed) :
             _is_code(content)                ? _code_card(content, collapsed)     :
             content
    SimpleIoMap(projection, part, output)
end

# A part's panel is MUTED and a turn's band is TINTED, because a part sits inside
# a turn: a code block in a user message would draw nothing if the two shared a
# color.
#
# A quiet tag: the one line a chromed part draws to name itself. No avatar — a
# glyph beside a word says the word twice.
_tag(label::AbstractString) =
    WidgetLabel(Point2D(0, 0), String(label); text_style = _KIND_STYLE)

# Code is separated from the prose around it, and its language named, because a
# panel cannot say which language it holds.
_code_card(content, collapsed::Bool) =
    WidgetCard(Point2D(0, 0);
               title = _tag(_kind_label(content)),
               content = _maybe_clip(content, collapsed),
               variant = :muted)

# Reasoning is secondary, so it folds. Its tag is the bare word, like every other
# tag: the `∴` it carried first drew as a missing-glyph box, because the chrome
# font holds no such character and the renderer falls back to nothing.
_thinking_card(t::ConversationThinking, collapsed::Bool) =
    WidgetCard(Point2D(0, 0);
               title = _tag("thinking"),
               content = _maybe_clip(_thinking_body(t), collapsed),
               variant = :muted)

_eval_card(ef::EvaluatorForm, collapsed::Bool) =
    WidgetCard(Point2D(0, 0);
               title = _tag(eval_kind_label(ef)),
               content = _maybe_clip(_eval_body(ef), collapsed),
               variant = :muted)

# An EvaluatorForm renders as its code over its result. The form (a
# JuliaDocument) and result (a TextBlock) are embedded directly as layout children
# so each is recursed through its own projection chain and **sizes to its
# content** — wrapping them in a fixed-height scroll pane would clip them to one
# row even when the part is expanded.
#
# The panel and the gap separate the two. A rule between them was tried and
# removed: a `WidgetSeparator` takes the width it is OFFERED, and no offer
# reaches it here — neither `child_width = Fill` on this layout nor a
# `LayoutConstraint` around the rule changed that — so it fell back to its own
# 200 px default and drew a stub that read as a mistake.
_eval_body(ef::EvaluatorForm) =
    VerticalLayout(Any[ef.form, ef.result]; gap = _GAP)

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
# able to point at a message and take a copy of it. So a click names the PART it
# landed in — `turns[i].parts[j]` — and the reader below declines every operation
# that would change what a turn says.
#
# Naming the part is a translation, and each level does its own step of it. The
# widget layer hands up a path in ITS domain,
# `children[i].content.children[j].content.…`, because a turn prints as a card in
# a layout and a part prints inside that card. Each level strips the steps it
# printed and delegates the rest to the child that printed them (School A: talk
# to the child IoMap, never re-walk the tree by type).
#
# It used to answer `EmptyReference()` at every level, which said "somewhere in
# me" and could not say where. Worse, an operation from below passed through
# untranslated, so a click in a text part put a WIDGET path — `children[2].
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
function _backward_level(iomap, reference, out_name::AbstractString,
                         in_name::AbstractString, skip::Int)
    steps = _steps(reference)
    steps === nothing && return EmptyReference()
    length(steps) >= skip || return EmptyReference()
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

# A part is the floor. Whatever was clicked inside it, what the selection names
# is the part — a transcript is read as messages, not as characters.
map_reference_backward(::ConversationPartToWidget, iomap, reference) = EmptyReference()
# And the floor going up: the part itself, wherever the caret is said to be
# inside it. A part with no chrome prints its content directly, so there is no
# step of this level's own to add.
map_reference_forward(::ConversationPartToWidget, iomap, reference) = EmptyReference()

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

# The WidgetCard header-click reader emits `ToggleCollapseOperation(card)` where
# `card` is the produced widget. Translate it back to the conversation domain
# node whose projection produced that card by walking the iomap tree.
function _find_collapse_target(iomap, target)
    iomap.output === target && return iomap.input
    if iomap isa ChildrenIoMap
        for entry in getfield(iomap, :child_iomaps)[]
            cim = entry isa Tuple ? entry[end] : entry
            node = _find_collapse_target(cim, target)
            node !== nothing && return node
        end
    end
    nothing
end

function read_intent(::ConversationConversationToWidgetComposite,
                         iomap, op::ToggleCollapseOperation)
    op.target === nothing && return op
    node = _find_collapse_target(iomap, op.target)
    node === nothing ? op : ToggleCollapseOperation(node)
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

end # module
