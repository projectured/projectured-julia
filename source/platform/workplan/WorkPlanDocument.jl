# Fragment of `WorkPlanModule` — the documents: one step of a plan, and the plan
# with the link that its steps hold; their titles, their file form, their copies,
# their nodes in a tree, and the facet of a step.

"""
    WORK_PLAN_STEP_STATUSES

The statuses of a [`WorkPlanStep`](@ref): `:pending`, `:in_progress`,
`:completed`, `:skipped` and `:deferred`. Blocked is no status: a pending step
is blocked while a step that it waits for is not completed
([`is_work_plan_step_blocked`](@ref)).
"""
const WORK_PLAN_STEP_STATUSES = (:pending, :in_progress, :completed, :skipped, :deferred)

# The priorities of a step, the highest first.
const _WORK_PLAN_STEP_PRIORITIES = (:high, :medium, :low)

"""
    WorkPlanStep(id, title; active_title = "", description = "", status = :pending,
                 priority = :medium, reason = "", blocked_by = String[], children = [])

One step of a [`WorkPlan`](@ref).

# Fields
- `id` — the name of the step in its plan, which `blocked_by` of another step
  names.
- `title` — what the step does.
- `active_title` — what a view shows while the step runs, such as "Writing the
  tests"; empty when the step gives none.
- `description` — what the step does, in more words.
- `status` — one of [`WORK_PLAN_STEP_STATUSES`](@ref).
- `priority` — `:high`, `:medium` or `:low`.
- `reason` — why the step has its status, such as why it was skipped.
- `blocked_by` — the ids of the steps of the same plan that this step waits for.
- `children` — the steps under this step, a `CellVector` of `WorkPlanStep`.
- `plan` — the link to the plan that holds the step, or `nothing`. Only the plan
  sets it ([`set_work_plan_steps!`](@ref)), a walk of the documents does not
  follow it, and a file does not keep it.
"""
@document struct WorkPlanStep <: Document
    id::String
    title::String
    active_title::String
    description::String
    status::Symbol
    priority::Symbol
    reason::String
    blocked_by::Vector{String}
    children::CellVector
    plan::Any
end

function WorkPlanStep(id::AbstractString, title::AbstractString; active_title::AbstractString = "",
                      description::AbstractString = "", status::Symbol = :pending,
                      priority::Symbol = :medium, reason::AbstractString = "",
                      blocked_by = String[], children = WorkPlanStep[])
    status in WORK_PLAN_STEP_STATUSES ||
        throw(ArgumentError(string("A step of a plan has no status ", repr(status), ".")))
    priority in _WORK_PLAN_STEP_PRIORITIES ||
        throw(ArgumentError(string("A step of a plan has no priority ", repr(priority), ".")))
    WorkPlanStep(String(id), String(title), String(active_title), String(description), status, priority,
                 String(reason), collect(String, blocked_by), CellVector(collect(Any, children)), nothing)
end

"""
    WorkPlan(id; title = "", steps = [], text = "", uri = "")

The plan of an agent, with one of three contents, as the content of a plan of
ACP: its `steps`, a `CellVector` of [`WorkPlanStep`](@ref); a Markdown `text`;
or the `uri` of a file that holds it. An empty content is none. The constructor
links each step to the plan, at every depth.

`link` holds what the plan gives its steps and its views and no walk of the
documents enters: the plan itself, which each of its steps holds in its field
`plan`, and the tree of its steps that a view of the plan shows, so the open
nodes of that tree stay when the view is drawn again. A file keeps the id, the
title and the content.
"""
@document struct WorkPlan <: Document
    id::String
    title::String
    steps::CellVector
    text::String
    uri::String
    link::Any
end

function WorkPlan(id::AbstractString; title::AbstractString = "", steps = WorkPlanStep[],
                  text::AbstractString = "", uri::AbstractString = "")
    plan = WorkPlan(String(id), String(title), CellVector(Any[]), String(text), String(uri), nothing)
    plan.link = _WorkPlanLink(plan, nothing)
    set_work_plan_steps!(plan, steps)
end

