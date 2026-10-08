# ══════════════════════════════════════════════════════════════════════════════
# A group of tasks: a worker for each job, what became of each task, a stop, a
# run again in place, and the result of the whole group in the words of
# `opp_repl` — its `MultipleTasks` and `MultipleTaskResults`.
# ══════════════════════════════════════════════════════════════════════════════

"""
    get_default_job_count() -> Int

How many tasks go at once when nobody says. One for each processor thread, which
is what `opp_repl` uses, and never less than one.
"""
get_default_job_count() = max(1, Sys.CPU_THREADS)

"""
    start_task(task; on_finish = nothing) -> TaskExecution

Start one task and answer at once with its [`TaskExecution`](@ref), which the task
writes while it runs and which holds its [`TaskResult`](@ref) once it ends.
`stop_task_execution!(execution)` stops the task. `on_finish` receives the
`TaskResult`. Each kind of task adds a method; a kind that runs a process starts
it with [`start_process_task!`](@ref).
"""
function start_task end

"""
    TaskStartFailure

What a task ended with when its start threw: `ERROR`, with the exception in its
`reason`. The group records it and goes on with its other tasks.
"""
struct TaskStartFailure <: TaskResult
    task::AbstractTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

"""
    TaskNotStarted

What a task of a group ended with when the preparation of the group ended with
a result that is not expected: `CANCEL`, with a reason that names the
preparation and its result. The task never started.
"""
struct TaskNotStarted <: TaskResult
    task::AbstractTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

"""
    TaskGroupSummary

What a group looks like at one moment, in one value, for a reader of the screen:

- `total`, `finished`, `running`, `pending` — how many tasks are in each state;
- `counts` — for each code that has a result, in the order of the codes,
  `(code, expected, unexpected)`;
- `result`, `is_expected` — the worst case of the group and whether every
  result was expected; `summary` and `reason` — the words of `opp_repl` for them;
- `progress` — between 0 and 1, a finished task whole and a task that runs by
  the fraction it reports;
- `elapsed` — the seconds since the last start; `remaining` — an estimate of the
  seconds left, from the mean time of a finished task, the tasks left and the job
  count; `rate` — the tasks finished in a minute;
- `slowest` — the task that took the longest so far, as its parameters and its
  seconds, or `nothing`.
"""
struct TaskGroupSummary
    total::Int
    finished::Int
    running::Int
    pending::Int
    counts::Vector{Tuple{String,Int,Int}}
    result::String
    is_expected::Bool
    summary::String
    reason::Union{String,Nothing}
    progress::Float64
    elapsed::Union{Float64,Nothing}
    remaining::Union{Float64,Nothing}
    rate::Union{Float64,Nothing}
    slowest::Union{Tuple{String,Float64},Nothing}
end

"""
    TaskGroupTally

What the scheduler of a group counts of the tasks of the group that are no
groups, so that a summary needs no walk of every task:

- `total` — how many tasks of the group are no groups; `inner` — the places of
  the tasks that are groups, which keep tallies of their own;
- `finished` — how many have a result, and `running` — the places that run;
- `num_expected`, `num_unexpected` — for each code, how many results were
  expected and how many were not;
- `details` — the detail of each unexpected result by its place: its reason, or
  its code when it gives none;
- `duration_sum`, `duration_count`, `slowest` — the times of the tasks that have
  both a start and an end, and the one that took the longest, as its parameters
  and its seconds;
- `single` — the result while exactly one is counted.

The construction and each start of the group build it once from the
executions; the scheduler adds each start and each end, on its own task, under
the lock of the group.
"""
mutable struct TaskGroupTally
    total::Int
    inner::Vector{Int}
    finished::Int
    running::Set{Int}
    num_expected::Dict{String,Int}
    num_unexpected::Dict{String,Int}
    details::Dict{Int,String}
    duration_sum::Float64
    duration_count::Int
    slowest::Union{Tuple{String,Float64},Nothing}
    single::Union{TaskResult,Nothing}
end

"""
    TaskGroupRuntime()

What a group needs while it runs, and which no view shows: the lock of its
tally, the task of its scheduler, `finish`, `on_start`, `on_preparation`, and
`preparation_run`, the execution of its preparation at the last start. The
shadow of a group does not hold it.
"""
mutable struct TaskGroupRuntime
    lock::ReentrantLock
    scheduler::Union{Task,Nothing}
    finish::Union{Function,Nothing}
    on_start::Union{Function,Nothing}
    on_preparation::Union{Function,Nothing}
    preparation_run::Union{TaskExecution,Nothing}
end

TaskGroupRuntime() = TaskGroupRuntime(ReentrantLock(), nothing, nothing, nothing, nothing, nothing)

