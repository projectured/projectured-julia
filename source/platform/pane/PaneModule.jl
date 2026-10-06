"""
    PaneModule

The **pane tree** — a layout of tab groups and splits, and the generic way to
organize documents on the screen.

A pane tree has four node kinds:

  * [`PaneTab`](@ref)   — a title and a content document.
  * [`PaneGroup`](@ref) — a tab group: an ordered list of tabs.
  * [`PaneSplit`](@ref) — an orientation, two or more children, and one weight
    per child.
  * [`PaneTree`](@ref)  — the root, plus the transient drag state.

**Focus is the selection.** No node carries a focus or an active-tab field. The
tree's selection names the focused tab (`root.elements[2].tabs[3]`), and each
node's own injected `selection` names the part of it that is on that path — so
the tab a group shows is the tab its own selection names. Every focus move and
every tab switch is one `ReplaceSelectionOperation`.

**Vertical and horizontal.** A `:vertical` split has a vertical divider, so its
children sit side by side; a `:horizontal` split stacks them. The symbol
`WidgetSplitPane` takes names the opposite thing — the axis the children lay out
along — and `PaneToWidget` is the one place that translates.

The tree edits live in `PaneSurgery.jl`, and they build generic operations; this
slice declares no operation of its own.
"""
module PaneModule

using ..CellModule
using ..ClipboardModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..DraggingModule
using ..EditorModule
using ..EventModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..ScreenModule
using ..SerializationModule
using ..StyleModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SelectionModule: has_dormant_selection
import ..ClipboardModule: find_clipboard_document
import ..DomainModule: accepts_pasted_replacement
import ..DocumentModule: get_document_title, get_edited_field
import ..SerializationModule: pred_arguments, make_pred_document
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default
import ..ScreenModule: show_document!
import ..OperationModule: find_drop_zone

export make_tabs_projection
export PaneDocument, PaneTree, PaneSplit, PaneGroup, PaneTab, PaneTabTitle,
       make_pane_tab_title, get_pane_tab_title_string, default_new_pane_tab,
       get_opposite_pane_orientation, get_pane_split_axis,
       get_pane_weight, get_pane_weights, get_pane_normalized_weights,
       get_pane_groups, get_pane_parent
export get_pane_path, get_pane_collection_path,
       get_pane_focus, get_pane_focus_title, find_pane_content_selection, get_pane_focused_group,
       get_pane_focused_tab_index,
       get_pane_shown_tab_index,
       get_pane_tab_reference, make_pane_focus_operation,
       get_pane_tab_name_path, get_pane_content_path, make_pane_title_caret_operation, make_pane_retarget_title_operation,
       make_pane_open_tab_operation, make_pane_close_tab_operation, make_pane_split_operation,
       make_pane_duplicate_tab_operation,
       make_pane_move_tab_operation, make_pane_drop_split_operation, make_pane_resize_operation,
       apply_pane_operation!
export get_pane_rectangles, get_pane_rectangle, get_pane_neighbour_group, get_pane_next_group,
       get_pane_group_at_point, get_pane_drop_zone, get_pane_zone_orientation
export show_layout, get_referenced_value, replace_referenced_value!,
       open_pane!, make_open_pane_operation, focus_pane!, make_focus_pane_operation,
       close_pane!, make_close_pane_operation, duplicate_pane!, make_duplicate_pane_operation,
       move_pane!, make_move_pane_operation, is_layout_line,
       find_pane, find_pane_reference, find_pane_tree_reference, is_pane_search_step,
       post_pane_operation!,
       get_window_tree, describe_document,
       pane_group_to_avoid, make_pane_api, make_interface_api
export PaneTreeToWidget, PaneTreeToWidgetIoMap,
       PaneSplitToWidgetSplitPane, PaneSplitToWidgetSplitPaneIoMap,
       PaneGroupToWidgetTabbedPane, PaneGroupToWidgetTabbedPaneIoMap,
       PaneToWidget
export save_user_interface, load_user_interface
export get_pane_file_group


include("PaneDocument.jl")
include("PaneSurgery.jl")
include("PaneGeometry.jl")
include("PaneProgram.jl")
include("PaneGestures.jl")
include("PaneToWidget.jl")
include("UserInterfaceFile.jl")
include("PaneFile.jl")
include("PaneTabsWrapper.jl")


end # module
