"""
    GraphLayoutEngineModule

A swappable interface for graph placement + edge routing. `GridEmbedding`
(pure Julia) places without simulating, so nothing downstream is blocked. The
force-directed engines ported from OMNeT++ live above this file; the native
binding (Adaptagrams: libcola for placement, libavoid for routing) lives in its
own package, `ProjecturedAdaptagrams`, because it pulls in an external native
dependency — it adds an `AdaptagramsLayout <: GraphLayoutEngine` method to
`layout_graph` behind this same interface. Core domain code never depends on it.

Interface:

```julia
layout_graph(engine, graph, sizes, constraints; extent = nothing, border = 0)
    -> (positions, routes)
```

where
- `graph`        is a `GraphGraph`,
- `sizes`        maps each `GraphVertex` (by `objectid`) to `(w, h)`,
- `constraints`  is a vector of `GraphConstraint`,
- `extent`       is `(width, height)`, the box the caller wants filled, or
                 `nothing` when the caller has no box in mind,
- `border`       is the inset kept on every side of that box,
- `positions`    maps each `GraphVertex` (by `objectid`) to `(x, y, w, h)`,
- `routes`       maps each `GraphEdge` (by `objectid`) to `Vector{Tuple{Int,Int}}`.

`extent` and `border` are one argument pair rather than engine fields, because
the same graph in two panes wants two layouts. OMNeT++ passes the same pair the
same way, as `GraphLayouter::setSize(width, height, border)`.

Keying on `objectid` keeps the engine call pure of any reactive cell, so the
projection can memoize it on topology + sizes + constraints.

An engine declares which `GraphConstraint` kinds it implements and
[`check_constraints`](@ref) refuses every other kind by name. An engine that
accepted a kind and dropped it would draw a picture indistinguishable from one
that was never asked for the constraint at all.
"""
module GraphLayoutEngineModule

import ..GraphModule: GraphGraph, GraphVertex, GraphEdge
import ..GraphLayoutModule: GraphConstraint

export GraphLayoutEngine, GridEmbedding, DeferredLayout, layout_graph,
       deferred_layout_engine, register_layout_engine!, resolved_layout_engine,
       supported_constraint_kinds, check_constraints, GRAPH_CONSTRAINT_KINDS,
       constraint_pins, constraint_fixed_sizes, layout_vertices, vertex_sizes,
       straight_routes, extent_transform, fit_into_extent!

abstract type GraphLayoutEngine end

"""
    layout_graph(engine, graph, sizes, constraints; extent = nothing, border = 0)
        -> (positions, routes)

Place the vertices and route the edges of `graph`. See module docs for the shapes.
"""
function layout_graph end

# ── The constraint vocabulary ────────────────────────────────────────────────

"""
Every `GraphConstraint.kind` this interface knows. A kind outside this tuple is
a typing mistake; a kind inside it that an engine does not implement is a
refusal, never a silent drop. See [`check_constraints`](@ref).
"""
const GRAPH_CONSTRAINT_KINDS =
    (:pin, :fixed_size, :cluster, :align, :same_rank, :min_separation)

"""
    supported_constraint_kinds(engine) -> Tuple{Vararg{Symbol}}

The `GraphConstraint` kinds `engine` implements. Every engine answers this, and
answers only kinds it really satisfies in its output.
"""
function supported_constraint_kinds end

supported_constraint_kinds(::GraphLayoutEngine) = ()

"""
    check_constraints(engine, constraints)

Throw an `ArgumentError` naming the first constraint kind `engine` does not
implement, and what it does implement. Every `layout_graph` method calls this
before it places anything.

A caller cannot tell a satisfied pin from an ignored one by looking at the
picture, so an engine must never accept a kind it drops.
"""
function check_constraints(engine::GraphLayoutEngine, constraints)
    supported = supported_constraint_kinds(engine)
    for constraint in constraints
        constraint isa GraphConstraint || throw(ArgumentError(
            "$(nameof(typeof(engine))): a layout constraint must be a " *
            "GraphConstraint, got $(typeof(constraint))."))
        kind = constraint.kind
        kind in supported && continue
        verb = kind in GRAPH_CONSTRAINT_KINDS ? "does not implement" : "does not know"
        throw(ArgumentError(
            "$(nameof(typeof(engine))) $verb the $(repr(kind)) graph constraint. " *
            "It implements " *
            (isempty(supported) ? "no constraint kind" :
             join((repr(k) for k in supported), ", ")) * "."))
    end
    nothing
