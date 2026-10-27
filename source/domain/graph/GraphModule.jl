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

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
    get_child_iomaps, read_child_by_route
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..DisplayModule: make_workload_file

export GraphDocument
export GraphLayoutDocument
export GraphLayoutEngine, GridEmbedding, layout_graph, layout_engine_name,
       get_supported_constraint_kinds, check_constraints, GRAPH_CONSTRAINT_KINDS,
       get_constraint_pins, get_constraint_starts, get_constraint_fixed_sizes,
       get_constraint_clusters,
       layout_vertices, get_vertex_sizes,
       get_straight_routes, get_extent_transform, fit_into_extent!
export FruchtermanReingoldLayout
export DeferredLayout, make_deferred_layout_engine, register_layout_engine!,
       resolve_layout_engine, make_pure_julia_layout_engine
export GraphGraphToGraphLayout, GraphToGraphLayout, GraphGraphToGraphLayoutIoMap
export GraphTheme, ScaledGraphTheme
export GraphLayoutToGraphicsCanvas, GraphToGraphics,
       GraphLayoutToGraphicsCanvasIoMap
export GraphGraphToWidgetScrollPane, GraphGraphToWidgetScrollPaneIoMap,
       make_scrolling_graph_projection
export GraphGraph, GraphVertex, GraphEdge, GraphConstraint, GraphLayout, VertexLayout, EdgeLayout


include("GraphDocument.jl")
include("GraphLayout.jl")
include("GraphLayoutEngine.jl")
include("FruchtermanReingoldLayout.jl")
include("GraphLayoutChoice.jl")
include("GraphToGraphLayout.jl")
include("GraphTheme.jl")
include("GraphLayoutToGraphics.jl")
include("GraphToWidgetScrollPane.jl")

# The file that a workload of the window opens (`run_file_workload`).
function make_workload_file(::Type{GraphGraph})
    first, second = GraphVertex(PrimitiveString("alpha")), GraphVertex(PrimitiveString("beta"))
    (; name = "a.pred",
     text = print_pred_text(GraphGraph([first, second], [GraphEdge(first, second; directed = true)])),
     shown = r"alpha")
end

end # module
