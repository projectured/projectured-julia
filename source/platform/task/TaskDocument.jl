# The document of one task: the task, its executions, and what the current
# execution says while it runs and when it ends. The slice knows nothing of what
# the task does; a view asks the task for what its kind adds
# ([`get_task_columns`](@ref)).

"""
    TaskDocument(task; status = :pending, progress = nothing)

One task as a document: the task, the state of its current execution, what it
ended with, and the executions before it.

Use it to show a task, and to start and stop it. A group of tasks holds one for
each of its tasks ([`TaskGroupDocument`](@ref)).

# Example

    document = TaskDocument(task)
    start_task!(document)
    wait_task_document(document)
    getfield(document, :status)[]          # :done

# Fields
- `task` — the task that runs, an `AbstractTask` of a domain. It does not change.
- `status::Symbol` — `:pending`, `:running`, `:cancelling`, `:done`, `:error`,
  `:cancelled` or `:skipped`.
- `progress` — a fraction in `[0, 1]` while the task runs, or `nothing` when the
  kind of task cannot say.
- `position` — where the task is, as a short text that its kind writes, such as
  `event #4200 t=1.5`, or `nothing`.
- `output` — the lines that the task printed on stdout, newest last, as a
  `Vector{String}`. A long task keeps its first and its last lines, and one line
  between them says how many were left out ([`TaskOutput`](@ref)).
- `error_output` — the lines on stderr, as `output` holds those of stdout.
- `process_id` — the identifier of the process while it runs, and after.
- `start_time`/`end_time` — when the task started and ended, as `time()` gives
  it.
- `processor_load` — the processor time that the process used, in percent of one
  processor, over the last interval.
- `resident_memory` — the memory of the process, in bytes.
- `running` — the current [`TaskExecution`](@ref): the one that the fields above
  show, from its start until the task waits to start again; `nothing` before.
- `result` — what the current execution ended with, a `TaskResult` of its kind.
- `executions` — every `TaskExecution` of the task, the newest last. A start
  again adds one and replaces none ([`add_task_execution!`](@ref)).

[`write_task_snapshot!`](@ref) writes every field that an execution changes, on
the task that reads the document: a [`TaskFeed`](@ref) carries what the
execution says to it.
"""
@document struct TaskDocument <: Document
    task::Any
    status::Symbol
    progress::Any
    position::Any
    output::Any
    error_output::Any
    process_id::Any
    start_time::Any
    end_time::Any
    processor_load::Any
    resident_memory::Any
    running::Any
    result::Any
    executions::Any
end

TaskDocument(task; status::Symbol = :pending, progress = nothing) =
    TaskDocument(Cell(task), Cell(status), Cell(progress), Cell(nothing),
                 Cell(String[]), Cell(String[]), Cell(nothing), Cell(nothing),
                 Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                 Cell(nothing), Cell(TaskExecution[]), Cell(nothing))

# A task is a tool: its view starts and stops a process. A paste leaves it alone.
# Its duplicate is the same task, not started, with a state of its own and an
# execution of its own once it runs; the task is a value that it shares.
accepts_pasted_document(::TaskDocument) = false
has_document_duplicate(::TaskDocument) = true
copy_document(policy::DuplicatePolicy, document::TaskDocument) =
    copy_document_fields(policy, document; status = :pending, progress = nothing,
                         position = nothing, output = String[], error_output = String[],
                         process_id = nothing, start_time = nothing, end_time = nothing,
                         processor_load = nothing, resident_memory = nothing,
                         running = nothing, result = nothing,
                         executions = TaskExecution[])

"""
    start_task!(document; options...) -> document

Start the task of `document` and answer at once. `options` go to the
[`start_task`](@ref) of its kind. The session `TaskFeedStore` carries what the
execution says into the document: a window copies it a few times a second, and
a caller with no window reads it after [`wait_task_document`](@ref).
"""
function start_task!(document::TaskDocument; options...)
    reset_task_document!(document, :running)
    execution = start_task(getfield(document, :task)[]; options...)
    add_task_execution!(document, execution)
    register_task_execution!(get_session_task_feed_store(), execution,
                             snapshot -> write_task_snapshot!(document, snapshot))
    document