end

"""
    constraint_pins(constraints) -> Dict{UInt,Tuple{Float64,Float64}}

The `:pin` constraints as `objectid(vertex) => (x, y)`, where `(x, y)` is the
**top-left** corner the vertex is pinned to — the same corner `positions`
reports. Two pins on one vertex: the last one wins.
"""
function constraint_pins(constraints)
    pins = Dict{UInt,Tuple{Float64,Float64}}()
    for constraint in constraints
        constraint.kind === :pin || continue
        payload = constraint.payload
        (payload isa Tuple && length(payload) == 2) || throw(ArgumentError(
            "a :pin constraint's payload must be (x, y), got $(repr(payload))."))
        pins[objectid(constraint.target)] = (Float64(payload[1]), Float64(payload[2]))
    end
    pins
end

"""
    constraint_fixed_sizes(constraints) -> Dict{UInt,Tuple{Float64,Float64}}

The `:fixed_size` constraints as `objectid(vertex) => (w, h)`. A payload of
`nothing` names the vertex without overriding its measured size, which is the
useful form: no engine here ever resizes a vertex, so `:fixed_size` states what
is already true and a caller may state it.
"""
function constraint_fixed_sizes(constraints)
    fixed = Dict{UInt,Tuple{Float64,Float64}}()
    for constraint in constraints
        constraint.kind === :fixed_size || continue
        payload = constraint.payload
        payload === nothing && continue
        (payload isa Tuple && length(payload) == 2) || throw(ArgumentError(
            "a :fixed_size constraint's payload must be (w, h) or nothing, " *
            "got $(repr(payload))."))
        fixed[objectid(constraint.target)] = (Float64(payload[1]), Float64(payload[2]))
    end
    fixed
end

# ── Shared placement helpers ─────────────────────────────────────────────────

"""
    layout_vertices(graph) -> Vector{GraphVertex}

The graph's vertices in the graph's own order. Order is the whole of an engine's
determinism: it seeds every placement and indexes every internal array, so it is
read once, here, and never from a `Dict`.
"""
layout_vertices(graph::GraphGraph) =
    GraphVertex[graph.vertices[i] for i in 1:length(graph.vertices)
                if graph.vertices[i] isa GraphVertex]

"""
    vertex_sizes(vertices, sizes, constraints) -> (widths, heights)

The width and height to place each vertex at, as two `Float64` vectors indexed
like `vertices`. A `:fixed_size` payload overrides the measured size; a vertex
with no entry in `sizes` gets 60 by 30.
"""
function vertex_sizes(vertices, sizes::Dict, constraints)
    fixed = constraint_fixed_sizes(constraints)
    n = length(vertices)
    widths = Vector{Float64}(undef, n)
    heights = Vector{Float64}(undef, n)
    for i in 1:n
        id = objectid(vertices[i])
        w, h = get(fixed, id, get(sizes, id, (60, 30)))
        widths[i] = Float64(w)
        heights[i] = Float64(h)
    end
    (widths, heights)
end

# Border-anchor point on a box (x,y,w,h) toward an external point (tx,ty):
# clamp the line from the box center to (tx,ty) onto the box border.
function _border_point(box, tx::Float64, ty::Float64)
    x, y, w, h = box
    cx = x + w/2; cy = y + h/2
    dx = tx - cx; dy = ty - cy
    (dx == 0 && dy == 0) && return (round(Int, cx), round(Int, cy))
    # Scale so the offset reaches the nearest box edge.
    sx = dx == 0 ? Inf : (w/2) / abs(dx)
    sy = dy == 0 ? Inf : (h/2) / abs(dy)
    s = min(sx, sy)
    (round(Int, cx + dx*s), round(Int, cy + dy*s))
end

"""
    straight_routes(graph, positions) -> Dict{UInt,Vector{Tuple{Int,Int}}}

Route every edge as a straight two-point polyline, from the source box's border
to the target box's border, anchored on the side facing the other box. Every
pure-Julia engine in this package routes this way; obstacle-avoiding routes are
libavoid's job and arrive with `AdaptagramsLayout`.
"""
function straight_routes(graph::GraphGraph, positions::Dict)
    routes = Dict{UInt,Vector{Tuple{Int,Int}}}()
    for i in 1:length(graph.edges)
        edge = graph.edges[i]
        edge isa GraphEdge || continue
        source = getfield(edge, :source)[]
        target = getfield(edge, :target)[]
        source_box = get(positions, objectid(source), nothing)
        target_box = get(positions, objectid(target), nothing)
        (source_box === nothing || target_box === nothing) && continue
        scx = source_box[1] + source_box[3]/2; scy = source_box[2] + source_box[4]/2
        tcx = target_box[1] + target_box[3]/2; tcy = target_box[2] + target_box[4]/2
        routes[objectid(edge)] = Tuple{Int,Int}[_border_point(source_box, tcx, tcy),
                                                _border_point(target_box, scx, scy)]
    end
    routes
