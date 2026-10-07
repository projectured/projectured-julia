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

`finish`, when it is set, is called with the group when the last task of a start
or of a run again has ended: an update writes its store there, once.

`on_start`, when it is set, is called as `on_start(index, execution)` each time
a task of the group starts, whoever started the group: the document of the
group sets it, so the tasks of an inner group reach their documents too.

**A group is a kind of task.** A task of a group can be a group, as a
`MultipleTasks` of `opp_repl` can hold others: a sequential group of phases,
each a concurrent group of steps. The counts, the progress and the result of a
group count the tasks that are no groups, at every depth.

**A group can have a preparation**, one task that runs at each start of the
group, before its tasks, as a batch of runs of `opp_repl` builds its project
first. When the preparation ends with a result that is not expected, no task
starts, and each ends with a [`TaskNotStarted`](@ref) result. The preparation
is not one of the tasks: the counts, the codes, the result and the places of
the group are those of its tasks. `preparation_run` is its execution of the
last start, and `on_preparation`, when it is set, is called with that
execution when the preparation starts.
"""
mutable struct TaskGroup <: AbstractTask
    tasks::Vector{AbstractTask}
    runs::Vector{Union{TaskExecution,Nothing}}
    name::String
    action::String
    jobs::Int
    codes::ResultCodes
    scheduler::Union{Task,Nothing}
    stopping::Bool
    start_time::Union{Float64,Nothing}
    end_time::Union{Float64,Nothing}
    finish::Union{Function,Nothing}
    on_start::Union{Function,Nothing}
    preparation::Union{AbstractTask,Nothing}
    preparation_run::Union{TaskExecution,Nothing}
    on_preparation::Union{Function,Nothing}
end

function TaskGroup(tasks::AbstractVector{<:AbstractTask}; name::AbstractString = "task",
                   action::AbstractString = "", jobs::Integer = get_default_job_count(),
                   codes::Union{ResultCodes,Nothing} = nothing,
                   preparation::Union{AbstractTask,Nothing} = nothing)
    resolved = codes !== nothing ? codes :
               isempty(tasks) ? RUN_RESULT_CODES : get_result_codes(first(tasks))
    TaskGroup(AbstractTask[t for t in tasks], Union{TaskExecution,Nothing}[nothing for _ in tasks],
              String(name), String(action), max(1, Int(jobs)), resolved,
              nothing, false, nothing, nothing, nothing, nothing, preparation, nothing, nothing)
end

get_result_codes(group::TaskGroup) = group.codes
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
    group.start_time = time()
    group.end_time = nothing
    group.scheduler = @async _drive!(group, indices, on_start, on_finish, on_change)
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
            on_start === nothing || on_start(index, group.runs[index])
            group.on_start === nothing || group.on_start(index, group.runs[index])
            on_change === nothing || on_change(group)
        end
        active == 0 && break
        take!(finished)
        active -= 1
        on_change === nothing || on_change(group)
    end
    close(finished)
    _finish_drive!(group)
end

# The end of a start of the group: its `finish`, and the time.
function _finish_drive!(group::TaskGroup)
    if group.finish !== nothing
        try
            group.finish(group)
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
    group.preparation_run = execution
    group.on_preparation === nothing || group.on_preparation(execution)
    wait_task_execution(execution)
    result = lock(() -> execution.result, execution.lock)
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
    group.on_start === nothing || group.on_start(index, execution)
    if task isa TaskGroup
        for inner in eachindex(task.tasks)
            _end_unstarted_task!(task, inner, reason, nothing, nothing, nothing)
        end
        result = compute_task_group_result(task)
    else
        result = TaskNotStarted(task, "CANCEL", group.codes.expected, reason, nothing)
    end
    finish_task_execution!(execution, result)
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
    run = group.preparation_run
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
    group.scheduler === nothing || wait(group.scheduler)
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
    follow(g) = update_task_execution!(execution) do e
        e.progress = measure_task_group_progress(g)
        e.position = _format_task_group_position(g)
    end
    update_task_execution!(execution) do e
        e.status = :running
        e.start_time = time()
    end
    follow(group)
    start_task_group!(group; on_change = follow)
    execution.reader = @async begin
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
    result = compute_task_group_result(group)
    counts = Dict{String,Int}()
    for task_result in result.results
        counts[task_result.result] = get(counts, task_result.result, 0) + 1
    end
    finished = length(result.results)
    leaves = _collect_task_group_leaves(group)
    running = count(((_, run),) -> run !== nothing && run.result === nothing, leaves)
    (counts = counts,
     overall = result.result,
     total = length(leaves),
     finished = finished,
     running = running,
     pending = length(leaves) - finished - running)
end

"""
    measure_task_group_progress(group) -> Float64

