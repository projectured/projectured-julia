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
- `executions` — the shadow of every execution of the task, the newest last, in
  a `CellVector`, so a selection goes into the page of an execution and of its
  streams. A view reads them; the feed of the session syncs each one while its
  execution runs. A start again adds one and replaces none
  ([`add_task_execution!`](@ref)).
- `result_document` — the document that the kind of the task gives for the
  result of the current execution ([`get_task_result_document`](@ref)), or
  `nothing`. It computes when a view reads it, on the editor task, and stays the
  same document until the result changes, so an edit of it stays while the
  person looks at another task. A path reaches it, so a key edits it where the
  detail of the task shows it.
- `process_tree` — the [`SystemProcessTree`](@ref) of the processes under the
  process of the current execution, or `nothing` while it has no process or has
  a result. It computes when a view reads it, and stays the same tree while the
  process runs. The feed of the session samples it while a view reads it, and
  the detail of the task shows it below its facts.
- `group` — a `Ref` to the group document that holds the task and the place of
  the task in it, `(group, index)`, which [`wrap_task_group_document`](@ref)
  sets, or to `nothing` for a task of no group. The page of the task stops it and
  runs it again through its group, so the counts of the group stay right. A
  `Ref`, so a walk and a copy of the documents do not go round through it.

While the document has a current execution, its shadow is the last of
`executions` ([`get_current_task_execution`](@ref)).
"""
@document struct TaskDocument <: Document
    task::Any
    running::Any
    executions::Any
    result_document::Any
    process_tree::Any
    group::Any
end

function TaskDocument(task; status::Symbol = :pending, progress = nothing)
    document = _follow_current_execution!(TaskDocument(Cell(task), Cell(nothing), Cell(CellVector()),
                                                       Cell(nothing), Cell(nothing), Cell(Ref{Any}(nothing)),
                                                       Cell(nothing)))
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
    _follow_current_execution!(copy_document_fields(policy, document; running = nothing,
                                                    executions = CellVector(), result_document = nothing,
                                                    process_tree = nothing, group = Ref{Any}(nothing)))

# A task is called by the task in one line, as the list of tasks writes it.
get_document_title(document::TaskDocument) = format_task_parameters(getfield(document, :task)[])

"""
    find_task_document_group(document) -> (group, index) or nothing

The group document that holds the task and the place of the task in it, or
`nothing` for a task of no group.
"""
find_task_document_group(document::TaskDocument) = getfield(document, :group)[][]

"""
    remove_task_output_files!(document::TaskDocument) -> document

Remove the files of the streams of every execution of the task; the kept lines
stay.
"""
function remove_task_output_files!(document::TaskDocument)
    for shadow in getfield(document, :executions)[]
        remove_task_output_files!(shadow.output)
        remove_task_output_files!(shadow.error_output)
    end
    document
end

# The document of the result follows the result of the current execution, and the
# tree of the processes follows its process until the result comes.
function _follow_current_execution!(document::TaskDocument)
    set_cell_computation!(getfield(document, :result_document), () -> begin
        result = get_task_document_result(document)
        result === nothing ? nothing : get_task_result_document(getfield(document, :task)[], result)
    end)
    set_cell_computation!(getfield(document, :process_tree), () -> begin
        current = get_current_task_execution(document)
        process_id = current === nothing ? nothing : current.process_id
        (process_id === nothing || current.result !== nothing) ? nothing : SystemProcessTree([process_id])
    end)
    document
end

# A view that reads the tree of the processes made it; the feed samples it then.
# A tree that no view read is not made for the drain.
function _drain_task_process_tree!(document::TaskDocument, now)
    cell = getfield(document, :process_tree)
    is_cell_valid(cell) || return nothing
    tree = peek(cell)
    tree === nothing || drain_system_process_tree!(tree; now)
    nothing
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

# The facets of a task in a roster of tasks, which a roster shows, filters, sorts
# and groups by.
get_item_facets(::Type{TaskDocument}) = [
    "name" => "the task in one line, as the list of tasks writes it",
    "status" => "the status of the current execution: pending, running, cancelling, done, error, " *
                "cancelled or skipped"]
compute_item_facet(document::TaskDocument, ::Val{:name}) = format_task_parameters(getfield(document, :task)[])
compute_item_facet(document::TaskDocument, ::Val{:status}) = get_task_document_status(document)

# The node of a task in a tree is a leaf: its name, its status and the time when
# it started while it runs, or the code of its result and how long it ran, with an
# icon of its status. It reads no clock, so it changes only when the task does.
function format_tree_node_label(document::TaskDocument)
    words = String[format_task_parameters(getfield(document, :task)[])]
    result = get_task_document_result(document)
    status = get_task_document_status(document)
    state = result === nothing ? String(status) : result.result
    (started, ended) = _get_task_document_times(document)
    if started === nothing
        push!(words, state)
    elseif ended === nothing
        push!(words, state * " since " * Libc.strftime("%H:%M:%S", started))
    else
        push!(words, state, format_elapsed_time(ended - started; precision = 1))
    end
    join(words, " · ")
end

function get_tree_node_icon(document::TaskDocument)
    status = get_task_document_status(document)
    status in (:running, :cancelling) ? :loader : status === :done ? :circle_check :
    status === :error ? :warning : status === :cancelled ? :stop :
    status === :skipped ? :skip_forward : :circle
end

# The start and the end of the current execution, each `nothing` before it.
function _get_task_document_times(document::TaskDocument)
    current = get_current_task_execution(document)
    current === nothing ? (nothing, nothing) : (current.start_time, current.end_time)
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

# Stop the current execution of the task with `SIGINT`. Nothing happens when the
# task did not start or has ended. The verb of a group, `stop_task!(group, index)`,
# carries the docstring of the name.
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
    push!(getfield(document, :executions)[], shadow)
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
