# The verbs of tasks: what a person at the REPL and a model through
# `execute_julia_code` call to read and to act on the groups of tasks of the
# session — list them, find one, describe a group or one task of it, read the
# output of a task, stop, run again, wait and close. A domain adds the verbs that
# start the groups of its kinds.
#
# Every verb takes the keyword `editor = get_evaluation_editor()`, so the code of
# a model names no editor, and does its document work on the task of the editor,
# so a person at the REPL, who passes `editor`, calls it while the window runs on
# a thread of its own. **A client of `execute_julia_code` never passes `wait = true`**: the
# call runs in a frame of the window, so a verb that waits holds the window, and
# the person can not press Stop, until the group ends.

# ── Reading a group ─────────────────────────────────────────────────────────

# The counts of a group, from its engine group now.
_get_group_summary(group::TaskGroupDocument) = compute_task_group_summary(get_task_group(group))

# The tasks of a group, as documents.
_get_task_documents(group::TaskGroupDocument) = collect(getfield(group, :tasks)[])

function _format_group_line(group::TaskGroupDocument)
    s = _get_group_summary(group)
    engine = get_task_group(group)
    counts = join([string(e + u, " ", code, u > 0 ? " (" * string(u) * " unexpected)" : "")
                   for (code, e, u) in s.counts], ", ")
    elapsed = s.elapsed === nothing ? "" : format_elapsed_time(s.elapsed; precision = 0)
    join(filter(!isempty, [getfield(group, :identifier)[], getfield(group, :title)[], engine.name,
                           String(getfield(group, :status)[]),
                           string(s.finished, "/", s.total), counts, elapsed]), " · ")
end

# The line of another work item: its identifier, its title, its kind, and its
# state and its line as its decoration says them.
function _format_work_item_line(item)
    decoration = get_document_decoration(item)
    state = isempty(decoration.conditions) ? "" : get_condition_look(Val(first(decoration.conditions).name)).words
    join(filter(!isempty, String[get_work_item_identifier(item), get_document_title(item),
                                 describe_work_item_kind(item, 1), state, decoration.detail]), " · ")
end

_format_work_item_line(group::TaskGroupDocument) = _format_group_line(group)

"""
    list_task_groups(; editor = get_evaluation_editor()) -> String

**Every open group of tasks of this session, newest first**, one line each: the
identifier, the title, the kind, the state, the finished tasks over all of them,
the counts of each result, and the time. Another work item of the task list, such
as a search, has a line too: its identifier, its title, its kind, its state and
what it found.

Use it to find a group that another person or another conversation started.

# Example

    list_task_groups()

See also `find_task_group`, `describe_task_group`.

For the assistant.
"""
function list_task_groups end

function list_task_groups(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "list_task_groups") do
        items = reverse(collect_work_items(get_session_task_group_list(; editor)))
        isempty(items) && return "No group of tasks is open in this session."
        join((_format_work_item_line(item) for item in items), "\n")
    end
end

"""
    find_task_group(name; editor = get_evaluation_editor()) -> TaskGroupDocument or nothing

The open group of this session whose identifier (`"T3"`) or title is `name`, or
`nothing` when no open group has it. Another work item of the task list, such as
a search (`"S1"`), is found the same way.

Use it to reach a group that this conversation did not start; a group that it
started is the value its start verb answered.

# Example

    t3 = find_task_group("T3")

See also `list_task_groups`.

For the assistant.
"""
function find_task_group end

function find_task_group(name::AbstractString; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "find_task_group") do
        items = collect_work_items(get_session_task_group_list(; editor))
        index = findfirst(item -> get_work_item_identifier(item) == name || get_document_title(item) == name,
                          items)
        index === nothing ? nothing : items[index]
    end
end

# The tasks a description names: their places in the group.
function _select_task_indices(group::TaskGroupDocument, tasks::Symbol)
    documents = _get_task_documents(group)
    tasks === :all && return collect(eachindex(documents))
    tasks === :running && return [i for (i, d) in enumerate(documents) if get_task_document_status(d) === :running]
    is_unexpected(d) = (r = get_task_document_result(d); r !== nothing && r.result != r.expected_result)
    tasks === :unexpected && return [i for (i, d) in enumerate(documents) if is_unexpected(d)]
    error("tasks is :unexpected, :running or :all, not $(repr(tasks))")
