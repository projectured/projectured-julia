export AdaptagramsLayout

# ── Native shim location ─────────────────────────────────────────────────────
# A *deterministic* path, not a generated deps.jl. Earlier we `include`d a
# build-time deps.jl, but that is a precompile-staleness trap: if the module is
# first loaded before `Pkg.build` (deps.jl absent), the empty path is baked into
# the precompile image and the later-created deps.jl — never an `include`
# dependency — does not invalidate it, so the shim stays "unavailable" even after
# building and restarting. The shim always lives at this fixed location, so the
# compiled-in value is correct regardless of build state; whether it has actually
# been built is a *runtime* check (`isavailable`). Building the .so is then picked
# up with no stale cache and without a restart.
const libadaptagrams_shim =
    joinpath(@__DIR__, "..", "..", "package", "ProjecturedAdaptagrams", "deps",
             "libadaptagrams_shim." * Libdl.dlext)

"`true` when the native shim is built and actually loadable (the shim and its
libcola/libavoid/libvpsc dependencies resolve at runtime). Re-checks the
filesystem on each call, so a freshly-built shim is seen without a restart."
isavailable() =
    isfile(libadaptagrams_shim) &&
    Libdl.dlopen(libadaptagrams_shim; throw_error = false) !== nothing

# Said once per session, not once per layout. An unbuilt shim used to error on
# every layout, which stopped whatever was drawing rather than drawing it, and a
# fresh checkout has no shim. Warning once and drawing with a pure-Julia engine
# is the useful answer, and the layout records which engine really ran, so
# nothing is silent about it.
const _WARNED_UNAVAILABLE = Ref(false)

function _warn_unavailable_once()
    _WARNED_UNAVAILABLE[] && return nothing
    _WARNED_UNAVAILABLE[] = true
    @warn """
    AdaptagramsLayout: the native shim is not built, so this session draws
    graphs with the pure-Julia layouters instead. To build it, run
        using Pkg; Pkg.build("ProjecturedAdaptagrams")
    after installing or building Adaptagrams (set ADAPTAGRAMS_DIR to its cola/
    directory, or put its .pc files on PKG_CONFIG_PATH).
    See package/adaptagrams/README.md."""
    nothing
end

# ── AdaptagramsLayout ────────────────────────────────────────────────────────

# Auto node-margin policy (AdaptagramsLayout `node_margin=nothing`): the hard
# minimum inter-box gap scales with the typical node size, floored so small
# graphs keep a sensible constant margin.
const _MARGIN_FRACTION = 0.2
const _MIN_NODE_MARGIN = 16.0

"""
    AdaptagramsLayout(; ideal_length=60.0, avoid_overlaps=true, orthogonal=false,
                      node_margin=nothing)

Native `GraphLayoutEngine`: libcola placement + libavoid routing.

- `ideal_length`   the **size-independent base gap** between connected boxes.
  The effective ideal edge length is computed *per edge* as
  `ideal_length + half_extent(source) + half_extent(target)` (with
  `half_extent = max(w, h) / 2`), so big card-sized nodes are spread apart in
  proportion to their size instead of being packed nearly on top of each other
  by a single fixed length. Passed to libcola as per-edge multipliers of
  `ideal_length`.
- `avoid_overlaps` libcola prevents node-box overlaps when `true` (a hard
  guarantee via `makeFeasible`, not just the soft force-directed term).
- `orthogonal`     libavoid orthogonal routes when `true`, else poly-line.
- `node_margin`    the hard minimum gap kept on each side of every node during
  overlap removal (so the boxes still clear each other once
  `GraphLayoutToGraphics` pads them, `_PAD` = 8 per side); also the inset of the
  layout from the origin. Pass `nothing` (the default) to derive it from the
  vertex sizes — like `ideal_length`, a fixed margin leaves big card nodes nearly
  touching, so the auto value scales with the typical node size
  (`$(Int(round(100*_MARGIN_FRACTION)))%` of the mean half-extent, floored at
  `$(Int(_MIN_NODE_MARGIN))px`). Pass a number to force a fixed margin.

Returns the same `(positions, routes)` shape as `GridEmbedding`:
`positions[objectid(vertex)] = (x,y,w,h)::NTuple{4,Int}` and
`routes[objectid(edge)] = Vector{Tuple{Int,Int}}`.
"""
struct AdaptagramsLayout <: GraphLayoutEngine
    ideal_length::Float64
    avoid_overlaps::Bool
    orthogonal::Bool
    node_margin::Union{Nothing,Float64}   # nothing ⇒ size-derived (see layout_graph)
end

AdaptagramsLayout(; ideal_length::Real=60.0, avoid_overlaps::Bool=true,
                  orthogonal::Bool=false, node_margin::Union{Nothing,Real}=nothing) =
    AdaptagramsLayout(Float64(ideal_length), avoid_overlaps, orthogonal,
                      node_margin === nothing ? nothing : Float64(node_margin))

