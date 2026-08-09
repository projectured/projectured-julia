"""
    GraphLayoutEngineModule

A swappable interface for graph placement + edge routing. `FallbackLayoutEngine`
(pure Julia) is the default so nothing downstream is blocked. The native binding
(Adaptagrams: libcola for placement, libavoid for routing) lives in its own
package, `ProjecturedAdaptagrams`, because it pulls in an external native
dependency — it adds an `AdaptagramsEngine <: GraphLayoutEngine` method to
`layout_graph` behind this same interface. Core domain code never depends on it.

Interface:

```julia
layout_graph(engine, graph, sizes, constraints) -> (positions, routes)
```

where
- `graph`        is a `GraphGraph`,
- `sizes`        maps each `GraphVertex` (by `objectid`) to `(w, h)`,
- `constraints`  is a vector of `GraphConstraint`,
- `positions`    maps each `GraphVertex` (by `objectid`) to `(x, y, w, h)`,
- `routes`       maps each `GraphEdge` (by `objectid`) to `Vector{Tuple{Int,Int}}`.

Keying on `objectid` keeps the engine call pure of any reactive cell, so the
projection can memoize it on topology + sizes + constraints.
"""
module GraphLayoutEngineModule

import ..GraphModule: GraphGraph, GraphVertex, GraphEdge
import ..GraphLayoutModule: GraphConstraint

export GraphLayoutEngine, FallbackLayoutEngine, DefaultLayoutEngine, layout_graph,
       default_layout_engine, register_layout_engine!, resolved_layout_engine

abstract type GraphLayoutEngine end

"""
    layout_graph(engine, graph, sizes, constraints) -> (positions, routes)

Place the vertices and route the edges of `graph`. See module docs for the shapes.
"""
function layout_graph end

# The engine `default_layout_engine` hands out. A package with a better one
# registers a factory here from its `__init__` — a mutation, not a second
# method: replacing a method during precompilation is fatal, and this seam
# exists precisely so an optional package can take over without one.
# `register_file_document_type!` is registered the same way, for the same reason.
const _PREFERRED_ENGINE = Ref{Any}(nothing)

"""
    register_layout_engine!(factory)

Make `factory(; orthogonal)` the engine [`default_layout_engine`](@ref) returns.
`ProjecturedAdaptagrams` calls this from its `__init__`, so a native layout
costs a `using` and no rewiring. `nothing` restores the fallback.
"""
register_layout_engine!(factory) = (_PREFERRED_ENGINE[] = factory; nothing)

"""
    DefaultLayoutEngine(; orthogonal = false)

The engine that decides which engine to be **when the layout runs**, rather than
when the projection is built. That distinction is the whole point: a projection
is usually constructed once at module load — an `Example` builds its projection
in its constructor — which is long before an optional engine package can be
loaded. An engine chosen at construction would be the fallback forever.

`orthogonal` is what a caller *asks for*, not an engine it picks. Right-angled
routes are what a flowchart wants — an arrow is read as flow, and a diagonal
between two boxes reads as a relation instead of a direction — while a plain
relationship graph reads better with direct lines. An engine that cannot honour
the request ignores it (the fallback draws straight lines either way), so asking
is always safe.
"""
struct DefaultLayoutEngine <: GraphLayoutEngine
    orthogonal::Bool
end

DefaultLayoutEngine(; orthogonal::Bool = false) = DefaultLayoutEngine(orthogonal)

"""
    default_layout_engine(; orthogonal = false) -> DefaultLayoutEngine

The engine a caller names when it has no reason to name a specific one.
"""
default_layout_engine(; orthogonal::Bool = false) = DefaultLayoutEngine(orthogonal)

"""
    resolved_layout_engine(engine) -> GraphLayoutEngine

What a `DefaultLayoutEngine` is right now: the registered engine, or the
fallback when nothing has registered. Any other engine is already itself.
"""
resolved_layout_engine(engine::GraphLayoutEngine) = engine

function resolved_layout_engine(engine::DefaultLayoutEngine)
    factory = _PREFERRED_ENGINE[]
    factory === nothing ? FallbackLayoutEngine() :
                          factory(; orthogonal = engine.orthogonal)
end

# Resolution happens per layout call. `GraphGraphToGraphLayout` memoizes on
# topology, sizes and constraints — not on the engine — so a graph already laid
# out keeps its old picture until something about it changes. Loading an engine
# package mid-session is a session-start concern, not a live-editing one.
layout_graph(engine::DefaultLayoutEngine, graph::GraphGraph, sizes::Dict,
             constraints::Vector) =
    layout_graph(resolved_layout_engine(engine), graph, sizes, constraints)

