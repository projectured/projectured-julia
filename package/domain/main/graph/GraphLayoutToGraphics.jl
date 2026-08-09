"""
    GraphLayoutToGraphicsModule

GraphLayout → Graphics projection. Draws each `VertexLayout` as a node box (a
rounded `GraphicsRect` outline at `(x, y, w, h)`) with the vertex's projected
content canvas placed inside, and each `EdgeLayout` as a `GraphicsPolyline`
connector along its `route` (an end arrowhead when the edge is directed), with the
edge's optional `label` recursed to a canvas and centred on the route midpoint.
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

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..GraphLayoutModule: GraphLayout, VertexLayout, EdgeLayout
import ..GraphModule: GraphVertex, GraphEdge
import ..GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsPolyline, layout_none, hit_element_at
import ..ColorModule: color_default, StyleColor
import ..IoMapModule: ChildrenIoMap
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep, EmptyReference
import ..ReferenceModule: var"@reference", var"@reference_step"
import ..ReferenceModule: var"@reference_case"
import ..PrinterContextModule: make_child_context
import ..OperationModule: ReplaceSelectionOperation
import ..EventModule: MousePress

export GraphLayoutToGraphicsCanvas, GraphLayoutToGraphics, GraphToGraphics,
       GraphLayoutToGraphicsCanvasIoMap

# Node box visual style.
const _BORDER_W = 2
const _BORDER = StyleColor(0x58 / 255, 0x6e / 255, 0x75 / 255, 1.0)   # solarized base01
const _FILL   = StyleColor(1.0, 1.0, 1.0, 1.0)   # opaque white fill
const _RADIUS = 6
const _PAD    = 8
# Edge style.
const _EDGE = StyleColor(0x58 / 255, 0x6e / 255, 0x75 / 255, 1.0)
const _EDGE_W = 2
const _ARROW = 10
# Highlight style (`GraphLayout.highlight_vertex` / `highlight_edge`): a ring
# just outside the node's box, and a re-stroke over the edge's own line. Both
# are *extra* elements keyed on the highlight cells alone — never a change to a
# node's content or geometry, so a highlight move never re-runs the layout.
const _HIGHLIGHT = StyleColor(0xb5 / 255, 0x89 / 255, 0x00 / 255, 1.0)   # solarized yellow
const _HIGHLIGHT_W = 3
const _HIGHLIGHT_GAP = 3

# The point halfway along a polyline route by arc length — where an edge label
# sits. Falls back to the single point / origin for degenerate routes.
function _route_midpoint(route)
    n = length(route)
    n == 0 && return (0, 0)
    n == 1 && return (Int(route[1][1]), Int(route[1][2]))
    seglen(i) = hypot(route[i+1][1] - route[i][1], route[i+1][2] - route[i][2])
    half = sum(seglen(i) for i in 1:n-1) / 2
    acc = 0.0
    for i in 1:n-1
        s = seglen(i)
        if acc + s >= half
            t = s == 0 ? 0.0 : (half - acc) / s
            return (round(Int, route[i][1] + t * (route[i+1][1] - route[i][1])),
                    round(Int, route[i][2] + t * (route[i+1][2] - route[i][2])))
        end
        acc += s
    end
    (Int(route[n][1]), Int(route[n][2]))
end

struct GraphLayoutToGraphicsCanvas <: Projection end

@iomap struct GraphLayoutToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell      # vector of (x, y, content_iomap) per vertex layout
    node_elements::Cell     # index into `output.elements` of each vertex's box
end

function print_document(p::GraphLayoutToGraphicsCanvas, recursion, layout::GraphLayout, ctx)
    # Recurse each vertex's content into a canvas, tracking its placed origin.
    child_iomaps = ComputedCell(() -> begin
        n = length(layout.vertex_layouts)
        entries = Any[]
        for i in 1:n
            vl = layout.vertex_layouts[i]
            if vl isa VertexLayout
                v = getfield(vl, :vertex)[]
                content = v isa GraphVertex ? getfield(v, :content)[] : nothing
                if content !== nothing
                    cim = print_child(recursion, content, make_child_context(ctx, layout, (@reference_step vertex_layouts), (@reference_step [i]), (@reference_step vertex), (@reference_step content)))
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

    # Recurse each edge's optional label into a canvas. A decoration, like the
    # edges themselves — not selectable in v1, so no per-label iomap delegation.
    edge_label_iomaps = ComputedCell(() -> begin
        m = length(layout.edge_layouts)
        out = Any[]
        for i in 1:m
            el = layout.edge_layouts[i]
            e = el isa EdgeLayout ? getfield(el, :edge)[] : nothing
            label = e isa GraphEdge ? getfield(e, :label)[] : nothing
            if label !== nothing
                push!(out, print_child(recursion, label, make_child_context(ctx, layout, (@reference_step edge_layouts), (@reference_step [i]), (@reference_step edge), (@reference_step label))))
            else
                push!(out, nothing)
            end
        end
        out
    end)

    # The drawing, and where each vertex's box ended up in it. The two are built
    # together because the second is a fact about the first: element order
    # depends on how many edges and edge labels came before the nodes, and a
    # second pass that recomputed it would be the same code twice.
    drawn = ComputedCell(() -> begin
        result = Any[]
        # Read the highlights once per repaint. They are compared by identity
        # against the vertex/edge each layout holds.
        highlight_vertex = layout.highlight_vertex
        highlight_edge = layout.highlight_edge
        # Where each vertex's node box lands in `result` — the reference target
        # for "beside node i", which is what an annotation anchors to.
        node_at = Union{Int,Nothing}[nothing for _ in 1:length(layout.vertex_layouts)]
        # Edges first (behind the nodes), each with its optional label centred on
        # the route midpoint.
        labels = edge_label_iomaps[]
        for i in 1:length(layout.edge_layouts)
            el = layout.edge_layouts[i]
            el isa EdgeLayout || continue
            route = el.route
            length(route) < 2 && continue
            e = getfield(el, :edge)[]
            directed = e isa GraphEdge ? e.directed : false
            push!(result, GraphicsPolyline(route, _EDGE;
                width=_EDGE_W, end_arrow=directed, arrow_size=_ARROW))
            # The highlighted edge is re-stroked over its own line, keeping the
            # arrowhead it already drew.
            if highlight_edge !== nothing && e === highlight_edge
                push!(result, GraphicsPolyline(route, _HIGHLIGHT;
                    width=_HIGHLIGHT_W, end_arrow=directed, arrow_size=_ARROW))
            end
            lim = i <= length(labels) ? labels[i] : nothing
            if lim !== nothing
                lo = lim.output
                lw = lo isa GraphicsCanvas ? Int(lo.w) : 0
                lh = lo isa GraphicsCanvas ? Int(lo.h) : 0
                mx, my = _route_midpoint(route)
                push!(result, GraphicsCanvas(mx - lw ÷ 2, my - lh ÷ 2,
                    CellVector(Cell[Cell(lo)]), layout_none, true))
            end
        end
        # Node boxes + content on top.
        entries = child_iomaps[]
        for i in 1:length(layout.vertex_layouts)
            vl = layout.vertex_layouts[i]
            vl isa VertexLayout || continue
            x, y, w, h = Int(vl.x), Int(vl.y), Int(vl.w), Int(vl.h)
            bx, by = x - _PAD, y - _PAD
            bw, bh = w + 2*_PAD, h + 2*_PAD
            # The ring goes behind the box, inflated by the gap, so the box's
            # own opaque fill leaves only the ring's edge showing.
            v = getfield(vl, :vertex)[]
            if highlight_vertex !== nothing && v === highlight_vertex
                g = _HIGHLIGHT_GAP + _HIGHLIGHT_W
                push!(result, GraphicsRect(bx - g, by - g, bw + 2*g, bh + 2*g,
                    _HIGHLIGHT, _RADIUS + g))
            end
            push!(result, GraphicsRect(bx, by, bw, bh,
                _FILL, _RADIUS;
                border_width=_BORDER_W, border_color=_BORDER))
            node_at[i] = length(result)
            entry = i <= length(entries) ? entries[i] : nothing
            if entry !== nothing && entry[3] !== nothing
                cim = entry[3]
                push!(result, GraphicsCanvas(x, y,
                    CellVector(Cell[Cell(cim.output)]), layout_none, true))
            end
        end
        (result, node_at)
    end)

    elements = ComputedCellVector(() -> drawn[][1])
    node_elements = ComputedCell(() -> drawn[][2])

    # How much room the graph needs, read off the layout that placed it.
    #
    # Without this the canvas declares 0×0, and every container that asks a
    # child how much room it wants is told "none": an `AnchoredLayout` around a
    # graph then reports zero height, the vertical layout above it reserves
    # nothing, and the graph draws straight over whatever follows it. That is
    # the same wrong answer for four nodes as for four hundred, which is why
    # callers ended up ESTIMATING a height from the node count — a guess that
    # cannot tell a tall thin chain from a wide flat mesh.
    #
    # A cell rather than a number, because the layout is reactive and often
    # arrives late: a topology exists only once a run has built the network, so
    # the graph is empty when first drawn and gets its nodes afterwards. The
    # extent has to recompute when it does, or its container reserves room for
    # the empty version for the rest of the session.
    #
    # Read from the layout rather than by walking the drawn elements: the
    # placement is what decides the size, and measuring elements would need a
    # text-measuring function this stage has no business holding.
    extent = ComputedCell(function ()
        right = bottom = 0
        for vertex_layout in layout.vertex_layouts
            vertex_layout isa VertexLayout || continue
            # The node BOX is the vertex inflated by `_PAD` on every side, and a
            # highlight ring sits outside that — both are painted, so both count.
            margin = _PAD + _HIGHLIGHT_GAP + _HIGHLIGHT_W
            right  = max(right,  Int(vertex_layout.x) + Int(vertex_layout.w) + margin)
            bottom = max(bottom, Int(vertex_layout.y) + Int(vertex_layout.h) + margin)
        end
        # A route may bow outside every box it connects, and an edge label sits
        # on the route, so the waypoints count too.
        for edge_layout in layout.edge_layouts
            edge_layout isa EdgeLayout || continue
            for point in edge_layout.route
                right  = max(right,  Int(point[1]))
                bottom = max(bottom, Int(point[2]))
            end
        end
        (right, bottom)
    end)

    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            ComputedCell(() -> Int32(extent[][1])),
                            ComputedCell(() -> Int32(extent[][2])),
                            elements, layout_none, true, Cell(nothing))
    GraphLayoutToGraphicsCanvasIoMap(p, layout, canvas, child_iomaps, node_elements)
end

# A GraphicsCanvas is not a selectable container, so we never forward a selection
# onto it here; the in-node cursor is forward-projected by the content's own
# sub-pipeline (the node-box selection band is drawn in place if added later).
function map_reference_forward(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, reference)
    @reference_case reference begin
        # A whole vertex is its node box in the drawing. Nothing selects a
        # vertex — the cursor lives in its content — but something has to be
        # able to *point at* one: an annotation anchored beside a node asks the
        # projection where that node was drawn, and this is the answer.
        ::GraphLayout.vertex_layouts[i].vertex => begin
            indices = iomap.node_elements
            (i < 1 || i > length(indices)) && return nothing
            k = indices[i]
            k === nothing ? nothing : (@reference iomap.output elements[k])
        end
        ::GraphLayout.vertex_layouts[i].vertex.content.rest... => begin
            entries = iomap.child_iomaps
            (i < 1 || i > length(entries)) && return nothing
            entry = entries[i]
            (entry === nothing || entry[3] === nothing) && return nothing
            cim = entry[3]
            map_reference_forward(cim.projection, cim, rest)
        end
        __ => nothing
    end
end

function map_reference_backward(::GraphLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

# Route a left click into the node whose content box contains it. Coordinates are
# translated into the content canvas's local frame (mirrors TableToGraphics).
function read_intent(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, event)
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
    entries = iomap.child_iomaps
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
        op = read_intent(cim.projection, cim, local_evt)
        op isa ReplaceSelectionOperation || return nothing
        return ReplaceSelectionOperation(@reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex::GraphVertex.content.^(op.path))
    end
    nothing
end

# Dispatch a coordless event to every node's content reader; the active node (the
# one whose content carries the cursor) answers. Mirrors TableToGraphics.
function _forward_to_selected(iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    entries = iomap.child_iomaps
    for i in 1:length(entries)
        entry = entries[i]
        (entry === nothing || entry[3] === nothing) && continue
        cim = entry[3]
        op = read_intent(cim.projection, cim, event)
        if op isa ReplaceSelectionOperation
            return ReplaceSelectionOperation(@reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex::GraphVertex.content.^(op.path))
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
