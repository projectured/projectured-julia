# Fragment of `GraphicsModule`.
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

# ── Live values ──────────────────────────────────────────────────────────
#
# A constructor takes each geometric argument — a coordinate, a size, the points
# of a line — as a number, as a cell that holds one, or as a function of no
# arguments. A function becomes a computed cell, so the shape follows what the
# function reads, as a dot that circles a ring follows a clock. A number is
# rounded to a whole pixel, and so is each coordinate of a point. An angle is a
# number of degrees and is not rounded. The text of a `GraphicsText` is live in
# the same way.

const _LiveNumber = Union{Real, Cell, Function}
const _LivePoints = Union{AbstractVector, Cell, Function}
const _LiveText = Union{AbstractString, Cell, Function}

_round_pixel(value::Integer) = Int32(value)
_round_pixel(value::Real) = round(Int32, value)

_make_pixel_cell(value::Real) = Cell(_round_pixel(value))
_make_pixel_cell(value::Cell) = value
_make_pixel_cell(value::Function) = Cell(@computation _round_pixel(value()))

_round_points(points) = Tuple{Int,Int}[(round(Int, point[1]), round(Int, point[2])) for point in points]

_make_points_cell(points::AbstractVector) = Cell(_round_points(points))
_make_points_cell(points::Cell) = points
_make_points_cell(points::Function) = Cell(@computation _round_points(points()))

_make_angle_cell(value::Real) = Cell(Float64(value))
_make_angle_cell(value::Cell) = value
_make_angle_cell(value::Function) = Cell(@computation Float64(value()))

_make_text_cell(text::AbstractString) = Cell(String(text))
_make_text_cell(text::Cell) = text
_make_text_cell(text::Function) = Cell(@computation String(text()))

# ── GraphicsInsertion ─────────────────────────────────────────────────────

@document struct GraphicsInsertion <: GraphicsDocument
    value::Any = nothing
end

# ── GraphicsText ───────────────────────────────────────────────────────

"""
    GraphicsText(text, x, y; font, color::StyleColor=color_white)

Words drawn at a place, in a font and a colour.

Use it when you build what is drawn by hand: a label of a chart, a word of a
rule, a caption under a picture. A projection that shows text produces these,
and a backend paints them.

# Example

    GraphicsText("delay", 10, 20; font = StyleFont("Ubuntu Mono", 20), color = color_black)

See also `GraphicsCanvas`, which holds what is drawn, and `GraphicsRect`.

**The box.** `x` is where the pen of the first glyph starts, and `y` is the top
of the text's box. [`compute_text_extent`](@ref) gives the box from the font
files: `(width, ascent, descent)` in whole logical pixels. The baseline is
`ascent` below `y`, and the box is `ascent + descent` high, so it holds the ink.
Every backend draws the baseline there, and a layout that puts texts of
different fonts on one baseline sets each `y` to the baseline minus that text's
ascent.

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

function GraphicsText(text::_LiveText, x::_LiveNumber, y::_LiveNumber;
                      font::StyleFont, color::StyleColor=color_white)  # @style: content of the document
    GraphicsText(_make_text_cell(text), _make_pixel_cell(x), _make_pixel_cell(y),
                 Cell(font), Cell(color),
                 Cell(nothing))
end

"""
    GraphicsRect(x, y, w, h; color=color_white, radius=0,
                 radius_tl=radius, radius_tr=radius,
                 radius_br=radius, radius_bl=radius,
                 border_width=0, border_color=nothing)

A filled box at a place, in a colour, with corners as round as you ask.

Use it for anything that is a coloured area: the background of a card, the band
behind a selected row, a caret, a rule, a border drawn as four thin boxes.

# Example

    GraphicsRect(0, 0, 120, 24; color = StyleColor(0.9, 0.9, 0.9, 1.0), radius = 4)

See also `GraphicsCanvas`, which holds it, and `GraphicsText`.

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
_norm_border(::Nothing) = color_transparent
_norm_border(c::StyleColor) = c

