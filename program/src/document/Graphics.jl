"""
    GraphicsModule

The graphics domain provides the final output stage before the SDL backend.
Elements are positioned, styled render primitives. The canvas is itself a
Document so the selection mechanism can descend into individual elements,
enabling mouse hit-testing and element-level selection in the reader.

The domain includes:
- **Render primitives**: `GraphicsText` (text rendering), `GraphicsRect` (filled rectangles)
- **Container types**: `GraphicsCanvas` (collection of graphics elements), `GraphicsViewport` (clipping viewport)
- **Hit testing**: `hit_element_at` for mouse hit detection

All fields are reactive Cells for automatic dependency tracking and incremental redraws.
"""
module GraphicsModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..FontModule: StyleFont
import ..ReferenceModule: Reference
export GraphicsDocument, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
       GraphicsInsertion, GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
       GraphicsPolyline, GraphicsSpline,
       GraphicsCanvas, GraphicsViewport, GraphicsImage,
       GraphicsFence, setfn!, hit_element_at,
       tessellate_spline, polyline_arrowhead, point_near_polyline,
       IGraphicsInsertion, IGraphicsText, IGraphicsRect, IGraphicsLine, IGraphicsCircle,
       IGraphicsPolyline, IGraphicsSpline,
       IGraphicsCanvas, IGraphicsViewport, IGraphicsImage,
       IGraphicsFence

abstract type GraphicsDocument <: Document end

@enum LayoutDirection layout_none layout_horizontal layout_vertical

# ── GraphicsInsertion ─────────────────────────────────────────────────────

@document struct GraphicsInsertion <: GraphicsDocument
    value::Any
    selection::Reference
end
GraphicsInsertion() = GraphicsInsertion(Cell(nothing), Cell(nothing))

# ── GraphicsText ───────────────────────────────────────────────────────

"""
    GraphicsText(text, x, y, font, r, g, b, a)

A reactive text element for rendering.
Each field is a `Cell`, so changes to any property are tracked
and can trigger incremental redraws.
"""
@document struct GraphicsText <: GraphicsDocument
    text::String
    x::Int32
    y::Int32
    font::StyleFont
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    selection::Reference
end

function GraphicsText(text::AbstractString, x::Integer, y::Integer,
                      font::StyleFont,
                      r::Integer=255, g::Integer=255, b::Integer=255, a::Integer=255)
    GraphicsText(Cell(text), Cell(Int32(x)), Cell(Int32(y)),
                 Cell(font),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(nothing))
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, t::GraphicsText)
    print(io, "GraphicsText(", repr(t.text),
          ", x=", t.x, ", y=", t.y,
          ", font=", repr(t.font),
          ", rgba=(", t.r, ",", t.g, ",", t.b, ",", t.a, "))")
end

"""
    GraphicsRect(x, y, w, h, r, g, b, a, radius=0;
                 radius_tl=radius, radius_tr=radius,
                 radius_br=radius, radius_bl=radius,
                 border_width=0, border_color=nothing)

A reactive filled rectangle for rendering (e.g. cursor lines, highlights).
Each corner has an independent radius in pixels (`0` means a square
corner). The positional `radius` is a shorthand that applies to all four
corners; per-corner keyword arguments override it.

An optional `border_width` (pixels) + `border_color` (an `(r,g,b,a)` tuple,
0–255) paints a rounded outline *inside* the rect, so a single primitive can
express the "rounded fill + 1px outline" idiom without stacking rects.
Each field is a `Cell`.
"""
@document struct GraphicsRect <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    radius_tl::Int32
    radius_tr::Int32
    radius_br::Int32
    radius_bl::Int32
    border_width::Int32
    border_r::UInt8
    border_g::UInt8
    border_b::UInt8
    border_a::UInt8
    selection::Reference
end

