"""
    ProjecturedAdaptagrams

The native graph-layout engine for ProjecturEd: an `AdaptagramsEngine` that places
vertices with **libcola** (constraint-based force-directed layout) and routes
edges with **libavoid** (obstacle-avoiding connectors), bridged through a small
`extern "C"` shim (`deps/adaptagrams_shim.cpp`) via `ccall`.

This lives in its own package, separate from `ProjecturedDomain`, precisely
because it carries an external native dependency (the Adaptagrams C++ libraries).
`ProjecturedDomain` only defines the `GraphLayoutEngine` interface and the
pure-Julia `FallbackLayoutEngine`; this package adds an `AdaptagramsEngine`
method to `layout_graph` behind that same interface, so nothing in core depends
on Adaptagrams being installed.

## Building

The shim is compiled by `deps/build.jl` against an installed/built Adaptagrams:

    using Pkg; Pkg.build("ProjecturedAdaptagrams")

Point `ADAPTAGRAMS_DIR` at the `cola/` directory of an Adaptagrams checkout, or
install it so its `.pc` files are on `PKG_CONFIG_PATH`. Until the shim is built,
`AdaptagramsEngine` loads but errors at use with build guidance; use
`FallbackLayoutEngine` in the meantime.

## Use

    using ProjecturedExample, ProjecturedAdaptagrams
    proj = make_graph_projection_example(engine = AdaptagramsEngine())
"""
module ProjecturedAdaptagrams

import ProjecturedDomain.GraphLayoutEngineModule: GraphLayoutEngine, layout_graph
import ProjecturedDomain.GraphModule: GraphGraph, GraphVertex, GraphEdge
import Libdl

export AdaptagramsEngine

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
    joinpath(@__DIR__, "..", "deps", "libadaptagrams_shim." * Libdl.dlext)

"`true` when the native shim is built and actually loadable (the shim and its
libcola/libavoid/libvpsc dependencies resolve at runtime). Re-checks the
filesystem on each call, so a freshly-built shim is seen without a restart."
isavailable() =
    isfile(libadaptagrams_shim) &&
    Libdl.dlopen(libadaptagrams_shim; throw_error = false) !== nothing

function _unavailable_error()
    error("""
    AdaptagramsEngine: the native shim is not built. Run
        using Pkg; Pkg.build("ProjecturedAdaptagrams")
    after installing/building Adaptagrams (set ADAPTAGRAMS_DIR to its cola/ dir,
    or put its .pc files on PKG_CONFIG_PATH). Use FallbackLayoutEngine until then.
    See package/adaptagrams/README.md.""")
end

# ── AdaptagramsEngine ────────────────────────────────────────────────────────

"""
    AdaptagramsEngine(; ideal_length=60.0, avoid_overlaps=true, orthogonal=false,
                      node_margin=16.0)

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
- `node_margin`    gap kept on each side of every node during overlap removal, so
  the boxes still clear each other once `GraphLayoutToGraphics` pads them
  (`_PAD` = 8 per side); also the inset of the layout from the origin. Must
  exceed that pad to leave a visible gap.

Returns the same `(positions, routes)` shape as `FallbackLayoutEngine`:
`positions[objectid(vertex)] = (x,y,w,h)::NTuple{4,Int}` and
`routes[objectid(edge)] = Vector{Tuple{Int,Int}}`.
"""
struct AdaptagramsEngine <: GraphLayoutEngine
    ideal_length::Float64
    avoid_overlaps::Bool
    orthogonal::Bool
    node_margin::Float64
end

AdaptagramsEngine(; ideal_length::Real=60.0, avoid_overlaps::Bool=true,
                  orthogonal::Bool=false, node_margin::Real=16.0) =
    AdaptagramsEngine(Float64(ideal_length), avoid_overlaps, orthogonal,
                      Float64(node_margin))

function layout_graph(engine::AdaptagramsEngine, graph::GraphGraph, sizes::Dict,
                      constraints::Vector)
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

    isavailable() || _unavailable_error()

    in_w = Vector{Cdouble}(undef, n)
    in_h = Vector{Cdouble}(undef, n)
    for i in 1:n
        w, h = get(sizes, objectid(nodes[i]), (60, 30))
        in_w[i] = Cdouble(w); in_h[i] = Cdouble(h)
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
                   Cint(engine.orthogonal), engine.node_margin, elen)
    handle == C_NULL && error("AdaptagramsEngine: native layout failed (see adaptagrams_shim.cpp).")

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

    (positions, routes)
end

end # module ProjecturedAdaptagrams
