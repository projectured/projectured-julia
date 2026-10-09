# The document of one task: the task and its executions, each as the shadow that
# a view reads. The slice knows nothing of what the task does; a view asks the
# task for what its kind adds ([`get_task_columns`](@ref)).

"""
    TaskDocument(task; status = :pending, progress = nothing)

One task as a document: the task, its current execution, and the executions
before it.

Use it to show a task, and to start and stop it. A group of tasks holds one for
each of its tasks ([`TaskGroupDocument`](@ref)). A `status` other than
`:pending` gives the document an execution that holds `status` and `progress`
and runs no process, for an example or a picture of a task.

# Example

    document = TaskDocument(task)
    start_task!(document)
    wait_task_document(document)
    get_task_document_status(document)       # :done

# Fields
- `task` — the task that runs, an `AbstractTask` of a domain. It does not change.
- `running` — the native layout of the current [`TaskExecution`](@ref), which a
  stop and a wait act on: from the start of the execution until the task waits
  to start again; `nothing` before.
- `executions` — the shadow of every execution of the task, the newest last. A
  view reads them; the feed of the session syncs each one while its execution
  runs. A start again adds one and replaces none ([`add_task_execution!`](@ref)).
- `result_document` — the document that the kind of the task gives for the
  result of the current execution ([`get_task_result_document`](@ref)), or
  `nothing`. It computes when a view reads it, on the editor task, and stays the
  same document until the result changes, so an edit of it stays while the
  person looks at another task. A path reaches it, so a key edits it where the
  detail of the task shows it.

While the document has a current execution, its shadow is the last of
`executions` ([`get_current_task_execution`](@ref)).
"""
@document struct TaskDocument <: Document
    task::Any
    running::Any
    executions::Any
    result_document::Any
end

function TaskDocument(task; status::Symbol = :pending, progress = nothing)
    document = _follow_result_document!(TaskDocument(Cell(task), Cell(nothing), Cell(Any[]),
                                                     Cell(nothing), Cell(nothing)))
    status === :pending && return document
    execution = TaskExecution(task)
    execution.status = status
    execution.progress = progress
    add_task_execution!(document, execution, make_task_execution_shadow(execution))
end

# A task is a tool: its view starts and stops a process. A paste leaves it alone.
# Its duplicate is the same task, not started, with executions of its own once
# it runs; the task is a value that it shares.
accepts_pasted_document(::TaskDocument) = false
has_document_duplicate(::TaskDocument) = true
copy_document(policy::DuplicatePolicy, document::TaskDocument) =
    _follow_result_document!(copy_document_fields(policy, document; running = nothing,
                                                  executions = Any[], result_document = nothing))

# The document of the result follows the result of the current execution.
function _follow_result_document!(document::TaskDocument)
    set_cell_computation!(getfield(document, :result_document), () -> begin
        result = get_task_document_result(document)
        result === nothing ? nothing : get_task_result_document(getfield(document, :task)[], result)
    end)
    document
end

"""
    get_current_task_execution(document) -> shadow or nothing

The shadow of the current execution of the task, or `nothing` before its first
start and while it waits to start again.
"""
function get_current_task_execution(document::TaskDocument)
    getfield(document, :running)[] === nothing && return nothing
    last(getfield(document, :executions)[])
end

"""
    get_task_document_status(document) -> Symbol

The status of the current execution, or `:pending` when the document has none.
"""
function get_task_document_status(document::TaskDocument)
    current = get_current_task_execution(document)
    current === nothing ? :pending : current.status
end

"""
    get_task_document_result(document) -> TaskResult or nothing

What the current execution ended with, or `nothing` while it runs or when the
document has none.
"""
function get_task_document_result(document::TaskDocument)
    current = get_current_task_execution(document)
    current === nothing ? nothing : current.result
end

"""
    collect_task_document_lines(document, stream = :output) -> Vector{String}

The kept lines of one stream of the current execution, `:output` or
`:error_output`; none when the document has no current execution.
"""
function collect_task_document_lines(document::TaskDocument, stream::Symbol = :output)
    current = get_current_task_execution(document)
    current === nothing ? String[] : collect_output_lines(getproperty(current, stream))
end

"""
    start_task!(document; options...) -> document

Start the task of `document` and answer at once. `options` go to the
[`start_task`](@ref) of its kind. The execution and its shadow are the current
ones at once, and the session `TaskFeedStore` syncs the shadow: a window a few
times a second, and a caller with no window after
[`wait_task_document`](@ref).
"""
function start_task!(document::TaskDocument; options...)
    execution = start_task(getfield(document, :task)[]; options...)
    shadow = make_task_execution_shadow(execution)
    add_task_execution!(document, execution, shadow)
    register_task_execution!(get_session_task_feed_store(), execution, document; shadow)
    document
end

"""
    wait_task_document(document) -> document

Wait for the current execution of the task to end, and sync what it said into
its shadow. For a caller with no window, on the task that reads the document.
"""
function wait_task_document(document::TaskDocument)
    execution = getfield(document, :running)[]
    execution === nothing || wait_task_execution(execution)
    drain_task_feed!()
    document
end

"""
    stop_task!(document) -> document

Stop the current execution of the task with `SIGINT`. Nothing happens when the
task did not start or has ended.
"""
function stop_task!(document::TaskDocument)
    execution = getfield(document, :running)[]
    execution === nothing || stop_task_execution!(execution)
    document
end

"""
    reset_task_document!(document) -> document

Make the task wait to start again: the document has no current execution then,
and keeps every execution before.
"""
function reset_task_document!(document::TaskDocument)
    set_cell_value!(getfield(document, :running), nothing)
    document
end

"""
    add_task_execution!(document, execution, shadow) -> document

Make `execution` the current execution of the document, and add its shadow to
the executions, the newest last. Call it on the task that reads the document,
when the execution starts.
"""
function add_task_execution!(document::TaskDocument, execution::TaskExecution, shadow)
    set_cell_value!(getfield(document, :executions),
                    push!(copy(getfield(document, :executions)[]), shadow))
    set_cell_value!(getfield(document, :running), execution)
    document
end

"""
    get_earlier_task_executions(document) -> Vector

The shadows of the executions that the document does not show as current, the
newest last: all of them while the task waits to start again.
"""
function get_earlier_task_executions(document::TaskDocument)
    executions = getfield(document, :executions)[]
    getfield(document, :running)[] === nothing ? collect(executions) : executions[1:end-1]
end

# A document is the owner of an execution that it started itself, and then it
# has the shadow already. A drain that made the shadow is for an execution that
# a group started for this document, its preparation: the document starts
# afresh with it.
function record_task_execution_sync!(document::TaskDocument, execution, shadow,
                                     before::Symbol, made::Bool)
    made || return nothing
    reset_task_document!(document)
    add_task_execution!(document, execution, shadow)
    nothing
end