"""
    TaskGroup(tasks; name = "task", action = "", jobs = get_default_job_count(),
              codes = nothing, preparation = nothing)

A group of tasks and what became of each: `MultipleTasks` of `opp_repl`.
`runs[i]` is `nothing` until `tasks[i]` starts, and the [`TaskExecution`](@ref) of
that task afterwards, for the whole life of the group: a run again replaces one
entry in place and renumbers nothing.

`name` is a noun and `action` a verb in its `-ing` form, as `opp_repl` writes
them: `"fingerprint test"` and `"Checking fingerprint"`. `jobs` is how many tasks
go at once; one job is the sequential case. `codes` are the result codes of the
group, by default those of its first task.

`runtime.finish`, when it is set, is called with the group when the last task
of a start or of a run again has ended: an update writes its store there, once.

`runtime.on_start`, when it is set, is called as `on_start(index, execution)`
each time a task of the group starts, whoever started the group: the document of
the group sets it, so the tasks of an inner group reach their documents too.

**A group is a live state** (P3 of the catalog), `@document [M, C]`: the bare
name is the native layout, which its scheduler writes; `tally` is what the
scheduler counts ([`TaskGroupTally`](@ref)), and `summary` and `counts` are the
summary of the last sync. The editor task shows a group through its shadow in
the cell layout ([`make_task_group_shadow`](@ref)), which `sync_document!` brings
up to date; the shadow holds no `runs`, `tally` or `runtime`.

**A group is a kind of task.** A task of a group can be a group, as a
`MultipleTasks` of `opp_repl` can hold others: a sequential group of phases,
each a concurrent group of steps. The counts, the progress and the result of a
group count the tasks that are no groups, at every depth.

**A group can have a preparation**, one task that runs at each start of the
group, before its tasks, as a batch of runs of `opp_repl` builds its project
first. When the preparation ends with a result that is not expected, no task
starts, and each ends with a [`TaskNotStarted`](@ref) result. The preparation
is not one of the tasks: the counts, the codes, the result and the places of
the group are those of its tasks. `runtime.preparation_run` is its execution of
the last start, and `runtime.on_preparation`, when it is set, is called with
that execution when the preparation starts.
"""
@document [M, C] struct TaskGroup <: AbstractTask
    tasks::Vector{AbstractTask}
    name::String
    action::String
    jobs::Int
    codes::ResultCodes
    preparation::Union{AbstractTask,Nothing}
    stopping::Bool
    start_time::Union{Float64,Nothing}
    end_time::Union{Float64,Nothing}
    runs::Vector{Union{TaskExecution,Nothing}}
    tally::Union{TaskGroupTally,Nothing}
    summary::Union{TaskGroupSummary,Nothing}
    counts::Any
    runtime::Union{TaskGroupRuntime,Nothing}
end

function TaskGroup(tasks::AbstractVector{<:AbstractTask}; name::AbstractString = "task",
                   action::AbstractString = "", jobs::Integer = get_default_job_count(),
                   codes::Union{ResultCodes,Nothing} = nothing,
                   preparation::Union{AbstractTask,Nothing} = nothing)
    resolved = codes !== nothing ? codes :
               isempty(tasks) ? RUN_RESULT_CODES : get_result_codes(first(tasks))
    group = TaskGroup(AbstractTask[t for t in tasks], String(name), String(action),
                      max(1, Int(jobs)), resolved, preparation, false, nothing, nothing,
                      Union{TaskExecution,Nothing}[nothing for _ in tasks], nothing, nothing,
                      nothing, TaskGroupRuntime())
    group.tally = _make_task_group_tally(group)
    group
end

get_result_codes(group::TaskGroup) = group.codes

# ── The tally ────────────────────────────────────────────────────────────────

# The tally of the executions that the group holds now. Call it under the lock of
# the group, or before anyone else holds the group.
function _make_task_group_tally(group::TaskGroup)
    tally = TaskGroupTally(0, Int[], 0, Set{Int}(), Dict{String,Int}(), Dict{String,Int}(),
                           Dict{Int,String}(), 0.0, 0, nothing, nothing)
    for (index, task) in enumerate(group.tasks)
        if task isa TaskGroup
            push!(tally.inner, index)
            continue
        end
        tally.total += 1
        run = group.runs[index]
        run === nothing && continue
        (result, started, ended) = lock(() -> (run.result, run.start_time, run.end_time),
                                        run.runtime.lock)
        result === nothing ? push!(tally.running, index) :
                             _add_task_result!(tally, index, task, result, started, ended)
    end
    tally
end

# Count one result of the task at `index`.
function _add_task_result!(tally::TaskGroupTally, index::Int, task, result::TaskResult,
                           started, ended)
    tally.finished += 1
    tally.single = tally.finished == 1 ? result : nothing
    expected = is_expected(result)
    counts = expected ? tally.num_expected : tally.num_unexpected
    counts[result.result] = get(counts, result.result, 0) + 1
    expected || (tally.details[index] = _has_text(result.reason) ? result.reason : result.result)
    if started !== nothing && ended !== nothing
        duration = ended - started
        tally.duration_sum += duration
        tally.duration_count += 1
        (tally.slowest === nothing || duration > tally.slowest[2]) &&
            (tally.slowest = (format_task_parameters(task), duration))
    end
    tally
end

