# ──────────────────────────────────────────────────────────────────────────
# Folded in from GraphicsDocument.jl.
#
# The graphics domain provides the final output stage before the SDL backend.
# Elements are positioned, styled render primitives. The canvas is itself a
# Document so the selection mechanism can descend into individual elements,
# enabling mouse hit-testing and element-level selection in the reader.
#
# The domain includes:
# - **Render primitives**: `GraphicsText` (text rendering), `GraphicsRect` (filled rectangles)
# - **Container types**: `GraphicsCanvas` (collection of graphics elements), `GraphicsViewport` (clipping viewport)
# - **Hit testing**: `hit_element_at` for mouse hit detection
#
# All fields are reactive Cells for automatic dependency tracking and incremental redraws.
abstract type GraphicsDocument <: Document end

@enum LayoutDirection layout_none layout_horizontal layout_vertical

# ── GraphicsInsertion ─────────────────────────────────────────────────────

@document struct GraphicsInsertion <: GraphicsDocument
    value::Any = nothing
end

# ── GraphicsText ───────────────────────────────────────────────────────

"""
    GraphicsText(text, x, y, font, color::StyleColor=color_white)

A reactive text element for rendering.
Each field is a `Cell`, so changes to any property are tracked
and can trigger incremental redraws. `color` is a [`StyleColor`](@ref); each
backend converts it to its own device encoding at draw time.
"""
@document struct GraphicsText <: GraphicsDocument
    text::String
    x::Int32
    y::Int32
    font::StyleFont
    color::StyleColor
end

function GraphicsText(text::AbstractString, x::Integer, y::Integer,
                      font::StyleFont, color::StyleColor=color_white)
    GraphicsText(Cell(text), Cell(Int32(x)), Cell(Int32(y)),
                 Cell(font), Cell(color),
                 Cell(nothing))
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

An optional `border_width` (pixels) + `border_color` (a [`StyleColor`](@ref))
paints a rounded outline *inside* the rect, so a single primitive can express
the "rounded fill + 1px outline" idiom without stacking rects. `border_color`
may be passed as `nothing` for "no border" (a transparent default).
Each field is a `Cell`.
"""
@document struct GraphicsRect <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    color::StyleColor
    radius_tl::Int32
    radius_tr::Int32
    radius_br::Int32
    radius_bl::Int32
    border_width::Int32
    border_color::StyleColor
end

# Normalize a `border_color` argument: `nothing` → fully transparent (no border
# drawn; `border_width` still gates whether an outline is painted).
_norm_border(::Nothing) = StyleColor(0.0, 0.0, 0.0, 0.0)
_norm_border(c::StyleColor) = c

function GraphicsRect(x::Integer, y::Integer, w::Integer, h::Integer,
                      color::StyleColor=color_white,
                      radius::Integer=0;
                      radius_tl::Integer=radius, radius_tr::Integer=radius,
                      radius_br::Integer=radius, radius_bl::Integer=radius,
                      border_width::Integer=0, border_color=nothing)
    GraphicsRect(Cell(Int32(x)), Cell(Int32(y)), Cell(Int32(w)), Cell(Int32(h)),
                 Cell(color),
                 Cell(Int32(radius_tl)), Cell(Int32(radius_tr)),
                 Cell(Int32(radius_br)), Cell(Int32(radius_bl)),
                 Cell(Int32(border_width)),
                 Cell(_norm_border(border_color)),
                 Cell(nothing))
end

# ── GraphicsLine ───────────────────────────────────────────────────────────

"""
    GraphicsLine(x1, y1, x2, y2, color::StyleColor=color_black; width=1, dash=nothing)

A reactive straight line from `(x1,y1)` to `(x2,y2)` in `color` (a
[`StyleColor`](@ref)) with the given stroke `width`. Axis-aligned lines
(separators, rules) render as a crisp filled span; diagonal lines render
anti-aliased.

`dash` selects a dashed stroke: `nothing` is solid, an integer `n` repeats an
`n`-pixel dash and `n`-pixel gap, and a `(on, off)` tuple gives independent
dash/gap lengths in pixels. Backends step the pattern along the line, so dashes
stay crisp on axis-aligned lines and follow the slope on diagonals.
"""
@document struct GraphicsLine <: GraphicsDocument
    x1::Int32
    y1::Int32
    x2::Int32
    y2::Int32
    color::StyleColor
    width::Int32
    dash::Any              # nothing | (on::Int, off::Int) — dash pattern in pixels
end

# Normalize a `dash` argument to `nothing` (solid) or a `(on, off)` pixel tuple.
_norm_dash(::Nothing) = nothing
_norm_dash(n::Integer) = (Int(n), Int(n))
_norm_dash(d) = (Int(d[1]), Int(d[2]))

function GraphicsLine(x1::Integer, y1::Integer, x2::Integer, y2::Integer,
                      color::StyleColor=color_black;
                      width::Integer=1, dash=nothing)
    GraphicsLine(Cell(Int32(x1)), Cell(Int32(y1)), Cell(Int32(x2)), Cell(Int32(y2)),
                 Cell(color),
                 Cell(Int32(width)), Cell(_norm_dash(dash)), Cell(nothing))
end

# ── GraphicsCircle ─────────────────────────────────────────────────────────

"""
    GraphicsCircle(cx, cy, radius, color::StyleColor=color_black; border_width=0, border_color=nothing)

