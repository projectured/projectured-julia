# Fragment of `WorkPlanModule` — the blocked steps of a plan, and its progress:
# the count of its steps of each status, at every depth, and the words for it.
# Each function reads the cells of the steps, so a view that calls it follows the
# plan.

"""
    is_work_plan_step_blocked(plan, step) -> Bool

Whether `step` is blocked: it is `:pending`, and one of the ids of its
`blocked_by` names a step of `plan`, at any depth, that is not `:completed`. An
id that names no step of `plan` blocks nothing. Blocked is no status of the step;
it follows the steps that it waits for, so it ends when the last of them
completes.
"""
function is_work_plan_step_blocked(plan::WorkPlan, step::WorkPlanStep)
    step.status === :pending || return false
    any(id -> _is_blocking_step(_find_work_plan_step(plan.steps, id)), step.blocked_by)
end

_is_blocking_step(blocker) = blocker !== nothing && blocker.status !== :completed

# Whether a step is blocked in the plan that it is linked to. A step that no plan
# holds is never blocked.
function _is_step_blocked(step::WorkPlanStep)
    plan = _get_step_plan(step)
    plan !== nothing && is_work_plan_step_blocked(plan, step)
end

# The ids of the steps that block `step` now, in the order of its `blocked_by`.
function _collect_blocking_ids(step::WorkPlanStep)
    plan = _get_step_plan(step)
    plan === nothing && return String[]
    String[id for id in step.blocked_by if _is_blocking_step(_find_work_plan_step(plan.steps, id))]
end

# The first step at any depth of `steps` whose id is `id`, a parent before its
# children, or `nothing`.
function _find_work_plan_step(steps, id::AbstractString)
    for step in steps
        step.id == id && return step
        found = _find_work_plan_step(step.children, id)
        found === nothing || return found
    end
    nothing
end

# The index path of the step whose id is `id` in `steps`, as reference steps from
# the plan: `steps[i].children[j]…`, or `nothing`.
function _find_work_plan_step_path(steps, id::AbstractString, field::AbstractString = "steps")
    for (index, step) in enumerate(steps)
        here = (FieldReferenceStep(field), ElementReferenceStep(index))
        step.id == id && return here
        below = _find_work_plan_step_path(step.children, id, "children")
        below === nothing || return (here..., below...)
    end
    nothing
end

# The words of the state of a step: its status, or the steps that block it.
function _describe_step_state(step::WorkPlanStep)
    blocking = _collect_blocking_ids(step)
    isempty(blocking) || return "blocked by step " * join(blocking, ", ")
    replace(String(step.status), "_" => " ")
end

"""
    WorkPlanProgress

The count of the steps of a plan, at every depth: `total`, and of each status
`pending`, `in_progress`, `completed`, `skipped` and `deferred`. `blocked` counts
the pending steps that are blocked ([`is_work_plan_step_blocked`](@ref)), which
`pending` counts too.
"""
struct WorkPlanProgress
    total::Int
    pending::Int
    in_progress::Int
    completed::Int
    skipped::Int
    deferred::Int
    blocked::Int
end

"""
    compute_work_plan_progress(plan) -> WorkPlanProgress

Count the steps of `plan` of each status, at every depth, and the blocked steps
apart.
"""
function compute_work_plan_progress(plan::WorkPlan)
    counts = Dict{Symbol,Int}(status => 0 for status in (WORK_PLAN_STEP_STATUSES..., :blocked))
    total = _count_work_plan_steps!(counts, plan, plan.steps)
    WorkPlanProgress(total, counts[:pending], counts[:in_progress], counts[:completed], counts[:skipped],
                     counts[:deferred], counts[:blocked])
end

function _count_work_plan_steps!(counts, plan, steps)
    total = 0
    for step in steps
        status = step.status
        haskey(counts, status) && (counts[status] += 1)
        is_work_plan_step_blocked(plan, step) && (counts[:blocked] += 1)
        total += 1 + _count_work_plan_steps!(counts, plan, step.children)
    end
    total
end

"""
    describe_work_plan_progress(plan) -> String

The progress of `plan` in words: `3 of 7 completed, 1 in progress, 1 blocked,
1 skipped, 1 deferred`. It always says how many of all the steps are completed,
and then each other count that is not zero: in progress, pending and not blocked,
blocked, skipped and deferred. A plan with no steps says `no steps`.
"""
function describe_work_plan_progress(plan::WorkPlan)
    progress = compute_work_plan_progress(plan)
    progress.total == 0 && return "no steps"
    parts = [string(progress.completed, " of ", progress.total, " completed")]
    for (count, words) in ((progress.in_progress, "in progress"), (progress.pending - progress.blocked, "pending"),
                           (progress.blocked, "blocked"), (progress.skipped, "skipped"),
                           (progress.deferred, "deferred"))
        count == 0 || push!(parts, string(count, " ", words))
    end
    join(parts, ", ")
end

# The share of the steps of `plan` that are completed, for a bar: 0 with no steps.
function _compute_completed_share(plan::WorkPlan)
    progress = compute_work_plan_progress(plan)
    progress.total == 0 ? 0.0 : progress.completed / progress.total
end