# Build the tally of the group again from its executions.
_rebuild_task_group_tally!(group::TaskGroup) =
    lock(() -> (group.tally = _make_task_group_tally(group)), group.runtime.lock)

# A task of the group started: a task that is no group runs from now.
function _record_task_start!(group::TaskGroup, index::Int)
    group.tasks[index] isa TaskGroup && return nothing
    lock(() -> push!(group.tally.running, index), group.runtime.lock)
    nothing
end

# A task of the group ended: count its result, which its execution holds.
function _record_task_end!(group::TaskGroup, index::Int)
    task = group.tasks[index]
    task isa TaskGroup && return nothing
    run = group.runs[index]
    (result, started, ended) = lock(() -> (run.result, run.start_time, run.end_time),
                                    run.runtime.lock)
    lock(group.runtime.lock) do
        delete!(group.tally.running, index)
        result === nothing || _add_task_result!(group.tally, index, task, result, started, ended)
    end
    nothing
end
format_task_parameters(group::TaskGroup) = group.name

# The tasks of the group that are no groups, at every depth, each with its
# execution or `nothing`. An inner group that did not start has its tasks
# pending.
function _collect_task_group_leaves(group::TaskGroup,
                                    leaves = Tuple{AbstractTask,Union{TaskExecution,Nothing}}[])
    for (task, run) in zip(group.tasks, group.runs)
        task isa TaskGroup ? _collect_task_group_leaves(task, leaves) : push!(leaves, (task, run))
    end
    leaves
end

Base.length(group::TaskGroup) = length(group.tasks)

Base.show(io::IO, group::TaskGroup) =
    print(io, "TaskGroup(", repr(group.name), ", ", length(group.tasks), " tasks, ",
          group.jobs, group.jobs == 1 ? " job)" : " jobs)")

"""Whether the tasks of the group go at once: more than one job."""
is_concurrent(group::TaskGroup) = group.jobs > 1

"""
    format_task_group_description(group) -> String

The group as `opp_repl` announces it when it starts:
`Checking fingerprint fingerprint test (40 concurrent)`.
"""
format_task_group_description(group::TaskGroup) =
    _describe_group(group.action, group)

"""
    format_task_group_close_description(group) -> String

The group as `opp_repl` names it when it ends, with the action in the past
tense: `Ran simulation (5 concurrent)`.
"""
format_task_group_close_description(group::TaskGroup) =
    _describe_group(format_past_tense(group.action), group)

_describe_group(action::AbstractString, group::TaskGroup) =
    (isempty(action) ? "" : action * " ") * group.name * " (" *
    string(length(group.tasks)) * (is_concurrent(group) ? " concurrent)" : " sequential)")

"""
    compute_task_group_indices(group, which) -> Vector{Int}

The positions a word names. `:all` is every task; `:unfinished` is every task
with no result yet; `:unexpected` is every task whose result is not the expected
one; `:failed` is every task whose result is neither `SKIP` nor of the role
`:success`. A vector of positions answers itself, so a caller can name one task.
"""
function compute_task_group_indices(group::TaskGroup, which)
    which isa AbstractVector && return Int[i for i in which if 1 <= i <= length(group.tasks)]
    which === :all && return collect(eachindex(group.tasks))
    which === :unfinished && return Int[i for (i, run) in enumerate(group.runs)
                                        if run === nothing || run.result === nothing]
    finished = [(i, run.result) for (i, run) in enumerate(group.runs)
                if run !== nothing && run.result !== nothing]
    which === :failed && return Int[i for (i, result) in finished if _is_failure(result)]
    which === :unexpected && return Int[i for (i, result) in finished if !is_expected(result)]
    error("Unknown selection: " * repr(which))
end

_is_failure(result::TaskResult) =
    result.result != "SKIP" && get_result_role(get_result_codes(result), result.result) !== :success

"""
    start_task_group!(group; on_start, on_finish, on_change)
    start_task_group!(group, indices; callbacks…)

Start the tasks of the group, at most `group.jobs` at a time, and answer at once.
The group runs on its own task; [`wait_task_group`](@ref) waits for it.

`on_start` is called with the position of a task and its [`TaskExecution`](@ref)
when the task starts, which is when a reader can begin to watch the record.
`on_finish` is called with the position and the `TaskResult` when it ends.
`on_change` is called with the group whenever a task starts or ends, which is
when a summary changes. Every callback is called on the task of the group.
"""
function start_task_group!(group::TaskGroup; kwargs...)
    start_task_group!(group, collect(eachindex(group.tasks)); kwargs...)
end

function start_task_group!(group::TaskGroup, indices::Vector{Int};
                           on_start = nothing, on_finish = nothing, on_change = nothing)
    group.stopping = false
    for index in indices
        group.runs[index] = nothing
    end
    _rebuild_task_group_tally!(group)
    group.start_time = time()
    group.end_time = nothing
    group.runtime.scheduler = @async _drive!(group, indices, on_start, on_finish, on_change)
    group
end