_norm_rgba(::Nothing) = (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
_norm_rgba(c::NTuple{4,<:Integer}) = (UInt8(c[1]), UInt8(c[2]), UInt8(c[3]), UInt8(c[4]))

function GraphicsRect(x::Integer, y::Integer, w::Integer, h::Integer,
                      r::Integer=255, g::Integer=255, b::Integer=255, a::Integer=255,
                      radius::Integer=0;
                      radius_tl::Integer=radius, radius_tr::Integer=radius,
                      radius_br::Integer=radius, radius_bl::Integer=radius,
                      border_width::Integer=0, border_color=nothing)
    br, bg, bb, ba = _norm_rgba(border_color)
    GraphicsRect(Cell(Int32(x)), Cell(Int32(y)), Cell(Int32(w)), Cell(Int32(h)),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(Int32(radius_tl)), Cell(Int32(radius_tr)),
                 Cell(Int32(radius_br)), Cell(Int32(radius_bl)),
                 Cell(Int32(border_width)),
                 Cell(br), Cell(bg), Cell(bb), Cell(ba),
                 Cell(nothing))
end

function Base.show(io::IO, r::GraphicsRect)
    print(io, "GraphicsRect(x=", r.x, ", y=", r.y,
          ", w=", r.w, ", h=", r.h,
          ", rgba=(", r.r, ",", r.g, ",", r.b, ",", r.a, ")",
          ", radius=(tl=", r.radius_tl, ",tr=", r.radius_tr,
          ",br=", r.radius_br, ",bl=", r.radius_bl, ")",
          ", border=(", r.border_width, ",rgba=(", r.border_r, ",", r.border_g,
          ",", r.border_b, ",", r.border_a, ")))")
end

# ── GraphicsLine ───────────────────────────────────────────────────────────

"""
    GraphicsLine(x1, y1, x2, y2, r, g, b, a; width=1)

A reactive straight line from `(x1,y1)` to `(x2,y2)` in color `(r,g,b,a)` with
the given stroke `width`. Axis-aligned lines (separators, rules) render as a
crisp filled span; diagonal lines render anti-aliased.
"""
@document struct GraphicsLine <: GraphicsDocument
    x1::Int32
    y1::Int32
    x2::Int32
    y2::Int32
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    width::Int32
    selection::Reference
end

function GraphicsLine(x1::Integer, y1::Integer, x2::Integer, y2::Integer,
                      r::Integer=0, g::Integer=0, b::Integer=0, a::Integer=255;
                      width::Integer=1)
    GraphicsLine(Cell(Int32(x1)), Cell(Int32(y1)), Cell(Int32(x2)), Cell(Int32(y2)),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(Int32(width)), Cell(nothing))
end

function Base.show(io::IO, l::GraphicsLine)
    print(io, "GraphicsLine((", l.x1, ",", l.y1, ")→(", l.x2, ",", l.y2, ")",
          ", rgba=(", l.r, ",", l.g, ",", l.b, ",", l.a, "), width=", l.width, ")")
end

# ── GraphicsCircle ─────────────────────────────────────────────────────────

"""
    GraphicsCircle(cx, cy, radius, r, g, b, a; border_width=0, border_color=nothing)

A reactive filled circle centered at `(cx,cy)`. Optional anti-aliased outline
via `border_width` + `border_color` (an `(r,g,b,a)` tuple). Used for avatars,
radio dots, switch knobs and slider thumbs.
"""
@document struct GraphicsCircle <: GraphicsDocument
    cx::Int32
    cy::Int32
    radius::Int32
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    border_width::Int32
    border_r::UInt8
    border_g::UInt8
    border_b::UInt8
    border_a::UInt8
    selection::Reference
end

function GraphicsCircle(cx::Integer, cy::Integer, radius::Integer,
                        r::Integer=0, g::Integer=0, b::Integer=0, a::Integer=255;
                        border_width::Integer=0, border_color=nothing)
    bor, bog, bob, boa = _norm_rgba(border_color)
    GraphicsCircle(Cell(Int32(cx)), Cell(Int32(cy)), Cell(Int32(radius)),
                   Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                   Cell(Int32(border_width)),
                   Cell(bor), Cell(bog), Cell(bob), Cell(boa),
                   Cell(nothing))
end

function Base.show(io::IO, c::GraphicsCircle)
    print(io, "GraphicsCircle(c=(", c.cx, ",", c.cy, "), r=", c.radius,
          ", rgba=(", c.r, ",", c.g, ",", c.b, ",", c.a, "))")
end

# ── GraphicsPolyline ─────────────────────────────────────────────────────

"""
    GraphicsPolyline(points, r, g, b, a; width=1, start_arrow=false, end_arrow=false, arrow_size=8)

A reactive connected sequence of straight segments through `points` (a
`Vector{Tuple{Int,Int}}` of absolute `(x, y)` pixels) in color `(r,g,b,a)` with
stroke `width`. This is the canonical edge primitive for a routed connector — a
libavoid-style polyline route. Optional filled-triangle arrowheads at the start
and/or end, sized `arrow_size` pixels, oriented along the adjacent segment.
"""
@document struct GraphicsPolyline <: GraphicsDocument
    points::Any            # Vector{Tuple{Int,Int}}
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    width::Int32
    start_arrow::Bool
    end_arrow::Bool
    arrow_size::Int32
    selection::Reference
end

function GraphicsPolyline(points::AbstractVector,
                          r::Integer=0, g::Integer=0, b::Integer=0, a::Integer=255;
                          width::Integer=1, start_arrow::Bool=false,
                          end_arrow::Bool=false, arrow_size::Integer=8)
    pts = Tuple{Int,Int}[(Int(p[1]), Int(p[2])) for p in points]
    GraphicsPolyline(Cell(pts),
                     Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                     Cell(Int32(width)), Cell(start_arrow), Cell(end_arrow),
                     Cell(Int32(arrow_size)), Cell(nothing))
end

function Base.show(io::IO, p::GraphicsPolyline)
    print(io, "GraphicsPolyline(n=", length(p.points),
          ", rgba=(", p.r, ",", p.g, ",", p.b, ",", p.a, "), width=", p.width,
          ", arrows=(", p.start_arrow, ",", p.end_arrow, "))")
end

# ── GraphicsSpline ───────────────────────────────────────────────────────

"""
    GraphicsSpline(points, r, g, b, a; kind=:catmullrom, width=1,
                   start_arrow=false, end_arrow=false, arrow_size=8, segments=12)

A reactive smooth curve through/along `points` (a `Vector{Tuple{Int,Int}}`).
`kind` is `:catmullrom` (curve passes through the points) or `:bezier` (the
points are control points of a cubic Bézier chain). Backends tessellate to a
polyline at render time via [`tessellate_spline`](@ref) (`segments` samples per
span), so curve quality is one shared knob. Arrowhead flags as on
`GraphicsPolyline`.
"""
@document struct GraphicsSpline <: GraphicsDocument
    points::Any            # Vector{Tuple{Int,Int}}
    kind::Symbol
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    width::Int32
    start_arrow::Bool
    end_arrow::Bool
    arrow_size::Int32
    segments::Int32
    selection::Reference
end

function GraphicsSpline(points::AbstractVector,
                        r::Integer=0, g::Integer=0, b::Integer=0, a::Integer=255;
                        kind::Symbol=:catmullrom, width::Integer=1,
                        start_arrow::Bool=false, end_arrow::Bool=false,
                        arrow_size::Integer=8, segments::Integer=12)
    pts = Tuple{Int,Int}[(Int(p[1]), Int(p[2])) for p in points]
    GraphicsSpline(Cell(pts), Cell(kind),
                   Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                   Cell(Int32(width)), Cell(start_arrow), Cell(end_arrow),
                   Cell(Int32(arrow_size)), Cell(Int32(segments)), Cell(nothing))
end

function Base.show(io::IO, s::GraphicsSpline)
    print(io, "GraphicsSpline(n=", length(s.points), ", kind=", s.kind,
          ", rgba=(", s.r, ",", s.g, ",", s.b, ",", s.a, "), width=", s.width, ")")
end

# ── Spline tessellation + arrowheads (shared by every backend) ────────────

"""
    tessellate_spline(points, kind, segments) -> Vector{Tuple{Float64,Float64}}

Sample a spline of `kind` (`:catmullrom` | `:bezier`) through/along `points`
(a vector of `(x, y)`) into a flat polyline of `(x, y)` floats, `segments`
samples per span. Fewer than two points returns the points unchanged. This is
the single tessellation path every backend (SDL/Web/PDF) uses, so curve quality
is controlled in one place.
"""
function tessellate_spline(points::AbstractVector, kind::Symbol, segments::Integer)
    n = length(points)
    n < 2 && return [(Float64(p[1]), Float64(p[2])) for p in points]
    seg = max(1, Int(segments))
    pts = [(Float64(p[1]), Float64(p[2])) for p in points]
    out = Tuple{Float64,Float64}[]
    if kind === :bezier
        # Cubic Bézier chain: consume points in groups of 3 after the first
        # anchor (p0, c1, c2, p1, c1, c2, p1, ...). A trailing partial group
        # degrades to a straight segment.
        i = 1
        push!(out, pts[1])
        while i + 3 <= n
            p0 = pts[i]; c1 = pts[i+1]; c2 = pts[i+2]; p1 = pts[i+3]
            for s in 1:seg
                t = s / seg
                mt = 1 - t
                x = mt^3*p0[1] + 3mt^2*t*c1[1] + 3mt*t^2*c2[1] + t^3*p1[1]
                y = mt^3*p0[2] + 3mt^2*t*c1[2] + 3mt*t^2*c2[2] + t^3*p1[2]
                push!(out, (x, y))
            end
            i += 3
        end
        # Any leftover points: connect straight.
        while i < n
            push!(out, pts[i+1]); i += 1
        end
    else
        # Catmull-Rom: the curve passes through every input point.
        for k in 1:(n-1)
            p0 = pts[max(1, k-1)]
            p1 = pts[k]
            p2 = pts[k+1]
            p3 = pts[min(n, k+2)]
            k == 1 && push!(out, p1)
            for s in 1:seg
                t = s / seg
                t2 = t*t; t3 = t2*t
                x = 0.5*((2p1[1]) + (-p0[1]+p2[1])*t +
                         (2p0[1]-5p1[1]+4p2[1]-p3[1])*t2 +
                         (-p0[1]+3p1[1]-3p2[1]+p3[1])*t3)
                y = 0.5*((2p1[2]) + (-p0[2]+p2[2])*t +
                         (2p0[2]-5p1[2]+4p2[2]-p3[2])*t2 +
                         (-p0[2]+3p1[2]-3p2[2]+p3[2])*t3)
                push!(out, (x, y))
            end
        end
    end
    out
end

"""
    polyline_arrowhead(points, size; at_end=true) -> Vector{Tuple{Float64,Float64}}

The three vertices of a filled triangle arrowhead of `size` pixels at the end
(`at_end=true`) or start of the polyline `points`, oriented along the adjacent
segment. Returns an empty vector when there is no segment to orient along.
"""
function polyline_arrowhead(points::AbstractVector, size::Real; at_end::Bool=true)
    n = length(points)
    n < 2 && return Tuple{Float64,Float64}[]
    if at_end
        tip = (Float64(points[n][1]), Float64(points[n][2]))
        prev = (Float64(points[n-1][1]), Float64(points[n-1][2]))
    else
        tip = (Float64(points[1][1]), Float64(points[1][2]))
        prev = (Float64(points[2][1]), Float64(points[2][2]))
    end
    dx = tip[1] - prev[1]; dy = tip[2] - prev[2]
    len = sqrt(dx*dx + dy*dy)
    len == 0 && return Tuple{Float64,Float64}[]
    ux = dx/len; uy = dy/len            # unit toward the tip
    px = -uy; py = ux                   # perpendicular
    sz = Float64(size)
    bx = tip[1] - ux*sz; by = tip[2] - uy*sz   # base center, `sz` back from the tip
    half = sz*0.5
    [tip, (bx + px*half, by + py*half), (bx - px*half, by - py*half)]
end

# ── Canvas ───────────────────────────────────────────────────────────────

"""
    GraphicsCanvas(elements[, layout[, overlapping_elements]])

A reactive container holding a list of graphics elements to render.
The `elements` field is a `Cell` wrapping a `CollectionDocument`
(`CellVector` or `ListNode`). The `layout` field declares the axis
along which the canvas may extend infinitely, enabling the renderer
to stop painting when elements are past the viewport edge.

When `overlapping_elements` is `false`, elements are guaranteed not to
overlap along the layout axis. This enables the renderer and hit-testing
to stop early once past the viewport or click point.
"""
@document struct GraphicsCanvas <: GraphicsDocument
    x::Int
    y::Int
    w::Int
    h::Int
    elements::CollectionDocument
    layout::LayoutDirection
    overlapping_elements::Bool
    selection::Reference
end

GraphicsCanvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), CellVector(), layout_none, true, Cell(nothing))
GraphicsCanvas(elems::Vector) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), CellVector(Cell[Cell(e) for e in elems]), layout_none, true, Cell(nothing))
GraphicsCanvas(elems::CollectionDocument, layout::LayoutDirection) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), elems, layout, true, Cell(nothing))
GraphicsCanvas(elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), elems, layout, overlapping, Cell(nothing))
GraphicsCanvas(x::Integer, y::Integer, elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(x), Int32(y), Int32(0), Int32(0), elems, layout, overlapping, Cell(nothing))
GraphicsCanvas(x::Integer, y::Integer, w::Integer, h::Integer, elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h), elems, layout, overlapping, Cell(nothing))