A reactive filled circle centered at `(cx,cy)` in `color` (a [`StyleColor`](@ref)).
Optional anti-aliased outline via `border_width` + `border_color` (a
[`StyleColor`](@ref), or `nothing` for no border). Used for avatars, radio dots,
switch knobs and slider thumbs.
"""
@document struct GraphicsCircle <: GraphicsDocument
    cx::Int32
    cy::Int32
    radius::Int32
    color::StyleColor
    border_width::Int32
    border_color::StyleColor
end

function GraphicsCircle(cx::Integer, cy::Integer, radius::Integer,
                        color::StyleColor=color_black;
                        border_width::Integer=0, border_color=nothing)
    GraphicsCircle(Cell(Int32(cx)), Cell(Int32(cy)), Cell(Int32(radius)),
                   Cell(color),
                   Cell(Int32(border_width)),
                   Cell(_norm_border(border_color)),
                   Cell(nothing))
end

# ── GraphicsPolyline ─────────────────────────────────────────────────────

"""
    GraphicsPolyline(points, color::StyleColor=color_black; width=1, dash=nothing,
                     start_arrow=false, end_arrow=false, arrow_size=8)

A reactive connected sequence of straight segments through `points` (a
`Vector{Tuple{Int,Int}}` of absolute `(x, y)` pixels) in `color` (a
[`StyleColor`](@ref)) with stroke `width`. This is the canonical edge primitive
for a routed connector — a libavoid-style polyline route. `dash` selects a
dashed stroke, same values as [`GraphicsLine`](@ref); backends carry the
on/off phase across segments so it stays continuous through the route's
corners instead of restarting at each vertex. Optional filled-triangle
arrowheads at the start and/or end, sized `arrow_size` pixels, oriented along
the adjacent segment.
"""
@document struct GraphicsPolyline <: GraphicsDocument
    points::Any            # Vector{Tuple{Int,Int}}
    color::StyleColor
    width::Int32
    dash::Any              # nothing | (on::Int, off::Int) — dash pattern in pixels
    start_arrow::Bool
    end_arrow::Bool
    arrow_size::Int32
end

function GraphicsPolyline(points::AbstractVector,
                          color::StyleColor=color_black;
                          width::Integer=1, dash=nothing, start_arrow::Bool=false,
                          end_arrow::Bool=false, arrow_size::Integer=8)
    pts = Tuple{Int,Int}[(Int(p[1]), Int(p[2])) for p in points]
    GraphicsPolyline(Cell(pts), Cell(color),
                     Cell(Int32(width)), Cell(_norm_dash(dash)),
                     Cell(start_arrow), Cell(end_arrow),
                     Cell(Int32(arrow_size)), Cell(nothing))
end

# ── GraphicsPolygon ──────────────────────────────────────────────────────

"""
    GraphicsPolygon(points, color::StyleColor=color_black; border_width=0, border_color=nothing)

A reactive closed filled shape through `points` (a `Vector{Tuple{Int,Int}}` of
absolute `(x, y)` pixels) in `color` (a [`StyleColor`](@ref)) — the filled
counterpart of [`GraphicsPolyline`](@ref). The outline closes on its own, so the
last point need not repeat the first. An optional `border_width` (pixels) +
`border_color` (a [`StyleColor`](@ref), or `nothing` for no border) strokes that
outline over the fill.

The outline may be concave — a star marker is — so backends must triangulate it
rather than fan it. Self-intersecting outlines are not supported.
"""
@document struct GraphicsPolygon <: GraphicsDocument
    points::Any            # Vector{Tuple{Int,Int}}
    color::StyleColor
    border_width::Int32
    border_color::StyleColor
end

function GraphicsPolygon(points::AbstractVector,
                         color::StyleColor=color_black;
                         border_width::Integer=0, border_color=nothing)
    pts = Tuple{Int,Int}[(Int(p[1]), Int(p[2])) for p in points]
    GraphicsPolygon(Cell(pts), Cell(color),
                    Cell(Int32(border_width)),
                    Cell(_norm_border(border_color)),
                    Cell(nothing))
end

# ── GraphicsSpline ───────────────────────────────────────────────────────

"""
    GraphicsSpline(points, color::StyleColor=color_black; kind=:catmullrom, width=1,
                   dash=nothing, start_arrow=false, end_arrow=false, arrow_size=8,
                   segments=12)