"""
    supported_constraint_kinds(::AdaptagramsLayout)

`:pin` and `:fixed_size`. The shim's `adaptagrams_layout` takes no constraint
argument, so a pin is imposed on the way out rather than fed to libcola: the
native run arranges the graph as if the vertex were free, and the vertex is then
placed where it was pinned. The contract holds — the vertex is where the caller
asked — but the neighbours were placed without knowing it. Teaching libcola
about pins means a wider C ABI, and that is not this plan's work.
"""
supported_constraint_kinds(::AdaptagramsLayout) = (:pin, :fixed_size)

"""
    effective_engine(engine, vertex_count) -> GraphLayoutEngine

`engine` when the shim is built, and the pure-Julia engine for a graph of this
size when it is not. Both `layout_graph` and `layout_engine_name` ask, so the
name a layout reports is always the engine that really placed it.
"""
function effective_engine(engine::AdaptagramsLayout, vertex_count::Integer)
    isavailable() && return engine
    _warn_unavailable_once()
    pure_julia_layout_engine(vertex_count; orthogonal = engine.orthogonal)
end

# Asking what this engine resolves to is asking what will really place the
# graph, so an unbuilt shim resolves to the engine that will. Both the name a
# layout records and the answer a caller gets go through here, and they agree
# because they ask the same question with the same vertex count.
resolved_layout_engine(engine::AdaptagramsLayout, vertex_count::Integer = 0) =
    effective_engine(engine, vertex_count)

layout_engine_name(engine::AdaptagramsLayout) =
    isavailable() ? :adaptagrams : layout_engine_name(effective_engine(engine, 0))