# ── Viewport ─────────────────────────────────────────────────────────────

"""
    GraphicsViewport(x, y, w, h, content)

A clipping viewport: renders `content` (a `GraphicsCanvas` whose element
coordinates are relative to the viewport origin, with any scroll offset
already applied) and clips the output to the rectangle `(x, y, w, h)`.
"""
@document struct GraphicsViewport <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    content::GraphicsCanvas
    selection::Reference
end

function GraphicsViewport(x::Integer, y::Integer, w::Integer, h::Integer,
                          content::GraphicsCanvas)
    GraphicsViewport(Cell(Int32(x)), Cell(Int32(y)),
                     Cell(Int32(w)), Cell(Int32(h)),
                     Cell(content),
                     Cell(nothing))
end

function Base.show(io::IO, v::GraphicsViewport)
    print(io, "GraphicsViewport(x=", v.x, ", y=", v.y,
          ", w=", v.w, ", h=", v.h, ")")
end

# ── Image (cached rasterized canvas) ─────────────────────────────────────

@document struct GraphicsImage <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    data::Any
    selection::Reference
end

function GraphicsImage(x::Integer, y::Integer, w::Integer, h::Integer, data)
    GraphicsImage(Cell(Int32(x)), Cell(Int32(y)),
                  Cell(Int32(w)), Cell(Int32(h)),
                  Cell(data),
                  Cell(nothing))