# The pool. It keeps at most `group.jobs` tasks alive: it starts what it can,
# then waits for one to report that it finished before it starts another.
#
# The channel is as large as the work, so a task that finishes before the driver
# waits — an executable that is missing answers at once — cannot block on the
# report. An unbuffered channel would deadlock exactly there.
function _drive!(group::TaskGroup, indices::Vector{Int}, on_start, on_finish, on_change)
    if group.preparation !== nothing
        reason = _run_preparation!(group)
        group.stopping && return _finish_drive!(group)
        if reason !== nothing
            for index in indices
                _end_unstarted_task!(group, index, reason, on_start, on_finish, on_change)
            end
            return _finish_drive!(group)
        end
    end
    finished = Channel{Int}(max(1, length(indices)))
    next = 1
    active = 0
    while next <= length(indices) || active > 0
        while !group.stopping && next <= length(indices) && active < group.jobs
            index = indices[next]
            next += 1
            active += 1
            finish_one = result -> begin
                on_finish === nothing || on_finish(index, result)
                put!(finished, index)
            end
            group.runs[index] = try
                start_task(group.tasks[index]; on_finish = finish_one)
            catch exception
                # A start that throws ends its task as an error, and the group
                # goes on with the others rather than stop.
                @error "the start of a task of the group $(repr(group.name)) failed" exception = (exception, catch_backtrace())
                finish_task_execution!(TaskExecution(group.tasks[index]),
                    TaskStartFailure(group.tasks[index], "ERROR", group.codes.expected,
                                     "The start failed: " * sprint(showerror, exception), nothing);
                    finish = finish_one)
            end
            _record_task_start!(group, index)
            on_start === nothing || on_start(index, group.runs[index])
            group.runtime.on_start === nothing || group.runtime.on_start(index, group.runs[index])
            on_change === nothing || on_change(group)
        end
        active == 0 && break
        _record_task_end!(group, take!(finished))
        active -= 1
        on_change === nothing || on_change(group)
    end
    close(finished)
    _finish_drive!(group)
end

# The end of a start of the group: its `finish`, and the time.
function _finish_drive!(group::TaskGroup)
    if group.runtime.finish !== nothing
        try
            group.runtime.finish(group)
        catch exception
            @error "the group $(repr(group.name)) failed to finish" exception = (exception, catch_backtrace())
        end
    end
    group.end_time = time()
    group
end

# Run the preparation of the group to its end. It answers why the tasks must not
# start, or `nothing` when they can. A start that throws ends the preparation as
# an error, as it ends a task.
function _run_preparation!(group::TaskGroup)
    preparation = group.preparation
    execution = try
        start_task(preparation)
    catch exception
        @error "the preparation of the group $(repr(group.name)) failed to start" exception = (exception, catch_backtrace())
        failed = TaskExecution(preparation)
        finish_task_execution!(failed,
            TaskStartFailure(preparation, "ERROR", get_result_codes(preparation).expected,
                             "The start failed: " * sprint(showerror, exception), nothing))
        failed
    end
    group.runtime.preparation_run = execution
    group.runtime.on_preparation === nothing || group.runtime.on_preparation(execution)
    wait_task_execution(execution)
    result = lock(() -> execution.result, execution.runtime.lock)
    result === nothing || is_expected(result) ? nothing :
        string("Not started: ", _describe_preparation(preparation), " ended ", result.result)
end

_describe_preparation(preparation::TaskGroup) =
    isempty(preparation.action) ? preparation.name : lowercase(preparation.action) * " " * preparation.name
_describe_preparation(preparation::AbstractTask) = format_task_parameters(preparation)

# End task `index` of the group without a start, as `CANCEL` with `reason`. An
# inner group ends each of its tasks so; its execution reaches its document
# before theirs, as a start does.
function _end_unstarted_task!(group::TaskGroup, index::Int, reason::String, on_start, on_finish, on_change)
    task = group.tasks[index]
    execution = TaskExecution(task)
    group.runs[index] = execution
    on_start === nothing || on_start(index, execution)
    group.runtime.on_start === nothing || group.runtime.on_start(index, execution)
    if task isa TaskGroup
        fill!(task.runs, nothing)
        _rebuild_task_group_tally!(task)
        for inner in eachindex(task.tasks)
            _end_unstarted_task!(task, inner, reason, nothing, nothing, nothing)
        end
        result = compute_task_group_result(task)
    else
        result = TaskNotStarted(task, "CANCEL", group.codes.expected, reason, nothing)
    end
    finish_task_execution!(execution, result)
    _record_task_end!(group, index)
    on_finish === nothing || on_finish(index, result)
    on_change === nothing || on_change(group)
    execution
end

"""
    stop_task_group!(group)

Stop every task that is going, and the preparation when it is going, and start
no more. A task that is going is interrupted rather than killed, so a program
that catches the interrupt can still finish its work, and the task ends as
`CANCEL`.
"""
function stop_task_group!(group::TaskGroup)
    group.stopping = true
    run = group.runtime.preparation_run
    if run !== nothing && is_task_running(run)
        group.preparation isa TaskGroup ? stop_task_group!(group.preparation) : stop_task_execution!(run)
    end
    for (task, run) in zip(group.tasks, group.runs)
        task isa TaskGroup ? stop_task_group!(task) : run === nothing || stop_task_execution!(run)
    end
    group
