"""
    ConversationToWidgetModule

ConversationDocument → WidgetDocument projection. Maps the conversation
document hierarchy into a vertical widget tree:

    ConversationConversation         → WidgetComposite of message widgets
    ConversationUserMessage          → WidgetComposite[label, body text]
    ConversationAssistantMessage     → WidgetComposite[label, block widgets...]
    ConversationToolUseMessage       → WidgetComposite[label, summary text]
    ConversationToolResultMessage    → WidgetComposite[label, body text]
    ConversationJuliaInputMessage    → WidgetComposite[label, projected julia]
    ConversationJuliaResultMessage   → WidgetComposite[label, body text]

    ConversationTextBlock            → TextText (recursed)
    ConversationCodeBlock            → projected julia or monospace text
    ConversationHeadingBlock         → bold TextText
    ConversationListBlock            → WidgetComposite of bullet rows
    ConversationToolUseBlock         → labeled summary TextText

The input editing surface lives on `WorkbenchAssistant` (not on the
conversation) and is handled by `WorkbenchAssistantToWidgetScrollPane`,
which stacks this conversation widget above the input row.
"""
module ConversationToWidgetModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationMessage,
                              ConversationUserMessage, ConversationAssistantMessage,
                              ConversationToolUseMessage, ConversationToolResultMessage,
                              ConversationJuliaInputMessage, ConversationJuliaResultMessage,
                              ConversationBlock,
                              ConversationTextBlock, ConversationCodeBlock,
                              ConversationHeadingBlock, ConversationListBlock,
                              ConversationToolUseBlock
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetComposite,
                       WidgetScrollPane, Point2D, Inset, inset_default
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference,
                          PositionReference, RangeReference, EmptyReferencePath,
                          FieldReference, append_reference
import ..ReferenceBuilderModule: var"@reference"
import ..TypeDispatchingModule: TypeDispatchingProjection

export ConversationConversationToWidgetComposite,
       ConversationUserMessageToWidgetComposite,
       ConversationAssistantMessageToWidgetComposite,
       ConversationToolUseMessageToWidgetComposite,
       ConversationToolResultMessageToWidgetComposite,
       ConversationJuliaInputMessageToWidgetComposite,
       ConversationJuliaResultMessageToWidgetComposite,
       ConversationTextBlockToText,
       ConversationCodeBlockToWidget,
       ConversationHeadingBlockToText,
       ConversationListBlockToWidgetComposite,
       ConversationToolUseBlockToText,
       ConversationToWidget

# ── Projection structs ──────────────────────────────────────────────────────

struct ConversationConversationToWidgetComposite       <: Projection end
struct ConversationUserMessageToWidgetComposite        <: Projection end
struct ConversationAssistantMessageToWidgetComposite   <: Projection end
struct ConversationToolUseMessageToWidgetComposite     <: Projection end
struct ConversationToolResultMessageToWidgetComposite  <: Projection end
struct ConversationJuliaInputMessageToWidgetComposite  <: Projection end
struct ConversationJuliaResultMessageToWidgetComposite <: Projection end
struct ConversationTextBlockToText                     <: Projection end
struct ConversationCodeBlockToWidget                   <: Projection end
struct ConversationHeadingBlockToText                  <: Projection end
struct ConversationListBlockToWidgetComposite          <: Projection end
struct ConversationToolUseBlockToText                  <: Projection end

# ── Helpers ────────────────────────────────────────────────────────────────

const _PAD5 = Inset(5, 5, 5, 5)
# Approximate vertical pitch for a one-line widget (label, scroll-paned text,
# nested message composite). WidgetComposite places every child at its own
# (cox, coy) offset — children stack only if each carries its own Y position.
const _ROW_H = 28

_recurse(recursion, doc, reference) =
    (recursion !== nothing && doc isa ConversationDocument) ?
        projection_print(recursion, doc, recursion, reference) :
        SimpleIoMap(nothing, doc, doc)

# WidgetLabel.content is rendered with `string(content)`, so pass a plain
# String, not a TextText (otherwise we'd see `TextText([TextString(...)])`).
_label(text::AbstractString) = WidgetLabel(Point2D(0, 0), String(text))