end

function Base.show(io::IO, img::GraphicsImage)
    print(io, "GraphicsImage(x=", img.x, ", y=", img.y,
          ", w=", img.w, ", h=", img.h, ")")
end

# ── Fence ──────────────────────────────────────────────────────────────────

"""
    GraphicsFence()

A barrier element placed inside a `GraphicsCanvas`'s element list.
It guarantees that elements before and after the fence do not overlap
along the canvas's layout axis. The fence is always perpendicular to
the canvas's `layout` direction. It carries no visual representation
and is skipped during rendering and hit-testing.
"""
@document struct GraphicsFence <: GraphicsDocument
    selection::Reference
end

GraphicsFence() = GraphicsFence(Cell(nothing))

# ── Hit testing ─────────────────────────────────────────────────────────────

function _rect_hit(elem::GraphicsRect, cx::Int, cy::Int)
    x, y, w, h = Int(elem.x), Int(elem.y), Int(elem.w), Int(elem.h)
    cx >= x && cx < x + w && cy >= y && cy < y + h
end

# Squared distance from point (px,py) to segment (ax,ay)-(bx,by).
function _dist2_point_segment(px, py, ax, ay, bx, by)
    dx = bx - ax; dy = by - ay
    if dx == 0 && dy == 0
        return (px - ax)^2 + (py - ay)^2
    end
    t = ((px - ax)*dx + (py - ay)*dy) / (dx*dx + dy*dy)
    t = clamp(t, 0.0, 1.0)
    qx = ax + t*dx; qy = ay + t*dy
    (px - qx)^2 + (py - qy)^2
