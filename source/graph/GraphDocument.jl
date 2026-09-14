"""
    GraphModule

The graph domain: a graph document, the layout that places it, the engines that
compute a layout, the registry that picks one, and the projections that draw the
result.

This file holds the document — vertices with a content `Document` (any domain: a
table, JSON, another graph) and edges connecting vertices by identity, which is
pure semantic structure. `GraphLayout.jl` holds positions and routes, and
`omnetpp/` holds a port of the C++ force-directed layout engine.
"""
module GraphModule

using ..CellModule
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
export GraphDocument
export GraphLayoutDocument
export GraphLayoutEngine, GridEmbedding, layout_graph, layout_engine_name,
       get_supported_constraint_kinds, check_constraints, GRAPH_CONSTRAINT_KINDS,
       get_constraint_pins, get_constraint_fixed_sizes, get_constraint_clusters,
       layout_vertices, get_vertex_sizes,
       get_straight_routes, get_extent_transform, fit_into_extent!
export LcgRandom, draw_uniform01!, draw_uniform!, draw!, set_seed!, run_lcg_self_test
export Pt, Rs, Rc, Ln,
       pt_nil, pt_zero, pt_radial, is_nil, is_zero, is_fully_specified,
       pt_length, pt_length_square, pt_distance, pt_normalize, pt_multiply,
       pt_reverse, convert_nan_to_zero, with_base_plane_projection, get_base_plane_length,
       get_base_plane_squared_length, get_base_plane_distance, get_base_plane_angle,
       rotate_base_plane, transpose_base_plane, with_x, with_y, with_z,
       rs_nil, get_diagonal_length, get_area,
       rc_nil, rc_from_center_size, rc_left, rc_right, rc_top, rc_bottom,
       rc_center, rc_left_top, rc_right_top, rc_left_bottom, rc_right_bottom,
       rc_center_top, rc_center_bottom, rc_left_center, rc_right_center,
       rc_contains, rc_bounding, ln_nil, rc_base_plane_distance,
       rc_base_plane_contains, rc_base_plane_intersects,
       Cc, cc_center_top, cc_center_bottom, cc_left_center, cc_right_center,
       cc_intersect, cc_enclosing
export LayoutVertex, LayoutEdge, GraphComponent,
       add_vertex!, add_edge!, index_of_vertex, find_vertex, get_bounding_rectangle,
       calculate_spanning_tree!, calculate_connected_sub_components!,
       get_vertex_count, get_edge_count
export SpringEmbedderLayout
export ForceDirectedParameters, Variable, PointConstrainedVariable,
       AbstractBody, AbstractForceProvider,
       reinitialize!, apply_forces!, get_potential_energy, get_class_name, set_embedding!,
       get_position, assign_position!, get_velocity, assign_velocity!,
       get_acceleration, get_kinetic_energy, reset_force!, get_mass, set_mass!,
       get_force, add_force!, subtract_force!,
       get_body_position, get_body_size, get_body_mass, get_body_charge, get_body_variable,
       get_body_left, get_body_right, get_body_top, get_body_bottom, get_body_left_top
export Body, RelativelyPositionedBody, WallBody, set_wall_position!, set_wall_variable!,
       ForceProviderConfig, AbstractElectricRepulsion, ElectricRepulsion,
       VerticalElectricRepulsion, HorizontalElectricRepulsion,
       AbstractSpring, Spring, VerticalSpring, HorizontalSpring,
       LeastExpandedSpring, BasePlaneSpring, Drag,
       get_spring_repose_length, get_spring_distance_and_vector
export ForceDirectedEmbedding, default_force_directed_parameters,
       add_body!, add_force_provider!, embed!, get_embedding_bounding_rectangle,
       total_kinetic_energy, total_potential_energy
export StarTreeEmbedding, embed_star_tree!
export HeapEmbedding, embed_heap!
export ForceDirectedLayout
export DeferredLayout, make_deferred_layout_engine, register_layout_engine!,
       resolve_layout_engine, make_pure_julia_layout_engine, QTENV_ADVANCED_LIMIT