How much of the group is done, between 0 and 1. A finished task counts whole,
and a task that is going counts the fraction it reports, or nothing when it
reports none.
"""
function measure_task_group_progress(group::TaskGroup)
    leaves = _collect_task_group_leaves(group)
    isempty(leaves) && return 1.0
    done = 0.0
    for (_, run) in leaves
        run === nothing && continue
        if run.result !== nothing
            done += 1.0
        elseif run.progress !== nothing
            done += run.progress
        end
    end
    clamp(done / length(leaves), 0.0, 1.0)
end

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
    result = isempty(results) ? String(expected_result) : first(codes.codes)
    for code in codes.codes
        if num_expected[code] != 0
            result = code
            break
        end
    end
    for code in codes.codes
        num_unexpected[code] != 0 && (result = code)
    end
    results = TaskResult[r for r in results]
    TaskGroupResult(group, results, codes, String(expected_result),
                    _format_unexpected_reason(results),
                    elapsed_wall_time === nothing ? nothing : Float64(elapsed_wall_time),
                    num_expected, num_unexpected, different, result)
end

get_result_codes(result::TaskGroupResult) = result.codes

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
function format_task_group_summary(result::TaskGroupResult)
    length(result.results) == 1 && return format_task_result(only(result.results))
    texts = String[]
    result.num_different_results != 1 && push!(texts, string(length(result.results), " TOTAL"))
    for code in result.codes.codes
        plain = get_result_role(result.codes, code) === :success
        expected = result.num_expected[code]
        unexpected = result.num_unexpected[code]
        expected != 0 && push!(texts, string(expected, " ", code, plain ? "" : " (expected)"))
        unexpected != 0 && push!(texts, string(unexpected, " ", code, plain ? "" : " (unexpected)"))
    end
    join(texts, ", ") *
        (_has_time(result.elapsed_wall_time) ? " in " * format_elapsed_time(result.elapsed_wall_time) : "")
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

function _format_unexpected_reason(results::Vector{TaskResult})
    counts = Pair{String,Int}[]                 # in the order the details appear
    for task_result in results
        is_expected(task_result) && continue
        detail = _has_text(task_result.reason) ? task_result.reason : task_result.result
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
    string(sum(last, counts), "/", length(results), " unexpected: ") * join(parts, ", ")
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
    compute_task_group_summary(group; now = time()) -> TaskGroupSummary

The [`TaskGroupSummary`](@ref) of the group now. Each record is read under its
lock, so a reader on another task than the readers of the processes may call it.
"""
function compute_task_group_summary(group::TaskGroup; now::Real = time())
    results = TaskResult[]
    running = 0
    progress = 0.0
    durations = Float64[]
    slowest = nothing
    leaves = _collect_task_group_leaves(group)
    for (task, run) in leaves
        run === nothing && continue
        (result, fraction, started, ended) = lock(run.lock) do
            (run.result, run.progress, run.start_time, run.end_time)
        end
        if result === nothing
            running += 1
            progress += something(fraction, 0.0)
            continue
        end
        push!(results, result)
        progress += 1.0
        if started !== nothing && ended !== nothing
            duration = ended - started
            push!(durations, duration)
            (slowest === nothing || duration > slowest[2]) &&
                (slowest = (format_task_parameters(task), duration))
        end
    end
    elapsed = group.start_time === nothing ? nothing : something(group.end_time, now) - group.start_time
    result = TaskGroupResult(results; codes = group.codes, elapsed_wall_time = elapsed, group = group)
    total = length(leaves)
    pending = total - length(results) - running
    counts = Tuple{String,Int,Int}[(code, result.num_expected[code], result.num_unexpected[code])
                                   for code in group.codes.codes
                                   if result.num_expected[code] + result.num_unexpected[code] > 0]
    left = pending + running
    remaining = (isempty(durations) || left == 0) ? nothing :
                sum(durations) / length(durations) * left / group.jobs
    rate = (elapsed === nothing || elapsed <= 0 || isempty(results)) ? nothing :
           length(results) / elapsed * 60
    TaskGroupSummary(total, length(results), running, pending, counts, result.result,
                     is_expected(result), isempty(results) ? "" : format_task_group_summary(result),
                     format_task_group_reason(result), total == 0 ? 1.0 : clamp(progress / total, 0.0, 1.0),
                     elapsed, remaining, rate, slowest)
end
