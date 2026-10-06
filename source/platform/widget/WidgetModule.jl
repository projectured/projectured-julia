"""
    WidgetModule

The widget document domain. Widgets are UI-layer documents that sit above
the graphics domain and below application-specific projections. Each widget
type subtypes the abstract WidgetDocument base (itself a Document) and
carries reactive Cell fields for all mutable properties.
"""
module WidgetModule

using ..CellModule
using ..ClockModule
using ..CollectionModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..EventModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..DomainModule
using ..PrimitiveModule
using ..SerializationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..SelectionModule
using ..StyleModule
using ..TextModule
using ..TooltipModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default
import ..DocumentModule: has_document_duplicate, get_wrapped_document, get_edited_field,
                         get_document_title
import ..DomainModule: compute_context_menu
import ..SerializationModule: pred_arguments
import ..GestureBindingModule: get_instance_gesture_bindings, get_document_gesture_bindings_own
import ..GraphicsModule: map_operation_position, find_first_baseline
import ..OperationModule: evaluate_operation, is_self_contained_operation,
                          is_collecting_operation, join_collected_operations,
                          operation_reference, retarget_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SelectionModule: has_dormant_selection

export Inset, Point2D, WidgetDocument, WidgetToolButton, WidgetMessageBox, WidgetInputDialog,
       WidgetTreeNode, CloseTabOperation, OpenTabOperation,
       DragTabOperation, DuplicateTabOperation, StartSplitterDragOperation, ResizeSplitPaneOperation,
       EndSplitterDragOperation, SetTableColumnWidthOperation, CommitTableCellOperation,
       DropTableCellOperation, EditTableCellOperation, read_table_column_drag, Shortcut,
       matches_action_shortcut,
       InvokeActionOperation, resolve_action,
       make_numeric_validator, evaluate_operation, inset_default, inset_size,
       inset_width, inset_height, inset_top_left, inset_top_right, inset_bottom_left,
       inset_bottom_right, set_cell_computation!, make_pager_widget, make_filter_bar_widget, make_column_chooser_widget,
       make_widget_list_selection, get_widget_list_selected,
       make_widget_table_row_selection, get_widget_table_selected_row, get_widget_table_column_count, get_widget_table_row_count,
       resolve_toggle_group_write, resolve_slider_write
export WidgetInsertionToGraphicsCanvas, WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
       WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
       WidgetTooltipToGraphicsCanvas, WidgetContextMenuToGraphicsCanvas,
       WidgetContextMenuToGraphicsCanvasIoMap,
       WidgetDialogToGraphicsCanvas, WidgetDialogToGraphicsCanvasIoMap,
       WidgetMenuToGraphicsCanvas,
       WidgetMenuItemToGraphicsCanvas, WidgetToolbarItemToGraphicsCanvas,
       WidgetCompositeToGraphicsCanvas,
       WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
       WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
       WidgetHighlightToGraphicsCanvas,
       WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
       WidgetTransformPaneToGraphicsCanvas, WidgetTransformPaneToGraphicsCanvasIoMap,
       WidgetToolbarToGraphicsCanvas, WidgetStatusBarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas,
       WidgetToGraphics, WidgetTheme, ScaledWidgetTheme, make_widget_theme,
       WidgetSelectToGraphicsCanvas, WidgetSelectToGraphicsCanvasIoMap,
       WidgetToggleGroupToGraphicsCanvas, WidgetToggleGroupToGraphicsCanvasIoMap,
       WidgetSliderToGraphicsCanvasIoMap,
       WidgetSpinBoxToGraphicsCanvas, WidgetSpinBoxToGraphicsCanvasIoMap,
       WidgetListToGraphicsCanvas, WidgetListToGraphicsCanvasIoMap,
       WidgetOptionToGraphicsCanvas,
       register_icon!, make_glyph_icon, make_image_icon, find_icon_character
export ObjectToWidget, ObjectToWidgetIoMap
export ObjectFieldToWidget, ObjectFieldToWidgetIoMap
export CellTableToWidgetTable
export WidgetTableListIoMap, make_widget_table_row
export compute_scroll_bar_value, compute_scroll_bar_top_row, read_scroll_bar_drag, make_owned_scroll_bar_drag
export make_embed_card, make_embed_card_path, find_embed_card_path_inside
export ProjectionConfiguringProjection, ProjectionConfiguringIoMap
export OpenContextMenuOperation, EditMenuPartOperation, make_context_menu_operation, make_context_menu_binding
export ContextMenuWindowProjection, ContextMenuWindowIoMap,
       make_context_menu_window_document, make_context_menu_window_projection,
       wrap_context_menu_window
export make_value_document, make_graphics_projection, collect_graphics_projection_types,
       refresh_document!
export WidgetInsertion, WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton, WidgetTooltip, WidgetContextMenu, WidgetDialog, WidgetMenu, WidgetMenuItem, WidgetToolbarItem, WidgetComposite, WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane, WidgetTabPage, WidgetTabLabel, WidgetHighlight, WidgetScrollPane, WidgetTransformPane, WidgetToolbar, WidgetStatusBar, WidgetScrollBar, WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgressBar, WidgetProgressRing, WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton, WidgetSwatch, WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetOption, WidgetTextarea, WidgetAccordion, WidgetSpinBox, WidgetList, WidgetTable, WidgetTableRows, WidgetTableRow, WidgetTableColumns, WidgetTableColumn, WidgetTree, Action, compute_code_pieces
export WidgetStyle, WidgetCheckboxStyle, WidgetDialogStyle, WidgetTitlePaneStyle, WidgetSplitPaneStyle,
       WidgetTabbedPaneStyle, WidgetScrollBarStyle, WidgetBadgeStyle, WidgetSeparatorStyle, WidgetCardStyle,
       WidgetAlertStyle, WidgetHighlightStyle, WidgetSwitchStyle, WidgetProgressStyle, WidgetSliderStyle,
       WidgetRadioGroupStyle, WidgetToggleStyle, WidgetToggleGroupStyle, WidgetSelectStyle, WidgetSpinBoxStyle,
       WidgetListStyle, WidgetAccordionStyle, WidgetTableStyle, WidgetTreeStyle
export FaultToWidget


include("WidgetDocument.jl")
include("WidgetStyle.jl")
include("WidgetTheme.jl")
include("WidgetToGraphics.jl")
include("FaultToWidget.jl")
include("WidgetTableParts.jl")
include("WidgetTableHeaderLevels.jl")
include("WidgetEmbedCard.jl")
include("ObjectToWidget.jl")
include("ObjectFieldToWidget.jl")
include("CellTableToWidgetTable.jl")
include("ProjectionConfiguring.jl")
include("ContextMenuOperation.jl")
include("ContextMenuWindow.jl")
include("DocumentComposition.jl")

end # module
