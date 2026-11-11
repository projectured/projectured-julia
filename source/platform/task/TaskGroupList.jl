# The groups of tasks of the session of an editor: every group and every task
# alone that any door of the editor started — a form, a verb, the assistant of the
# window, a client over MCP — in the order of their starts, in one `TaskGroupList`.
# A row keeps its place: a close of its row leaves a `ClosedTaskGroup` there, so a
# path to a later row still names that row.

"""
    TaskGroupList(; groups = CellVector())

The rows of the task list of a session, in the order of their starts: `groups`
holds one document for each group of tasks, task alone or other work item that
started, or a [`ClosedTaskGroup`](@ref) in the place of a row that a person
closed.

`table` is the table of the Tasks pane: an arrangement, with no entry at first,
around a roster of the open rows, newest first, with the columns `title`,
`identifier`, `kind`, `started_by`, `state`, `counts`, `progress` and `elapsed`. A
person filters, sorts and finds in its bar, and the title of a row is a link to
its page. `selected` is the identifier of the row that the buttons of the pane act
on, which a press on a row writes, or an empty string; it is view state.

Use it to reach every group of tasks that the session started.

# Example

    list_1 = get_session_task_group_list()
    groups_1 = search_documents(list_1, part -> part isa TaskGroupDocument)

See also `get_session_task_group_list`, `list_task_groups`, `find_task_group` and
`ClosedTaskGroup`.

For the assistant.
"""
@document struct TaskGroupList <: Document
    groups::CellVector
    selected::String
    table::Any
end

function TaskGroupList(; groups::CellVector = CellVector())
    list = TaskGroupList(groups, Cell(""), Cell(nothing))
    roster = Roster(_OpenWorkItems(); columns = _TASK_LIST_COLUMNS, title = "Tasks", shares = _TASK_LIST_SHARES)
    set_cell_computation!(getfield(roster, :marked), () -> _find_selected_work_item(list))
    link_roster!(roster, list)
    list.table = ArrangementDocument(roster, ArrangementEntry[])
    list
end

# The columns of the table of the Tasks pane, and their shares of its width.
const _TASK_LIST_COLUMNS = ["title", "identifier", "kind", "started_by", "state", "counts", "progress", "elapsed"]
const _TASK_LIST_SHARES = [4, 1, 2, 2, 1, 3, 1, 1]

# The open row of `list` that the buttons of the Tasks pane act on: the item whose
# identifier `selected` names, or `nothing` when no open row has it.
function _find_selected_work_item(list::TaskGroupList)
    identifier = getfield(list, :selected)[]
    isempty(identifier) && return nothing
    for item in list.groups
        item isa ClosedTaskGroup && continue
        get_work_item_identifier(item) == identifier && return item
    end
    nothing
end

# The open rows of the list of a roster, newest first, each at its place
# `groups[j]` of the list, so the link of a row opens the item at that place.
struct _OpenWorkItems end

get_roster_item_type(::_OpenWorkItems) = Document
collect_roster_parts(::_OpenWorkItems, link) = link isa TaskGroupList ? Any[link] : Any[]

function collect_roster_items(::_OpenWorkItems, link, list::TaskGroupList)
    items = collect(list.groups)
    RosterItem[RosterItem(items[j], nothing, extend_reference(EmptyReference(), FieldReferenceStep("groups"),
                                                              ElementReferenceStep(j)))
               for j in length(items):-1:1 if !(items[j] isa ClosedTaskGroup)]
end

get_document_title(::TaskGroupList) = "Tasks"

# The list is a tool pane: a paste does not replace it, and a duplicate would be the
# same list. A walk reaches the rows through `groups`, not through the table.
accepts_pasted_document(::TaskGroupList) = false
has_document_duplicate(::TaskGroupList) = false
is_field_walked(::TaskGroupList, name::Symbol) = name === :groups

"""
    get_session_task_group_list(; editor = find_evaluation_editor()) -> TaskGroupList

The list of the groups of the session of `editor`: by default the editor of the
evaluation, or of the loop that runs the calling code. Each editor has its own,
made at the first call: the list that a tab of its window shows or holds in its
content, which a window made before its editor existed, or else a new list. With no editor, such as a
script that runs outside every window, a new list, which nothing keeps; so a
group that starts there joins no list.

Use it to read the groups of tasks and the other work items of the session.

# Example

    list_1 = get_session_task_group_list()

See also `collect_work_items` and `list_task_groups`.

For the assistant.
"""
function get_session_task_group_list end

get_session_task_group_list(; editor = find_evaluation_editor()) =
    editor isa Editor ?
        get_session_document!(() -> something(_find_window_task_group_list(editor), TaskGroupList()), editor,
                              TaskGroupList) :
        TaskGroupList()

# The list of the session is what a person adds by name, to a tab or to an
# explorer, and the kind is in the list of `+` of an explorer.
get_insertion_aliases(::Type{TaskGroupList}) = ["tasks"]
make_insertion_document(::Type{TaskGroupList}) = get_session_task_group_list()
is_explorer_entry_type(::Type{TaskGroupList}) = true