end

function _format_task_line(group::TaskGroupDocument, index::Integer)
    document = _get_task_documents(group)[index]
    task = getfield(document, :task)[]
    result = get_task_document_result(document)
    state = result === nothing ? String(get_task_document_status(document)) : format_task_result(result)
    string(index, ". ", format_task_parameters(task), " — ", state)
end

"""
    describe_task_group(group; tasks = :unexpected, limit = 20, editor = get_evaluation_editor()) -> String

**What a group of tasks did**: the summary line of `opp_repl` (how many tasks, of
each result, expected or not, and the time), the reason of what was not
expected, the state of the preparation when the group has one (such as the
build before its runs), and then one line for each task that `tasks` names —
`:unexpected`, `:running` or `:all` — at most `limit` of them. Another work item
of the task list, such as a search, says its state and what it found, at most
`limit` lines of it.

Use it to tell the person how a group of tasks went, and which tasks failed.

# Example

    describe_task_group(t1; tasks = :all, limit = 10)

See also `describe_task`, `get_task_output`, `list_task_groups`.

For the assistant.
"""
function describe_task_group end

function describe_task_group(group::TaskGroupDocument; tasks::Symbol = :unexpected,
                             limit::Integer = 20, editor = get_evaluation_editor())
    run_on_editor_task!(() -> _describe_task_group(group, tasks, limit), editor; description = "describe_task_group")
end

# Another work item says what it did in its own words.
function describe_task_group(item; limit::Integer = 20, editor = get_evaluation_editor())
    run_on_editor_task!(() -> describe_work_item(item; limit), editor; description = "describe_task_group")
end

function _describe_task_group(group::TaskGroupDocument, tasks::Symbol, limit::Integer)
    s = _get_group_summary(group)
    engine = get_task_group(group)
    running = getfield(group, :status)[] in (:running, :stopping)
    lines = String[]
    if running
        push!(lines, string(format_task_group_description(engine), ": ", s.finished, " of ",
                            s.total, " finished, ", s.running, " running"))
    end
    isempty(s.summary) || push!(lines, s.summary)
    s.reason === nothing || push!(lines, s.reason)
    get_task_group_preparation(group) === nothing ||
        push!(lines, first(describe_task_group_preparation(group)))
    indices = _select_task_indices(group, tasks)
    for index in first(indices, limit)
        push!(lines, _format_task_line(group, index))
    end
    length(indices) > limit && push!(lines, string("… and ", length(indices) - limit, " more"))
    join(lines, "\n")
end

"""
    describe_task(group, index; editor = get_evaluation_editor()) -> String

**Everything of one task of a group**: its state and its result, what its kind
says of it (`format_task_details`, such as its command line, its exit code and
its error), its process, its time, how many executions ran and what the earlier
ones ended with, and the last lines of its output and of its errors.

Use it to tell the person why one task failed.

# Example

    describe_task(t1, 3)

See also `get_task_output`, `describe_task_group`.

For the assistant.
"""
function describe_task end

function describe_task(group::TaskGroupDocument, index::Integer; editor = get_evaluation_editor())
    run_on_editor_task!(() -> _describe_task(group, index), editor; description = "describe_task")
end

describe_task(group::ReferencedDocument, index::Integer; keywords...) =
    describe_task(get_document(group), index; keywords...)

function _describe_task(group::TaskGroupDocument, index::Integer)
    document = _get_task_documents(group)[index]
    task = getfield(document, :task)[]
    current = get_current_task_execution(document)
    result = current === nothing ? nothing : current.result
    lines = String[_format_task_line(group, index), format_task_details(task, result)...]
    if current !== nothing
        current.process_id === nothing || push!(lines, "process: " * string(current.process_id))
        started = current.start_time
        if started !== nothing
            finished = something(current.end_time, time())
            push!(lines, "elapsed: " * format_elapsed_time(finished - started; precision = 1))
        end
    end
    executions = getfield(document, :executions)[]
    isempty(executions) || push!(lines, "executions: " * string(length(executions)))
    for (number, execution) in enumerate(get_earlier_task_executions(document))
        push!(lines, string("  earlier ", number, ": ", first(describe_task_execution(execution))))
    end
    for (label, stream) in (("stdout", :output), ("stderr", :error_output))
        output = collect_task_document_lines(document, stream)
        isempty(output) && continue
        push!(lines, label * ":")
        append!(lines, last(output, 10))
    end
    join(lines, "\n")