_wrap_widget(w::WidgetDocument) = w
# Non-widget content (TextText, JuliaDocument, etc.) is embedded in a
# WidgetScrollPane, which recurses its Document content through the outer
# projection chain. (WidgetText would stringify instead.) A small viewport
# keeps each item to one row.
_wrap_widget(x) = WidgetScrollPane(x;
                                   size=Point2D(800, _ROW_H),
                                   padding=inset_default)

_text_widget(s::AbstractString) =
    WidgetScrollPane(TextText(TextString(String(s),
                                         font_ubuntu_monospace_regular_24,
                                         color_default));
                     size=Point2D(800, _ROW_H),
                     padding=inset_default)

# Stack widgets vertically by setting each child's `position` to (0, y).
# `WidgetCompositeToGraphicsCanvas` places every child at the same (cox, coy);
# the child's own position is what produces the vertical offset.
function _set_position!(w::WidgetDocument, x::Int, y::Int)
    hasproperty(w, :position) && (w.position = Point2D(x, y))
    w
end
_set_position!(w, _x, _y) = w  # no-op for anything without a position field

# Approximate intrinsic height of a widget for vertical-stacking purposes.
# A `WidgetComposite` is itself a stack, so its height is the sum of its
# children's heights — recursive. Anything else is one row.
function _widget_height(w::WidgetComposite)
    h = 0
    for child in w.elements
        h += _widget_height(child)
    end
    max(h, _ROW_H)
end
_widget_height(w::WidgetScrollPane) =
    (sz = w.size; sz isa Point2D ? Int(sz.y[]) : _ROW_H)
_widget_height(_) = _ROW_H

function _stack_vertical!(widgets::Vector)
    y = 0
    for w in widgets
        _set_position!(w, 0, y)
        y += _widget_height(w)
    end
    widgets
end

_compose(elements::Vector) =
    WidgetComposite(Point2D(0, 0),
                    _stack_vertical!(Any[_wrap_widget(e) for e in elements]);
                    padding=_PAD5)

# Reactive composite — the inner CellVector recomputes its elements each
# time `cv.elements` is invalidated (i.e. whenever the source thunk's
# dependencies change). Used by the conversation/assistant projections so
# that pushing a message to the source CellVector lights up the renderer
# without re-running `projection_print`.
function _reactive_compose(f::Function)
    elements_cv = CellVector(() -> _stack_vertical!(f()))
    # Direct inner-constructor call; the @document macro wraps each raw
    # value in `Cell` so the `elements_cv` ends up as `Cell{CellVector}`,
    # matching the layout of an eagerly-built WidgetComposite.
    WidgetComposite(
        Point2D(0, 0),    # position
        elements_cv,      # elements (CellVector, will be Cell-wrapped)
        true,             # visible
        inset_default,    # margin
        nothing,          # margin_color
        inset_default,    # border
        nothing,          # border_color
        _PAD5,            # padding
        nothing,          # padding_color
        nothing,          # selection
    )
end

# ── projection_print: top-level conversation ────────────────────────────────
# The widget's elements list is wrapped in a CellVector thunk so that
# `push!(c.messages, …)` invalidates the inner cell and the next read of
# `composite.elements` re-projects every message. This is what makes the
# chat scroll-back update without re-running `projection_print`.

function projection_print(::ConversationConversationToWidgetComposite,
                          c::ConversationConversation, recursion, reference)
    rec, ref = recursion, reference
    composite = _reactive_compose(() -> begin
        msgs = c.messages
        widgets = Any[]
        for i in eachindex(msgs)
            child_ref = @reference ^(ref).messages[i]
            iomap = _recurse(rec, msgs[i], child_ref)
            push!(widgets, _wrap_widget(iomap.output))
        end
        widgets
    end)
    SimpleIoMap(nothing, c, composite)
end

# ── projection_print: user message ──────────────────────────────────────────