# What a plan gives its steps and its views: the plan, and the `DocumentTree` of
# its steps, which the first view of the plan makes.
mutable struct _WorkPlanLink
    plan::Any
    step_tree::Any
end

# A walk of the documents does not go from a step into its plan, so a search
# finds each step once, at its place in the plan.
is_walk_opaque(::_WorkPlanLink) = true

"""
    set_work_plan_steps!(plan, steps) -> plan

Replace the steps of `plan` with `steps`, and link each of them, at every depth,
to `plan`. A step is blocked only by a step of the plan that it is linked to, so
write the steps of a plan through this function.
"""
function set_work_plan_steps!(plan::WorkPlan, steps)
    link = plan.link
    for step in steps
        _link_work_plan_step!(step, link)
    end
    plan.steps = CellVector(collect(Any, steps))
    plan
end

function _link_work_plan_step!(step::WorkPlanStep, link)
    step.plan = link
    for child in step.children
        _link_work_plan_step!(child, link)
    end
end

# The plan of a step, or `nothing` for a step that no plan holds.
function _get_step_plan(step::WorkPlanStep)
    link = step.plan
    link === nothing ? nothing : link.plan
end

get_document_title(plan::WorkPlan) = isempty(plan.title) ? "Plan" : plan.title
get_document_title(step::WorkPlanStep) = step.title

# A file keeps what the agent gave, and no link: the constructors make it again.
pred_arguments(plan::WorkPlan) =
    (plan.id,), Pair{Symbol,Any}[:title => plan.title, :steps => collect(Any, plan.steps),
                                 :text => plan.text, :uri => plan.uri]
pred_arguments(step::WorkPlanStep) =
    (step.id, step.title), Pair{Symbol,Any}[:active_title => step.active_title,
                                            :description => step.description, :status => step.status,
                                            :priority => step.priority, :reason => step.reason,
                                            :blocked_by => collect(String, step.blocked_by),
                                            :children => collect(Any, step.children)]

# A copy of a plan has a link of its own, and its steps, copied too, link to the
# copy. A step copied alone belongs to no plan.
function copy_document(policy::CopyPolicy, plan::WorkPlan)
    is_descendable_for_copy(policy, plan) || return make_copy_placeholder(policy, plan)
    copied = copy_document_fields(policy, plan; link = nothing)
    copied.link = _WorkPlanLink(copied, nothing)
    set_work_plan_steps!(copied, collect(Any, copied.steps))
end

function copy_document(policy::CopyPolicy, step::WorkPlanStep)
    is_descendable_for_copy(policy, step) || return make_copy_placeholder(policy, step)
    copy_document_fields(policy, step; plan = nothing)
end

# ── The nodes of a tree ──────────────────────────────────────────────────────

get_tree_children_steps(::WorkPlan) = ((FieldReferenceStep("steps"),),)
get_tree_children_steps(::WorkPlanStep) = ((FieldReferenceStep("children"),),)

format_tree_node_label(plan::WorkPlan) =
    string(get_document_title(plan), " · ", describe_work_plan_progress(plan))

# The text that a step shows while it runs, or its title, and its state.
function format_tree_node_label(step::WorkPlanStep)
    shown = step.status === :in_progress && !isempty(step.active_title) ? step.active_title : step.title
    string(shown, " · ", _describe_step_state(step))
end

get_tree_node_icon(::WorkPlan) = :list

# A picture for each status, and one for a blocked step.
function get_tree_node_icon(step::WorkPlanStep)
    _is_step_blocked(step) && return :stop
    status = step.status
    status === :in_progress ? :loader : status === :completed ? :circle_check :
    status === :skipped ? :skip_forward : status === :deferred ? :circle_pause : :circle
end

# ── The facet ────────────────────────────────────────────────────────────────

# The facet of a step in a roster. Its status and its title are its fields.
get_item_facets(::Type{WorkPlanStep}) =
    ["blocked" => "whether the step waits for a step of its plan that is not completed"]
compute_item_facet(step::WorkPlanStep, ::Val{:blocked}) = _is_step_blocked(step)