end

"""Wait for the group to end. It answers the group."""
function wait_task_group(group::TaskGroup)
    group.runtime.scheduler === nothing || wait(group.runtime.scheduler)
    group
end

"""
    rerun_task_group!(group, which = :failed; callbacks…)

Run part of the group again, in place. `which` is what
[`compute_task_group_indices`](@ref) understands. The entries it names go back to
pending and run; every other entry keeps the result it has.
"""
# @optional: which follows the group, as what a rerun command names next.
function rerun_task_group!(group::TaskGroup, which = :failed; kwargs...)
    indices = compute_task_group_indices(group, which)
    isempty(indices) && return group
    wait_task_group(group)
    start_task_group!(group, indices; kwargs...)
end

"""
    run_task_group(group; callbacks…) -> TaskGroup

Run every task of the group to the end and answer the group. The blocking form,
for a caller with nothing else to do.
"""
function run_task_group(group::TaskGroup; kwargs...)
    start_task_group!(group; kwargs...)
    wait_task_group(group)
end

# ── A group as a task of another group ───────────────────────────────────────

"""
    start_task(group::TaskGroup; on_finish = nothing) -> TaskExecution

Start an inner group as a task of its outer group, and answer at once with an
execution that has no process: its `progress` and its `position`, the finished
tasks over all of them, follow the group, and its result is the
[`TaskGroupResult`](@ref) of the group when the group ends. A stop of the outer
group stops the inner group (`stop_task_group!`).
"""
function start_task(group::TaskGroup; on_finish = nothing)
    execution = TaskExecution(group)
    function follow(g)
        progress = measure_task_group_progress(g)
        position = _format_task_group_position(g)
        update_task_execution!(e -> (e.progress = progress; e.position = position), execution)
    end
    update_task_execution!(execution) do e
        e.status = :running
        e.start_time = time()
    end
    follow(group)
    start_task_group!(group; on_change = follow)
    execution.runtime.reader = @async begin
        wait_task_group(group)
        follow(group)
        finish_task_execution!(execution, compute_task_group_result(group); finish = on_finish)
    end
    execution
end

_format_task_group_position(group::TaskGroup) =
    (summary = build_task_group_summary(group); string(summary.finished, "/", summary.total))

"""The results of the group, in the order of its tasks. A task that has not
finished answers `nothing`."""
collect_task_group_results(group::TaskGroup) =
    Union{TaskResult,Nothing}[run === nothing ? nothing : run.result for run in group.runs]

"""
    measure_task_group_elapsed_time(group) -> Float64 or nothing

How long the group ran, in seconds: from its last start to its end, or to now
while it runs. `nothing` before it starts.
"""
measure_task_group_elapsed_time(group::TaskGroup) =
    group.start_time === nothing ? nothing : something(group.end_time, time()) - group.start_time

"""
    build_task_group_summary(group) -> NamedTuple

What the group looks like now: `counts` by result code, the worst case `overall`
of [`TaskGroupResult`](@ref), the `total`, and how many tasks are `finished`,
`running` and `pending`.
"""
function build_task_group_summary(group::TaskGroup)
    tallied = _sum_task_group_tally!(_TaskGroupSum(), group)
    counts = Dict{String,Int}()
    for table in (tallied.num_expected, tallied.num_unexpected), (code, n) in table
        counts[code] = get(counts, code, 0) + n
    end
    running = length(tallied.running)
    (counts = counts,
     overall = _get_tallied_worst_code(tallied, group.codes),
     total = tallied.total,
     finished = tallied.finished,
     running = running,
     pending = tallied.total - tallied.finished - running)
end

"""
    measure_task_group_progress(group) -> Float64

How much of the group is done, between 0 and 1. A finished task counts whole,
and a task that is going counts the fraction it reports, or nothing when it
reports none.
"""
function measure_task_group_progress(group::TaskGroup)
    tallied = _sum_task_group_tally!(_TaskGroupSum(), group)
    tallied.total == 0 && return 1.0
    clamp(_measure_tallied_progress(tallied) / tallied.total, 0.0, 1.0)
end

# The tallies of the group and of its inner groups, summed: the unexpected
# details in the order of the tasks, and the executions that run.
mutable struct _TaskGroupSum
    total::Int
    finished::Int
    running::Vector{TaskExecution}
    num_expected::Dict{String,Int}
    num_unexpected::Dict{String,Int}
    details::Vector{String}
    duration_sum::Float64
    duration_count::Int
    slowest::Union{Tuple{String,Float64},Nothing}
    single::Union{TaskResult,Nothing}
end

_TaskGroupSum() = _TaskGroupSum(0, 0, TaskExecution[], Dict{String,Int}(), Dict{String,Int}(),
                                String[], 0.0, 0, nothing, nothing)

