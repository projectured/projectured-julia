# The document of one task: the task and its executions, each as the shadow that
# a view reads. The slice knows nothing of what the task does; a view asks the
# task for what its kind adds ([`get_task_columns`](@ref)).

"""
    TaskDocument(task; status = :pending, progress = nothing, identifier = "", title = "")

One task as a document: the task, its current execution, and the executions
before it.

Use it to show a task, and to start and stop it. A group of tasks holds one for
each of its tasks ([`TaskGroupDocument`](@ref)). A task with no group and an
`identifier` is a row of the task list of its own, a task alone, which
`run_tasks!(task)` starts. A `status` other than `:pending` gives the document an
execution that holds `status` and `progress` and runs no process, for an example
or a picture of a task.

# Example

    found_1 = search_documents(find_task_group("T3"), part -> part isa TaskDocument)

See also `TaskGroupDocument`, `TaskExecution`, `find_task_group` and `list_task_groups`.

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
- `kind_document` — the document that the kind of the task gives
  ([`make_task_kind_document`](@ref)), or `nothing`. It exists before the
  result and is made again when the result of the current execution changes. It
  computes when a view reads it, on the editor task, and stays the
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
- `inner_group` — the [`TaskGroupDocument`](@ref) of a task that is a group, or
  `nothing`. It is a field, so the inner group has a path under the outer group,
  `tasks[i].inner_group`, and the page of the task shows the page of that group.
- `identifier` — `T1`, `T2`, … for a task alone, from the counter of the groups
  ([`make_task_group_identifier`](@ref)), so its row and its closed row keep it;
  an empty string for a task of a group.
- `title` — what the row and the page of a task alone call it, or an empty string
  for the task in one line ([`format_task_parameters`](@ref)).
- `started_by` — who started a task alone, a [`WorkStarter`](@ref) that its first
  start records, or `nothing` before it and for a task of a group, whose group
  records it.

While the document has a current execution, its shadow is the last of
`executions` ([`get_current_task_execution`](@ref)).

For the assistant.
"""
@document struct TaskDocument <: Document
    task::Any
    running::Any
    executions::Any
    kind_document::Any
    process_tree::Any
    group::Any
    inner_group::Any
    identifier::String
    title::String
    started_by::Any
end