end

"""
    get_task_output(group, index; stream = :stdout, lines = 50, editor = get_evaluation_editor()) -> String

**The last `lines` lines that one task of a group printed** on `stream`,
`:stdout` or `:stderr`.

Use it to read what a task printed, such as the error of a task that failed.

# Example

    get_task_output(t1, 3; stream = :stderr)

See also `describe_task`.

For the assistant.
"""
function get_task_output end

function get_task_output(group::TaskGroupDocument, index::Integer;
                         stream::Symbol = :stdout, lines::Integer = 50, editor = get_evaluation_editor())
    stream in (:stdout, :stderr) || error("stream is :stdout or :stderr, not $(repr(stream))")
    run_on_editor_task!(editor; description = "get_task_output") do
        document = _get_task_documents(group)[index]
        output = collect_task_document_lines(document, stream === :stdout ? :output : :error_output)
        isempty(output) && return "(nothing printed)"
        join(last(output, lines), "\n")
    end
end

get_task_output(group::ReferencedDocument, index::Integer; keywords...) =
    get_task_output(get_document(group), index; keywords...)

# ── Acting on a group ───────────────────────────────────────────────────────

"""
    wait_for_task_group!(editor, group; timeout = nothing) -> group

Wait for `group` to end, and then copy what its tasks said into their documents.
The wait is on the calling task, so a person at the REPL waits while the window
draws, and the copy runs on the task of the editor. Called on the task of the
editor, it holds the window until the group ends.

With a `timeout` in seconds, the wait also ends when that time has passed, and
the group goes on; what its tasks said so far is copied, and
[`is_task_group_running`](@ref) tells the two ends apart. A model that waits
for a long group waits in steps shorter than the time limit of its client.

In a code unit, a stop of the unit ends the wait and throws `InterruptException`;
the group goes on, and its own stop stops it.
"""
function wait_for_task_group!(editor, group::TaskGroupDocument; timeout::Union{Real,Nothing} = nothing)
    task_group = get_task_group(group)
    deadline = timeout === nothing ? Inf : time() + Float64(timeout)
    scheduler = task_group.runtime.scheduler
    if get_current_code_unit() === nothing
        if timeout === nothing
            wait_task_group(task_group)
        elseif scheduler !== nothing
            timedwait(() -> istaskdone(scheduler), max(0.0, deadline - time()); pollint = 0.1)
        end
    else
        while scheduler !== nothing && !istaskdone(scheduler) && time() < deadline
            wait_in_code_unit(min(0.1, max(0.0, deadline - time())))
        end
    end
    if is_task_group_running(group)
        run_on_editor_task!(() -> _sync_task_group_shadow!(group), editor)
    else
        run_on_editor_task!(() -> wait_task_group_document(group; editor), editor)
    end
    group
end

"""
    is_task_group_running(group) -> Bool

Whether the tasks of `group` still run: its scheduler started and has not
ended.

Use it to tell whether a group of tasks still runs.

# Example

    is_task_group_running(find_task_group("S1"))

See also `describe_task_group` and `stop_tasks!`.

For the assistant.
"""
function is_task_group_running end

function is_task_group_running(group::TaskGroupDocument)
    scheduler = get_task_group(group).runtime.scheduler
    scheduler !== nothing && !istaskdone(scheduler)
end

is_task_group_running(group::ReferencedDocument) = is_task_group_running(get_document(group))


"""
    stop_tasks!(group; editor = get_evaluation_editor()) -> String

**Stop every task of a group.** A task that runs is interrupted, so it can end
in order and still write what it writes at its end, and a task that waits does
not start. Another work item of the task list stops too: a search keeps what it
found and reads nothing more.

Use it to stop, cancel or abort a group of tasks.

# Example

    stop_tasks!(t1)

See also `stop_task!` for one task, `rerun_tasks!`.

For the assistant.
"""
function stop_tasks! end

function stop_tasks!(group; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "stop_tasks!") do
        group isa TaskGroupDocument ? evaluate_operation(editor, StopTaskGroupOperation(group)) :
                                      stop_work_item!(group)
        string("Stopping the ", describe_work_item_kind(group, 1), " ", get_work_item_identifier(group), ".")
    end