# A file keeps that it shows the list, not the groups, which belong to a session.
# A file that loads before its window exists gives a new list, which the window
# makes the list of its session.
pred_arguments(::TaskGroupList) = (), Pair{Symbol,Any}[]
make_pred_document(::Type{<:TaskGroupList}, positional, keywords) = get_session_task_group_list()

# The list that a tab of the window of `editor` shows, or that the content of a tab
# holds a few documents down, such as the workspace of a navigator; `nothing` when
# no tab has one. A document that holds no pane tree, such as one page in an editor
# of its own, shows none.
function _find_window_task_group_list(editor::Editor)
    tree = try
        get_window_tree(getfield(editor, :document))
    catch
        nothing
    end
    tree isa PaneTree || return nothing
    for group in get_pane_groups(tree), tab in group.tabs
        found = search_documents(tab.content, document -> document isa TaskGroupList;
                                 maxdepth = _LIST_SEARCH_DEPTH,
                                 walk = DocumentWalk(; descend = _is_held_document))
        isempty(found) || return first(found)
    end
    nothing
end

# How many documents down the content of a tab the search for the list goes: a
# history, an explorer, its navigator, the content of the navigator and the list.
const _LIST_SEARCH_DEPTH = 5

# The search enters a document that a field holds, and no collection, so it reads
# no lazy part of a content, such as the files of a project.
_is_held_document(_, child) = child isa Document && !is_element_collection(child)

"""
    ClosedTaskGroup(identifier, title, summary, kind)

What stays of a row of the list of its session after a person closes it: its
identifier, its title, the line that sums it up, which [`remove_task_group!`](@ref)
makes, and the word for its kind, such as "group", "task" or "search". It holds no
task and no execution, so their memory goes. It keeps the place of the row in the
list, and its page says that the row closed.

Use it to tell a group that a person closed from one that is open.

# Example

    closed_1 = search_documents(get_session_task_group_list(), part -> part isa ClosedTaskGroup)

See also `TaskGroupList`, `get_session_task_group_list` and `list_task_groups`.

For the assistant.
"""
@document struct ClosedTaskGroup <: Document
    identifier::String
    title::String
    summary::String
    kind::String
end

get_document_title(group::ClosedTaskGroup) = getfield(group, :title)[]
get_work_item_identifier(group::ClosedTaskGroup) = getfield(group, :identifier)[]

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

# The line of a closed group: its kind, its counts and the time it took. Another
# work item gives its kind and the line of its decoration.
function _format_closed_task_group_summary(group::TaskGroupDocument)
    summary = get_task_group_document_summary(group)
    parts = String[get_task_group(group).name, _format_group_counts(get_task_group_document_counts(group))]
    summary.elapsed === nothing || push!(parts, format_elapsed_time(summary.elapsed; precision = 0))
    join(filter(!isempty, parts), " · ")
end

_format_closed_task_group_summary(item) =
    join(filter(!isempty, String[describe_work_item_kind(item, 1), get_document_decoration(item).detail]), " · ")

"""
    collect_task_group_documents(list) -> Vector{TaskGroupDocument}

The open groups of `list`, in the order of their starts: every group but the
closed ones.
"""
collect_task_group_documents(list::TaskGroupList) =
    TaskGroupDocument[group for group in list.groups if group isa TaskGroupDocument]

"""
    collect_work_items(list) -> Vector

The open work items of `list`, in the order of their starts: each group of tasks
and each other work item, such as a search, but the closed rows.

Use it to read every work item of the session, whatever its kind.

# Example

    items_1 = collect_work_items(get_session_task_group_list())

See also `list_task_groups`, which lists them in lines for a person.

For the assistant.
"""
function collect_work_items end

collect_work_items(list::TaskGroupList) = Any[item for item in list.groups if !(item isa ClosedTaskGroup)]
collect_work_items(list::ReferencedDocument) = collect_work_items(get_document(list))

# ── The addresses ────────────────────────────────────────────────────────────
#
# A navigator over a content that holds the list asks the list where a group or a
# task is (`find_navigator_address`), so a link that names one opens its page at
# its full address. Each answer comes from the structure: a task knows its group
# and its place, and an inner group is in the task that holds it.

_get_element_steps(field::AbstractString, index::Int) = (FieldReferenceStep(field), RangeReferenceStep(index - 1, index))

# The steps from `outer`, a group, to `group` among the groups inside it: an inner
# group of one of its tasks, or its preparation, at any depth; `nothing` when it
# holds none.
function _find_inner_group_steps(outer::TaskGroupDocument, group)
    preparation = getfield(outer, :preparation)[]
    preparation === group && return (FieldReferenceStep("preparation"),)
    if preparation isa TaskGroupDocument
        below = _find_inner_group_steps(preparation, group)
        below === nothing || return (FieldReferenceStep("preparation"), below...)
    end
    for (index, task) in enumerate(collect(getfield(outer, :tasks)[]))
        inner = getfield(task, :inner_group)[]
        inner === nothing && continue
        steps = (_get_element_steps("tasks", index)..., FieldReferenceStep("inner_group"))
        inner === group && return steps
        below = _find_inner_group_steps(inner, group)
        below === nothing || return (steps..., below...)
    end
    nothing