A reactive smooth curve through/along `points` (a `Vector{Tuple{Int,Int}}`) in
`color` (a [`StyleColor`](@ref)).
`kind` is `:catmullrom` (curve passes through the points) or `:bezier` (the
points are control points of a cubic Bézier chain). Backends tessellate to a
polyline at render time via [`tessellate_spline`](@ref) (`segments` samples per
span), so curve quality is one shared knob. `dash` and the arrowhead flags
behave as on `GraphicsPolyline`.
"""
@document struct GraphicsSpline <: GraphicsDocument
    points::Any            # Vector{Tuple{Int,Int}}
    kind::Symbol
    color::StyleColor
    width::Int32
    dash::Any              # nothing | (on::Int, off::Int) — dash pattern in pixels
    start_arrow::Bool
    end_arrow::Bool
    arrow_size::Int32
    segments::Int32
end

function GraphicsSpline(points::AbstractVector,
                        color::StyleColor=color_black;
                        kind::Symbol=:catmullrom, width::Integer=1, dash=nothing,
                        start_arrow::Bool=false, end_arrow::Bool=false,
                        arrow_size::Integer=8, segments::Integer=12)
    pts = Tuple{Int,Int}[(Int(p[1]), Int(p[2])) for p in points]
    GraphicsSpline(Cell(pts), Cell(kind), Cell(color),
                   Cell(Int32(width)), Cell(_norm_dash(dash)),
                   Cell(start_arrow), Cell(end_arrow),
                   Cell(Int32(arrow_size)), Cell(Int32(segments)), Cell(nothing))
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
    build_polyline_arrowhead(points, size; at_end=true) -> Vector{Tuple{Float64,Float64}}

The three vertices of a filled triangle arrowhead of `size` pixels at the end
(`at_end=true`) or start of the polyline `points`, oriented along the adjacent
segment. Returns an empty vector when there is no segment to orient along.
"""
function build_polyline_arrowhead(points::AbstractVector, size::Real; at_end::Bool=true)
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
    x::Int32 = Int32(0)
    y::Int32 = Int32(0)
    w::Int32 = Int32(0)
    h::Int32 = Int32(0)
    elements::CollectionDocument = CellVector()
    layout::LayoutDirection = layout_none
    overlapping_elements::Bool = true
end

# `GraphicsCanvas()` is the macro's keyword constructor — an empty canvas at the
# origin. Every field defaults, so Rule Y emits no positional constructor and the
# typed constructors below stay in sole charge of positional construction.
GraphicsCanvas(elems::Vector; x::Integer=0, y::Integer=0, w::Integer=0, h::Integer=0,
               layout::LayoutDirection=layout_none, overlapping::Bool=true) =
    GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h),
                   CellVector(Cell[Cell(e) for e in elems]), layout, overlapping, Cell(nothing))
GraphicsCanvas(elems::CollectionDocument, layout::LayoutDirection) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), elems, layout, true, Cell(nothing))
GraphicsCanvas(elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), elems, layout, overlapping, Cell(nothing))
GraphicsCanvas(x::Integer, y::Integer, elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(x), Int32(y), Int32(0), Int32(0), elems, layout, overlapping, Cell(nothing))
GraphicsCanvas(x::Integer, y::Integer, w::Integer, h::Integer, elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h), elems, layout, overlapping, Cell(nothing))

# ── Viewport ─────────────────────────────────────────────────────────────

"""
    GraphicsViewport(x, y, w, h, content; transform=affine_identity)

A clipping viewport: renders `content` (a `GraphicsCanvas` whose element
coordinates are relative to the viewport origin, with any scroll offset
already applied) and clips the output to the rectangle `(x, y, w, h)`.

`transform` is an [`AffineTransform`](@ref) applied to `content` *inside* the
clip rectangle (local content space → viewport space). It defaults to the
identity, so an ordinary scrolling viewport bakes its offset into the content
canvas's origin as before and leaves `transform` alone. A `WidgetTransformPane`
instead drives `transform` to zoom/pan its content. Backends honour the
translate+scale subset (`is_affine_axis_aligned`); rotation/shear is future
work.
"""
@document struct GraphicsViewport <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    content::GraphicsCanvas
    transform::AffineTransform
