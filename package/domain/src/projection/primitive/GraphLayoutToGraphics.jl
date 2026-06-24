"""
    GraphLayoutToGraphicsModule

GraphLayout → Graphics projection. Draws each `VertexLayout` as a node box (a
rounded `GraphicsRect` outline at `(x, y, w, h)`) with the vertex's projected
content canvas placed inside, and each `EdgeLayout` as a `GraphicsPolyline`
connector along its `route` (an end arrowhead when the edge is directed).
Edges are drawn first, nodes on top.

Selection: a path `vertex_layouts[i].vertex.content.…` routes into the i-th
node's content sub-pipeline (tutorial School A — peel the steps this projection
owns and delegate the tail through the stored child IO maps). The
`GraphToGraphLayout` stage above maps `vertices[i].content.…` ↔
`vertex_layouts[i].vertex.content.…`, so a selection into vertex content
round-trips through the whole graph pipeline. Edges are decorations in v1
(selectable later via the Phase 1 polyline hit-test).
"""
module GraphLayoutToGraphicsModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection, Change, as_change
import ..GraphLayoutModule: GraphLayout, VertexLayout, EdgeLayout
import ..GraphModule: GraphVertex, GraphEdge
import ..GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsPolyline, layout_none, hit_element_at
import ..ColorModule: color_default
import ..IoMapModule: ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference, EmptyReferencePath
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..MouseModule: MousePress

export GraphLayoutToGraphicsCanvas, GraphLayoutToGraphics, GraphToGraphics,
       GraphLayoutToGraphicsCanvasIoMap

# Node box visual style.
const _BORDER_W = 2
const _BORDER = (0x58, 0x6e, 0x75, 0xff)   # solarized base01
const _FILL   = (0xff, 0xff, 0xff, 0xff)   # faint translucent fill
const _RADIUS = 6
const _PAD    = 8
# Edge style.
const _EDGE = (0x58, 0x6e, 0x75, 0xff)
const _EDGE_W = 2
const _ARROW = 10

struct GraphLayoutToGraphicsCanvas <: Projection end

struct GraphLayoutToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell      # vector of (x, y, content_iomap) per vertex layout
end

function projection_print(p::GraphLayoutToGraphicsCanvas, recursion, layout::GraphLayout, ctx)
    reference = ctx.reference

    # Recurse each vertex's content into a canvas, tracking its placed origin.
    child_iomaps = Cell(() -> begin
        n = length(layout.vertex_layouts)
        entries = Any[]
        for i in 1:n
            vl = layout.vertex_layouts[i]
            if vl isa VertexLayout
                v = getfield(vl, :vertex)[]
                content = v isa GraphVertex ? getfield(v, :content)[] : nothing
                if content !== nothing
                    cref = @reference ^(reference).vertex_layouts[i].vertex.content
                    cim = projection_printer_recurse(recursion, content, child_context(ctx, cref))
                    push!(entries, (Int(vl.x), Int(vl.y), cim))
                else
                    push!(entries, (Int(vl.x), Int(vl.y), nothing))
                end
            else
                push!(entries, (0, 0, nothing))
            end
        end
        entries
    end)

    elements = CellVector(() -> begin
        result = Any[]
        # Edges first (behind the nodes).
        for i in 1:length(layout.edge_layouts)
            el = layout.edge_layouts[i]
            el isa EdgeLayout || continue
            route = el.route
            length(route) < 2 && continue
            e = getfield(el, :edge)[]
            directed = e isa GraphEdge ? e.directed : false
            push!(result, GraphicsPolyline(route, _EDGE...;
                width=_EDGE_W, end_arrow=directed, arrow_size=_ARROW))
        end
        # Node boxes + content on top.
        entries = child_iomaps[]
        for i in 1:length(layout.vertex_layouts)
            vl = layout.vertex_layouts[i]
            vl isa VertexLayout || continue
            x, y, w, h = Int(vl.x), Int(vl.y), Int(vl.w), Int(vl.h)
            bx, by = x - _PAD, y - _PAD
            bw, bh = w + 2*_PAD, h + 2*_PAD
            push!(result, GraphicsRect(bx, by, bw, bh,
                _FILL[1], _FILL[2], _FILL[3], _FILL[4], _RADIUS;
                border_width=_BORDER_W, border_color=_BORDER))
            entry = i <= length(entries) ? entries[i] : nothing
            if entry !== nothing && entry[3] !== nothing
                cim = entry[3]
                push!(result, GraphicsCanvas(x, y,
                    CellVector(Cell[Cell(cim.output)]), layout_none, true))
            end
        end
        result
    end)

    canvas = GraphicsCanvas(elements, layout_none)
    GraphLayoutToGraphicsCanvasIoMap(p, layout, canvas, child_iomaps)