end

"""
    extent_transform(cx, cy, widths, heights, indices, extent, border)
        -> (fx, fy, x1, y1, ox, oy) or nothing

The affine that maps the placement of `indices` onto `extent` inset by `border`:
`new_x = ox + (x - x1) * fx`, and the same on y. `nothing` when there is nothing
to map or no room to map it into.

Only centres are mapped; a box keeps the size it was measured at. That is what
OMNeT++ does — `BasicSpringEmbedderLayout::execute` rescales `n.x` and `n.y` and
never `n.sx`, `n.sy` — and it is what makes `:fixed_size` true for every engine
here without any engine doing anything about it.

The two axes scale apart, so a graph asked to fill a wide box becomes wide. That
is also OMNeT++'s behaviour: it computes `xfact` and `yfact` separately.
"""
function extent_transform(cx, cy, widths, heights, indices, extent, border::Real)
    isempty(indices) && return nothing
    available_w = Float64(extent[1]) - 2*border
    available_h = Float64(extent[2]) - 2*border
    (available_w <= 0 || available_h <= 0) && return nothing

    # The centres are scaled, not the boxes, so the room the centres may span is
    # the extent less the widest box: a box reaches at most half of that past its
    # own centre, so every box lands inside.
    x1 = minimum(cx[i] for i in indices); x2 = maximum(cx[i] for i in indices)
    y1 = minimum(cy[i] for i in indices); y2 = maximum(cy[i] for i in indices)
    widest = maximum(widths[i] for i in indices)
    tallest = maximum(heights[i] for i in indices)
    fx = x2 > x1 ? max(0.0, available_w - widest) / (x2 - x1) : 1.0
    fy = y2 > y1 ? max(0.0, available_h - tallest) / (y2 - y1) : 1.0
    (fx, fy, x1, y1, border + widest/2, border + tallest/2)
end

"""
    fit_into_extent!(cx, cy, widths, heights, indices, extent, border) -> transform

Apply [`extent_transform`](@ref) to the centres in place, and return it so a
caller can apply the same map to whatever else lives in those coordinates — a
routed edge, for one.
"""
function fit_into_extent!(cx, cy, widths, heights, indices, extent, border::Real)
    transform = extent_transform(cx, cy, widths, heights, indices, extent, border)
    transform === nothing && return nothing
    fx, fy, x1, y1, ox, oy = transform
    for i in indices
        cx[i] = ox + (cx[i] - x1) * fx
        cy[i] = oy + (cy[i] - y1) * fy
    end
    transform
end

# The engine `deferred_layout_engine` hands out. A package with a better one
# registers a factory here from its `__init__` — a mutation, not a second
# method: replacing a method during precompilation is fatal, and this seam
# exists precisely so an optional package can take over without one.
# `register_file_document_type!` is registered the same way, for the same reason.
const _PREFERRED_ENGINE = Ref{Any}(nothing)

"""
    register_layout_engine!(factory)

Make `factory(; orthogonal)` the engine [`deferred_layout_engine`](@ref) returns.
`ProjecturedAdaptagrams` calls this from its `__init__`, so a native layout
costs a `using` and no rewiring. `nothing` restores the pure-Julia choice.
"""
register_layout_engine!(factory) = (_PREFERRED_ENGINE[] = factory; nothing)

"""
    DeferredLayout(; orthogonal = false)

The engine that decides which engine to be **when the layout runs**, rather than
when the projection is built. That distinction is the whole point: a projection
is usually constructed once at module load — an `Example` builds its projection
in its constructor — which is long before an optional engine package can be
loaded. An engine chosen at construction would be the grid forever.

`orthogonal` is what a caller *asks for*, not an engine it picks. Right-angled
routes are what a flowchart wants — an arrow is read as flow, and a diagonal
between two boxes reads as a relation instead of a direction — while a plain
relationship graph reads better with direct lines. An engine that cannot honour
the request ignores it (every pure-Julia engine here draws straight lines), so
asking is always safe.
"""
struct DeferredLayout <: GraphLayoutEngine
    orthogonal::Bool
