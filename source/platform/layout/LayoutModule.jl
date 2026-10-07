"""
    LayoutModule

Generic, content-driven layout documents. Each layout type holds an
ordered `children::CellVector` of arbitrary `Document`s and a few
axis-specific knobs (alignment, gap, max extent). Layouts are *not*
tied to widgets — children can be any document type that has a
projection to `GraphicsCanvas`.

Layouts have no `position`/`size` of their own; their projected
canvas is intrinsic (computed from the children's `w`/`h` cells).
A parent that needs to place a layout positions the outer canvas
the layout produces.
"""
module LayoutModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..EventModule
using ..FocusModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: has_document_duplicate
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export LayoutDocument, FormLayout, LayoutExpr, make_layout_anchor, constrain, allocate_axis,
       compute_axis_offsets, find_axis_band, compute_axis_extents, layout_min,
       layout_max, layout_preferred, get_column_span, layout_weight,
       SizePolicy, Fixed, Content, Relative, Fill,
       AnchoredEntry, AnchoredLayout, compute_anchored_positions,
       ScrollLayout, SCROLL_LAYOUT_PARTS, compute_scroll_layout_extents,
       get_scroll_layout_place, find_scroll_layout_part_at
export SolverAnchor, SolverRelation, ConstraintSolver, FallbackConstraintSolver,
       solve_constraint_layout
export HorizontalLayoutToGraphicsCanvas, VerticalLayoutToGraphicsCanvas,
       GridLayoutToGraphicsCanvas, FlowLayoutToGraphicsCanvas,
       StackLayoutToGraphicsCanvas, LayoutConstraintToGraphicsCanvas,
       ConstraintLayoutToGraphicsCanvas, AnchoredLayoutToGraphicsCanvas,
       ScrollLayoutToGraphicsCanvas, LayoutToGraphics, GridLayoutIoMap, LayoutListIoMap, GridLayoutListIoMap,
       get_grid_list_head, find_grid_list_row, get_grid_list_column_head, find_grid_list_cell
export CellVectorToVerticalLayout
export HorizontalLayout, VerticalLayout, GridLayout, FlowLayout, StackLayout
export descend_reference_forward, make_slot_reference, clip_child_to_slot, make_cross_axis_context
export read_child_event, make_layout_selection_ring


include("LayoutDocument.jl")
include("ConstraintSolver.jl")
include("LayoutToGraphics.jl")
include("LayoutList.jl")
include("GridList.jl")
include("GridColumnList.jl")
include("CollectionToLayout.jl")

end # module