end

"""
    point_near_polyline(points, x, y, tolerance) -> Bool

True when `(x, y)` is within `tolerance` pixels of any segment of the polyline
`points` (a vector of `(x, y)`). Used for edge hit-testing.
"""
function point_near_polyline(points::AbstractVector, x::Real, y::Real, tolerance::Real)
    n = length(points)
    n == 0 && return false
    n == 1 && return (x - points[1][1])^2 + (y - points[1][2])^2 <= tolerance^2
    tol2 = Float64(tolerance)^2
    for i in 1:(n-1)
        a = points[i]; b = points[i+1]
        _dist2_point_segment(Float64(x), Float64(y),
                             Float64(a[1]), Float64(a[2]),
                             Float64(b[1]), Float64(b[2])) <= tol2 && return true
    end
    false
end

"""
    hit_element_at(canvas::GraphicsCanvas, x::Int, y::Int) -> Int or nothing

Returns the 1-based index of the first element in `canvas` whose bounding area
contains `(x, y)`, or `nothing` if no element matches.
Supports `GraphicsViewport` (rectangle bounds), `GraphicsRect` (rectangle
bounds), and `GraphicsText` (vertical font-size band).
Skips `GraphicsFence` elements. For `ListNode`-backed canvases with a layout
direction, stops early when the element position exceeds the click coordinate
along the layout axis.
"""
function hit_element_at(canvas::GraphicsCanvas, x::Int, y::Int)
    layout = canvas.layout
    elements = canvas.elements
    early_stop = !canvas.overlapping_elements && layout != layout_none
    if elements isa ListNode
        # Check prev-direction elements (negative offsets)
        prev_node = elements.prev
        pi = 0
        while prev_node !== nothing
            pi -= 1
            elem = prev_node.value
            if elem isa GraphicsFence
                prev_node = prev_node.prev
                continue
            end
            if early_stop
                if layout == layout_vertical
                    ey = _elem_y(elem)
                    ey !== nothing && ey < y && break
                elseif layout == layout_horizontal
                    ex = _elem_x(elem)
                    ex !== nothing && ex < x && break
                end
            end
            hit = _hit_test_element(elem, x, y)
            hit && return pi
            prev_node = prev_node.prev
        end
        # Check forward-direction elements
        i = 0
        node = elements
        while node !== nothing
            i += 1
            elem = node.value
            if elem isa GraphicsFence
                node = node.next
                continue
            end
            if early_stop
                if layout == layout_vertical
                    ey = _elem_y(elem)
                    ey !== nothing && ey > y && return nothing
                elseif layout == layout_horizontal
                    ex = _elem_x(elem)
                    ex !== nothing && ex > x && return nothing
                end
            end
            hit = _hit_test_element(elem, x, y)
            hit && return i - 1
            node = node.next
        end
    else
        for (i, elem) in enumerate(elements)
            elem isa GraphicsFence && continue
            if early_stop
                if layout == layout_vertical
                    ey = _elem_y(elem)
                    ey !== nothing && ey > y && return nothing
                elseif layout == layout_horizontal
                    ex = _elem_x(elem)
                    ex !== nothing && ex > x && return nothing
                end
            end
            hit = _hit_test_element(elem, x, y)
            hit && return i - 1
        end
    end
    nothing