end

DeferredLayout(; orthogonal::Bool = false) = DeferredLayout(orthogonal)

"""
    deferred_layout_engine(; orthogonal = false) -> DeferredLayout

The engine a caller names when it has no reason to name a specific one.
"""
deferred_layout_engine(; orthogonal::Bool = false) = DeferredLayout(orthogonal)

"""
    resolved_layout_engine(engine) -> GraphLayoutEngine

What a `DeferredLayout` is right now: the registered engine, or the pure-Julia
choice when nothing has registered. Any other engine is already itself.
"""
resolved_layout_engine(engine::GraphLayoutEngine) = engine

function resolved_layout_engine(engine::DeferredLayout)
    factory = _PREFERRED_ENGINE[]
    factory === nothing ? GridEmbedding() :
                          factory(; orthogonal = engine.orthogonal)
end

supported_constraint_kinds(engine::DeferredLayout) =
    supported_constraint_kinds(resolved_layout_engine(engine))

# Resolution happens per layout call. `GraphGraphToGraphLayout` memoizes on
# topology, sizes and constraints — not on the engine — so a graph already laid
# out keeps its old picture until something about it changes. Loading an engine
# package mid-session is a session-start concern, not a live-editing one.
layout_graph(engine::DeferredLayout, graph::GraphGraph, sizes::Dict,
             constraints::Vector; extent = nothing, border::Real = 0) =
    layout_graph(resolved_layout_engine(engine), graph, sizes, constraints;
                 extent = extent, border = border)

# ── GridEmbedding ────────────────────────────────────────────────────────────

"""
    GridEmbedding(; node_sep=40, rank_sep=60, columns=nothing, direction=:tb,
                  circle_max=12)

Pure-Julia deterministic placement with no simulation at all: vertices go on a
grid (row-major), sized by `sizes`, with `node_sep`/`rank_sep` gaps. Edges are
routed as straight border-to-border polylines. No native dependency and no
iteration count, so every downstream phase is testable and instant.

`columns` fixes the grid width; when `nothing` it defaults to `ceil(sqrt(n))`.
`direction` affects nothing structurally, but is accepted for parity with the
engine interface.

Given an `extent`, the placement is bounded by it instead of growing without
limit: `circle_max` vertices or fewer go on a circle, more go on a grid whose
column count matches the extent's shape, and either way the result is scaled to
fill the extent. Without an `extent` the grid is unbounded, which is what the
caller asked for by naming no box.

It implements `:pin` — a pinned vertex is placed at its coordinate and takes no
grid cell — and `:fixed_size`. It refuses every other kind, because a grid has
nothing to say about them.
"""
struct GridEmbedding <: GraphLayoutEngine
    node_sep::Int
    rank_sep::Int
    columns::Union{Int,Nothing}
    direction::Symbol
    circle_max::Int
end

GridEmbedding(; node_sep::Integer=40, rank_sep::Integer=60,
              columns::Union{Integer,Nothing}=nothing, direction::Symbol=:tb,
              circle_max::Integer=12) =
    GridEmbedding(Int(node_sep), Int(rank_sep),
                  columns === nothing ? nothing : Int(columns), direction,
                  Int(circle_max))

supported_constraint_kinds(::GridEmbedding) = (:pin, :fixed_size)

# How many columns the grid gets. Without an extent it is the caller's `columns`
# or a square grid. With one, it is the count that makes the grid's shape match
# the extent's, from `cols*cell_w / (rows*cell_h) == available_w/available_h`
# with `rows == m/cols`.
function _grid_columns(m, indices, widths, heights, engine::GridEmbedding,
                       extent, border::Real)
    engine.columns === nothing || return max(1, engine.columns)
    extent === nothing && return max(1, ceil(Int, sqrt(m)))
    available_w = Float64(extent[1]) - 2*border
    available_h = Float64(extent[2]) - 2*border
    (available_w <= 0 || available_h <= 0) && return max(1, ceil(Int, sqrt(m)))
    cell_w = sum(widths[i] for i in indices)/m + engine.node_sep
    cell_h = sum(heights[i] for i in indices)/m + engine.rank_sep
    clamp(round(Int, sqrt(m * cell_h * available_w / (cell_w * available_h))), 1, m)