end

# A GraphicsCanvas is not a selectable container, so we never forward a selection
# onto it here; the in-node cursor is forward-projected by the content's own
# sub-pipeline (the node-box selection band is drawn in place if added later).
function map_reference_forward(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, reference)
    @reference_case reference begin
        vertex_layouts[i].vertex.content.rest... => begin
            entries = iomap.child_iomaps[]
            (i < 1 || i > length(entries)) && return nothing
            entry = entries[i]
            (entry === nothing || entry[3] === nothing) && return nothing
            cim = entry[3]
            map_reference_forward(cim.projection, cim, rest)
        end
        _ => nothing
    end
end

function map_reference_backward(::GraphLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

# Route a left click into the node whose content box contains it. Coordinates are
# translated into the content canvas's local frame (mirrors TableToGraphics).
function projection_read(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    if event isa MousePress && event.button === :left
        op = _route_click(iomap, event)
        op === nothing || return op
        return nothing
    end
    # Coordless events (keyboard) go to whichever node content holds the cursor.
    _forward_to_selected(iomap, event)
end

function _route_click(iomap::GraphLayoutToGraphicsCanvasIoMap, g::MousePress)
    layout = iomap.input
    entries = iomap.child_iomaps[]
    for i in 1:length(layout.vertex_layouts)
        vl = layout.vertex_layouts[i]
        vl isa VertexLayout || continue
        x, y, w, h = Int(vl.x), Int(vl.y), Int(vl.w), Int(vl.h)
        (g.x >= x && g.x < x + w && g.y >= y && g.y < y + h) || continue
        entry = i <= length(entries) ? entries[i] : nothing
        (entry === nothing || entry[3] === nothing) && return nothing
        cim = entry[3]
        canvas = cim.output
        ox = canvas isa GraphicsCanvas ? Int(canvas.x) : 0
        oy = canvas isa GraphicsCanvas ? Int(canvas.y) : 0
        local_evt = MousePress(g.button, g.x - x - ox, g.y - y - oy, g.modifiers)
        op = projection_read(cim.projection, cim, local_evt)
        op isa ReplaceSelectionOperation || return nothing
        return ReplaceSelectionOperation(@reference vertex_layouts[i].vertex.content.^(op.path))
    end
    nothing
end

# Dispatch a coordless event to every node's content reader; the active node (the
# one whose content carries the cursor) answers. Mirrors TableToGraphics.
function _forward_to_selected(iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    entries = iomap.child_iomaps[]
    for i in 1:length(entries)
        entry = entries[i]
        (entry === nothing || entry[3] === nothing) && continue
        cim = entry[3]
        op = projection_read(cim.projection, cim, event)
        if op isa ReplaceSelectionOperation
            return ReplaceSelectionOperation(@reference vertex_layouts[i].vertex.content.^(op.path))
        end
    end
    nothing
end

"""
    GraphToGraphics(; engine=nothing)

Convenience pipeline straight to a `GraphicsCanvas` (no `TextToGraphics` step —
like `TableToGraphics`). Composes the two graph stages; the content `recursion`
is supplied by the enclosing `NestingProjection` in the example. Pass an engine
to override the default `FallbackLayoutEngine`.

This is provided as documentation of the intended composition; examples build the
chain explicitly so they can thread the content projection as the recursion.
"""
function GraphToGraphics end

end # module