function _sum_task_group_tally!(tallied::_TaskGroupSum, group::TaskGroup)
    places = lock(group.runtime.lock) do
        tally = group.tally
        tallied.total += tally.total
        tally.finished == 1 && (tallied.single = tally.single)
        tallied.finished += tally.finished
        for index in tally.running
            run = group.runs[index]
            run === nothing || push!(tallied.running, run)
        end
        for (sum_table, table) in ((tallied.num_expected, tally.num_expected),
                                   (tallied.num_unexpected, tally.num_unexpected)),
            (code, n) in table
            sum_table[code] = get(sum_table, code, 0) + n
        end
        tallied.duration_sum += tally.duration_sum
        tallied.duration_count += tally.duration_count
        slowest = tally.slowest
        if slowest !== nothing && (tallied.slowest === nothing || slowest[2] > tallied.slowest[2])
            tallied.slowest = slowest
        end
        sort!(Tuple{Int,Union{String,Nothing}}[[(i, d) for (i, d) in tally.details];
                                                [(i, nothing) for i in tally.inner]]; by = first)
    end
    for (index, detail) in places
        detail === nothing ? _sum_task_group_tally!(tallied, group.tasks[index]) :
                             push!(tallied.details, detail)
    end
    tallied
end

# The finished tasks, and the fraction of each one that runs.
function _measure_tallied_progress(tallied::_TaskGroupSum)
    done = Float64(tallied.finished)
    for run in tallied.running
        fraction = lock(() -> run.progress, run.runtime.lock)
        fraction === nothing || (done += fraction)
    end
    done
end

# The counts of each code of the group, zero for a code with no result.
_get_tallied_counts(table::Dict{String,Int}, codes::ResultCodes) =
    Dict{String,Int}(code => get(table, code, 0) for code in codes.codes)

_get_tallied_worst_code(tallied::_TaskGroupSum, codes::ResultCodes) =
    _get_worst_code(codes, _get_tallied_counts(tallied.num_expected, codes),
                    _get_tallied_counts(tallied.num_unexpected, codes), tallied.finished == 0,
                    codes.expected)

# ── The result of a group ────────────────────────────────────────────────────

"""
    TaskGroupResult(results; codes, expected_result = codes.expected,
                    elapsed_wall_time = nothing, group = nothing)

The result of a group of tasks, as `MultipleTaskResults` of `opp_repl` computes
it: for each code, how many results were expected and how many were not, and the
worst case in `result`.

**The worst case** is the rule of `opp_repl`: the first code, in the order of
`codes`, that has an expected result; then the last code that has an unexpected
result. An unexpected result of any code wins. A group with no result takes
`expected_result`.

It is a `TaskResult`: `task` is the group, and `reason` is
[`format_task_group_reason`](@ref), so a group that is a task of another group
ends with it.
"""
struct TaskGroupResult <: TaskResult
    task::Union{TaskGroup,Nothing}
    results::Vector{TaskResult}
    codes::ResultCodes
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
    num_expected::Dict{String,Int}
    num_unexpected::Dict{String,Int}
    num_different_results::Int
    result::String
end

function TaskGroupResult(results::AbstractVector; codes::ResultCodes,
                         expected_result::AbstractString = codes.expected,
                         elapsed_wall_time::Union{Real,Nothing} = nothing,
                         group::Union{TaskGroup,Nothing} = nothing)
    num_expected = Dict{String,Int}()
    num_unexpected = Dict{String,Int}()
    different = 0
    for code in codes.codes
        expected = count(r -> r.result == code && is_expected(r), results)
        unexpected = count(r -> r.result == code && !is_expected(r), results)
        num_expected[code] = expected
        num_unexpected[code] = unexpected
        different += (expected != 0) + (unexpected != 0)
    end
    result = _get_worst_code(codes, num_expected, num_unexpected, isempty(results), expected_result)
    results = TaskResult[r for r in results]
    TaskGroupResult(group, results, codes, String(expected_result),
                    _format_unexpected_reason(results),
                    elapsed_wall_time === nothing ? nothing : Float64(elapsed_wall_time),
                    num_expected, num_unexpected, different, result)
end

get_result_codes(result::TaskGroupResult) = result.codes

# The worst case of the rule of `opp_repl`: the first code, in the order of
# `codes`, that has an expected result; then the last code that has an
# unexpected one. A group with no result takes `expected_result`.
function _get_worst_code(codes::ResultCodes, num_expected, num_unexpected, empty::Bool,
                         expected_result::AbstractString)
    result = empty ? String(expected_result) : first(codes.codes)
    for code in codes.codes
        if num_expected[code] != 0
            result = code
            break
        end
    end
    for code in codes.codes
        num_unexpected[code] != 0 && (result = code)
    end
    result
end

# A group that is a task of another group shows its summary as its result.
format_task_result(result::TaskGroupResult) = format_task_group_summary(result)