end

function GraphicsViewport(x::Integer, y::Integer, w::Integer, h::Integer,
                          content::GraphicsCanvas; transform::AffineTransform=affine_identity)
    GraphicsViewport(Cell(Int32(x)), Cell(Int32(y)),
                     Cell(Int32(w)), Cell(Int32(h)),
                     Cell(content),
                     Cell(transform),
                     Cell(nothing))
end

# ── Image (cached rasterized canvas) ─────────────────────────────────────

@document struct GraphicsImage <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    data::Any
end

function GraphicsImage(x::Integer, y::Integer, w::Integer, h::Integer, data)
    GraphicsImage(Cell(Int32(x)), Cell(Int32(y)),
                  Cell(Int32(w)), Cell(Int32(h)),
                  Cell(data),
                  Cell(nothing))
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
end

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
    is_point_near_polyline(points, x, y, tolerance) -> Bool

True when `(x, y)` is within `tolerance` pixels of any segment of the polyline
`points` (a vector of `(x, y)`). Used for edge hit-testing.
"""
function is_point_near_polyline(points::AbstractVector, x::Real, y::Real, tolerance::Real)
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
    is_point_in_polygon(points, x, y) -> Bool

True when `(x, y)` lies inside the closed polygon `points` (a vector of
`(x, y)`), by ray casting: a ray along `+x` crosses an odd number of edges.
Concave outlines are handled; a point exactly on an edge may fall either way.
Used for filled-shape hit-testing.
"""
function is_point_in_polygon(points::AbstractVector, x::Real, y::Real)
    n = length(points)
    n < 3 && return false
    px = Float64(x); py = Float64(y)
    inside = false
    j = n
    for i in 1:n
        xi = Float64(points[i][1]); yi = Float64(points[i][2])
        xj = Float64(points[j][1]); yj = Float64(points[j][2])
        if (yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi
            inside = !inside
        end
        j = i
    end
    inside
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
    # A hit must fall within the canvas's own bounds. Some elements are unbounded
    # on one side (a GraphicsText has no right edge — see `_hit_test_element`), so
    # without this clip a canvas would claim hits in a sibling's column and
    # misroute pointer events in horizontal composites. Guarded so auto-sized
    # canvases (`w`/`h` == 0) keep their previous, unclipped behaviour.
    cw = canvas.w; ch = canvas.h
    (cw > 0 && (x < 0 || x >= cw)) && return nothing
    (ch > 0 && (y < 0 || y >= ch)) && return nothing
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
        fs = font_logical_size(elem.font)
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
        is_point_near_polyline(elem.points, x, y, max(3, Int(elem.width) + 2))
    elseif elem isa GraphicsPolygon
        # A filled shape claims its whole interior, unlike the stroked polyline
        # which only claims a tolerance band around its path.
        is_point_in_polygon(elem.points, x, y)
    elseif elem isa GraphicsSpline
        pts = tessellate_spline(elem.points, elem.kind, elem.segments)
        is_point_near_polyline(pts, x, y, max(3, Int(elem.width) + 2))
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
        h = font_logical_size(elem.font)
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
    elseif elem isa GraphicsPolygon
        # The outline is the extent; a stroked border straddles it by half its
        # width, so pad by the whole width and stay conservative.
        hw = Int(elem.border_width)
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

# Text-width fallback for `get_graphics_size`: this layer has no font backend, so a
# bare `GraphicsText` contributes height (from its font) but no width.
_zero_text_measure(_, _) = (0, 0)

"""
    get_graphics_size(doc::GraphicsDocument[, measure]) -> (w, h)

The natural pixel extent of any graphics document, measured from the origin —
the maximum x / y its content reaches. This lets a layout place a bare primitive
(a `GraphicsCircle`, `GraphicsLine`, …) directly, asking it for its size, instead
of requiring it to be wrapped in a sized `GraphicsCanvas`. Shares the per-element
extent logic with the content-bounds machinery. `measure(text, font) -> (w, h)`
sizes a `GraphicsText`; the default ignores text width (no font backend here), so
pass a real `measure` when laying out bare text.
"""
function get_graphics_size(doc::GraphicsDocument, measure = _zero_text_measure)
    minx = Ref(typemax(Int)); miny = Ref(typemax(Int))
    maxx = Ref(typemin(Int)); maxy = Ref(typemin(Int))
    _bounds_elem!(doc, 0, 0, measure, minx, miny, maxx, maxy)
    maxx[] == typemin(Int) && return (0, 0)   # nothing drawn
    (max(Int(maxx[]), 0), max(Int(maxy[]), 0))
end
