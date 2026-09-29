"""
    GraphModule

The graph domain: a graph document, the layout that places it, the engines that
compute a layout, the registry that picks one, and the projections that draw the
result.

This file holds the document — vertices with a content `Document` (any domain: a
table, JSON, another graph) and edges connecting vertices by identity, which is
pure semantic structure. `GraphLayout.jl` holds positions and routes, and
`FruchtermanReingoldLayout.jl` holds the force-directed engine of this package.
"""
module GraphModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export GraphDocument
export GraphLayoutDocument
export GraphLayoutEngine, GridEmbedding, layout_graph, layout_engine_name,
       get_supported_constraint_kinds, check_constraints, GRAPH_CONSTRAINT_KINDS,
       get_constraint_pins, get_constraint_fixed_sizes, get_constraint_clusters,
       layout_vertices, get_vertex_sizes,
       get_straight_routes, get_extent_transform, fit_into_extent!
export FruchtermanReingoldLayout
export DeferredLayout, make_deferred_layout_engine, register_layout_engine!,
       resolve_layout_engine, make_pure_julia_layout_engine
export GraphGraphToGraphLayout, GraphToGraphLayout, GraphGraphToGraphLayoutIoMap
export GraphLayoutToGraphicsCanvas, GraphToGraphics,
       GraphLayoutToGraphicsCanvasIoMap
export GraphGraph, GraphVertex, GraphEdge, GraphConstraint, GraphLayout, VertexLayout, EdgeLayout


include("GraphDocument.jl")
include("GraphLayout.jl")
include("GraphLayoutEngine.jl")
include("FruchtermanReingoldLayout.jl")
include("GraphLayoutChoice.jl")
include("GraphToGraphLayout.jl")
include("GraphLayoutToGraphics.jl")

end # module
