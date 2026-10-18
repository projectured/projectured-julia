"""
    TreeModule

A document of any type shown as a tree of its parts: the `DocumentTree`, the
three generics that say how a document is a node of a tree, and the projection
that shows a tree as one `WidgetTree`. A node is a document, its children are
the documents of one or more of its collections, and the tree keeps its open
nodes by the identity of their documents, so a node stays open when another one
comes before it. Each slice that owns a kind of node adds its own methods of the
generics, so this module names none of them.
"""
module TreeModule

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..RosterModule
using ..ScreenModule
using ..SerializationModule
using ..StyleModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: acquire_document!, release_document!
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments, make_pred_document
import ..WidgetModule: make_graphics_projection

export get_tree_children_steps, format_tree_node_label, has_tree_children,
       demand_tree_children, is_explorer_entry_type
export DocumentTree, collect_open_tree_documents
export DocumentTreeToWidgetTree, DocumentTreeToWidgetTreeIoMap, collect_tree_children, collect_read_tree_children
export show_document_tree!

include("TreeInterface.jl")
include("TreeDefaults.jl")
include("TreeDocument.jl")
include("DocumentTreeToWidgetTree.jl")
include("TreeProgram.jl")

end # module