function TaskDocument(task; status::Symbol = :pending, progress = nothing, identifier::AbstractString = "",
                      title::AbstractString = "")
    document = _follow_current_execution!(TaskDocument(Cell(task), Cell(nothing), Cell(CellVector()),
                                                       Cell(nothing), Cell(nothing), Cell(Ref{Any}(nothing)),
                                                       Cell(nothing), Cell(String(identifier)), Cell(String(title)),
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

# A search finds the group of a task where the group is, not back through the task.
is_field_walked(::TaskDocument, name::Symbol) = name !== :group

"""
    is_task_search_field(parent, name) -> Bool

Whether a search for tasks reads the field `name` of `parent`: from a task, only
its inner group, which holds the tasks of a task that is a group; from a group,
only its tasks and its preparation; from anything else, every field. So a search
for the tasks of a group reads no task value, no execution and no kind document
of a task, and computes none of them.

Use it as the `enter_field` of a search for tasks, such as the source of a roster
of the tasks of groups.

# Example

    Roster(ItemsWithin(CollectionItems(@reference(groups)), TaskDocument; enter_field = is_task_search_field))
"""
is_task_search_field(parent, name) = true
is_task_search_field(parent::TaskDocument, name) = name === :inner_group

# A file that keeps a roster of tasks names the function.
is_pred_constructible(::typeof(is_task_search_field)) = true
copy_document(policy::DuplicatePolicy, document::TaskDocument) =
    _follow_current_execution!(copy_document_fields(policy, document; running = nothing,
                                                    executions = CellVector(), kind_document = nothing,
                                                    process_tree = nothing, group = Ref{Any}(nothing),
                                                    inner_group = nothing, identifier = "",
                                                    started_by = nothing))

# A task is called by its title, or by the task in one line, as the list of tasks
# writes it.
function get_document_title(document::TaskDocument)
    title = getfield(document, :title)[]
    isempty(title) ? format_task_parameters(getfield(document, :task)[]) : title
end

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
    inner = getfield(document, :inner_group)[]
    inner === nothing || remove_task_output_files!(inner)
    document
end

# The document of the kind is made before the result and again when the result
# changes, and the tree of the processes follows its process until the result comes.
function _follow_current_execution!(document::TaskDocument)
    set_cell_computation!(getfield(document, :kind_document), () ->
        make_task_kind_document(getfield(document, :task)[], get_task_document_result(document)))
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

# A field of the current execution of a task, as its shadow holds it, or
# `nothing` when the task has no current execution.
function _get_current_field(document::TaskDocument, name::Symbol)
    current = get_current_task_execution(document)
    current === nothing ? nothing : getproperty(current, name)
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
# and groups by. The columns of the kind of the task are facets too
# ([`get_task_columns`](@ref)); a facet below wins over a column of the same name.
get_item_facets(::Type{TaskDocument}) = [
    "name" => "the task in one line, as the list of tasks writes it",
    "status" => "the status of the current execution: pending, running, cancelling, done, error, " *
                "cancelled or skipped",
    "result" => "the result code of the current execution, such as PASS or ERROR, or nothing before it ends",
    "expected" => "whether that result is the expected one, true or false, or nothing before it ends",
    "reason" => "why the result is what it is, such as the first error, or nothing",
    "expected_result" => "the code that the result is expected to be: the code of the result after the task ends, " *
                         "before that the expected code that the kind of the task says, or nothing",
    "state" => "the word that the table of a group shows for the task: its result code once it ends, else " *
               "running, stopping or its status",
    "progress" => "the fraction of the work that the running task reports, or nothing",
    "elapsed" => "the time in seconds that a finished task took, or nothing while it runs or before it starts",
    "process" => "the number of the process of the current execution, or nothing",
    "processor" => "the load of the processor of the current execution, in percent, or nothing",
    "memory" => "the resident memory of the process of the current execution, in bytes, or nothing",
    "kind" => "the column kind of the kind of the task when it has one; else \"task\" for a task alone, a row " *
              "of the task list, or nothing"]
compute_item_facet(document::TaskDocument, ::Val{:name}) = format_task_parameters(getfield(document, :task)[])
compute_item_facet(document::TaskDocument, ::Val{:status}) = get_task_document_status(document)
compute_item_facet(document::TaskDocument, ::Val{:result}) =
    (result = get_task_document_result(document); result === nothing ? nothing : result.result)
compute_item_facet(document::TaskDocument, ::Val{:expected}) =
    (result = get_task_document_result(document); result === nothing ? nothing : is_expected(result))
compute_item_facet(document::TaskDocument, ::Val{:reason}) =
    (result = get_task_document_result(document); result === nothing ? nothing : result.reason)
function compute_item_facet(document::TaskDocument, ::Val{:expected_result})
    result = get_task_document_result(document)
    result === nothing || return result.expected_result
    text = format_task_column(getfield(document, :task)[], "expected_result")
    isempty(text) ? nothing : text
end
compute_item_facet(document::TaskDocument, ::Val{:state}) = _get_task_state_word(document)
compute_item_facet(document::TaskDocument, ::Val{:progress}) = _get_current_field(document, :progress)
function compute_item_facet(document::TaskDocument, ::Val{:elapsed})
    (started, ended) = _get_task_document_times(document)
    (started === nothing || ended === nothing) ? nothing : ended - started
end
compute_item_facet(document::TaskDocument, ::Val{:process}) = _get_current_field(document, :process_id)
compute_item_facet(document::TaskDocument, ::Val{:processor}) = _get_current_field(document, :processor_load)
compute_item_facet(document::TaskDocument, ::Val{:memory}) = _get_current_field(document, :resident_memory)
function compute_item_facet(document::TaskDocument, ::Val{:kind})
    task = getfield(document, :task)[]
    any(column -> first(column) == "kind", get_task_columns(task)) &&
        return get_task_column_value(task, get_task_document_result(document), "kind")
    isempty(getfield(document, :identifier)[]) ? nothing : describe_work_item_kind(document, 1)
end

# What a task document says in the column `state` of a table of tasks: its result
# code once it has one, else the state it is in.
function _get_task_state_word(document::TaskDocument)
    result = get_task_document_result(document)
    result === nothing || return result.result
    status = get_task_document_status(document)
    status === :running ? "running" : status === :cancelling ? "stopping" : string(status)
end

# The facets of the items of one kind of task: the declared facets of a task and
# the columns of its kind. The task of a document does not change, so the type
# of the task says which columns the document has.
struct TaskKindFacets{T} end

get_item_facet_type(document::TaskDocument) = TaskKindFacets{typeof(getfield(document, :task)[])}

# A field of the document wins over a column of the same name, as it wins over a
# facet; a column of the kind is the value that `get_task_column_value` gives for
# the task and its result.
function has_item_facet(document::TaskDocument, name::AbstractString)
    _has_item_facet(TaskDocument, name) && return true
    Symbol(name) in fieldnames(TaskDocument) && return false
    any(column -> first(column) == name, get_task_columns(getfield(document, :task)[]))
end
compute_item_facet(document::TaskDocument, name::Val{:type}) =
    invoke(compute_item_facet, Tuple{Document,Val{:type}}, document, name)
compute_item_facet(document::TaskDocument, name::Val) =
    get_task_column_value(getfield(document, :task)[], get_task_document_result(document),
                          String(only(typeof(name).parameters)))

# The node of a task in a tree: its name; its decoration says its status as its
# icon, the code of its result as a count, and the time when it started or how
# long it ran as its detail. It reads no clock, so it changes only when the task
# does. A task that is a group has the tasks of its inner group under its node;
# any other task is a leaf.
function get_tree_children_steps(document::TaskDocument)
    getfield(document, :inner_group)[] === nothing && return ()
    ((FieldReferenceStep("inner_group"), FieldReferenceStep("tasks")),)
end

function format_tree_node_label(document::TaskDocument)
    name = get_document_title(document)
    isempty(name) ? String(get_task_document_status(document)) : name
end

# A task is a work item: its icon is its status, and an ended task whose result is
# not the expected one shows a cross, whatever its status.
function get_document_decoration(document::TaskDocument)
    status = get_task_document_status(document)
    result = get_task_document_result(document)
    conditions = DocumentCondition[]
    counts = DocumentCount[]
    status in (:running, :cancelling) && push!(conditions, DocumentCondition(:running))
    status === :pending && push!(conditions, DocumentCondition(:pending))
    status in (:cancelled, :skipped) && push!(conditions, DocumentCondition(:stopped))
    expected = result === nothing || is_expected(result)
    if result !== nothing
        role = get_result_role(get_result_codes(result), result.result)
        push!(counts, DocumentCount(result.result; role))
        push!(conditions, expected ? DocumentCondition(:done) :
                          DocumentCondition(role === :error ? :failed : :unexpected; role))
    elseif status === :error
        push!(conditions, DocumentCondition(:failed))
    end
    icon = !expected ? :x :
           status in (:running, :cancelling) ? :loader : status === :done ? :circle_check :
           status === :error ? :warning : status === :cancelled ? :stop :
           status === :skipped ? :skip_forward : :circle
    (started, ended) = _get_task_document_times(document)
    detail = started === nothing ? String(status) :
             ended === nothing ? String(status) * " since " * Libc.strftime("%H:%M:%S", started) :
             result === nothing ? String(status) * " · " * format_elapsed_time(ended - started; precision = 1) :
             format_elapsed_time(ended - started; precision = 1)
    DocumentDecoration(; icon, conditions, counts, detail, tooltip = () -> _make_task_note(document), work_item = true)
end

# What a row of a task says when the pointer rests on it: the task line, the
# facts of its current execution, and why its result is what it is, or what
# the kind of task says about its result.
function _make_task_note(document::TaskDocument)
    task = getfield(document, :task)[]
    current = get_current_task_execution(document)
    current === nothing && return TooltipNote(; title = format_task_parameters(task), facts = ["State" => "pending"])
    result = current.result
    facts = Pair{String,Any}["State" => string(current.status)]
    result === nothing || push!(facts, "Result" => string(result.result))
    current.start_time === nothing || push!(facts, "Started" => Libc.strftime("%H:%M:%S", current.start_time))
    current.start_time === nothing ||
        push!(facts, "Duration" => format_elapsed_time((current.end_time === nothing ? time() : current.end_time) -
                                                       current.start_time; precision = 1))
    current.position === nothing || isempty(current.position) || push!(facts, "Position" => string(current.position))
    current.process_id === nothing || push!(facts, "Process" => string(current.process_id))
    current.resident_memory === nothing ||
        push!(facts, "Memory" => string(round(current.resident_memory / 2^20; digits = 1), " MB"))
    text = result !== nothing && result.reason !== nothing ? string(result.reason) : nothing
    TooltipNote(; title = format_task_parameters(task), text, facts)
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
    start_task!(document; editor = find_evaluation_editor(), started_by = get_work_starter(),
                options...) -> document

Start the task of `document` and answer at once. `options` go to the
[`start_task`](@ref) of its kind. The execution and its shadow are the current
ones at once, and the session `TaskFeedStore` syncs the shadow: the window of
`editor` a few times a second, and a caller with no window after
[`wait_task_document`](@ref).

A task alone, which has an `identifier`, is a row of the task list: its first
start records `started_by`, who started it, and each start puts the row at the
end of the list of the session of `editor`, or back into its place when a person
closed it. A start that throws, such as a program in a folder that does not exist,
adds no row.
"""
function start_task!(document::TaskDocument; editor = find_evaluation_editor(),
                     started_by = get_work_starter(), options...)
    execution = start_task(getfield(document, :task)[]; options...)
    shadow = make_task_execution_shadow(execution)
    add_task_execution!(document, execution, shadow)
    register_task_execution!(get_session_task_feed_store(), execution, document; shadow, editor)
    isempty(getfield(document, :identifier)[]) && return document
    starter = getfield(document, :started_by)
    starter[] === nothing && set_cell_value!(starter, started_by)
    add_task_group!(get_session_task_group_list(; editor), document)
    document
end

"""
    wait_task_document(document; editor = find_evaluation_editor()) -> document

Wait for the current execution of the task to end, and sync what it said into
its shadow. For a caller with no window, on the task that reads the document;
`editor` is the editor that started the task, if any.
"""
function wait_task_document(document::TaskDocument; editor = find_evaluation_editor())
    execution = getfield(document, :running)[]
    execution === nothing || wait_task_execution(execution)
    drain_task_feed!(; editor)
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
