# Fragment of `GraphModule`.
#
# Which engine a caller gets when it names none, and when that is decided.
#
# `DeferredLayout` decides **when the layout runs**, not when the projection is
# built. With nothing registered it is `FruchtermanReingoldLayout`. A package
# with an engine of its own registers a factory and takes over; the factory may
# answer an engine that decides by the size of the graph, which is why the
# vertex count travels with the choice.
#
# This module sits above the engines rather than beside the interface, because
# choosing between them means naming them.
"""
The vertex count at which the choice turns from the advanced layouter to the
fast one. It is `LIMIT` in `ModuleLayouter::getSubmodulePositions`, and the
comment there says why it is 20: at thirty or forty modules the advanced
layouter is already very slow.
"""
const ADVANCED_LAYOUT_LIMIT = 20

# The engine `make_deferred_layout_engine` hands out. A package with a better one
# registers a factory here from its `__init__` — a mutation, not a second
# method: replacing a method during precompilation is fatal, and this seam
# exists precisely so an optional package can take over without one.
# `register_file_document_type!` is registered the same way, for the same reason.
const _PREFERRED_ENGINE = Ref{Any}(nothing)

"""
    register_layout_engine!(factory)

Make `factory(; orthogonal)` the engine [`make_deferred_layout_engine`](@ref) returns.
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
    make_deferred_layout_engine(; orthogonal = false) -> DeferredLayout

The engine a caller names when it has no reason to name a specific one.
"""
make_deferred_layout_engine(; orthogonal::Bool = false) = DeferredLayout(orthogonal)

"""
    make_pure_julia_layout_engine(vertex_count; orthogonal = false) -> GraphLayoutEngine

The engine to use for a graph of this size when nothing is installed:
[`FruchtermanReingoldLayout`](@ref), for every size.

`orthogonal` is accepted and ignored, because it routes edges as straight lines.
"""
make_pure_julia_layout_engine(::Integer; orthogonal::Bool = false) = FruchtermanReingoldLayout()

"""
    resolve_layout_engine(engine[, vertex_count]) -> GraphLayoutEngine

What a `DeferredLayout` is right now: the registered engine, or the pure-Julia
choice for a graph of `vertex_count` vertices. Any other engine is already
itself.

Without a count it answers the choice for an empty graph, which is what a caller
asking "what would I get?" outside a layout means.
"""
resolve_layout_engine(engine::GraphLayoutEngine, ::Integer = 0) = engine

function resolve_layout_engine(engine::DeferredLayout, vertex_count::Integer = 0)
    factory = _PREFERRED_ENGINE[]
    factory === nothing ?
        make_pure_julia_layout_engine(vertex_count; orthogonal = engine.orthogonal) :
        factory(; orthogonal = engine.orthogonal)
end

get_supported_constraint_kinds(engine::DeferredLayout) =
    get_supported_constraint_kinds(resolve_layout_engine(engine))

layout_engine_name(engine::DeferredLayout) =
    layout_engine_name(resolve_layout_engine(engine))

# Resolution happens per layout call, and reads the vertex count, so an engine
# that a package registered can draw a small graph and a large one differently.
#
# `GraphGraphToGraphLayout` memoizes on topology, sizes and constraints — not on
# the engine — so a graph already laid out keeps its old picture until something
# about it changes. Loading an engine package mid-session is a session-start
# concern, not a live-editing one.
layout_graph(engine::DeferredLayout, graph::GraphGraph, sizes::Dict,
             constraints::Vector; extent = nothing, border::Real = 0) =
    layout_graph(resolve_layout_engine(engine, length(layout_vertices(graph))),
                 graph, sizes, constraints; extent = extent, border = border)
