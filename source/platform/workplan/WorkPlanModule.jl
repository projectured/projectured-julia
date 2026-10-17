"""
    WorkPlanModule

The plan of an agent as documents. A `WorkPlan` holds one of three contents: its
steps, a Markdown text, or the address of a file. A `WorkPlanStep` has a status,
the ids of the steps that it waits for, and the steps under it. A pending step
that waits for a step of its plan that is not completed is blocked. Blocked is no
status: it is a relation between the steps of one plan, so a plan gives each of
its steps a link to itself, which a walk of the documents does not follow, and
only the plan sets it. The progress of a plan counts its steps at every depth.

`WorkPlanDocument.jl` holds the two documents, the link, their nodes in a tree
and the facet of a step, and `WorkPlanProgress.jl` the blocked steps and the
progress. `WorkPlanToWidget.jl` draws a plan as its progress and the tree of its
steps, and `WorkPlanStepToWidget.jl` draws a step as a page with a link to each
step that it waits for. A plan is read only: no view of it takes an edit.
"""
module WorkPlanModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..GestureBindingModule
using ..GestureModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..RosterModule
using ..StyleModule
using ..TreeModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: copy_document, get_document_title, is_walk_opaque
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward
import ..RosterModule: get_item_facets, compute_item_facet
import ..SerializationModule: pred_arguments
import ..TreeModule: get_tree_children_steps, format_tree_node_label
import ..DomainModule: get_document_decoration
import ..WidgetModule: make_graphics_projection

export WORK_PLAN_STEP_STATUSES, set_work_plan_steps!
export is_work_plan_step_blocked, WorkPlanProgress, compute_work_plan_progress,
       describe_work_plan_progress

include("WorkPlanDocument.jl")
include("WorkPlanProgress.jl")
include("WorkPlanToWidget.jl")
include("WorkPlanStepToWidget.jl")

end # module