using ..ProjectionModule
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..IntentModule
using ..GraphicsModule
using ..IoMapModule
export GraphGraphToGraphLayout, GraphToGraphLayout, GraphGraphToGraphLayoutIoMap
using ..StyleModule
using ..OperationModule
using ..EventModule
export GraphLayoutToGraphicsCanvas, GraphLayoutToGraphics, GraphToGraphics,
       GraphLayoutToGraphicsCanvasIoMap
using ..ProjectionAlgebraModule
using ..NaturalModule
export GraphGraph, GraphVertex, GraphEdge, GraphConstraint, GraphLayout, VertexLayout, EdgeLayout




abstract type GraphDocument <: Document end

"""
A placeholder for graph content being entered (the insert-by-typing cursor).
"""
@document struct GraphInsertion <: GraphDocument
    value::Any = nothing
end

"""
A vertex whose `content` is an arbitrary `Document`. Identity = the object
itself, so an edge can point at it (same identity model as `TableCell.content`).
"""
@document struct GraphVertex <: GraphDocument
    content::Any          # required: keeps the 1-arg `GraphVertex(content)` ctor
                          # (macro Rule Y needs req≥1; all-defaulted would drop it)
end

"""
An edge from `source` to `target` (both `GraphVertex`, held by identity).
`directed` draws an end arrowhead; `label` is an optional content document.
"""
@document struct GraphEdge <: GraphDocument
    source::Document
    target::Document
    directed::Bool = true
    label::Any = nothing
end

# Mixed positional+keyword form the macro can't generate (source/target are
# positional; directed/label are keywords). Typed args keep it distinct from the
# macro's Rule Y `GraphEdge(source, target)`.
function GraphEdge(source::GraphVertex, target::GraphVertex;
                   directed::Bool=true, label=nothing)
    GraphEdge(Cell(source), Cell(target), Cell(directed), Cell(label), Cell(nothing))
end

"""
A graph: `CellVector` of `GraphVertex` + `CellVector` of `GraphEdge`. Because a
vertex's `content` is arbitrary, a vertex may hold another `GraphGraph` for free.

`highlight_vertex` / `highlight_edge` name one vertex and one edge to draw
emphasized — a ring around the node, a thickened stroke on the edge. They are
**presentation state, not content**: a producer wires them as derived cells over
whatever it is tracking (a running state machine's current state, a search hit),
and they flow through `GraphLayout` to the renderer without touching a vertex's
`content` — which is what keeps a highlight change from invalidating the
measured sizes and re-running the whole layout. Both hold the referent by
identity, like an edge's endpoints; a `VertexLayout` is rebuilt on every layout
recompute and must never be held here.
"""
@document struct GraphGraph <: GraphDocument
    vertices::CellVector = CellVector()
    edges::CellVector = CellVector()
    highlight_vertex::Any = nothing
    highlight_edge::Any = nothing
end

# Two-CellVector convenience: Rule C only covers a single CellVector, so this
# Vector→CellVector form is not macro-generated.
function GraphGraph(vertices::Vector, edges::Vector)
    GraphGraph(CellVector(Cell[v isa Cell ? v : Cell(v) for v in vertices]),
               CellVector(Cell[e isa Cell ? e : Cell(e) for e in edges]),
               Cell(nothing), Cell(nothing), Cell(nothing))
end


include("GraphLayout.jl")
include("GraphLayoutEngine.jl")
include("omnetpp/LcgRandom.jl")
include("omnetpp/LayoutGeometry.jl")
include("omnetpp/GraphComponent.jl")
include("omnetpp/BasicSpringEmbedderLayout.jl")
include("omnetpp/ForceDirectedParametersBase.jl")
include("omnetpp/ForceDirectedParameters.jl")
include("omnetpp/ForceDirectedEmbedding.jl")
include("omnetpp/StarTreeEmbedding.jl")
include("omnetpp/HeapEmbedding.jl")
include("omnetpp/ForceDirectedGraphLayouter.jl")
include("GraphLayoutChoice.jl")
include("GraphToGraphLayout.jl")
include("GraphLayoutToGraphics.jl")

end # module