function GraphicsRect(x::_LiveNumber, y::_LiveNumber, w::_LiveNumber, h::_LiveNumber;
                      color::StyleColor=color_white, radius::Integer=0,  # @style: content of the document
                      radius_tl::Integer=radius, radius_tr::Integer=radius,
                      radius_br::Integer=radius, radius_bl::Integer=radius,
                      border_width::Integer=0, border_color=nothing)
    GraphicsRect(_make_pixel_cell(x), _make_pixel_cell(y), _make_pixel_cell(w), _make_pixel_cell(h),
                 Cell(color),
                 Cell(Int32(radius_tl)), Cell(Int32(radius_tr)),
                 Cell(Int32(radius_br)), Cell(Int32(radius_bl)),
                 Cell(Int32(border_width)),
                 Cell(_norm_border(border_color)),
                 Cell(nothing))
end

# ── GraphicsLine ───────────────────────────────────────────────────────────

"""
    GraphicsLine(x1, y1, x2, y2; color::StyleColor=color_black, width=1, dash=nothing)

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

function GraphicsLine(x1::_LiveNumber, y1::_LiveNumber, x2::_LiveNumber, y2::_LiveNumber;
                      color::StyleColor=color_black,  # @style: content of the document
                      width::Integer=1, dash=nothing)
    GraphicsLine(_make_pixel_cell(x1), _make_pixel_cell(y1), _make_pixel_cell(x2), _make_pixel_cell(y2),
                 Cell(color),
                 Cell(Int32(width)), Cell(_norm_dash(dash)), Cell(nothing))
end

# ── GraphicsCircle ─────────────────────────────────────────────────────────

"""
    GraphicsCircle(cx, cy, radius; color::StyleColor=color_black, border_width=0, border_color=nothing)

A reactive filled circle centered at `(cx,cy)` in `color` (a [`StyleColor`](@ref)).
`cx`, `cy` and `radius` are each a number, a cell, or a function of no arguments
that the circle computes again when what it reads changes:
`GraphicsCircle(() -> 90 + 60 * cos(phase()), () -> 90 - 60 * sin(phase()), 5)`.
The same holds for the geometry of every graphics element.
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

function GraphicsCircle(cx::_LiveNumber, cy::_LiveNumber, radius::_LiveNumber;
                        color::StyleColor=color_black,  # @style: content of the document
                        border_width::Integer=0, border_color=nothing)
    GraphicsCircle(_make_pixel_cell(cx), _make_pixel_cell(cy), _make_pixel_cell(radius),
                   Cell(color),
                   Cell(Int32(border_width)),
                   Cell(_norm_border(border_color)),
                   Cell(nothing))
end

# ── GraphicsArc ────────────────────────────────────────────────────────────

"""
    GraphicsArc(cx, cy, radius; width=1, start_angle=0, sweep_angle=360,
                color::StyleColor=color_black)

A reactive stroke along a part of the circle centered at `(cx,cy)`, in `color`
(a [`StyleColor`](@ref)). `radius` is the outer edge, and the stroke of `width`
pixels lies inside it, so the arc covers the ring of
`GraphicsCircle(cx, cy, radius; border_width = width)`. The two ends are flat.

`start_angle` and `sweep_angle` are degrees: 0 is at the top, and a positive
angle goes clockwise on the screen. A sweep of 360 or more draws the whole ring,
and a sweep of 0 or less draws nothing. `cx`, `cy`, `radius` and the two angles
are each a number, a cell, or a function of no arguments, as the geometry of
every graphics element is. An angle is not rounded. Used for the indicator of a
progress ring.
"""
@document struct GraphicsArc <: GraphicsDocument
    cx::Int32
    cy::Int32
    radius::Int32
    width::Int32
    start_angle::Float64
    sweep_angle::Float64
    color::StyleColor
end

function GraphicsArc(cx::_LiveNumber, cy::_LiveNumber, radius::_LiveNumber;
                     width::Integer=1, start_angle::_LiveNumber=0, sweep_angle::_LiveNumber=360,
                     color::StyleColor=color_black)  # @style: content of the document
    GraphicsArc(_make_pixel_cell(cx), _make_pixel_cell(cy), _make_pixel_cell(radius),
                Cell(Int32(width)),
                _make_angle_cell(start_angle), _make_angle_cell(sweep_angle),
                Cell(color),
                Cell(nothing))
