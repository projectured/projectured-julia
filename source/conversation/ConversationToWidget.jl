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
import ..WidgetModule: WidgetDocument, WidgetCard, WidgetAvatar, WidgetLabel,
                       WidgetScrollPane, WidgetSeparator, Point2D, Inset, inset_default
import ..LayoutModule: VerticalLayout, HorizontalLayout, LayoutConstraint, Fill, Content, Fixed
import ..TextModule: TextBlock, TextString
import ..StyleTextModule: StyleText
import ..FontModule: font_ubuntu_bold_14
import ..ColorModule: color_indigo_600, color_solarized_cyan, color_slate_600
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: EmptyReference
import ..OperationModule: ToggleCollapseOperation, Operation, ReplaceSelectionOperation
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
const _AVATAR_SIZE   = 16
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

# The role line is metadata, and the message is the content, so the role line
# renders SMALLER than the body it introduces. It was bold 22 — bigger than the
# words it labelled, which put the label above the message in the reading order
# and made a transcript read as a stack of headings. The role keeps its color,
# because color is what tells a person who spoke.
const _TITLE_FONT = font_ubuntu_bold_14
_role_style(role::Symbol) =
    StyleText(_TITLE_FONT, role === :user      ? color_indigo_600 :
                           role === :assistant ? color_solarized_cyan : color_slate_600)
const _KIND_STYLE = StyleText(_TITLE_FONT, color_slate_600)

_role_glyph(role::Symbol) = role === :user ? "U" : role === :assistant ? "A" : "?"

"""
    FORMAT_GLYPHS, FORMAT_LABELS, CODE_FORMATS

The decoration a part can carry, keyed by the format its document is written in.
A domain's insertion is a subtype of that domain's root, so one entry covers a
kind while it is typed and after it is committed.

`FORMAT_LABELS` holds the two formats whose key is an abbreviation of the
language's name; every other label is the key itself. `FORMAT_GLYPHS` is the
composer's, which marks the part it is editing.

`CODE_FORMATS` is the set of formats that read as code. A part in one of them
gets a panel, because code between two paragraphs of prose must be told from
them; a part in any other format gets none. The decoration and this judgement
belong to this package; the kinds do not, and a format that names itself in
neither table is prose as far as this file is concerned.
"""
const FORMAT_GLYPHS = Dict(:jl => "λ", :json => "{}", :xml => "<>", :md => "¶")
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

# A header row: a small avatar glyph followed by a styled title label.
_header(glyph::AbstractString, label::AbstractString, style::StyleText) =
    HorizontalLayout(Any[
        WidgetAvatar(Point2D(0, 0), String(glyph); size = _AVATAR_SIZE),
        WidgetLabel(Point2D(0, 0), String(label); text_style = style),
    ]; vertical_align = :center, gap = 8)

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
                      title = _header(_role_glyph(t.role), String(t.role), _role_style(t.role)),
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

# Reasoning is secondary, so it folds. It keeps its glyph, because "thinking" is
# a claim about the text and not a description of it.
_thinking_card(t::ConversationThinking, collapsed::Bool) =
    WidgetCard(Point2D(0, 0);
               title = _header("∴", "thinking", _KIND_STYLE),
               content = _maybe_clip(_thinking_body(t), collapsed),
               variant = :muted)

_eval_card(ef::EvaluatorForm, collapsed::Bool) =
    WidgetCard(Point2D(0, 0);
               title = _tag(eval_kind_label(ef)),
               content = _maybe_clip(_eval_body(ef), collapsed),
               variant = :muted)

# An EvaluatorForm renders as its code over its result, with a rule between them
# to say where the form ends. The form (a JuliaDocument) and result (a TextBlock)
# are embedded directly as layout children so each is recursed through its own
# projection chain and **sizes to its content** — wrapping them in a fixed-height
# scroll pane would clip them to one row even when the part is expanded. The rule
# takes the width it is offered, so it spans whatever the card gives it.
_eval_body(ef::EvaluatorForm) =
    VerticalLayout(Any[ef.form, WidgetSeparator(Point2D(0, 0)), ef.result]; gap = _GAP)

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

# Forward: nothing. A caret inside a transcript is not a thing yet — a turn is a
# record, and the one place a reader writes is the composer.
#
# Backward: the element itself. A click lands SOMEWHERE in a bubble, and what a
# bubble can honestly say is "in me". Answering `nothing` instead said "not
# mine", which is what left a conversation embedded in a document inert: the
# click found no owner, so the caret stayed wherever it was and every key went
# there. Whichever surround holds the conversation then re-roots this the way it
# re-roots any other selection.
for P in (ConversationConversationToWidgetComposite,
          ConversationTurnToWidgetComposite,
          ConversationPartToWidget)
    @eval map_reference_forward(::$P, iomap, ref)  = nothing
    @eval map_reference_backward(::$P, iomap, ref) = EmptyReference()
    # A click in a bubble puts the caret on the conversation, the way a click in
    # the composer puts it on the draft: a transcript takes the keyboard as a
    # whole, and whichever surround holds it decides what a key then means.
    @eval read_intent(::$P, iomap, ::MousePress) =
        ReplaceSelectionOperation(EmptyReference())
    # An operation from below passes; a raw gesture does not. Answering an event
    # would claim a gesture as if it were an intent, and the level above cannot
    # tell the two apart.
    @eval read_intent(::$P, iomap, op::Operation) = op
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