function layout_graph(engine::AdaptagramsLayout, graph::GraphGraph, sizes::Dict,
                      constraints::Vector; extent = nothing, border::Real = 0)
    check_constraints(engine, constraints)

    # Nothing to do here when the shim is absent: hand the whole call to whatever
    # can actually draw it.
    standing_in = effective_engine(engine, length(layout_vertices(graph)))
    standing_in === engine ||
        return layout_graph(standing_in, graph, sizes, constraints;
                            extent = extent, border = border)

    positions = Dict{UInt,NTuple{4,Int}}()
    routes = Dict{UInt,Vector{Tuple{Int,Int}}}()

    # Ordered node list + objectid → 0-based index map (the shim's index space).
    nodes = GraphVertex[]
    index = Dict{UInt,Int}()
    for i in 1:length(graph.vertices)
        v = graph.vertices[i]
        v isa GraphVertex || continue
        index[objectid(v)] = length(nodes)   # 0-based
        push!(nodes, v)
    end
    n = length(nodes)
    n == 0 && return (positions, routes)

    widths, heights = vertex_sizes(nodes, sizes, constraints)
    in_w = Vector{Cdouble}(undef, n)
    in_h = Vector{Cdouble}(undef, n)
    for i in 1:n
        in_w[i] = Cdouble(widths[i]); in_h[i] = Cdouble(heights[i])
    end

    # Edges with both endpoints present, aligned to the route index space. For
    # each edge also compute a per-edge ideal-length *multiplier* of
    # `ideal_length`, so the effective ideal length grows with the endpoint node
    # sizes: a fixed length packs large boxes nearly on top of each other (their
    # centres want to sit `ideal_length` apart, far less than the boxes' own
    # extent), leaving the connectors invisible. The target centre-to-centre
    # distance is `ideal_length` (a base gap) plus each endpoint's half-extent
    # (`max(w, h) / 2`), so connected boxes clear each other by ~`ideal_length`
    # regardless of orientation. The multiplier divides that by `ideal_length`
    # since libcola's effective length is `ideal_length * eLengths[i]`.
    base = engine.ideal_length > 0 ? engine.ideal_length : 60.0
    half_extent(i) = max(in_w[i], in_h[i]) / 2          # i is 1-based into in_w/in_h

    # Hard minimum inter-box gap. A fixed margin (the old 16px) leaves big card
    # nodes nearly touching, so when `node_margin` is left unset derive it from
    # the typical node size — a fraction of the mean half-extent, floored so small
    # graphs keep a sensible constant gap. An explicit `node_margin` overrides.
    node_margin = engine.node_margin
    if node_margin === nothing
        mean_half = sum(half_extent(i) for i in 1:n) / n
        node_margin = max(_MIN_NODE_MARGIN, _MARGIN_FRACTION * mean_half)
    end

    edge_objs = GraphEdge[]
    esrc = Cint[]; edst = Cint[]; elen = Cdouble[]
    for i in 1:length(graph.edges)
        e = graph.edges[i]
        e isa GraphEdge || continue
        s = getfield(e, :source)[]; t = getfield(e, :target)[]
        si = get(index, objectid(s), -1); ti = get(index, objectid(t), -1)
        (si < 0 || ti < 0) && continue
        push!(edge_objs, e); push!(esrc, Cint(si)); push!(edst, Cint(ti))
        target = base + half_extent(si + 1) + half_extent(ti + 1)
        push!(elen, Cdouble(target / base))
    end
    ne = length(edge_objs)

    handle = ccall((:adaptagrams_layout, libadaptagrams_shim), Ptr{Cvoid},
                   (Cint, Ptr{Cdouble}, Ptr{Cdouble}, Cint, Ptr{Cint}, Ptr{Cint},
                    Cdouble, Cint, Cint, Cdouble, Ptr{Cdouble}),
                   Cint(n), in_w, in_h, Cint(ne), esrc, edst,
                   engine.ideal_length, Cint(engine.avoid_overlaps),
                   Cint(engine.orthogonal), node_margin, elen)
    handle == C_NULL && error("AdaptagramsLayout: native layout failed (see adaptagrams_shim.cpp).")

    try
        rx = Ref{Cdouble}(0.0); ry = Ref{Cdouble}(0.0)
        rw = Ref{Cdouble}(0.0); rh = Ref{Cdouble}(0.0)
        for i in 1:n
            ccall((:adaptagrams_node_box, libadaptagrams_shim), Cvoid,
                  (Ptr{Cvoid}, Cint, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
                  handle, Cint(i - 1), rx, ry, rw, rh)
            positions[objectid(nodes[i])] =
                (round(Int, rx[]), round(Int, ry[]), round(Int, rw[]), round(Int, rh[]))
        end

        px = Ref{Cdouble}(0.0); py = Ref{Cdouble}(0.0)
        for e in 1:ne
            m = ccall((:adaptagrams_route_size, libadaptagrams_shim), Cint,
                      (Ptr{Cvoid}, Cint), handle, Cint(e - 1))
            pts = Tuple{Int,Int}[]
            for k in 1:m
                ccall((:adaptagrams_route_point, libadaptagrams_shim), Cvoid,
                      (Ptr{Cvoid}, Cint, Cint, Ptr{Cdouble}, Ptr{Cdouble}),
                      handle, Cint(e - 1), Cint(k - 1), px, py)
                push!(pts, (round(Int, px[]), round(Int, py[])))
            end
            routes[objectid(edge_objs[e])] = pts
        end
    finally
        ccall((:adaptagrams_free, libadaptagrams_shim), Cvoid, (Ptr{Cvoid},), handle)
    end

    _fit_and_pin!(positions, routes, nodes, widths, heights, constraints,
                  extent, border)
    (positions, routes)
end

# The extent and the pins, applied to what the native run answered. The extent
# maps positions *and* routed points, because libavoid's waypoints live in the
# same coordinates as the boxes and a route left behind would miss its own
# endpoints. A pin is imposed last, so nothing moves it afterwards.
function _fit_and_pin!(positions, routes, nodes, widths, heights, constraints,
                       extent, border)
    n = length(nodes)
    if extent !== nothing && n > 0
        cx = Vector{Float64}(undef, n); cy = Vector{Float64}(undef, n)
        for i in 1:n
            x, y, w, h = positions[objectid(nodes[i])]
            cx[i] = x + w/2; cy[i] = y + h/2
        end
        transform = extent_transform(cx, cy, widths, heights, 1:n, extent, border)
        if transform !== nothing
            fx, fy, x1, y1, ox, oy = transform
            map_x(x) = ox + (x - x1) * fx
            map_y(y) = oy + (y - y1) * fy
            for i in 1:n
                x, y, w, h = positions[objectid(nodes[i])]
                positions[objectid(nodes[i])] =
                    (round(Int, map_x(x + w/2) - w/2), round(Int, map_y(y + h/2) - h/2), w, h)
            end
            for (id, points) in routes
                routes[id] = Tuple{Int,Int}[(round(Int, map_x(p[1])), round(Int, map_y(p[2])))
                                            for p in points]
            end
        end
    end

    pins = constraint_pins(constraints)
    isempty(pins) && return nothing
    for i in 1:n
        pin = get(pins, objectid(nodes[i]), nothing)
        pin === nothing && continue
        _, _, w, h = positions[objectid(nodes[i])]
        positions[objectid(nodes[i])] = (round(Int, pin[1]), round(Int, pin[2]), w, h)
    end
    nothing
end

# ── The default engine, once this package is loaded ──────────────────────────
#
# Registering is the whole opt-in: anything that asks for
# `deferred_layout_engine()` — an example, a workbench page, a live diagram —
# gets native placement and routing from the moment this package is in the
# session, with nothing else rewired. Done from `__init__` so the mutation
# survives precompilation; defining a second method instead would be a
# precompile-fatal overwrite.

function __init__()
    register_layout_engine!((; orthogonal::Bool = false) ->
                                AdaptagramsLayout(orthogonal = orthogonal))
end
