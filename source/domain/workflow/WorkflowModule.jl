"""
    WorkflowModule

The workflow document domain: the record of a piece of human work. A workflow is
an AND/OR tree. A step holds its sub-steps, which all belong to it; a decision
holds its options, of which one is chosen. Each node keeps a dated journal and
cards that show documents of any domain.

The domain includes:
- **The tree**: `WorkflowStep`, `WorkflowDecision`, `WorkflowOption`
- **The record**: `WorkflowEntry`, `WorkflowCard`
"""
module WorkflowModule

import Dates

using ..KernelModule
using ..PlatformModule

export WorkflowDocument, WorkflowStep, WorkflowDecision, WorkflowOption, WorkflowEntry, WorkflowCard
export WORKFLOW_STEP_STATES, WORKFLOW_OPTION_STATES, WORKFLOW_ENTRY_KINDS, WORKFLOW_ENTRY_AUTHORS
export format_workflow_time, get_workflow_time, find_workflow_time, get_workflow_states,
       is_workflow_node, get_workflow_node_title, get_workflow_node_children
export make_workflow_entry, make_workflow_decision, get_next_workflow_state,
       make_add_workflow_entry_operation, make_workflow_state_operation,
       make_insert_workflow_node_operation, make_delete_workflow_node_operation,
       make_add_workflow_card_operation, make_delete_workflow_card_operation,
       make_choose_workflow_option_operation, collect_workflow_entries
export record_workflow_decision!, choose_workflow_option!, reject_workflow_option!,
       add_workflow_entry!, add_workflow_step!, change_workflow_state!, add_workflow_card!

include("WorkflowDocument.jl")
include("WorkflowEdits.jl")

end # module