end

# Whether `(x, y)` is on the stroke of `arc`: within a few pixels of the middle of
# its band, and at an angle inside its sweep.
function _is_point_on_arc(arc::GraphicsArc, x::Int, y::Int)
    sweep = Float64(arc.sweep_angle)
    sweep > 0 || return false
    dx, dy = x - Int(arc.cx), y - Int(arc.cy)
    width = max(1, Int(arc.width))
    middle = Int(arc.radius) - width / 2
    abs(hypot(dx, dy) - middle) <= max(3, width / 2 + 2) || return false
    sweep >= 360 && return true
    angle = mod(rad2deg(atan(dx, -dy)), 360.0)
    mod(angle - Float64(arc.start_angle), 360.0) <= sweep
end

# ── GraphicsPolyline ─────────────────────────────────────────────────────

"""
    GraphicsPolyline(points; color::StyleColor=color_black, width=1, dash=nothing,
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

function GraphicsPolyline(points::_LivePoints;
                          color::StyleColor=color_black,  # @style: content of the document
                          width::Integer=1, dash=nothing, start_arrow::Bool=false,
                          end_arrow::Bool=false, arrow_size::Integer=8)
    GraphicsPolyline(_make_points_cell(points), Cell(color),
                     Cell(Int32(width)), Cell(_norm_dash(dash)),
                     Cell(start_arrow), Cell(end_arrow),
                     Cell(Int32(arrow_size)), Cell(nothing))
end

# ── GraphicsPolygon ──────────────────────────────────────────────────────

"""
    GraphicsPolygon(points; color::StyleColor=color_black, border_width=0, border_color=nothing)

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

function GraphicsPolygon(points::_LivePoints;
                         color::StyleColor=color_black,  # @style: content of the document
                         border_width::Integer=0, border_color=nothing)
    GraphicsPolygon(_make_points_cell(points), Cell(color),
                    Cell(Int32(border_width)),
                    Cell(_norm_border(border_color)),
                    Cell(nothing))
end

# ── GraphicsSpline ───────────────────────────────────────────────────────

"""
    GraphicsSpline(points; color::StyleColor=color_black, kind=:catmullrom, width=1,
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

function GraphicsSpline(points::_LivePoints;
                        color::StyleColor=color_black,  # @style: content of the document
                        kind::Symbol=:catmullrom, width::Integer=1, dash=nothing,
                        start_arrow::Bool=false, end_arrow::Bool=false,
                        arrow_size::Integer=8, segments::Integer=12)
    GraphicsSpline(_make_points_cell(points), Cell(kind), Cell(color),
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
    GraphicsCanvas(elements; x = 0, y = 0, w = 0, h = 0, layout = layout_none, overlapping = true)
    GraphicsCanvas(elements, layout)

A sheet that holds what is drawn, at a place and of a size.

`elements` is a `Vector` of graphics documents, which the canvas holds one cell
each, or a `CollectionDocument` it holds as it is.

Use it as the result of anything that draws: a projection answers one, a
backend paints one, and a test reads one to see what reached the screen. Its
elements are drawn in order, and a canvas may hold other canvases.

# Example

    canvas = GraphicsCanvas([GraphicsText("hello", 4, 4; font = StyleFont("Ubuntu Mono", 20),
                                          color = color_black)];
                            w = 200, h = 50)

See also `GraphicsViewport`, which shows a part of one, and `GraphicsText`.

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
GraphicsCanvas(elements::CollectionDocument; x::_LiveNumber=0, y::_LiveNumber=0, w::_LiveNumber=0,
               h::_LiveNumber=0, layout::LayoutDirection=layout_none, overlapping::Bool=true) =
    GraphicsCanvas(_make_pixel_cell(x), _make_pixel_cell(y), _make_pixel_cell(w), _make_pixel_cell(h),
                   elements, layout, overlapping, Cell(nothing))
GraphicsCanvas(elements::Vector; kwargs...) =
    GraphicsCanvas(CellVector(Cell[Cell(e) for e in elements]); kwargs...)
GraphicsCanvas(elements::CollectionDocument, layout::LayoutDirection) =
    GraphicsCanvas(elements; layout)

# ── Viewport ─────────────────────────────────────────────────────────────

"""
    GraphicsViewport(x, y, w, h, content; transform=affine_identity)