end

function _hit_test_element(elem, x::Int, y::Int)
    if elem isa GraphicsViewport
        vx, vy = Int(elem.x), Int(elem.y)
        vw, vh = Int(elem.w), Int(elem.h)
        x >= vx && x < vx + vw && y >= vy && y < vy + vh
    elseif elem isa GraphicsRect
        _rect_hit(elem, x, y)
    elseif elem isa GraphicsText
        ex, ey = Int(elem.x), Int(elem.y)
        fs = elem.font.size
        x >= ex && y >= ey && y < ey + fs
    elseif elem isa GraphicsCircle
        dx, dy = x - Int(elem.cx), y - Int(elem.cy)
        rad = Int(elem.radius)
        dx * dx + dy * dy <= rad * rad
    elseif elem isa GraphicsLine
        lx = min(Int(elem.x1), Int(elem.x2)); ly = min(Int(elem.y1), Int(elem.y2))
        lw = abs(Int(elem.x2) - Int(elem.x1)); lh = abs(Int(elem.y2) - Int(elem.y1))
        hw = max(1, Int(elem.width))
        x >= lx - hw && x <= lx + lw + hw && y >= ly - hw && y <= ly + lh + hw
    elseif elem isa GraphicsPolyline
        point_near_polyline(elem.points, x, y, max(3, Int(elem.width) + 2))
    elseif elem isa GraphicsSpline
        pts = tessellate_spline(elem.points, elem.kind, elem.segments)
        point_near_polyline(pts, x, y, max(3, Int(elem.width) + 2))
    elseif elem isa GraphicsCanvas
        # Delegate hit test into the nested canvas (coordinates relative to canvas origin)
        cx, cy = Int(elem.x), Int(elem.y)
        hit_element_at(elem, x - cx, y - cy) !== nothing
    else
        false
    end
end

_elem_x(elem) = hasproperty(elem, :x) ? Int(elem.x) : nothing
_elem_y(elem) = hasproperty(elem, :y) ? Int(elem.y) : nothing

