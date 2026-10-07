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

"""
    list_task_groups(; editor = get_evaluation_editor()) -> Text

**Every group of tasks of this session, newest first**, one line each: the
identifier, the title, the kind, the state, the finished tasks over all of them,
the counts of each result, and the time.

Use it to find a group that another person or another conversation started.

# Example

    list_task_groups()

See also `find_task_group`, `describe_task_group`.
"""
function list_task_groups(; editor = get_evaluation_editor())
    run_on_editor_task!(editor) do
        groups = collect(get_session_task_group_list().groups)
        isempty(groups) && return Text("No group of tasks ran in this session.")
        Text(join((_format_group_line(group) for group in groups), "\n"))
    end
end

"""
    find_task_group(name; editor = get_evaluation_editor()) -> TaskGroupDocument or nothing

The group of this session whose identifier (`"T3"`) or title is `name`, or
`nothing` when no group has it.

Use it to reach a group that this conversation did not start; a group that it
started is the value its start verb answered.

# Example

    t3 = find_task_group("T3")

See also `list_task_groups`.
"""
function find_task_group(name::AbstractString; editor = get_evaluation_editor())
    run_on_editor_task!(editor) do
        groups = collect(get_session_task_group_list().groups)
        index = findfirst(g -> getfield(g, :identifier)[] == name || getfield(g, :title)[] == name,
                          groups)
        index === nothing ? nothing : groups[index]
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
    describe_task_group(group; tasks = :unexpected, limit = 20, editor = get_evaluation_editor()) -> Text

**What a group of tasks did**: the summary line of `opp_repl` (how many tasks, of
each result, expected or not, and the time), the reason of what was not
expected, the state of the preparation when the group has one (such as the
build before its runs), and then one line for each task that `tasks` names —
`:unexpected`, `:running` or `:all` — at most `limit` of them.

Use it to tell the person how a group of tasks went, and which tasks failed.

# Example

    describe_task_group(t1; tasks = :all, limit = 10)

See also `describe_task`, `get_task_output`, `list_task_groups`.
"""
function describe_task_group(group::TaskGroupDocument; tasks::Symbol = :unexpected,
                             limit::Integer = 20, editor = get_evaluation_editor())
    run_on_editor_task!(() -> _describe_task_group(group, tasks, limit), editor)
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
    Text(join(lines, "\n"))
end

"""
    describe_task(group, index; editor = get_evaluation_editor()) -> Text

**Everything of one task of a group**: its state and its result, what its kind
says of it (`format_task_details`, such as its command line, its exit code and
its error), its process, its time, how many executions ran and what the earlier
ones ended with, and the last lines of its output and of its errors.

Use it to tell the person why one task failed.

# Example

    describe_task(t1, 3)

See also `get_task_output`, `describe_task_group`.
"""
function describe_task(group::TaskGroupDocument, index::Integer; editor = get_evaluation_editor())
    run_on_editor_task!(() -> _describe_task(group, index), editor)
end

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
    Text(join(lines, "\n"))
end

"""
    get_task_output(group, index; stream = :stdout, lines = 50, editor = get_evaluation_editor()) -> Text

**The last `lines` lines that one task of a group printed** on `stream`,
`:stdout` or `:stderr`.

Use it to read what a task printed, such as the error of a task that failed.

# Example

    get_task_output(t1, 3; stream = :stderr)

See also `describe_task`.
"""
function get_task_output(group::TaskGroupDocument, index::Integer;
                         stream::Symbol = :stdout, lines::Integer = 50, editor = get_evaluation_editor())
    stream in (:stdout, :stderr) || error("stream is :stdout or :stderr, not $(repr(stream))")
    run_on_editor_task!(editor) do
        document = _get_task_documents(group)[index]
        output = collect_task_document_lines(document, stream === :stdout ? :output : :error_output)
        isempty(output) && return Text("(nothing printed)")
        Text(join(last(output, lines), "\n"))
    end
end

# ── Acting on a group ───────────────────────────────────────────────────────

"""
    wait_for_task_group!(editor, group) -> group

Wait for `group` to end, and then copy what its tasks said into their documents.
The wait is on the calling task, so a person at the REPL waits while the window
draws, and the copy runs on the task of the editor. Called on the task of the
editor, it holds the window until the group ends.
"""
function wait_for_task_group!(editor, group::TaskGroupDocument)
    wait_task_group(get_task_group(group))
    run_on_editor_task!(() -> wait_task_group_document(group), editor)
    group
end


"""
    stop_tasks!(group; editor = get_evaluation_editor()) -> Text

**Stop every task of a group.** A task that runs is interrupted, so it can end
in order and still write what it writes at its end, and a task that waits does
not start.

Use it to stop, cancel or abort a group of tasks.

# Example

    stop_tasks!(t1)

See also `stop_task!` for one task, `rerun_tasks!`.
"""
function stop_tasks!(group::TaskGroupDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor) do
        stop_task_group_document!(group)
        Text("Stopping the group " * getfield(group, :identifier)[] * ".")
    end
end

"""
    stop_task!(group, index; editor = get_evaluation_editor()) -> Text

**Stop one task of a group**, the task at `index`, and let the others go on.

# Example

    stop_task!(t1, 3)

See also `stop_tasks!`.
"""
function stop_task!(group::TaskGroupDocument, index::Integer; editor = get_evaluation_editor())
    run_on_editor_task!(editor) do
        run = get_task_group(group).runs[index]
        run === nothing && return Text("Task $(index) has not started.")
        stop_task_execution!(run)
        Text("Stopping task $(index).")
    end
end

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
"""
function rerun_tasks!(group::TaskGroupDocument; which = :unexpected, wait::Bool = false, editor = get_evaluation_editor())
    run_on_editor_task!(() -> rerun_task_group_document!(group, which), editor)
    wait && wait_for_task_group!(editor, group)
    group
end

"""
    close_task_group!(group; editor = get_evaluation_editor()) -> Text

**Close the pane of a group and its row in the Tasks tab.** A group that runs
goes on; stop it first with `stop_tasks!(group)` when it must end.

# Example

    close_task_group!(t1)
"""
function close_task_group!(group::TaskGroupDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor) do
        found = search_references(getfield(editor, :document),
                                  node -> node isa PaneTab && node.content === group;
                                  descend = is_pane_search_step)
        for reference in found
            close_pane!(reference; editor)
        end
        remove_task_group!(get_session_task_group_list(), group)
        Text("Closed the group " * getfield(group, :identifier)[] * ".")
    end
end

# ── The verbs a model may call ─────────────────────────────────────────────

"""
    make_task_api() -> Vector

The verbs of tasks that a model may call, as the module and the names: list,
find and describe the groups of the session and their tasks, read the output of
a task, stop, run again and close, and the title of the tab of a group. A window
declares them beside the verbs of its domain, which start the groups.
"""
make_task_api() = Any[
    TaskModule => (:list_task_groups, :find_task_group, :describe_task_group, :describe_task,
                   :get_task_output, :stop_tasks!, :stop_task!, :rerun_tasks!,
                   :close_task_group!, :make_task_group_tab_title),
]
