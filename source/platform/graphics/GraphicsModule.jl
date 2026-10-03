"""
    GraphicsModule

The `PointReferenceStep` step type — a reference step that identifies a point
within an element by pixel coordinates relative to that element's origin.
Lives with the graphics slice because pixel coordinates are the graphics
domain's own vocabulary; the kernel reference layer never names it.

Registered as a `:terminal` step type (identifies a location but does not
descend), and registers its own `.point(x, y)` entries with the kernel
`@reference` / `@reference_case` DSLs via the reference layer's
`build_reference_step` / `match_reference_step` seams.
"""
module GraphicsModule

using ..CellModule
using ..CellStructModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export PointReferenceStep, RegionReferenceStep, find_reference_point, find_reference_box,
       find_node_reference
export compute_part_at_point, is_outward_gesture, read_child_part_gesture,
       read_container_gesture, read_child_move, read_child_leave, get_child_frame_offset,
       read_routed_child_in_frame, read_routed_entry_child
export GraphicsDocument, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
       set_cell_computation!, hit_element_at, get_graphics_size, tessellate_spline, build_polyline_arrowhead,
       is_point_near_polyline, is_point_in_polygon
export GraphicsCanvasToGraphicsImage, GraphicsCaching, GraphicsToGraphics
export is_infinite_canvas, compute_first_visible_index, has_declared_extent
export GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsViewport
export ContentBounds, get_content_box, extend_content_bounds!, extend_canvas_bounds!,
       extend_element_bounds!, get_canvas_content_bounds
export make_selection_ring
export GraphicsTheme, ScaledGraphicsTheme
export POINTER_SHAPES, find_pointer_shape
export map_operation_position, shift_operation_position, shift_event_position, map_event_position
export FaultToGraphics


include("PointReferenceStep.jl")
include("RegionReferenceStep.jl")
include("GraphicsDocument.jl")
include("PointerShape.jl")
include("GraphicsCaching.jl")
include("GraphicsToGraphics.jl")
include("GraphicsTheme.jl")
include("FaultToGraphics.jl")
include("SelectionRing.jl")
include("OperationPosition.jl")
include("EventPosition.jl")
include("ChildMove.jl")
include("ReferenceBox.jl")

end # module
