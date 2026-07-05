"""
    TextToWidgetModule

Generic projection: `TextText` → `WidgetScrollPane`.

Wraps rendered text content in a scrollable widget container, providing
scroll, border, and padding support. This is a domain-agnostic step that
sits between `SyntaxToText` and the final graphics rendering:

    Domain → Syntax → Text → **Widget** (TextToWidget) → Graphics

The `WidgetScrollPaneToGraphicsCanvas` (inside `WidgetToGraphics`) handles
the actual scroll viewport rendering; it recurses into the scroll pane's
`content` field, which holds the original `TextText`, dispatching it to
`TextToGraphics` for layout.

Use `WidgetAndTextToGraphics` as the final pipeline step — it merges the
full `WidgetToGraphics` dispatch with `TextText => TextToGraphics` so the
recursive rendering handles both widget chrome and text content.
"""
module TextToWidgetModule

import ..CellModule: Cell
import ..ProjectionApiModule: print_document, read_intent,
                               map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText
import ..WidgetModule: WidgetScrollPane, Point2D, Inset, inset_default
import ..IoMapApiModule: IoMap
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation, ReplaceReferencedValueOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference
import ..FontModule: StyleFont
import ..ColorModule: StyleColor
import ..TextToGraphicsModule: TextToGraphics
import ..WidgetToGraphicsModule: WidgetToGraphics, WidgetTheme, widget_theme_slate_light
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..RecursiveProjectionModule: RecursiveProjection

export TextToWidget, TextToWidgetIoMap, WidgetAndTextToGraphics

# ── TextToWidget ─────────────────────────────────────────────────────────

struct TextToWidget <: Projection
    default_width::Int
    default_height::Int
    content_fill_color::Union{Nothing, StyleColor}
    border::Inset
    border_color::Union{Nothing, StyleColor}
    padding::Inset
    padding_color::Union{Nothing, StyleColor}
end
TextToWidget(; default_width::Int=800, default_height::Int=600,
               content_fill_color=nothing,
               border::Inset=inset_default, border_color=nothing,
               padding::Inset=inset_default, padding_color=nothing) =
    TextToWidget(default_width, default_height,
                 content_fill_color, border, border_color, padding, padding_color)

struct TextToWidgetIoMap <: IoMap
    projection::TextToWidget
    input::TextText
    output::WidgetScrollPane
end

# ── Printer ──────────────────────────────────────────────────────────────

function print_document(p::TextToWidget, recursion, input::TextText, ctx)
    scroll_pane = WidgetScrollPane(input;
        size=Point2D(p.default_width, p.default_height),
        content_fill_color=p.content_fill_color,
        border=p.border, border_color=p.border_color,
        padding=p.padding, padding_color=p.padding_color)
    iomap = TextToWidgetIoMap(p, input, scroll_pane)
    # Wire selection forward: TextText.selection → content.<sel> on the
    # scroll pane so the cursor position propagates through the widget.
    sel_cell = getfield(scroll_pane, :selection)
    sel_cell[] = Cell(() -> begin
        sel = input.selection
        sel === nothing && return nothing
        ConcreteReferencePath(Cell(FieldReference("content")), Cell(sel))
    end)
    iomap
end

# ── Reference mapping ────────────────────────────────────────────────────

function map_reference_forward(::TextToWidget, ::TextToWidgetIoMap, ref)
    ref === nothing && return nothing
    ConcreteReferencePath(Cell(FieldReference("content")), Cell(ref))
end

function map_reference_backward(::TextToWidget, ::TextToWidgetIoMap, ref)
    # The widget selection is canonical at rest: skip leading TypeReference
    # checkpoints before reading the `.content` step that wraps the text path.
    ref = ref
    ref isa ConcreteReferencePath || return nothing
    h = ref.head
    (h isa FieldReference && h.name == "content") || return nothing
    ref.tail
end

# ── Reader ───────────────────────────────────────────────────────────────

function read_intent(p::TextToWidget, iomap::TextToWidgetIoMap, op)
    if op isa ReplaceSelectionOperation
        new_path = map_reference_backward(p, iomap, op.path)
        return new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    elseif op isa ToggleCollapseOperation
        return op
    elseif op isa ReplaceReferencedValueOperation
        # Identity-rooted writes (e.g. the scroll-pane's scroll_position) target a
        # carried widget, not a path in this projection's domain — pass through.
        # A document-rooted one would need re-targeting, but none reach here.
        return op.document === nothing ? nothing : op
    elseif op isa ReplaceStringRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceStringRangeOperation(new_ref, op.replacement)
    end
    return nothing
end

# ── WidgetAndTextToGraphics ──────────────────────────────────────────────

"""
    WidgetAndTextToGraphics(font; measure, default_fg) -> RecursiveProjection

Build a recursive type-dispatching projection that renders both widget
documents (via `WidgetToGraphics`) and `TextText` (via `TextToGraphics`).
This is the standard final step after `TextToWidget` in the pipeline.
"""
function WidgetAndTextToGraphics(font::StyleFont; measure::Function,
                                  theme::WidgetTheme=widget_theme_slate_light(font=font))
    w2g = WidgetToGraphics(font; measure=measure, theme=theme)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextText => TextToGraphics(measure=measure)],
    )))
end

end # module