"""
    compute_task_group_result(group) -> TaskGroupResult

The result of the group now, over the tasks that have finished and are no
groups, at every depth.
"""
compute_task_group_result(group::TaskGroup) =
    TaskGroupResult(TaskResult[run.result for (_, run) in _collect_task_group_leaves(group)
                               if run !== nothing && run.result !== nothing];
                    codes = group.codes,
                    elapsed_wall_time = measure_task_group_elapsed_time(group),
                    group = group)

"""Whether no result of the group was unexpected."""
is_expected(result::TaskGroupResult) = sum(values(result.num_unexpected); init = 0) == 0

"""
    format_task_group_summary(result) -> String

The counts of a group, as `get_summary` of `opp_repl` writes them:
`40 TOTAL, 37 PASS, 2 FAIL (unexpected), 1 ERROR (unexpected) in 3:12`. The total
is left out when one kind of count is all there is, and a count of the role
`:success` carries no `(expected)` or `(unexpected)`. A group of one result is
that result, as [`format_task_result`](@ref) writes it.
"""
format_task_group_summary(result::TaskGroupResult) =
    _format_result_counts(length(result.results),
                         length(result.results) == 1 ? only(result.results) : nothing,
                         result.codes, result.num_expected, result.num_unexpected,
                         result.elapsed_wall_time)

# The words of the counts of a group: `count` results, `single` the result when
# there is one, and the counts of each code of `codes`.
function _format_result_counts(count::Int, single, codes::ResultCodes, num_expected,
                              num_unexpected, elapsed)
    count == 1 && single !== nothing && return format_task_result(single)
    different = sum((num_expected[code] != 0) + (num_unexpected[code] != 0)
                    for code in codes.codes; init = 0)
    texts = String[]
    different != 1 && push!(texts, string(count, " TOTAL"))
    for code in codes.codes
        plain = get_result_role(codes, code) === :success
        expected = num_expected[code]
        unexpected = num_unexpected[code]
        expected != 0 && push!(texts, string(expected, " ", code, plain ? "" : " (expected)"))
        unexpected != 0 && push!(texts, string(unexpected, " ", code, plain ? "" : " (unexpected)"))
    end
    join(texts, ", ") * (_has_time(elapsed) ? " in " * format_elapsed_time(elapsed) : "")
end

"""
    format_task_group_reason(result) -> String or nothing

Why a group is not what was expected, as the `reason` of `MultipleTaskResults`
says it: the unexpected results grouped by their reason, or by their code when
they give none, the most frequent first, three at most —
`3/40 unexpected: 2x Fingerprint mismatch, 1x Calculated fingerprint not found`.
`nothing` when every result was expected.
"""
format_task_group_reason(result::TaskGroupResult) = result.reason

_format_unexpected_reason(results::Vector{TaskResult}) =
    _format_unexpected_details(String[_has_text(r.reason) ? r.reason : r.result
                                      for r in results if !is_expected(r)],
                               length(results))

# The details of the unexpected results, in the order of their tasks, of `total`
# results, grouped and ranked.
function _format_unexpected_details(details::Vector{String}, total::Int)
    counts = Pair{String,Int}[]                 # in the order the details appear
    for detail in details
        index = findfirst(entry -> entry.first == detail, counts)
        index === nothing ? push!(counts, detail => 1) :
                            (counts[index] = detail => counts[index].second + 1)
    end
    isempty(counts) && return nothing
    # A stable sort, so details of equal count keep the order they came in, as
    # the sort of `opp_repl` keeps it.
    ranked = sort(counts; by = last, rev = true, alg = MergeSort)
    parts = [string(n, "x ", detail) for (detail, n) in ranked[1:min(3, end)]]
    length(ranked) > 3 && push!(parts, "+" * string(length(ranked) - 3) * " more")
    string(sum(last, counts), "/", total, " unexpected: ") * join(parts, ", ")
end

# What `opp_repl` prints for a group result: the heading and the summary, then a
# line for each unexpected result of the role `:warning` or `:error`.
function Base.show(io::IO, result::TaskGroupResult)
    group = result.task
    name = group === nothing ? "task" : group.name
    past = group === nothing ? "" : format_past_tense(group.action)
    prefix = isempty(past) ? "" : past * " "
    if isempty(result.results)
        reason = format_task_group_reason(result)
        result.result == first(result.codes.codes) ?
            print(io, prefix, name, ": empty") :
            print(io, prefix, name, ": ", result.result, reason === nothing ? "" : " (" * reason * ")")
    elseif length(result.results) == 1
        print(io, prefix, name, ": Result: ", format_task_result(only(result.results)))
    else
        heading = group === nothing ? name : format_task_group_close_description(group)
        print(io, heading, ": ", format_task_group_summary(result))
        for code in result.codes.codes
            get_result_role(result.codes, code) in (:warning, :error) || continue
            for task_result in result.results
                (task_result.result == code && !is_expected(task_result)) || continue
                print(io, "\n  ", format_task_parameters(task_result.task), " ",
                      format_task_result(task_result))
            end
        end
    end
end