# ── Content bounds ──────────────────────────────────────────────────────
#
# Compute the axis-aligned bounding box, in absolute pixels, of everything a
# canvas would draw. Offsets accumulate through nested canvases exactly as the
# backend renders them, so the result is the natural extent of the laid-out
# content. Used to size an output (image/PDF) to the content when no explicit
# width/height is requested. `measure(text, font)` returns the pixel
# `(width, height)` of a text element — supplied by the caller so this stays
# free of any backend (SDL, PDF) dependency.

function _canvas_content_bounds(canvas::GraphicsCanvas, measure)
    minx = Ref(typemax(Int)); miny = Ref(typemax(Int))
    maxx = Ref(typemin(Int)); maxy = Ref(typemin(Int))
    _accumulate_bounds!(canvas, 0, 0, measure, minx, miny, maxx, maxy)
    maxx[] == typemin(Int) && return (0, 0, 0, 0)   # empty canvas
    (minx[], miny[], maxx[], maxy[])
end

function _accumulate_bounds!(canvas::GraphicsCanvas, ox::Int, oy::Int, measure,
                             minx, miny, maxx, maxy)
    for elem in canvas.elements
        _bounds_elem!(elem, ox, oy, measure, minx, miny, maxx, maxy)
    end
end

function _bounds_extend!(minx, miny, maxx, maxy, x0::Int, y0::Int, x1::Int, y1::Int)
    minx[] = min(minx[], x0); miny[] = min(miny[], y0)
    maxx[] = max(maxx[], x1); maxy[] = max(maxy[], y1)
    nothing
end

function _bounds_elem!(elem, ox::Int, oy::Int, measure, minx, miny, maxx, maxy)
    if elem isa GraphicsText
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        w, _ = measure(elem.text, elem.font)
        h = elem.font.size
        _bounds_extend!(minx, miny, maxx, maxy, x, y, x + Int(w), y + h)
    elseif elem isa GraphicsRect
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        w, h = Int(elem.w), Int(elem.h)   # read both (validates computed cells)
        # A zero-size rect paints nothing — contribute no bounds, so an inactive
        # (hidden) overlay rect parked at the origin does not drag the dirty box
        # to (0, 0).
        (w > 0 && h > 0) && _bounds_extend!(minx, miny, maxx, maxy, x, y, x + w, y + h)
    elseif elem isa GraphicsImage
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        w, h = Int(elem.w), Int(elem.h)
        (w > 0 && h > 0) && _bounds_extend!(minx, miny, maxx, maxy, x, y, x + w, y + h)
    elseif elem isa GraphicsViewport
        # A viewport clips its content, so its extent is its declared box.
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        _bounds_extend!(minx, miny, maxx, maxy, x, y, x + Int(elem.w), y + Int(elem.h))
    elseif elem isa GraphicsLine
        hw = max(1, Int(elem.width))
        x0 = ox + min(Int(elem.x1), Int(elem.x2)) - hw
        y0 = oy + min(Int(elem.y1), Int(elem.y2)) - hw
        x1 = ox + max(Int(elem.x1), Int(elem.x2)) + hw
        y1 = oy + max(Int(elem.y1), Int(elem.y2)) + hw
        _bounds_extend!(minx, miny, maxx, maxy, x0, y0, x1, y1)
    elseif elem isa GraphicsCircle
        rad = Int(elem.radius) + Int(elem.border_width)
        cx, cy = ox + Int(elem.cx), oy + Int(elem.cy)
        _bounds_extend!(minx, miny, maxx, maxy, cx - rad, cy - rad, cx + rad, cy + rad)
    elseif elem isa GraphicsPolyline || elem isa GraphicsSpline
        hw = max(1, Int(elem.width)) + Int(elem.arrow_size)
        for p in elem.points
            px = ox + Int(p[1]); py = oy + Int(p[2])
            _bounds_extend!(minx, miny, maxx, maxy, px - hw, py - hw, px + hw, py + hw)
        end
    elseif elem isa GraphicsCanvas
        _accumulate_bounds!(elem, ox + Int(elem.x), oy + Int(elem.y), measure,
                            minx, miny, maxx, maxy)
    end
    # GraphicsFence and unknown types contribute nothing.
end

end # module