A clipping viewport: renders `content` (a `GraphicsCanvas` whose element
coordinates are relative to the viewport origin, with any scroll offset
already applied) and clips the output to the rectangle `(x, y, w, h)`.

Show a part of something drawn, and keep the rest outside.

Use it for anything that scrolls, zooms or pans: a pane of a window, a chart a
person drags, a long page shown one screen at a time. It has a place and a
size, and it holds one canvas of content.

# Example

    GraphicsViewport(Int32(0), Int32(0), Int32(300), Int32(200), page)

See also `GraphicsCanvas`, `WidgetScrollPane` and `AffineTransform`.

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

function GraphicsViewport(x::_LiveNumber, y::_LiveNumber, w::_LiveNumber, h::_LiveNumber,
                          content::GraphicsCanvas; transform::AffineTransform=affine_identity)
    GraphicsViewport(_make_pixel_cell(x), _make_pixel_cell(y),
                     _make_pixel_cell(w), _make_pixel_cell(h),
                     Cell(content),
                     Cell(transform),
                     Cell(nothing))
end

# A viewport whose box is reactive and whose transform is the identity: what a
# layout builds when it clips a child to a slot that moves with the layout.
function GraphicsViewport(x::Cell, y::Cell, w::Cell, h::Cell, content::Cell)
    GraphicsViewport(x, y, w, h, content, Cell(affine_identity), Cell(nothing))
end

# ── Image (cached rasterized canvas) ─────────────────────────────────────

@document struct GraphicsImage <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    data::Any
end

