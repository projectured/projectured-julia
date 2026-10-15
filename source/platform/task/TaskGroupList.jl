# The groups of tasks of the session of an editor: every group that any door of
# the editor started — a form, a verb, the assistant of the window, a client over
# MCP — in the order of their starts, in one `TaskGroupList`. A group keeps its
# place: a close of its row leaves a `ClosedTaskGroup` there, so a path to a later
# group still names that group.

"""
    TaskGroupList()

The groups of a session, in the order of their starts: `groups` holds one group
document for each group that started, or a [`ClosedTaskGroup`](@ref) in the place
of a group whose row a person closed. The Tasks pane shows the open groups,
newest first. A window sets what Show does with [`set_task_group_opener!`](@ref);
with no window, Show does nothing.

# Example

    list = get_session_task_group_list()
    [getfield(group, :title)[] for group in collect_task_group_documents(list)]
"""
@document struct TaskGroupList <: Document
    groups::CellVector
    opener::Any                       # Ref, holding what Show does, or nothing
end

TaskGroupList() = TaskGroupList(CellVector(), Ref{Any}(nothing))

get_document_title(::TaskGroupList) = "Tasks"

# The list is a tool pane: a paste does not replace it.
accepts_pasted_document(::TaskGroupList) = false

"""
    get_session_task_group_list(; editor = find_evaluation_editor()) -> TaskGroupList

The list of the groups of the session of `editor`: by default the editor of the
evaluation, or of the loop that runs the calling code. Each editor has its own,
made at the first call: the list that a tab of its window shows, which a window
made before its editor existed, or else a new list. With no editor, such as a
script that runs outside every window, a new list, which nothing keeps; so a
group that starts there joins no list.
"""
get_session_task_group_list(; editor = find_evaluation_editor()) =
    editor isa Editor ?
        get_session_document!(() -> something(_find_window_task_group_list(editor), TaskGroupList()), editor,
                              TaskGroupList) :
        TaskGroupList()

# The list that a tab of the window of `editor` shows, or `nothing`. A document that
# holds no pane tree, such as one page in an editor of its own, shows none.
function _find_window_task_group_list(editor::Editor)
    tree = try
        get_window_tree(getfield(editor, :document))
    catch
        nothing
    end
    tree isa PaneTree || return nothing
    lists = collect_pane_tab_contents(tree, TaskGroupList)
    isempty(lists) ? nothing : first(lists)
end

"""
    ClosedTaskGroup(identifier, title, summary)

What stays of a group in the list of its session after a person closes its row:
its identifier, its title and the line that sums it up, which
[`remove_task_group!`](@ref) makes. It holds no task and no execution, so their
memory goes. It keeps the place of the group in the list, and its page says that
the group closed.
"""
@document struct ClosedTaskGroup <: Document
    identifier::String
    title::String
    summary::String
end

get_document_title(group::ClosedTaskGroup) = getfield(group, :title)[]

# The counts of a group in a line: each code, then the tasks that run and wait.
function _format_group_counts(counts)
    parts = String[]
    for (code, expected, unexpected) in counts.counts
        expected > 0 && push!(parts, string(expected, " ", code))
        unexpected > 0 && push!(parts, string(unexpected, " ", code, " unexpected"))
    end
    counts.running > 0 && push!(parts, string(counts.running, " running"))
    counts.pending > 0 && push!(parts, string(counts.pending, " waiting"))
    join(parts, " · ")
end

# The line of a closed group: its kind, its counts and the time it took.
function _format_closed_task_group_summary(group::TaskGroupDocument)
    summary = get_task_group_document_summary(group)
    parts = String[get_task_group(group).name, _format_group_counts(get_task_group_document_counts(group))]
    summary.elapsed === nothing || push!(parts, format_elapsed_time(summary.elapsed; precision = 0))
    join(filter(!isempty, parts), " · ")
end

"""
    collect_task_group_documents(list) -> Vector{TaskGroupDocument}

The open groups of `list`, in the order of their starts: every group but the
closed ones.
"""
collect_task_group_documents(list::TaskGroupList) =
    TaskGroupDocument[group for group in list.groups if group isa TaskGroupDocument]

"""
    add_task_group!(list, group) -> list

Put `group` at the end of the list, unless it is there already. A group whose row
a person closed goes back into its place. A group that starts adds itself, so the
caller is the task that writes the documents.
"""
function add_task_group!(list::TaskGroupList, group::TaskGroupDocument)
    groups = collect(list.groups)
    any(g -> g === group, groups) && return list
    identifier = getfield(group, :identifier)[]
    place = findfirst(g -> g isa ClosedTaskGroup && getfield(g, :identifier)[] == identifier, groups)
    place === nothing ? push!(list.groups, group) : (list.groups[place] = group)
    list
end

"""
    remove_task_group!(list, group) -> list

Close the row of `group`: a [`ClosedTaskGroup`](@ref) takes its place in the
list, and the files of the streams of its tasks go. The group goes on if it runs,
and its tasks keep their bounded lines.
"""
function remove_task_group!(list::TaskGroupList, group::TaskGroupDocument)
    index = findfirst(g -> g === group, collect(list.groups))
    index === nothing && return list
    list.groups[index] = ClosedTaskGroup(Cell(String(getfield(group, :identifier)[])),
                                         Cell(String(getfield(group, :title)[])),
                                         Cell(_format_closed_task_group_summary(group)))
    remove_task_output_files!(group)
    list
end

"""
    set_task_group_opener!(list, action) -> list

Say what Show does: `action(editor, group)` puts the pane of `group` on the
screen of the editor that evaluates the press. A window sets it when it opens.
It captures no editor, because no document stores one
(PAR-NO-EDITOR-IN-DOCUMENT).
"""
function set_task_group_opener!(list::TaskGroupList, action)
    getfield(list, :opener)[][] = action
    list
end

"""Put the pane of `group` on the screen of `editor`, as the window said; `nothing` when no window did."""
function open_task_group_pane(editor, list::TaskGroupList, group)
    action = getfield(list, :opener)[][]
    action === nothing ? nothing : action(editor, group)
end

# The tasks of the groups of the session, as a roster reads them: one part for
# each open group of the session list, and each task with its group as `within`.
# A group that starts or a row that a person closes changes the parts; a task that
# runs changes only its own row.
struct _SessionTasks end

get_roster_item_type(::_SessionTasks) = TaskDocument
collect_roster_parts(::_SessionTasks, link) = Any[group for group in collect_task_group_documents(get_session_task_group_list())]
collect_roster_items(::_SessionTasks, link, group) = RosterItem[RosterItem(task, group) for task in group.tasks]