# ── FallbackLayoutEngine ─────────────────────────────────────────────────────

"""
    FallbackLayoutEngine(; node_sep=40, rank_sep=60, columns=nothing, direction=:tb)

Pure-Julia deterministic placement: vertices are laid out on a simple grid
(row-major), sized by `sizes`, with `node_sep`/`rank_sep` gaps. Edges are routed
as straight two-point polylines from the source box's border to the target box's
border (anchored on the side facing the other box). No native dependency, so
every downstream phase is testable.

`columns` fixes the grid width; when `nothing` it defaults to `ceil(sqrt(n))`.
`direction` only affects nothing structurally in v1 (the grid is the same), but
is accepted for parity with the engine interface.
"""
struct FallbackLayoutEngine <: GraphLayoutEngine
    node_sep::Int
    rank_sep::Int
    columns::Union{Int,Nothing}
    direction::Symbol
end

FallbackLayoutEngine(; node_sep::Integer=40, rank_sep::Integer=60,
                     columns::Union{Integer,Nothing}=nothing, direction::Symbol=:tb) =
    FallbackLayoutEngine(Int(node_sep), Int(rank_sep),
                         columns === nothing ? nothing : Int(columns), direction)

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

function layout_graph(engine::FallbackLayoutEngine, graph::GraphGraph, sizes::Dict,
                      constraints::Vector)
    vertices = [graph.vertices[i] for i in 1:length(graph.vertices)]
    n = length(vertices)
    positions = Dict{UInt,NTuple{4,Int}}()
    n == 0 && return (positions, Dict{UInt,Vector{Tuple{Int,Int}}}())

    cols = engine.columns === nothing ? max(1, ceil(Int, sqrt(n))) : max(1, engine.columns)
    rows = ceil(Int, n / cols)

    # Column widths / row heights from the per-vertex sizes (grid cells sized to
    # the largest member, like GridLayout).
    col_w = fill(0, cols)
    row_h = fill(0, rows)
    for i in 1:n
        w, h = get(sizes, objectid(vertices[i]), (60, 30))
        c = mod(i - 1, cols) + 1
        r = div(i - 1, cols) + 1
        col_w[c] = max(col_w[c], Int(w))
        row_h[r] = max(row_h[r], Int(h))
    end
    col_x = fill(0, cols)
    for c in 2:cols
        col_x[c] = col_x[c-1] + col_w[c-1] + engine.node_sep
    end
    row_y = fill(0, rows)
    for r in 2:rows
        row_y[r] = row_y[r-1] + row_h[r-1] + engine.rank_sep
    end

    for i in 1:n
        v = vertices[i]
        w, h = get(sizes, objectid(v), (60, 30))
        c = mod(i - 1, cols) + 1
        r = div(i - 1, cols) + 1
        # Center each vertex within its grid cell.
        x = col_x[c] + div(col_w[c] - Int(w), 2)
        y = row_y[r] + div(row_h[r] - Int(h), 2)
        positions[objectid(v)] = (x, y, Int(w), Int(h))
    end

    # Route edges as straight border-to-border polylines.
    routes = Dict{UInt,Vector{Tuple{Int,Int}}}()
    for i in 1:length(graph.edges)
        edge = graph.edges[i]
        src = getfield(edge, :source)[]
        tgt = getfield(edge, :target)[]
        sb = get(positions, objectid(src), nothing)
        tb = get(positions, objectid(tgt), nothing)
        (sb === nothing || tb === nothing) && continue
        scx = sb[1] + sb[3]/2; scy = sb[2] + sb[4]/2
        tcx = tb[1] + tb[3]/2; tcy = tb[2] + tb[4]/2
        p1 = _border_point(sb, tcx, tcy)
        p2 = _border_point(tb, scx, scy)
        routes[objectid(edge)] = Tuple{Int,Int}[p1, p2]
    end

    (positions, routes)
end

# ── AdaptagramsEngine lives in the ProjecturedAdaptagrams package ─────────────
#
# The native engine (`AdaptagramsEngine <: GraphLayoutEngine`, an FFI binding to
# libcola/libavoid through a small C shim) is intentionally *not* defined here:
# it carries an external native dependency that the core domain must not require.
# It is a separate package that adds its own `layout_graph` method behind this
# interface. See `package/adaptagrams/` and plan/pending/graph-domain.md Phase 4/9.

end # module
