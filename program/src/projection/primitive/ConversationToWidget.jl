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
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetComposite, Point2D, Inset, inset_default
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference,
                          PositionReference, RangeReference, EmptyReferencePath,
                          FieldReference, append_reference
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

_recurse(recursion, doc, reference) =
    (recursion !== nothing && doc isa ConversationDocument) ?
        projection_print(recursion, doc, recursion, reference) :
        SimpleIoMap(nothing, doc, doc)

_label(text::AbstractString) =
    WidgetLabel(Point2D(0, 0), TextText(TextString(String(text))))

_wrap_widget(w::WidgetDocument) = w
_wrap_widget(x) = WidgetText(Point2D(0, 0), x)

_text_widget(s::AbstractString) =
    WidgetText(Point2D(0, 0),
               TextText(TextString(String(s), font_ubuntu_monospace_regular_24, color_default)))

_compose(elements::Vector) =
    WidgetComposite(Point2D(0, 0), Any[_wrap_widget(e) for e in elements]; padding=_PAD5)

# ── projection_print: top-level conversation ────────────────────────────────

function projection_print(::ConversationConversationToWidgetComposite,
                          c::ConversationConversation, recursion, reference)
    child_iomaps = Any[]
    widgets = Any[]
    for i in eachindex(c.messages)
        msg = c.messages[i]
        child_ref = append_reference(reference,
                                     FieldReference("messages"),
                                     ElementReference(i))
        iomap = _recurse(recursion, msg, child_ref)
        push!(child_iomaps, iomap)
        push!(widgets, iomap.output)
    end
    composite = _compose(widgets)
    ChildrenIoMap(nothing, c, composite, Cell(child_iomaps))
end

# ── projection_print: user message ──────────────────────────────────────────

function projection_print(::ConversationUserMessageToWidgetComposite,
                          m::ConversationUserMessage, recursion, reference)
    body_ref = append_reference(reference, FieldReference("text"))
    body_iomap = _recurse(recursion, m.text, body_ref)
    composite = _compose(Any[
        _label("user"),
        body_iomap.output,
    ])
    ContentIoMap(nothing, m, composite, body_iomap)
end

# ── projection_print: assistant message ─────────────────────────────────────

function projection_print(::ConversationAssistantMessageToWidgetComposite,
                          m::ConversationAssistantMessage, recursion, reference)
    block_iomaps = Any[]
    block_widgets = Any[]
    for i in eachindex(m.blocks)
        b = m.blocks[i]
        block_ref = append_reference(reference,
                                     FieldReference("blocks"),
                                     ElementReference(i))
        iomap = _recurse(recursion, b, block_ref)
        push!(block_iomaps, iomap)
        push!(block_widgets, iomap.output)
    end
    elements = Any[_label("assistant")]
    append!(elements, block_widgets)
    composite = _compose(elements)
    ChildrenIoMap(nothing, m, composite, Cell(block_iomaps))
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
    body_ref = append_reference(reference, FieldReference("content"))
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
    code_ref = append_reference(reference, FieldReference("code"))
    code_iomap = _recurse(recursion, m.code, code_ref)
    composite = _compose(Any[
        _label("julia input"),
        code_iomap.output,
    ])
    ContentIoMap(nothing, m, composite, code_iomap)
end

function projection_print(::ConversationJuliaResultMessageToWidgetComposite,
                          m::ConversationJuliaResultMessage, recursion, reference)
    body_ref = append_reference(reference, FieldReference("output"))
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
    text_ref = append_reference(reference, FieldReference("text"))
    inner = _recurse(recursion, b.text, text_ref)
    ContentIoMap(nothing, b, inner.output, inner)
end

function projection_print(::ConversationCodeBlockToWidget,
                          b::ConversationCodeBlock, recursion, reference)
    body_ref = append_reference(reference, FieldReference("body"))
    inner = _recurse(recursion, b.body, body_ref)
    composite = _compose(Any[
        _label("code [$(b.language)]"),
        inner.output,
    ])
    ContentIoMap(nothing, b, composite, inner)
end

function projection_print(::ConversationHeadingBlockToText,
                          b::ConversationHeadingBlock, recursion, reference)
    text_ref = append_reference(reference, FieldReference("text"))
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
        item_ref = append_reference(reference,
                                    FieldReference("items"),
                                    ElementReference(i))
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
