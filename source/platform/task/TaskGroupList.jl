# The groups of tasks of the session: every group that any door started — a
# form, a verb, the assistant of the window, a client over MCP — newest first, in
# one `TaskGroupList`. A group stays in the list until a person closes its row,
# also when its pane was closed.

"""
    TaskGroupList()

The groups of the session, newest first: `groups` holds one group document for
each group that started. A window sets what Show does with
[`set_task_group_opener!`](@ref); with no window, Show does nothing.

# Example

    list = get_session_task_group_list()
    [getfield(group, :title)[] for group in list.groups]
"""
@document struct TaskGroupList <: Document
    groups::CellVector
    opener::Any                       # Ref, holding what Show does, or nothing
end

TaskGroupList() = TaskGroupList(CellVector(), Ref{Any}(nothing))

get_document_title(::TaskGroupList) = "Tasks"

# The list is a tool pane: a paste does not replace it.
accepts_pasted_document(::TaskGroupList) = false

# Made at the first use, so no cell is made when the package loads.
const _SESSION_TASK_GROUP_LIST = Ref{Any}(nothing)

"""The list of the session, made at the first call."""
function get_session_task_group_list()
    list = _SESSION_TASK_GROUP_LIST[]
    list === nothing || return list
    _SESSION_TASK_GROUP_LIST[] = TaskGroupList()
end

"""
    add_task_group!(list, group) -> list

Put `group` at the top of the list, unless it is there already. A group that
starts adds itself, so the caller is the task that writes the documents.
"""
function add_task_group!(list::TaskGroupList, group)
    any(g -> g === group, list.groups) && return list
    insert!(list.groups, 1, group)
    list
end

"""
    remove_task_group!(list, group) -> list

Take the row of `group` out of the list. The group goes on if it runs.
"""
function remove_task_group!(list::TaskGroupList, group)
    index = findfirst(g -> g === group, collect(list.groups))
    index === nothing || deleteat!(list.groups, index)
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