function projection_print(::ConversationUserMessageToWidgetComposite,
                          m::ConversationUserMessage, recursion, reference)
    body_ref = @reference ^(reference).text
    body_iomap = _recurse(recursion, m.text, body_ref)
    composite = _compose(Any[
        _label("user"),
        body_iomap.output,
    ])
    ContentIoMap(nothing, m, composite, body_iomap)
end

# ── projection_print: assistant message ─────────────────────────────────────
# Same reactive thunk pattern as the top-level conversation: pushing a
# block (e.g. as streaming deltas arrive in the real wiring, or the canned
# "Yes, sir!" in MVP) invalidates the cell and the next read re-projects.

function projection_print(::ConversationAssistantMessageToWidgetComposite,
                          m::ConversationAssistantMessage, recursion, reference)
    rec, ref = recursion, reference
    composite = _reactive_compose(() -> begin
        blocks = m.blocks
        widgets = Any[_label("assistant")]
        for i in eachindex(blocks)
            block_ref = @reference ^(ref).blocks[i]
            iomap = _recurse(rec, blocks[i], block_ref)
            push!(widgets, _wrap_widget(iomap.output))
        end
        widgets
    end)
    SimpleIoMap(nothing, m, composite)
end

# ── projection_print: tool messages ─────────────────────────────────────────

function projection_print(::ConversationToolUseMessageToWidgetComposite,
                          m::ConversationToolUseMessage, recursion, reference)
    summary = "tool_use $(m.name) [$(m.status)] $(m.id)"
    composite = _compose(Any[
        _label("tool use"),
        _text_widget(summary),
    ])
    SimpleIoMap(nothing, m, composite)
end

function projection_print(::ConversationToolResultMessageToWidgetComposite,
                          m::ConversationToolResultMessage, recursion, reference)
    body_ref = @reference ^(reference).content
    body_iomap = _recurse(recursion, m.content, body_ref)
    composite = _compose(Any[
        _label(m.is_error ? "tool result (error)" : "tool result"),
        body_iomap.output,
    ])
    ContentIoMap(nothing, m, composite, body_iomap)
end

# ── projection_print: julia messages ────────────────────────────────────────

function projection_print(::ConversationJuliaInputMessageToWidgetComposite,
                          m::ConversationJuliaInputMessage, recursion, reference)
    code_ref = @reference ^(reference).code
    code_iomap = _recurse(recursion, m.code, code_ref)
    composite = _compose(Any[
        _label("julia input"),
        code_iomap.output,
    ])
    ContentIoMap(nothing, m, composite, code_iomap)
end

function projection_print(::ConversationJuliaResultMessageToWidgetComposite,
                          m::ConversationJuliaResultMessage, recursion, reference)
    body_ref = @reference ^(reference).output
    body_iomap = _recurse(recursion, m.output, body_ref)
    composite = _compose(Any[
        _label(m.is_error ? "julia error" : "julia result"),
        body_iomap.output,
    ])
    ContentIoMap(nothing, m, composite, body_iomap)
end

# ── projection_print: blocks ────────────────────────────────────────────────

function projection_print(::ConversationTextBlockToText,
                          b::ConversationTextBlock, recursion, reference)
    text_ref = @reference ^(reference).text
    inner = _recurse(recursion, b.text, text_ref)
    ContentIoMap(nothing, b, inner.output, inner)
end

function projection_print(::ConversationCodeBlockToWidget,
                          b::ConversationCodeBlock, recursion, reference)
    body_ref = @reference ^(reference).body
    inner = _recurse(recursion, b.body, body_ref)
    composite = _compose(Any[
        _label("code [$(b.language)]"),
        inner.output,
    ])
    ContentIoMap(nothing, b, composite, inner)
end

function projection_print(::ConversationHeadingBlockToText,
                          b::ConversationHeadingBlock, recursion, reference)
    text_ref = @reference ^(reference).text
    inner = _recurse(recursion, b.text, text_ref)
    composite = _compose(Any[
        _label("h$(b.level)"),
        inner.output,
    ])
    ContentIoMap(nothing, b, composite, inner)
end

