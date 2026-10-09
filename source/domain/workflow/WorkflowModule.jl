"""
    WorkflowModule

The workflow document domain: the record of a piece of human work. A workflow is
an AND/OR tree. A step holds its sub-steps, which all belong to it; a decision
holds its options, of which one is chosen. Each node keeps a dated journal and
cards that show documents of any domain.

The domain includes:
- **The tree**: `WorkflowStep`, `WorkflowDecision`, `WorkflowOption`
- **The record**: `WorkflowEntry`, `WorkflowCard`
- **A view**: `WorkflowJournal`, the entries of a whole tree as a table
"""
module WorkflowModule

import Dates

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward

export WorkflowDocument, WorkflowStep, WorkflowDecision, WorkflowOption, WorkflowEntry, WorkflowCard, WorkflowJournal
export WORKFLOW_STEP_STATES, WORKFLOW_OPTION_STATES, WORKFLOW_ENTRY_KINDS, WORKFLOW_ENTRY_AUTHORS
export format_workflow_time, get_workflow_time, find_workflow_time, get_workflow_states,
       is_workflow_node, get_workflow_node_title, get_workflow_node_children
export make_workflow_entry, make_workflow_decision, get_next_workflow_state,
       make_add_workflow_entry_operation, make_workflow_state_operation,
       make_insert_workflow_node_operation, make_delete_workflow_node_operation,
       make_add_workflow_card_operation, make_delete_workflow_card_operation,
       make_choose_workflow_option_operation, collect_workflow_entries
export WorkflowTheme, ScaledWorkflowTheme
export WorkflowNodeToWidget, WorkflowEntryToWidget, WorkflowCardToWidget, WorkflowJournalToWidget,
       WorkflowToWidgetIoMap,
       make_workflow_projections, make_workflow_graphics_entries
export WORKFLOW_ASSISTANT_API
export record_workflow_decision!, choose_workflow_option!, reject_workflow_option!,
       add_workflow_entry!, add_workflow_step!, change_workflow_state!, add_workflow_card!

include("WorkflowDocument.jl")
include("WorkflowEdits.jl")
include("WorkflowTheme.jl")
include("WorkflowToWidget.jl")
include("WorkflowJournalToWidget.jl")

function __init__()
    # The rows that let the renderer draw a workflow, and a node, an entry or a
    # card of one inside any other document.
    register_natural_graphics!(:workflow, make_workflow_graphics_entries)

    # What the model of an assistant may write about a workflow: the documents,
    # the verbs that record the work as the assistant, and the read of a journal.
    # Each verb is an edit of the editor, which a person takes back with Ctrl+Z.
    register_assistant_api!(WorkflowModule => WORKFLOW_ASSISTANT_API)
end

end # module
