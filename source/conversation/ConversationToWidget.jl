"""
    ConversationToWidgetModule

ConversationDocument → WidgetDocument projection — a vertical list of chat
bubbles:

    ConversationConversation → VerticalLayout of turn cards
    ConversationTurn         → WidgetCard: title = [avatar(role) + role label],
                               content = VerticalLayout of part widgets
    ConversationPart         → WidgetCard: title = [avatar(kind) + kind label],
                               content = the part's `content` document (recursed)

Both the turn and the part are independently collapsible: when `collapsed` is
set, the body is wrapped in a `WidgetScrollPane` clipped to a few lines (a
graphics-viewport clip). The richer first-line collapse (`TextFirstLine`) is a
later refinement.

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
                       WidgetScrollPane, Point2D, Inset, inset_default
import ..LayoutModule: VerticalLayout, HorizontalLayout
import ..TextModule: TextBlock, TextString
import ..StyleTextModule: StyleText
import ..FontModule: font_ubuntu_bold_22
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

const _CARD_WIDTH    = 760
const _PART_WIDTH    = 720
const _AVATAR_SIZE   = 22
const _COLLAPSED_H   = 30   # clipped viewport height (≈ one row) when collapsed
const _GAP           = 6
# Mirrors the WidgetCard padding configured in the WidgetToGraphics theme builder
# (the source of truth). Used to size a collapsed body's clip to the card's
# *interior* width so the clipped viewport never widens the card past its
# authored width.
const _CARD_PADDING  = 16

# Card titles render bigger and bolder than the body, in a distinct accent, so a
# turn's role and a part's kind read as headings rather than body text. Roles are
# color-coded (user vs assistant); every part kind shares one muted heading color.
const _TITLE_FONT = font_ubuntu_bold_22
_role_style(role::Symbol) =
    StyleText(_TITLE_FONT, role === :user      ? color_indigo_600 :
                           role === :assistant ? color_solarized_cyan : color_slate_600)
const _KIND_STYLE = StyleText(_TITLE_FONT, color_slate_600)

_role_glyph(role::Symbol) = role === :user ? "U" : role === :assistant ? "A" : "?"

"""
    FORMAT_GLYPHS, FORMAT_LABELS

The badge a part carries, keyed by the format its document is written in. A
domain's insertion is a subtype of that domain's root, so one entry covers a kind
while it is typed and after it is committed.

`FORMAT_LABELS` holds the two formats whose key is an abbreviation of the
language's name; every other label is the key itself. The decoration belongs to
this package; the kinds do not, and a format with no entry draws the generic
badge.
"""
const FORMAT_GLYPHS = Dict(:jl => "λ", :json => "{}", :xml => "<>", :md => "¶")
const FORMAT_LABELS = Dict(:jl => "julia", :md => "markdown")

function _kind_glyph(content)
    content isa EvaluatorForm      && return "="
    content isa ConversationThinking && return "∴"
    content isa TextBlock           && return "¶"
    key = get_natural_format(typeof(content))
    key === nothing && return "?"
    get(FORMAT_GLYPHS, key, "{}")
end
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

# Collapse a body document by clipping it into a short scroll-pane viewport,
# sized to the owning card's *interior* width (`width - 2·padding`). The scroll
# pane prefers the parent-allocated width in the live editor; this fallback width
# keeps an isolated/unallocated render from widening the card past `width`. Using
# the card's own width (not a hardcoded constant) is what stops a 720px part card
# from ballooning to the 760px turn width when collapsed.
_maybe_clip(body, collapsed::Bool, width::Integer) =
    collapsed ? WidgetScrollPane(body;
                                 size = Point2D(width - 2 * _CARD_PADDING, _COLLAPSED_H),
                                 padding = inset_default) : body

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
    layout = VerticalLayout(ComputedCellVector(() -> Any[im.output for im in ioms[]]),
                            Cell(:left), Cell(_GAP), Cell(nothing))
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
    body = VerticalLayout(ComputedCellVector(() -> Any[im.output for im in ioms[]]),
                          Cell(:left), Cell(_GAP), Cell(nothing))
    card = WidgetCard(Point2D(0, 0);
                      title = _header(_role_glyph(t.role), String(t.role), _role_style(t.role)),
                      content = _maybe_clip(body, t.collapsed === true, _CARD_WIDTH),
                      width = _CARD_WIDTH)
    ChildrenIoMap(projection, t, card, ioms)
end

# ── print_document: part → card with kind header + recursed content ─────────

function print_document(projection::ConversationPartToWidget,
                          recursion, part::ConversationPart, ctx)
    rec, ref = recursion, ctx.reference
    content = part.content
    body = content isa EvaluatorForm      ? _eval_body(content) :
           content isa ConversationThinking ? _thinking_body(content) :
           content
    card = WidgetCard(Point2D(0, 0);
                      title = _header(_kind_glyph(content), _kind_label(content), _KIND_STYLE),
                      content = _maybe_clip(body, part.collapsed === true, _PART_WIDTH),
                      width = _PART_WIDTH)
    SimpleIoMap(projection, part, card)
end

# An EvaluatorForm renders as its code over its result. The form (a
# JuliaDocument) and result (a TextBlock) are embedded directly as layout
# children so each is recursed through its own projection chain and **sizes to
# its content** — wrapping them in a fixed-height scroll pane would clip them to
# one row even when the part is expanded.
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