end

"""
    wait_task_document(document) -> document

Wait for the execution of the task to end, and copy what it said into the
document. For a caller with no window, on the task that reads the document.
"""
function wait_task_document(document::TaskDocument)
    execution = getfield(document, :running)[]
    execution === nothing || wait_task_execution(execution)
    drain_task_feed!()
    document
end

"""
    stop_task!(document) -> document

Stop the execution of the task with `SIGINT`. Nothing happens when the task did
not start or has ended.
"""
function stop_task!(document::TaskDocument)
    execution = getfield(document, :running)[]
    execution === nothing || stop_task_execution!(execution)
    document
end

"""
    reset_task_document!(document, status) -> document

Put the document back to the state of a task that has not printed anything,
with `status`, before the task starts again. The document has no current
execution then, and keeps every execution before.
"""
function reset_task_document!(document::TaskDocument, status::Symbol)
    set_cell_value!(getfield(document, :status), status)
    set_cell_value!(getfield(document, :output), String[])
    set_cell_value!(getfield(document, :error_output), String[])
    for field in (:progress, :position, :process_id, :start_time, :end_time,
                  :processor_load, :resident_memory, :running, :result)
        set_cell_value!(getfield(document, field), nothing)
    end
    document
end

"""
    add_task_execution!(document, execution) -> document

Make `execution` the current execution of the document, and add it to its
executions, the newest last. Call it on the task that reads the document, when
the execution starts.
"""
function add_task_execution!(document::TaskDocument, execution::TaskExecution)
    set_cell_value!(getfield(document, :running), execution)
    set_cell_value!(getfield(document, :executions),
                    vcat(getfield(document, :executions)[], execution))
    document
end

"""
    get_earlier_task_executions(document) -> Vector{TaskExecution}

The executions of the task that its document does not show as current, the
newest last: all of them while the task waits to start again.
"""
function get_earlier_task_executions(document::TaskDocument)
    current = getfield(document, :running)[]
    TaskExecution[e for e in getfield(document, :executions)[] if e !== current]
end

"""
    write_task_snapshot!(document, snapshot) -> (before, after)

Write a copy of a `TaskExecution` ([`get_task_execution_snapshot`](@ref)) into
the document, and answer the status before and after, so a group of tasks can
keep its count. A value that did not change is not written, so a reader of it
is not invalidated; a stream whose lines did not change comes as `nothing` and
stays as it is.
"""
function write_task_snapshot!(document::TaskDocument, snapshot)
    before = getfield(document, :status)[]
    for field in (:process_id, :start_time, :end_time, :processor_load,
                  :resident_memory, :position, :progress)
        _write_if_changed!(getfield(document, field), getfield(snapshot, field))
    end
    snapshot.output === nothing ||
        set_cell_value!(getfield(document, :output), snapshot.output)
    snapshot.error_output === nothing ||
        set_cell_value!(getfield(document, :error_output), snapshot.error_output)
    if snapshot.result === nothing
        _write_if_changed!(getfield(document, :status), snapshot.status)
    else
        record_task_result!(document, snapshot.result)
    end
    (before, getfield(document, :status)[])
end

_write_if_changed!(cell, value) = isequal(cell[], value) || set_cell_value!(cell, value)

"""
    record_task_result!(document, result) -> document

Put what a task ended with into the document: the result, and the status of its
code ([`get_task_status`](@ref)).
"""
function record_task_result!(document::TaskDocument, result::TaskResult)
    set_cell_value!(getfield(document, :status), get_task_status(result.result))
    set_cell_value!(getfield(document, :result), result)
    document
end
