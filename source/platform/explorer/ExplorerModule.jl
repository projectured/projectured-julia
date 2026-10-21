"""
    ExplorerModule

The explorer: one place to find and look at what the editor holds. An
`ExplorerSection` is a list of entries that a person controls, and an entry is any
document: a folder, the task list of the editor, a project, another section. An
`Explorer` shows one root section as a tree, and beside the tree a navigator that
shows the page of the node that a person presses. A press on a node shows its page
beside the tree, Ctrl+press opens the page in a new tab, and a double press or
Return puts the keyboard in the page. Each editor has one root section, which
every explorer of its window shows.
"""
module ExplorerModule

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..EventModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureHelpModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NavigatorModule
using ..OperationModule
using ..PaneModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..SelectionModule
using ..StyleModule
using ..TaskModule
using ..ToolModule
using ..TooltipModule
using ..TreeModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, has_document_duplicate, copy_document, is_walk_opaque
import ..DomainModule: acquire_document!, release_document!, accepts_opened_file,
                       get_insertion_aliases, make_insertion_document, get_document_decoration
import ..GestureHelpModule: collect_part_commands
import ..NavigatorModule: find_navigator_address
import ..OperationModule: evaluate_operation, make_inverse_operation, describe_operation, is_self_contained_operation
import ..SerializationModule: pred_arguments, make_pred_document
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..TreeModule: get_tree_children_steps, format_tree_node_label, is_explorer_entry_type
import ..TaskModule: get_work_item_identifier, describe_work_item_kind, stop_work_item!, describe_work_item
import ..WidgetModule: make_graphics_projection

export ExplorerFilter
export ExplorerSection, Explorer, get_session_explorer_content, find_explorer_content, open_explorer_page!
export ExplorerToWidget
export ExplorerSectionToWidget
export ExplorerSearch, StartExplorerSearchOperation
export ExplorerSearchToWidget
export DashboardCard, Dashboard
export DashboardToWidget
export get_explorer_content_file, save_explorer_content!, load_explorer_content

include("ExplorerFilter.jl")
include("ExplorerDocument.jl")
include("ExplorerToWidget.jl")
include("ExplorerSectionToWidget.jl")
include("ExplorerSearch.jl")
include("ExplorerSearchToWidget.jl")
include("Dashboard.jl")
include("DashboardToWidget.jl")
include("ExplorerRowMenu.jl")
include("ExplorerEntryEdits.jl")
include("ExplorerContentFile.jl")

end # module