end

"""
    stop_task!(group, index; editor = get_evaluation_editor()) -> String

**Stop one task of a group**, the task at `index`, and let the others go on.

Use it to stop one task of a group and let the others run.

# Example

    stop_task!(t1, 3)

See also `stop_tasks!`.

For the assistant.
"""
function stop_task! end

function stop_task!(group::TaskGroupDocument, index::Integer; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "stop_task!") do
        get_task_group(group).runs[index] === nothing && return "Task $(index) has not started."
        evaluate_operation(editor, StopTaskOperation(group, index))
        "Stopping task $(index)."
    end
end

stop_task!(task::ReferencedDocument, arguments...; keywords...) =
    stop_task!(get_document(task), arguments...; keywords...)

"""
    rerun_tasks!(group; which = :unexpected, wait = false, editor = get_evaluation_editor()) -> TaskGroupDocument

**Run tasks of a group again, in place**: `:unexpected` (the default), `:failed`,
`:unfinished`, `:all`, or a vector of their places.

Use it to repeat the tasks that failed after a fix.

# Example

    rerun_tasks!(t1)

`wait = true` runs to the end before answering. **A client of
`execute_julia_code` never passes it**: the call holds the window until the group
ends. A person at the REPL can: there the call waits, and the window draws.

See also `stop_task!` and `describe_task_group`.

For the assistant.
"""
function rerun_tasks! end

function rerun_tasks!(group::TaskGroupDocument; which = :unexpected, wait::Bool = false, editor = get_evaluation_editor())
    run_on_editor_task!(() -> evaluate_operation(editor, RerunTaskGroupOperation(group, which)), editor;
                        description = "rerun_tasks!")
    wait && wait_for_task_group!(editor, group)
    group
end

rerun_tasks!(group::ReferencedDocument; keywords...) =
    rerun_tasks!(get_document(group); keywords...)

"""
    wait_for_tasks!(group; timeout = 30, editor = get_evaluation_editor()) -> String

**Wait a short while for a group of tasks to end**, at most `timeout` seconds,
and say how it stands: ended, with the line that sums it up, or still running,
with what is done so far.

**The wait holds the window**, as every call of `execute_julia_code` does, so
keep it short. For a group that runs for minutes, say how long it takes and end
the turn: an assistant whose wake is on starts a turn of its own when a group
that its turn started ends.

Use it to wait for runs, a build or a test that end within seconds, before you
read what they wrote.

# Example

    wait_for_tasks!(t1; timeout = 20)

See also `describe_task_group`, `stop_tasks!`.

For the assistant.
"""
function wait_for_tasks! end

function wait_for_tasks!(group::TaskGroupDocument; timeout::Real = 30, editor = get_evaluation_editor())
    started = time()
    wait_for_task_group!(editor, group; timeout)
    run_on_editor_task!(editor; description = "wait_for_tasks!") do
        summary = compute_task_group_summary(get_task_group(group)).summary
        waited = format_elapsed_time(time() - started; precision = 0)
        is_task_group_running(group) ?
            string("Still running after ", waited, ": ", summary, ".") :
            string("Ended: ", summary, ".")
    end
end

wait_for_tasks!(group::ReferencedDocument; keywords...) =
    wait_for_tasks!(get_document(group); keywords...)

"""
    close_task_group!(group; editor = get_evaluation_editor()) -> String

**Close the pane of a group and its row in the Tasks tab.** A group that runs
goes on; stop it first with `stop_tasks!(group)` when it must end. Another work
item of the task list, such as a search, closes the same way.

Use it to close a group when its work is over.

# Example

    close_task_group!(t1)

See also `stop_task!` and `list_task_groups`.

For the assistant.
"""
function close_task_group! end

function close_task_group!(group; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "close_task_group!") do
        found = search_references(getfield(editor, :document),
                                  node -> node isa PaneTab && node.content === group;
                                  walk = DocumentWalk(; descend = is_pane_search_step), limit = nothing)
        for reference in found
            close_pane!(reference; editor)
        end
        evaluate_operation(editor, CloseTaskGroupOperation(get_session_task_group_list(; editor), group))
        string("Closed the ", describe_work_item_kind(group, 1), " ", get_work_item_identifier(group), ".")
    end
end

