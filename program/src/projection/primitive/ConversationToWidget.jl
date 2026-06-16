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
part updates the layout without re-running `projection_print` (streaming). The
`collapsed` state is read at print time.
"""
module ConversationToWidgetModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationTurn, ConversationPart
import ..EvaluatorModule: EvaluatorForm
import ..JuliaModule: JuliaDocument
import ..WidgetModule: WidgetDocument, WidgetCard, WidgetAvatar, WidgetLabel,
                       WidgetScrollPane, Point2D, Inset, inset_default
import ..LayoutModule: VerticalLayout, HorizontalLayout
import ..TextModule: TextText, TextString
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..OperationModule: ToggleCollapseOperation
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..PrinterContextModule: child_context

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

_role_glyph(role::Symbol) = role === :user ? "U" : role === :assistant ? "A" : "?"

function _kind_glyph(content)
    content isa EvaluatorForm && return "="
    content isa JuliaDocument && return "λ"
    content isa TextText      && return "¶"
    return "?"
end
function _kind_label(content)
    content isa EvaluatorForm && return "eval"
    content isa JuliaDocument && return "julia"
    content isa TextText      && return "text"
    return "doc"
end

# ── Helpers ────────────────────────────────────────────────────────────────

# A header row: a small avatar glyph followed by a label.
_header(glyph::AbstractString, label::AbstractString) =
    HorizontalLayout(Any[
        WidgetAvatar(Point2D(0, 0), String(glyph); size = _AVATAR_SIZE),
        WidgetLabel(Point2D(0, 0), String(label)),
    ]; vertical_align = :center, gap = 8)

# Collapse a body document by clipping it into a short scroll-pane viewport.
_maybe_clip(body, collapsed::Bool) =
    collapsed ? WidgetScrollPane(body; size = Point2D(_CARD_WIDTH, _COLLAPSED_H),
                                 padding = inset_default) : body

# ── projection_print: conversation → vertical list of turn cards ──────────────

function projection_print(::ConversationConversationToWidgetComposite,
                          recursion, c::ConversationConversation, ctx)
    rec, ref = recursion, ctx.reference
    # Cache the child turn iomaps (recomputed only when the turn list changes),
    # so the produced cards keep a stable identity that the toggle reader can
    # match against. The layout reads each iomap's `.output`.
    ioms = Cell(() -> Any[
        projection_print(rec, rec, c.turns[i], child_context(ctx, ref))
        for i in eachindex(c.turns)
    ])
    layout = VerticalLayout(CellVector(() -> Any[im.output for im in ioms[]]),
                            Cell(:left), Cell(_GAP), Cell(nothing))
    ChildrenIoMap(nothing, c, layout, ioms)
end

# ── projection_print: turn → card with avatar header + part stack ─────────────

function projection_print(::ConversationTurnToWidgetComposite,
                          recursion, t::ConversationTurn, ctx)
    rec, ref = recursion, ctx.reference
    ioms = Cell(() -> Any[
        projection_print(rec, rec, t.parts[i], child_context(ctx, ref))
        for i in eachindex(t.parts)
    ])
    body = VerticalLayout(CellVector(() -> Any[im.output for im in ioms[]]),
                          Cell(:left), Cell(_GAP), Cell(nothing))
    card = WidgetCard(Point2D(0, 0);
                      title = _header(_role_glyph(t.role), String(t.role)),
                      content = _maybe_clip(body, t.collapsed === true),
                      width = _CARD_WIDTH)
    ChildrenIoMap(nothing, t, card, ioms)
end

# ── projection_print: part → card with kind header + recursed content ─────────

function projection_print(::ConversationPartToWidget,
                          recursion, part::ConversationPart, ctx)
    rec, ref = recursion, ctx.reference
    content = part.content
    body = content isa EvaluatorForm ? _eval_body(content) : content
    card = WidgetCard(Point2D(0, 0);
                      title = _header(_kind_glyph(content), _kind_label(content)),
                      content = _maybe_clip(body, part.collapsed === true),
                      width = _PART_WIDTH)
    SimpleIoMap(nothing, part, card)
end

# An EvaluatorForm renders as its code over its result. The form (a
# JuliaDocument) and result (a TextText) are embedded directly as layout
# children so each is recursed through its own projection chain and **sizes to
# its content** — wrapping them in a fixed-height scroll pane would clip them to
# one row even when the part is expanded.
_eval_body(ef::EvaluatorForm) =
    VerticalLayout(Any[ef.form, ef.result]; gap = _GAP)

# ── Reference mapping / reader ───────────────────────────────────────────────

for P in (ConversationConversationToWidgetComposite,
          ConversationTurnToWidgetComposite,
          ConversationPartToWidget)
    @eval map_reference_forward(::$P, iomap, ref)  = nothing
    @eval map_reference_backward(::$P, iomap, ref) = nothing
    @eval projection_read(::$P, iomap, op) = op
end

# The WidgetCard header-click reader emits `ToggleCollapseOperation(card)` where
# `card` is the produced widget. Translate it back to the conversation domain
# node whose projection produced that card by walking the iomap tree.
function _find_collapse_target(iomap, target)
    iomap.output === target && return iomap.input
    if iomap isa ChildrenIoMap
        for entry in iomap.child_iomaps[]
            cim = entry isa Tuple ? entry[end] : entry
            node = _find_collapse_target(cim, target)
            node !== nothing && return node
        end
    end
    nothing
end

function projection_read(::ConversationConversationToWidgetComposite,
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
