"""
    GraphLayoutEngineModule

A swappable interface for graph placement + edge routing. The native binding
(Adaptagrams: libcola for placement, libavoid for routing) is one seam behind
this interface; until that build lands, `FallbackLayoutEngine` (pure Julia) is
the default so nothing downstream is blocked.

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

export GraphLayoutEngine, FallbackLayoutEngine, AdaptagramsEngine, layout_graph

abstract type GraphLayoutEngine end

"""
    layout_graph(engine, graph, sizes, constraints) -> (positions, routes)

Place the vertices and route the edges of `graph`. See module docs for the shapes.
"""
function layout_graph end

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

# ── AdaptagramsEngine (stub) ─────────────────────────────────────────────────

"""
    AdaptagramsEngine()

TODO (Phase 9): FFI binding to Adaptagrams — libcola for constraint-honouring
node placement and libavoid for obstacle-avoiding connector routing, bridged via
`ccall` (the established pattern in `Sdl.jl`). Blocked on a native dependency:
there is no Adaptagrams JLL yet, so either an `Adaptagrams_jll` (BinaryBuilder) or
a small `extern "C"` C shim must land first. Until then this constructor exists
behind the same interface but `layout_graph` is unimplemented; use
`FallbackLayoutEngine`.
"""
struct AdaptagramsEngine <: GraphLayoutEngine end

function layout_graph(::AdaptagramsEngine, graph::GraphGraph, sizes::Dict, constraints::Vector)
    error("AdaptagramsEngine is not yet implemented (no Adaptagrams JLL / C shim). " *
          "Use FallbackLayoutEngine. See plan/pending/graph-domain.md Phase 4/9.")
end

end # module
