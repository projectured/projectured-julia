"""
    ConversationToWidgetModule

ConversationDocument → WidgetDocument projection. Maps the conversation
document hierarchy into a vertical widget tree:

    ConversationConversation        → WidgetComposite of message widgets
    ConversationUserMessage         → WidgetComposite[label, body text]
    ConversationAssistantMessage    → WidgetComposite[label, block widgets...]
    ConversationCodeExecution       → WidgetComposite[label, code, result]
                                       — one projection for both user
                                         (ALT+ENTER) and AI (tool call) runs.

    ConversationTextBlock           → TextText (recursed)
    ConversationCodeBlock           → projected julia or monospace text
    ConversationHeadingBlock        → bold TextText
    ConversationListBlock           → WidgetComposite of bullet rows

The input editing surface lives on `WorkbenchAssistant` (not on the
conversation) and is handled by `WorkbenchAssistantToWidgetSplitPane`,
which stacks this conversation widget above the input row.
"""
module ConversationToWidgetModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationMessage,
                              ConversationUserMessage, ConversationAssistantMessage,
                              ConversationCodeExecution,
                              ConversationBlock,
                              ConversationTextBlock, ConversationCodeBlock,
                              ConversationHeadingBlock, ConversationListBlock
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetComposite,
                       WidgetScrollPane, Point2D, Inset, inset_default
import ..LayoutModule: VerticalLayout
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
import ..PrinterContextModule: child_context

export ConversationConversationToWidgetComposite,
       ConversationUserMessageToWidgetComposite,
       ConversationAssistantMessageToWidgetComposite,
       ConversationCodeExecutionToWidgetComposite,
       ConversationTextBlockToText,
       ConversationCodeBlockToWidget,
       ConversationHeadingBlockToText,
       ConversationListBlockToWidgetComposite,
       ConversationToWidget

# ── Projection structs ──────────────────────────────────────────────────────

struct ConversationConversationToWidgetComposite       <: Projection end
struct ConversationUserMessageToWidgetComposite        <: Projection end
struct ConversationAssistantMessageToWidgetComposite   <: Projection end
struct ConversationCodeExecutionToWidgetComposite      <: Projection end
struct ConversationTextBlockToText                     <: Projection end
struct ConversationCodeBlockToWidget                   <: Projection end
struct ConversationHeadingBlockToText                  <: Projection end
struct ConversationListBlockToWidgetComposite          <: Projection end

# ── Helpers ────────────────────────────────────────────────────────────────

# Fixed one-row viewport for scroll-paned non-widget content (see _wrap_widget).
# Sizing this viewport to its content is a separate §4 concern; the vertical
# *stacking* is now done by VerticalLayout from each child's intrinsic height,
# so no per-row pitch estimate is needed for the stack itself.
const _ITEM_VIEWPORT_H = 28

_recurse(recursion, doc, ctx) =
    (recursion !== nothing && doc isa ConversationDocument) ?
        projection_print(recursion, recursion, doc, ctx) :
        SimpleIoMap(nothing, doc, doc)

# WidgetLabel.content is rendered with `string(content)`, so pass a plain
# String, not a TextText (otherwise we'd see `TextText([TextString(...)])`).
_label(text::AbstractString) = WidgetLabel(Point2D(0, 0), String(text))

_wrap_widget(w::WidgetDocument) = w
_wrap_widget(w::VerticalLayout) = w   # a composed message/block stack passes through
# Non-widget content (TextText, JuliaDocument, etc.) is embedded in a
# WidgetScrollPane, which recurses its Document content through the outer
# projection chain. (WidgetText would stringify instead.) A small viewport
# keeps each item to one row.
_wrap_widget(x) = WidgetScrollPane(x;
                                   size=Point2D(800, _ITEM_VIEWPORT_H),
                                   padding=inset_default)

_text_widget(s::AbstractString) =
    WidgetScrollPane(TextText(TextString(String(s),
                                         font_ubuntu_monospace_regular_24,
                                         color_default));
                     size=Point2D(800, _ITEM_VIEWPORT_H),
                     padding=inset_default)

# Stack children vertically via VerticalLayout — each child's y comes from the
# intrinsic heights of the children before it, so there are no manual positions
# or row-height estimates (and no overlap/gap bugs when an item is tall).
_compose(elements::Vector) =
    VerticalLayout(Any[_wrap_widget(e) for e in elements])

# Reactive vertical stack — the inner CellVector recomputes its children each
# time the source thunk's dependencies change (e.g. a message pushed to the
# conversation), so the rendered scroll-back updates without re-running
# `projection_print`. `f` already returns wrapped widgets.
function _reactive_compose(f::Function)
    children_cv = CellVector(() -> f())
    # Direct inner-constructor call; the @document macro Cell-wraps the raw
    # CellVector so `children` ends up as `Cell{CellVector}`, matching the
    # layout of an eagerly-built VerticalLayout.
    VerticalLayout(children_cv, Cell(:left), Cell(0), Cell(nothing))
end

# ── projection_print: top-level conversation ────────────────────────────────
# The widget's elements list is wrapped in a CellVector thunk so that
# `push!(c.messages, …)` invalidates the inner cell and the next read of
# `composite.elements` re-projects every message. This is what makes the
# chat scroll-back update without re-running `projection_print`.

