"""
    GraphModule

The graph domain: a graph document, the layout that places it, the engines that
compute a layout, the registry that picks one, and the projections that draw the
result.

This file holds the document — vertices with a content `Document` (any domain: a
table, JSON, another graph) and edges connecting vertices by identity, which is
pure semantic structure. `GraphLayout.jl` holds positions and routes, and
`cpp/` holds a port of the C++ force-directed layout engine.
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
       resolve_layout_engine, make_pure_julia_layout_engine, ADVANCED_LAYOUT_LIMIT
export GraphGraphToGraphLayout, GraphToGraphLayout, GraphGraphToGraphLayoutIoMap
export GraphLayoutToGraphicsCanvas, GraphLayoutToGraphics, GraphToGraphics,
       GraphLayoutToGraphicsCanvasIoMap
export GraphGraph, GraphVertex, GraphEdge, GraphConstraint, GraphLayout, VertexLayout, EdgeLayout


include("GraphDocument.jl")
include("GraphLayout.jl")
include("GraphLayoutEngine.jl")
include("cpp/LcgRandom.jl")
include("cpp/LayoutGeometry.jl")
include("cpp/GraphComponent.jl")
include("cpp/BasicSpringEmbedderLayout.jl")
include("cpp/ForceDirectedParametersBase.jl")
include("cpp/ForceDirectedParameters.jl")
include("cpp/ForceDirectedEmbedding.jl")
include("cpp/StarTreeEmbedding.jl")
include("cpp/HeapEmbedding.jl")
include("cpp/ForceDirectedGraphLayouter.jl")
include("GraphLayoutChoice.jl")
include("GraphToGraphLayout.jl")
include("GraphLayoutToGraphics.jl")

end # module