"""
    summarize_results(results) -> (; counts, overall, total)

The results of tasks in short: the `counts` by code, the worst case `overall` of
[`TaskGroupResult`](@ref), and the `total`.
"""
function summarize_results(results)
    counts = Dict{String,Int}()
    for r in results
        counts[r.result] = get(counts, r.result, 0) + 1
    end
    overall = isempty(results) ? RUN_RESULT_CODES.expected :
              TaskGroupResult(collect(results); codes = get_result_codes(first(results))).result
    (counts = counts, overall = overall, total = length(results))
end

# ── What a group looks like now ──────────────────────────────────────────────


"""
    compute_task_group_summary(group; now = time()) -> TaskGroupSummary

The [`TaskGroupSummary`](@ref) of the group now, from the tally of the group and
of its inner groups ([`TaskGroupTally`](@ref)) and the progress of the running
executions: it costs the codes, the inner groups and the running tasks, not a
walk of every task. Each tally and each execution is read under its lock, so any
task may call it.
"""
function compute_task_group_summary(group::TaskGroup; now::Real = time())
    tallied = _sum_task_group_tally!(_TaskGroupSum(), group)
    codes = group.codes
    num_expected = _get_tallied_counts(tallied.num_expected, codes)
    num_unexpected = _get_tallied_counts(tallied.num_unexpected, codes)
    finished = tallied.finished
    running = length(tallied.running)
    total = tallied.total
    pending = total - finished - running
    elapsed = group.start_time === nothing ? nothing : something(group.end_time, now) - group.start_time
    counts = Tuple{String,Int,Int}[(code, num_expected[code], num_unexpected[code])
                                   for code in codes.codes
                                   if num_expected[code] + num_unexpected[code] > 0]
    left = pending + running
    remaining = (tallied.duration_count == 0 || left == 0) ? nothing :
                tallied.duration_sum / tallied.duration_count * left / group.jobs
    rate = (elapsed === nothing || elapsed <= 0 || finished == 0) ? nothing : finished / elapsed * 60
    words = finished == 0 ? "" :
            _format_result_counts(finished, tallied.single, codes, num_expected, num_unexpected, elapsed)
    progress = _measure_tallied_progress(tallied)
    TaskGroupSummary(total, finished, running, pending, counts,
                     _get_worst_code(codes, num_expected, num_unexpected, finished == 0, codes.expected),
                     sum(values(num_unexpected); init = 0) == 0, words,
                     _format_unexpected_details(tallied.details, finished),
                     total == 0 ? 1.0 : clamp(progress / total, 0.0, 1.0),
                     elapsed, remaining, rate, tallied.slowest)
end

"""
    get_task_group_counts(summary) -> NamedTuple

The parts of a summary that change only when a task starts or ends: `total`,
`finished`, `running`, `pending`, `counts`, `result` and `is_expected`. A view of
them is not drawn again at each sync.
"""
get_task_group_counts(summary::TaskGroupSummary) =
    (total = summary.total, finished = summary.finished, running = summary.running,
     pending = summary.pending, counts = summary.counts, result = summary.result,
     is_expected = summary.is_expected)

# ── The shadow ───────────────────────────────────────────────────────────────

# The fields that a shadow takes; it holds no `runs`, `tally` or `runtime`.
const _GROUP_SHADOW_FIELDS = (:name, :action, :jobs, :codes, :stopping, :start_time,
                              :end_time, :summary, :counts)

# The summary of the group now, kept in the group with its counts.
function _refresh_task_group_summary!(group::TaskGroup)
    summary = compute_task_group_summary(group)
    lock(group.runtime.lock) do
        group.summary = summary
        group.counts = get_task_group_counts(summary)
    end
    group
end

"""
    make_task_group_shadow(group) -> shadow

The shadow of `group` in the cell layout, which a view reads: its fields and its
summary as they are now. Its list of runs is empty, because the slot of a task
reads the run of that task. Make it on the editor task.
"""
function make_task_group_shadow(group::TaskGroup)
    _refresh_task_group_summary!(group)
    lock(group.runtime.lock) do
        ACTaskGroup(group.tasks, group.name, group.action, group.jobs, group.codes,
                    group.preparation, group.stopping, group.start_time, group.end_time,
                    Union{TaskExecution,Nothing}[], nothing, group.summary, group.counts, nothing)
    end
end

"""
    sync_document!(shadow, group) -> shadow

Bring the shadow of a group up to date, on the editor task: compute the summary
of the group, keep it in the group, and write each field of the shadow whose
value changed. The counts change only when a task starts or ends, so a view of
them is not drawn again at each sync.
"""
function sync_document!(shadow::ACTaskGroup, group::TaskGroup, policy, depth::Int)
    _refresh_task_group_summary!(group)
    lock(group.runtime.lock) do
        for name in _GROUP_SHADOW_FIELDS
            value = getfield(group, name)
            isequal(getproperty(shadow, name), value) || setproperty!(shadow, name, value)
        end
    end
    shadow
end

sync_document!(shadow::ACTaskGroup, group::TaskGroup) = sync_document!(shadow, group, nothing, 0)