function projection_print(::ConversationConversationToWidgetComposite,
                          recursion, c::ConversationConversation, ctx)
    rec, ref = recursion, ctx.reference
    composite = _reactive_compose(() -> begin
        msgs = c.messages
        widgets = Any[]
        for i in eachindex(msgs)
            child_ref = child_context(ctx, @reference ^(ref).messages[i])
            iomap = _recurse(rec, msgs[i], child_ref)
            push!(widgets, _wrap_widget(iomap.output))
        end
        widgets
    end)
    SimpleIoMap(nothing, c, composite)
end

# ── projection_print: user message ──────────────────────────────────────────

function projection_print(::ConversationUserMessageToWidgetComposite,
                          recursion, m::ConversationUserMessage, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).text)
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
                          recursion, m::ConversationAssistantMessage, ctx)
    rec, ref = recursion, ctx.reference
    composite = _reactive_compose(() -> begin
        blocks = m.blocks
        widgets = Any[_label("assistant")]
        for i in eachindex(blocks)
            block_ref = child_context(ctx, @reference ^(ref).blocks[i])
            iomap = _recurse(rec, blocks[i], block_ref)
            push!(widgets, _wrap_widget(iomap.output))
        end
        widgets
    end)
    SimpleIoMap(nothing, m, composite)
end

# ── projection_print: code execution (user or AI) ──────────────────────────

function projection_print(::ConversationCodeExecutionToWidgetComposite,
                          recursion, m::ConversationCodeExecution, ctx)
    initiator = m.initiator === :assistant ? "assistant" : "user"
    result_label = m.is_error ? "$(initiator): error" : "$(initiator): julia"
    composite = _compose(Any[
        _label(result_label),
        _text_widget("> " * m.code),
        _text_widget("= " * m.result),
    ])
    SimpleIoMap(nothing, m, composite)
end

# ── projection_print: blocks ────────────────────────────────────────────────

function projection_print(::ConversationTextBlockToText,
                          recursion, b::ConversationTextBlock, ctx)
    text_ref = child_context(ctx, @reference ^(ctx.reference).text)
    inner = _recurse(recursion, b.text, text_ref)
    ContentIoMap(nothing, b, inner.output, inner)
end

function projection_print(::ConversationCodeBlockToWidget,
                          recursion, b::ConversationCodeBlock, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    inner = _recurse(recursion, b.body, body_ref)
    composite = _compose(Any[
        _label("code [$(b.language)]"),
        inner.output,
    ])
    ContentIoMap(nothing, b, composite, inner)
end

function projection_print(::ConversationHeadingBlockToText,
                          recursion, b::ConversationHeadingBlock, ctx)
    text_ref = child_context(ctx, @reference ^(ctx.reference).text)
    inner = _recurse(recursion, b.text, text_ref)
    composite = _compose(Any[
        _label("h$(b.level)"),
        inner.output,
    ])
    ContentIoMap(nothing, b, composite, inner)
end

function projection_print(::ConversationListBlockToWidgetComposite,
                          recursion, b::ConversationListBlock, ctx)
    item_iomaps = Any[]
    item_widgets = Any[]
    for i in eachindex(b.items)
        item = b.items[i]
        item_ref = child_context(ctx, @reference ^(ctx.reference).items[i])
        iomap = _recurse(recursion, item, item_ref)
        push!(item_iomaps, iomap)
        push!(item_widgets, iomap.output)
    end
    composite = _compose(item_widgets)
    ChildrenIoMap(nothing, b, composite, Cell(item_iomaps))
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

function map_reference_forward(::ConversationCodeExecutionToWidgetComposite, iomap, reference)
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

# ── map_reference_backward ──────────────────────────────────────────────────

map_reference_backward(::ConversationConversationToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationUserMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationAssistantMessageToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationCodeExecutionToWidgetComposite, iomap, ref) = nothing
map_reference_backward(::ConversationTextBlockToText, iomap, ref) = nothing
map_reference_backward(::ConversationCodeBlockToWidget, iomap, ref) = nothing
map_reference_backward(::ConversationHeadingBlockToText, iomap, ref) = nothing
map_reference_backward(::ConversationListBlockToWidgetComposite, iomap, ref) = nothing

# ── projection_read ─────────────────────────────────────────────────────────
# Default: pass operations through unchanged.

projection_read(::ConversationConversationToWidgetComposite, iomap, op) = op
projection_read(::ConversationUserMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationAssistantMessageToWidgetComposite, iomap, op) = op
projection_read(::ConversationCodeExecutionToWidgetComposite, iomap, op) = op
projection_read(::ConversationTextBlockToText, iomap, op) = op
projection_read(::ConversationCodeBlockToWidget, iomap, op) = op
projection_read(::ConversationHeadingBlockToText, iomap, op) = op
projection_read(::ConversationListBlockToWidgetComposite, iomap, op) = op

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
        ConversationCodeExecution       => ConversationCodeExecutionToWidgetComposite(),
        ConversationTextBlock           => ConversationTextBlockToText(),
        ConversationCodeBlock           => ConversationCodeBlockToWidget(),
        ConversationHeadingBlock        => ConversationHeadingBlockToText(),
        ConversationListBlock           => ConversationListBlockToWidgetComposite(),
    )
end

end # module