end

# The steps from `list` to `group`: an open group of the list, or a group inside
# one.
function _find_group_steps(list::TaskGroupList, group)
    for (index, outer) in enumerate(collect(list.groups))
        outer isa TaskGroupDocument || continue
        steps = _get_element_steps("groups", index)
        outer === group && return steps
        below = _find_inner_group_steps(outer, group)
        below === nothing || return (steps..., below...)
    end
    nothing
end

# Every group of `list`: the open groups, and the groups inside them.
function _collect_inner_task_groups(list::TaskGroupList)
    found = TaskGroupDocument[]
    function add!(group)
        push!(found, group)
        preparation = getfield(group, :preparation)[]
        preparation isa TaskGroupDocument && add!(preparation)
        for task in collect(getfield(group, :tasks)[])
            inner = getfield(task, :inner_group)[]
            inner === nothing || add!(inner)
        end
    end
    foreach(add!, collect_task_group_documents(list))
    found
end

function find_navigator_address(list::TaskGroupList, group::TaskGroupDocument)
    steps = _find_group_steps(list, group)
    steps === nothing ? nothing : extend_reference(EmptyReference(), steps...)
end

# Any other work item of the list is at its place in the list.
function find_navigator_address(list::TaskGroupList, item)
    index = findfirst(other -> other === item, collect(list.groups))
    index === nothing ? nothing : extend_reference(EmptyReference(), _get_element_steps("groups", index)...)
end

# A task alone is at its place in the list. A task of a group is at its place in
# its group, or it is the preparation of a group.
function find_navigator_address(list::TaskGroupList, task::TaskDocument)
    index = findfirst(item -> item === task, collect(list.groups))
    index === nothing || return extend_reference(EmptyReference(), _get_element_steps("groups", index)...)
    place = find_task_document_group(task)
    if place !== nothing
        (group, index) = place
        steps = _find_group_steps(list, group)
        return steps === nothing ? nothing : extend_reference(EmptyReference(), steps..., _get_element_steps("tasks", index)...)
    end
    for group in _collect_inner_task_groups(list)
        getfield(group, :preparation)[] === task || continue
        steps = _find_group_steps(list, group)
        return steps === nothing ? nothing : extend_reference(EmptyReference(), steps..., FieldReferenceStep("preparation"))
    end
    nothing
end

"""
    add_task_group!(list, group) -> list

Put `group`, a group of tasks or another work item, at the end of the list,
unless it is there already. An item whose row a person closed goes back into its
place. A group that starts adds itself, so the caller is the task that writes the
documents.
"""
function add_task_group!(list::TaskGroupList, group)
    groups = collect(list.groups)
    any(g -> g === group, groups) && return list
    identifier = get_work_item_identifier(group)
    place = findfirst(g -> g isa ClosedTaskGroup && getfield(g, :identifier)[] == identifier, groups)
    place === nothing ? push!(list.groups, group) : (list.groups[place] = group)
    list
end

"""
    remove_task_group!(list, group) -> list

Close the row of `group`, a group of tasks or another work item: a
[`ClosedTaskGroup`](@ref) takes its place in the list, and the files of the
streams of the tasks of a group, and of a task alone, go. A group goes on if it
runs, and its tasks keep their bounded lines.
"""
function remove_task_group!(list::TaskGroupList, group)
    index = findfirst(g -> g === group, collect(list.groups))
    index === nothing && return list
    list.groups[index] = ClosedTaskGroup(Cell(String(get_work_item_identifier(group))),
                                         Cell(String(get_document_title(group))),
                                         Cell(_format_closed_task_group_summary(group)),
                                         Cell(describe_work_item_kind(group, 1)))
    _remove_work_item_files!(group)
    list
end

_remove_work_item_files!(group::TaskGroupDocument) = remove_task_output_files!(group)
_remove_work_item_files!(document::TaskDocument) = remove_task_output_files!(document)
_remove_work_item_files!(_) = nothing

# The tasks of the session, as a roster reads them: one part for each open group
# of the session list, and each task with its group as `within`, and one part for
# each open task alone, with no `within`. A row that starts or that a person
# closes changes the parts; a task that runs changes only its own row.
struct _SessionTasks end

get_roster_item_type(::_SessionTasks) = TaskDocument
collect_roster_parts(::_SessionTasks, link) =
    Any[item for item in collect_work_items(get_session_task_group_list()) if item isa Union{TaskGroupDocument,TaskDocument}]
collect_roster_items(::_SessionTasks, link, group::TaskGroupDocument) =
    RosterItem[RosterItem(task, group) for task in group.tasks]
collect_roster_items(::_SessionTasks, link, task::TaskDocument) = RosterItem[RosterItem(task, nothing)]