function GraphicsImage(x::_LiveNumber, y::_LiveNumber, w::_LiveNumber, h::_LiveNumber, data)
    GraphicsImage(_make_pixel_cell(x), _make_pixel_cell(y),
                  _make_pixel_cell(w), _make_pixel_cell(h),
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

# ── Pointer shape ──────────────────────────────────────────────────────────

"""
    POINTER_SHAPES

The shapes that a pointer can take, named by the picture: `:arrow`, `:ibeam`,
`:double_arrow_horizontal`, `:double_arrow_vertical`, `:pointing_hand`,
`:open_hand`, `:closed_hand`, `:crossed_circle` and `:hourglass`. A backend maps
each one to a shape of its own, and shows the arrow for a shape it does not know.
"""
const POINTER_SHAPES = (:arrow, :ibeam, :double_arrow_horizontal, :double_arrow_vertical,
                        :pointing_hand, :open_hand, :closed_hand, :crossed_circle, :hourglass)

_make_shape_cell(shape::Symbol) = Cell(shape)
_make_shape_cell(shape::Cell) = shape
_make_shape_cell(shape::Function) = Cell(@computation Symbol(shape()))

"""
    GraphicsPointerShape(x, y, w, h, shape)

A box where the pointer takes `shape`, one of [`POINTER_SHAPES`](@ref). It draws
nothing.

A part puts one into what it draws where a press does something: the edge of a
column, the divider of a split pane, a text that a person edits. A backend finds
the shape at the pointer with [`find_pointer_shape`](@ref), and every backend
paints nothing for it.

`shape` is a `Symbol`, a cell that holds one, or a function of no arguments,
which becomes a computed cell.

# Example

    GraphicsPointerShape(97, 0, 7, 24, :double_arrow_horizontal)

**A laid-out canvas.** The box has a place on both axes, so a canvas that lays
out its elements without overlap reads it as an element of the order: put a
region in such a canvas only where its place keeps the order, or in a canvas
without a layout.
"""
@document struct GraphicsPointerShape <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    shape::Symbol
end

function GraphicsPointerShape(x::_LiveNumber, y::_LiveNumber, w::_LiveNumber, h::_LiveNumber,
                              shape::Union{Symbol,Cell,Function})
    GraphicsPointerShape(_make_pixel_cell(x), _make_pixel_cell(y),
                         _make_pixel_cell(w), _make_pixel_cell(h),
                         _make_shape_cell(shape), Cell(nothing))
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

Returns the 0-based offset of the first element in `canvas` whose bounding area
contains `(x, y)`, or `nothing` if no element matches.
Supports `GraphicsViewport` and `GraphicsImage` (rectangle bounds),
`GraphicsRect` (rectangle bounds), and `GraphicsText` (the box of
[`compute_text_extent`](@ref)).
Skips `GraphicsFence` elements. For `ListNode`-backed canvases with a layout
direction, stops early when the element position exceeds the click coordinate
along the layout axis.
"""
function hit_element_at(canvas::GraphicsCanvas, x::Int, y::Int)
    layout = canvas.layout
    elements = canvas.elements
    # A hit must fall within the canvas's own bounds, so that an element drawn
    # past the edge of the canvas never claims a hit in a sibling's box. An
    # auto-sized canvas (`w` or `h` is 0) has no bound on that axis.
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
        first = compute_first_visible_index(canvas, layout == layout_horizontal ? x : y)
        for i in first:length(elements)
            elem = elements[i]
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
    if elem isa GraphicsViewport || elem isa GraphicsImage
        vx, vy = Int(elem.x), Int(elem.y)
        vw, vh = Int(elem.w), Int(elem.h)
        x >= vx && x < vx + vw && y >= vy && y < vy + vh
    elseif elem isa GraphicsRect
        _rect_hit(elem, x, y)
    elseif elem isa GraphicsText
        ex, ey = Int(elem.x), Int(elem.y)
        width, ascent, descent = compute_text_extent(elem.text, elem.font)
        ex <= x < ex + width && ey <= y < ey + ascent + descent
    elseif elem isa GraphicsCircle
        dx, dy = x - Int(elem.cx), y - Int(elem.cy)
        rad = Int(elem.radius)
        dx * dx + dy * dy <= rad * rad
    elseif elem isa GraphicsArc
        _is_point_on_arc(elem, x, y)
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

"""
    compute_first_visible_index(canvas, edge) -> Int

The index of the first element of `canvas` that can reach past `edge`, the near
edge of a clip on the layout axis, in the coordinates of `canvas`.

The elements of a laid-out canvas do not overlap, and they follow the axis, so
an element ends where the next one starts. The answer is the last element that
starts at or before `edge`, and every element before it ends at or before
`edge`. The search reads the position of a few elements, about `log2(n)`, and
the content of none.

It answers `1` for a canvas without a layout, for elements that can overlap,
for a `ListNode`, and when an element it reads has no position on the axis.

# Example

    rows = GraphicsCanvas(CellVector(Cell[Cell(row) for row in rows]), layout_vertical;
                          overlapping = false)
    first = compute_first_visible_index(rows, 460)   # the row under y = 460

See also `hit_element_at`, which starts its test there, and `has_declared_extent`.
"""
function compute_first_visible_index(canvas::GraphicsCanvas, edge::Int)
    layout = canvas.layout
    (layout == layout_none || canvas.overlapping_elements) && return 1
    elements = canvas.elements
    elements isa ListNode && return 1
    position = layout == layout_horizontal ? _elem_x : _elem_y
    compute_first_visible_index(i -> position(elements[i]), length(elements), edge)
end

# The search itself, over `count` elements: `get_start(i)` is where element `i`
# starts on the axis, or `nothing`, which answers `1`. A walk that must test an
# element before it reads it gives its own `get_start`, and so reads the same
# elements as the render.
function compute_first_visible_index(get_start::Function, count::Int, edge::Int)
    first = 1
    low, high = 1, count
    while low <= high
        middle = (low + high) >>> 1
        start = get_start(middle)
        start === nothing && return 1
        if start <= edge
            first = middle
            low = middle + 1
        else
            high = middle - 1
        end
    end
    first
end

"""
    has_declared_extent(canvas) -> Bool

Whether `canvas` states its own extent, so that a query of its size takes its
box and does not walk its elements.

A canvas that lays out its elements along an axis, without overlap, can hold
more elements than a reader must read: the rows of a long tree, of which the
screen shows a few. Such a canvas states its extent in `w` and `h`. A canvas
without a layout, with elements that can overlap, or without both a width and a
height, states none, and a query walks its elements.

# Example

    rows = GraphicsCanvas(elements; layout = layout_vertical, overlapping = false, w = 300, h = 23_000)
    has_declared_extent(rows)          # true: its size is 300 × 23000, read from the box

See also `get_graphics_size` and `compute_first_visible_index`.
"""
has_declared_extent(canvas::GraphicsCanvas) =
    canvas.layout != layout_none && !canvas.overlapping_elements &&
    Int(canvas.w) > 0 && Int(canvas.h) > 0


# ── Content bounds ──────────────────────────────────────────────────────
#
# The axis-aligned bounding box, in absolute pixels, of everything a canvas
# would draw. Offsets accumulate through nested canvases exactly as the backend
# renders them, so the result is the natural extent of the laid-out content. It
# sizes an output (image, PDF) to the content when no width or height is asked
# for, and a backend repaints the box of what changed. A text element covers its
# box, as `measure` measures it (`compute_text_extent`); the default measures
# from the font files, as every backend draws.

"""
    ContentBounds()

The box of what a graphics document draws, in absolute pixels, as it grows: it
starts empty, and each element or box it is extended by makes it cover that
too. [`get_content_box`](@ref) reads it.
"""
mutable struct ContentBounds
    minx::Int
    miny::Int
    maxx::Int
    maxy::Int
end

ContentBounds() = ContentBounds(typemax(Int), typemax(Int), typemin(Int), typemin(Int))

"""
    get_content_box(bounds::ContentBounds) -> (x0, y0, x1, y1) or nothing

The box that `bounds` covers, or `nothing` when nothing extended it.
"""
get_content_box(bounds::ContentBounds) =
    bounds.maxx == typemin(Int) ? nothing : (bounds.minx, bounds.miny, bounds.maxx, bounds.maxy)

"""
    extend_content_bounds!(bounds, box) -> bounds

Make `bounds` cover the box `(x0, y0, x1, y1)` too.
"""
function extend_content_bounds!(bounds::ContentBounds, box::NTuple{4,Int})
    bounds.minx = min(bounds.minx, box[1]); bounds.miny = min(bounds.miny, box[2])
    bounds.maxx = max(bounds.maxx, box[3]); bounds.maxy = max(bounds.maxy, box[4])
    bounds
end

"""
    extend_canvas_bounds!(bounds, canvas, origin; measure = FontFileMeasure()) -> bounds

Make `bounds` cover what the elements of `canvas` draw when the canvas sits at
`origin`, `(x, y)`: its declared box when it has one, else each element.
"""
function extend_canvas_bounds!(bounds::ContentBounds, canvas::GraphicsCanvas,
                               origin::NTuple{2,Int}; measure::TextMeasure = FontFileMeasure())
    (ox, oy) = origin
    has_declared_extent(canvas) &&
        return extend_content_bounds!(bounds, (ox, oy, ox + Int(canvas.w), oy + Int(canvas.h)))
    for elem in canvas.elements
        extend_element_bounds!(bounds, elem, origin; measure)
    end
    bounds
end

"""
    extend_element_bounds!(bounds, element, origin; measure = FontFileMeasure()) -> bounds

Make `bounds` cover what `element` draws, placed at its own position from
`origin`, `(x, y)`. A rectangle or an image of no size, a fence and a type this
slice does not know draw nothing and add nothing.
"""
function extend_element_bounds!(bounds::ContentBounds, elem, origin::NTuple{2,Int};
                                measure::TextMeasure = FontFileMeasure())
    (ox, oy) = origin
    if elem isa GraphicsText
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        width, ascent, descent = compute_text_extent(measure, elem.text, elem.font)
        extend_content_bounds!(bounds, (x, y, x + width, y + ascent + descent))
    elseif elem isa GraphicsRect
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        w, h = Int(elem.w), Int(elem.h)   # read both (validates computed cells)
        # A zero-size rect paints nothing — contribute no bounds, so an inactive
        # (hidden) overlay rect parked at the origin does not drag the dirty box
        # to (0, 0).
        (w > 0 && h > 0) && extend_content_bounds!(bounds, (x, y, x + w, y + h))
    elseif elem isa GraphicsImage
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        w, h = Int(elem.w), Int(elem.h)
        (w > 0 && h > 0) && extend_content_bounds!(bounds, (x, y, x + w, y + h))
    elseif elem isa GraphicsViewport
        # A viewport clips its content, so its extent is its declared box.
        x, y = ox + Int(elem.x), oy + Int(elem.y)
        extend_content_bounds!(bounds, (x, y, x + Int(elem.w), y + Int(elem.h)))
    elseif elem isa GraphicsLine
        hw = max(1, Int(elem.width))
        x0 = ox + min(Int(elem.x1), Int(elem.x2)) - hw
        y0 = oy + min(Int(elem.y1), Int(elem.y2)) - hw
        x1 = ox + max(Int(elem.x1), Int(elem.x2)) + hw
        y1 = oy + max(Int(elem.y1), Int(elem.y2)) + hw
        extend_content_bounds!(bounds, (x0, y0, x1, y1))
    elseif elem isa GraphicsCircle
        rad = Int(elem.radius) + Int(elem.border_width)
        cx, cy = ox + Int(elem.cx), oy + Int(elem.cy)
        extend_content_bounds!(bounds, (cx - rad, cy - rad, cx + rad, cy + rad))
    elseif elem isa GraphicsArc
        # The box of the ring of a circle of the same radius and width, whatever
        # the angles: an arc that turns keeps one box.
        rad = Int(elem.radius) + Int(elem.width)
        cx, cy = ox + Int(elem.cx), oy + Int(elem.cy)
        extend_content_bounds!(bounds, (cx - rad, cy - rad, cx + rad, cy + rad))
    elseif elem isa GraphicsPolyline || elem isa GraphicsSpline
        hw = max(1, Int(elem.width)) + Int(elem.arrow_size)
        for p in elem.points
            px = ox + Int(p[1]); py = oy + Int(p[2])
            extend_content_bounds!(bounds, (px - hw, py - hw, px + hw, py + hw))
        end
    elseif elem isa GraphicsPolygon
        # The outline is the extent; a stroked border straddles it by half its
        # width, so pad by the whole width and stay conservative.
        hw = Int(elem.border_width)
        for p in elem.points
            px = ox + Int(p[1]); py = oy + Int(p[2])
            extend_content_bounds!(bounds, (px - hw, py - hw, px + hw, py + hw))
        end
    elseif elem isa GraphicsCanvas
        extend_canvas_bounds!(bounds, elem, (ox + Int(elem.x), oy + Int(elem.y)); measure)
    end
    # GraphicsFence and unknown types contribute nothing.
    bounds
end

"""
    get_canvas_content_bounds(canvas[, measure]) -> (x0, y0, x1, y1)

The box of what `canvas` draws at the origin, `(0, 0, 0, 0)` for an empty one.
"""
function get_canvas_content_bounds(canvas::GraphicsCanvas, measure::TextMeasure = FontFileMeasure())
    box = get_content_box(extend_canvas_bounds!(ContentBounds(), canvas, (0, 0); measure))
    something(box, (0, 0, 0, 0))
end

"""
    get_graphics_size(doc::GraphicsDocument[, measure]) -> (w, h)

The natural pixel extent of any graphics document, measured from the origin —
the maximum x / y its content reaches. This lets a layout place a bare primitive
(a `GraphicsCircle`, `GraphicsLine`, …) directly, asking it for its size, instead
of requiring it to be wrapped in a sized `GraphicsCanvas`. Shares the per-element
extent logic with the content-bounds machinery. A `GraphicsText` covers its box
as `measure` measures it; the default measures from the font files, as every
backend draws.
"""
function get_graphics_size(doc::GraphicsDocument, measure::TextMeasure = FontFileMeasure())
    box = get_content_box(extend_element_bounds!(ContentBounds(), doc, (0, 0); measure))
    box === nothing && return (0, 0)   # nothing drawn
    (max(box[3], 0), max(box[4], 0))
end