end

# Row-major grid over `indices`, cells sized to the largest member of their
# column and row, each box centred in its cell. Writes centres into cx/cy.
function _place_on_grid!(cx, cy, indices, widths, heights, engine::GridEmbedding,
                         extent, border::Real)
    m = length(indices)
    m == 0 && return nothing
    cols = _grid_columns(m, indices, widths, heights, engine, extent, border)
    rows = ceil(Int, m / cols)

    column_w = fill(0, cols)
    row_h = fill(0, rows)
    for k in 1:m
        i = indices[k]
        c = mod(k - 1, cols) + 1
        r = div(k - 1, cols) + 1
        column_w[c] = max(column_w[c], round(Int, widths[i]))
        row_h[r] = max(row_h[r], round(Int, heights[i]))
    end
    column_x = fill(0, cols)
    for c in 2:cols
        column_x[c] = column_x[c-1] + column_w[c-1] + engine.node_sep
    end
    row_y = fill(0, rows)
    for r in 2:rows
        row_y[r] = row_y[r-1] + row_h[r-1] + engine.rank_sep
    end

    for k in 1:m
        i = indices[k]
        c = mod(k - 1, cols) + 1
        r = div(k - 1, cols) + 1
        w = round(Int, widths[i]); h = round(Int, heights[i])
        cx[i] = column_x[c] + div(column_w[c] - w, 2) + w/2
        cy[i] = row_y[r] + div(row_h[r] - h, 2) + h/2
    end
    nothing
end

# A ring, starting at the top and going clockwise, with a radius that keeps
# neighbours from touching. `fit_into_extent!` then spreads it over the extent,
# so the radius here only has to be big enough, never exactly right.
function _place_on_circle!(cx, cy, indices, widths, heights, engine::GridEmbedding)
    m = length(indices)
    m == 0 && return nothing
    if m == 1
        cx[indices[1]] = 0.0; cy[indices[1]] = 0.0
        return nothing
    end
    chord = maximum(max(widths[i], heights[i]) for i in indices) + engine.node_sep
    radius = chord / (2 * sin(pi / m))
    for k in 1:m
        i = indices[k]
        angle = 2pi * (k - 1) / m - pi/2
        cx[i] = radius * cos(angle)
        cy[i] = radius * sin(angle)
    end
    nothing
end

function layout_graph(engine::GridEmbedding, graph::GraphGraph, sizes::Dict,
                      constraints::Vector; extent = nothing, border::Real = 0)
    check_constraints(engine, constraints)

    vertices = layout_vertices(graph)
    n = length(vertices)
    positions = Dict{UInt,NTuple{4,Int}}()
    n == 0 && return (positions, Dict{UInt,Vector{Tuple{Int,Int}}}())

    widths, heights = vertex_sizes(vertices, sizes, constraints)
    pins = constraint_pins(constraints)
    cx = zeros(Float64, n); cy = zeros(Float64, n)
    free = [i for i in 1:n if !haskey(pins, objectid(vertices[i]))]

    if extent !== nothing && length(free) <= engine.circle_max
        _place_on_circle!(cx, cy, free, widths, heights, engine)
    else
        _place_on_grid!(cx, cy, free, widths, heights, engine, extent, border)
    end
    extent === nothing ||
        fit_into_extent!(cx, cy, widths, heights, free, extent, border)

    # A pin is placed last and verbatim, so no scaling or centring can move it.
    for i in 1:n
        pin = get(pins, objectid(vertices[i]), nothing)
        pin === nothing && continue
        cx[i] = pin[1] + widths[i]/2
        cy[i] = pin[2] + heights[i]/2
    end

    for i in 1:n
        positions[objectid(vertices[i])] =
            (round(Int, cx[i] - widths[i]/2), round(Int, cy[i] - heights[i]/2),
             round(Int, widths[i]), round(Int, heights[i]))
    end

    (positions, straight_routes(graph, positions))
end

# ── AdaptagramsLayout lives in the ProjecturedAdaptagrams package ─────────────
#
# The native engine (`AdaptagramsLayout <: GraphLayoutEngine`, an FFI binding to
# libcola/libavoid through a small C shim) is intentionally *not* defined here:
# it carries an external native dependency that the core domain must not require.
# It is a separate package that adds its own `layout_graph` method behind this
# interface. See `package/adaptagrams/`.

end # module
