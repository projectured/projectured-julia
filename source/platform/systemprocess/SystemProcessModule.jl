"""
    SystemProcessModule

The processes of the system as documents. A pure read of `/proc` answers plain
records of the processes under a set of roots; a `SystemProcessTree` keeps one
`SystemProcess` for each, by its process id and its start ticks, and a sync on
the editor task writes only the cells that changed. The read runs on a task of
its own, once in an interval and only while a view reads the tree, and the
owner of a tree drains it from a feed that its window already has. A tree draws
as a tree, a process as a page of its facts with Interrupt and Stop, and a
roster lists the processes of a tree as rows.

`SystemProcessRead.jl` reads `/proc`, `SystemProcessDocument.jl` holds the two
documents, their nodes in a tree and the facets of a process,
`SystemProcessSignal.jl` sends a signal to a process that is still the one the
document shows, `SystemProcessSync.jl` brings a read into the documents and
holds the feed, `SystemProcessTreeToDocumentTree.jl` and
`SystemProcessToWidget.jl` draw a tree and a process, `SystemProcessRoster.jl`
is the source of a roster, and `SystemProcessProgram.jl` holds the verbs of code
and of a model. Only Linux has `/proc`; on another system a read answers no
process.
"""
module SystemProcessModule

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..FeedModule
using ..FocusModule
using ..GraphicsModule
using ..IoMapModule
using ..LayoutModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..RosterModule
using ..StyleModule
using ..ToolModule
using ..TooltipModule
using ..TreeModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, is_walk_opaque
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward
import ..RosterModule: collect_roster_parts, collect_roster_items, get_roster_item_type,
                       get_item_facets, compute_item_facet
import ..TreeModule: get_tree_children_steps, format_tree_node_label
import ..WidgetModule: make_graphics_projection

import ..DomainModule: get_document_decoration
import ..SerializationModule: pred_arguments, make_pred_document
export SystemProcessRecord, read_system_processes, read_system_process_usage,
       get_clock_ticks_per_second
export format_memory_size
export interrupt_system_process!, stop_system_process!
export sync_system_process_tree!, drain_system_process_tree!,
       compute_system_process_tree_deadline, SystemProcessFeed
export SystemProcessTreeToDocumentTree, SystemProcessTreeToDocumentTreeIoMap
export SystemProcesses
export show_system_process_tree!, describe_system_process_tree

include("SystemProcessRead.jl")
include("SystemProcessDocument.jl")
include("SystemProcessSignal.jl")
include("SystemProcessSync.jl")
include("SystemProcessTreeToDocumentTree.jl")
include("SystemProcessToWidget.jl")
include("SystemProcessRoster.jl")
include("SystemProcessProgram.jl")

end # module
