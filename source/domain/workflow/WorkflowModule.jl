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

include("WorkflowDocument.jl")

end # module