function projection_print(::ConversationListBlockToWidgetComposite,
                          b::ConversationListBlock, recursion, reference)
    item_iomaps = Any[]
    item_widgets = Any[]
    for i in eachindex(b.items)
        item = b.items[i]
        item_ref = @reference ^(reference).items[i]
        iomap = _recurse(recursion, item, item_ref)
        push!(item_iomaps, iomap)
        push!(item_widgets, iomap.output)
    end
    composite = _compose(item_widgets)
    ChildrenIoMap(nothing, b, composite, Cell(item_iomaps))
end

function projection_print(::ConversationToolUseBlockToText,
                          b::ConversationToolUseBlock, recursion, reference)
    summary = "tool_use $(b.name) $(b.id)"
    composite = _compose(Any[
        _label("tool use"),
        _text_widget(summary),
    ])
    SimpleIoMap(nothing, b, composite)
end

# ── map_reference_forward ───────────────────────────────────────────────────
# Selection forwarding is intentionally minimal in v1; the projections
# are structure-only and the inner iomap chains handle deep selections.

function map_reference_forward(::ConversationConversationToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationUserMessageToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationAssistantMessageToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationToolUseMessageToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationToolResultMessageToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationJuliaInputMessageToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationJuliaResultMessageToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationTextBlockToText, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationCodeBlockToWidget, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationHeadingBlockToText, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationListBlockToWidgetComposite, iomap, reference)
    return nothing
end

function map_reference_forward(::ConversationToolUseBlockToText, iomap, reference)
    return nothing
end

# ── map_reference_backward ──────────────────────────────────────────────────

map_reference_backward(::ConversationConversationToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationUserMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationAssistantMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationToolUseMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationToolResultMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationJuliaInputMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationJuliaResultMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationTextBlockToText, iomap, ref) = nothing
map_reference_backward(::ConversationCodeBlockToWidget, iomap, ref) = nothing
map_reference_backward(::ConversationHeadingBlockToText, iomap, ref) = nothing
map_reference_backward(::ConversationListBlockToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationToolUseBlockToText, iomap, ref) = nothing

# ── projection_read ─────────────────────────────────────────────────────────
# Default: pass operations through unchanged.

projection_read(::ConversationConversationToWidgetComposite, iomap, op) = op
projection_read(::ConversationUserMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationAssistantMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationToolUseMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationToolResultMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationJuliaInputMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationJuliaResultMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationTextBlockToText, iomap, op) = op
projection_read(::ConversationCodeBlockToWidget, iomap, op) = op
projection_read(::ConversationHeadingBlockToText, iomap, op) = op
projection_read(::ConversationListBlockToWidgetComposite, iomap, op) = op
projection_read(::ConversationToolUseBlockToText, iomap, op) = op

# ── Factory ─────────────────────────────────────────────────────────────────

"""
    ConversationToWidget()

Build a type-dispatching projection covering every concrete conversation
document type. Wrap in `RecursiveProjection` at the call site to enable
recursion into child messages and blocks.
"""
function ConversationToWidget()
    TypeDispatchingProjection(
        ConversationConversation        => ConversationConversationToWidgetComposite(),
        ConversationUserMessage         => ConversationUserMessageToWidgetComposite(),
        ConversationAssistantMessage    => ConversationAssistantMessageToWidgetComposite(),
        ConversationToolUseMessage      => ConversationToolUseMessageToWidgetComposite(),
        ConversationToolResultMessage   => ConversationToolResultMessageToWidgetComposite(),
        ConversationJuliaInputMessage   => ConversationJuliaInputMessageToWidgetComposite(),
        ConversationJuliaResultMessage  => ConversationJuliaResultMessageToWidgetComposite(),
        ConversationTextBlock           => ConversationTextBlockToText(),
        ConversationCodeBlock           => ConversationCodeBlockToWidget(),
        ConversationHeadingBlock        => ConversationHeadingBlockToText(),
        ConversationListBlock           => ConversationListBlockToWidgetComposite(),
        ConversationToolUseBlock        => ConversationToolUseBlockToText(),
    )
end

end # module
