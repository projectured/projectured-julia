"""
    ConversationToWidgetModule

ConversationDocument → WidgetDocument projection. Stage-1 port to the uniform
turn/part model — a vertical stack:

    ConversationConversation → VerticalLayout of turn widgets
    ConversationTurn         → VerticalLayout[ role label, part widgets… ]
    ConversationPart         → the content wrapped for display (EvaluatorForm
                               rendered as code-over-result)

This keeps the reactive-thunk behavior (pushing a turn / part updates the
layout's children without re-running `projection_print`). The rich widget
chat-UI presentation (collapsible cards, icons) is the Stage-2 rewrite.
"""
module ConversationToWidgetModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ConversationModule: ConversationDocument, ConversationConversation,
                              ConversationTurn, ConversationPart
import ..EvaluatorModule: EvaluatorForm
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetComposite,
                       WidgetScrollPane, Point2D, Inset, inset_default
import ..LayoutModule: VerticalLayout
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap
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

# ── Helpers ────────────────────────────────────────────────────────────────

const _ITEM_VIEWPORT_H = 28

_recurse(recursion, doc, ctx) =
    (recursion !== nothing && doc isa ConversationDocument) ?
        projection_print(recursion, recursion, doc, ctx) :
        SimpleIoMap(nothing, doc, doc)

_label(text::AbstractString) = WidgetLabel(Point2D(0, 0), String(text))

_wrap_widget(w::WidgetDocument) = w
_wrap_widget(w::VerticalLayout) = w
_wrap_widget(x) = WidgetScrollPane(x;
                                   size=Point2D(800, _ITEM_VIEWPORT_H),
                                   padding=inset_default)

_text_widget(s::AbstractString) =
    WidgetScrollPane(TextText(TextString(String(s),
                                         font_ubuntu_monospace_regular_24,
                                         color_default));
                     size=Point2D(800, _ITEM_VIEWPORT_H),
                     padding=inset_default)

_compose(elements::Vector) = VerticalLayout(Any[_wrap_widget(e) for e in elements])

# Reactive vertical stack — recomputes its children when the source thunk's
# dependencies change (e.g. a turn pushed to the conversation, a part pushed
# to a turn), so the rendered stack updates without re-running projection_print.
function _reactive_compose(f::Function)
    children_cv = CellVector(() -> f())
    VerticalLayout(children_cv, Cell(:left), Cell(0), Cell(nothing))
end

_content_to_string(t::TextText) = begin
    io = IOBuffer()
    for span in t.elements
        hasproperty(span, :content) && print(io, span.content)
    end
    String(take!(io))
end
_content_to_string(d) = hasproperty(d, :name) ? String(d.name) : string(d)

# ── projection_print: conversation ───────────────────────────────────────────

function projection_print(::ConversationConversationToWidgetComposite,
                          recursion, c::ConversationConversation, ctx)
    rec, ref = recursion, ctx.reference
    composite = _reactive_compose(() -> begin
        turns = c.turns
        widgets = Any[]
        for i in eachindex(turns)
            child_ref = child_context(ctx, ref)
            iomap = _recurse(rec, turns[i], child_ref)
            push!(widgets, _wrap_widget(iomap.output))
        end
        widgets
    end)
    SimpleIoMap(nothing, c, composite)
end

# ── projection_print: turn ───────────────────────────────────────────────────

function projection_print(::ConversationTurnToWidgetComposite,
                          recursion, t::ConversationTurn, ctx)
    rec, ref = recursion, ctx.reference
    composite = _reactive_compose(() -> begin
        parts = t.parts
        widgets = Any[_label(string(t.role))]
        for i in eachindex(parts)
            child_ref = child_context(ctx, ref)
            iomap = _recurse(rec, parts[i], child_ref)
            push!(widgets, _wrap_widget(iomap.output))
        end
        widgets
    end)
    SimpleIoMap(nothing, t, composite)
end

# ── projection_print: part ───────────────────────────────────────────────────

function projection_print(::ConversationPartToWidget,
                          recursion, part::ConversationPart, ctx)
    content = part.content
    if content isa EvaluatorForm
        composite = _compose(Any[
            _text_widget("> " * _content_to_string(content.form)),
            _text_widget("= " * _content_to_string(content.result)),
        ])
        return SimpleIoMap(nothing, part, composite)
    end
    SimpleIoMap(nothing, part, _wrap_widget(content))
end

# ── Reference mapping / reader (v1: pass-through) ────────────────────────────

for P in (ConversationConversationToWidgetComposite,
          ConversationTurnToWidgetComposite,
          ConversationPartToWidget)
    @eval map_reference_forward(::$P, iomap, ref)  = nothing
    @eval map_reference_backward(::$P, iomap, ref) = nothing
    @eval projection_read(::$P, iomap, op) = op
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
