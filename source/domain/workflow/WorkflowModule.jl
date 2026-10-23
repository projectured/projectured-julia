"""
    WorkflowModule

The workflow document domain: the record of a piece of human work. A workflow is
an AND/OR tree. A step holds its sub-steps, which all belong to it; a decision
holds its options, of which one is chosen. Each node keeps a dated journal and
the documents of any domain that the work needs, as its elements.

The domain includes:
- **The tree**: `WorkflowStep`, `WorkflowDecision`, `WorkflowOption`
- **The record**: `WorkflowEntry`
- **The views**: `WorkflowJournal`, the entries of a whole tree as a table, and
  `WorkflowCatalog`, the workflows of a folder
"""
module WorkflowModule

import Dates

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..DocumentModule: get_document_title, get_view_state_fields
import ..DomainModule: make_pasted_document_operation, get_insertion_aliases, make_insertion_document
import ..TreeModule: is_explorer_entry_type
import ..OperationModule: evaluate_operation, make_inverse_operation, is_self_contained_operation

export WorkflowDocument, WorkflowStep, WorkflowDecision, WorkflowOption, WorkflowEntry,
       WorkflowJournal, WorkflowCatalog, WORKFLOW_STEP_STATES, WORKFLOW_OPTION_STATES,
       WORKFLOW_ENTRY_KINDS, WORKFLOW_ENTRY_AUTHORS, format_workflow_time, get_workflow_time,
       find_workflow_time, get_workflow_states, is_workflow_node, get_workflow_node_title,
       get_workflow_node_children
export make_add_workflow_entry_operation, make_workflow_entry, make_workflow_state_operation,
       get_next_workflow_state, make_insert_workflow_node_operation, make_delete_workflow_node_operation,
       make_workflow_decision,
       make_choose_workflow_option_operation, WORKFLOW_ASSISTANT_API, record_workflow_decision!,
       choose_workflow_option!, reject_workflow_option!, add_workflow_entry!, add_workflow_step!,
       change_workflow_state!, collect_workflow_entries
export WorkflowTheme, ScaledWorkflowTheme
export WorkflowNodeToWidget, WorkflowEntryToWidget, make_workflow_projections,
       make_workflow_graphics_entries, WorkflowToWidgetIoMap
export WorkflowJournalToWidget
export WorkflowCatalogToWidget, collect_workflow_files, create_workflow_file!, CreateWorkflowFileOperation

include("WorkflowDocument.jl")
include("WorkflowEdits.jl")
include("WorkflowTheme.jl")
include("WorkflowToWidget.jl")
include("WorkflowJournalToWidget.jl")
include("WorkflowCatalogToWidget.jl")

function __init__()
    # The rows that let the renderer draw a workflow, and a node or an entry of one
    # inside any other document.
    register_natural_graphics!(:workflow, make_workflow_graphics_entries)

    # What the model of an assistant may write about a workflow: the documents,
    # the verbs that record the work as the assistant, and the read of a journal.
    # Each verb is an edit of the editor, which a person takes back with Ctrl+Z.
    register_assistant_api!(WorkflowModule => WORKFLOW_ASSISTANT_API;
        description = "A workflow records the work as steps, decisions and elements: " *
                      "`add_workflow_step!` and `record_workflow_decision!` add to it, " *
                      "`add_element!` adds a document of any domain to a node, and " *
                      "`collect_workflow_entries` reads its journal.")
end

end # module
