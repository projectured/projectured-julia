# Fragment of `TaskModule` — a work item of the task list: a group of tasks, or
# any other work that a person starts and watches there, such as a search below a
# node of an explorer. The list, its rows and the verbs of tasks read a work item
# through the four functions below and through its decoration, which says its
# state (`get_document_decoration`, with `work_item = true`) and its line of
# detail.

"""
    get_work_item_identifier(item) -> String

The identifier of the work item `item` in the task list of its session: `T3` for
a group of tasks, `S1` for a search. It never changes, and the closed row of the
item keeps it.

Use it to name a work item, as the rows of the Tasks pane and the verbs of tasks
do.

# Example

    get_work_item_identifier(find_task_group("T3"))

See also `describe_work_item_kind` and `collect_work_items`.
"""
function get_work_item_identifier end

"""
    describe_work_item_kind(item, count) -> String

The word for `count` work items of the kind of `item`: "group" or "groups" for a
group of tasks, "search" or "searches" for a search.

Use it to say what a work item is, as the heading of the Tasks pane does
("2 groups · 1 search").

# Example

    describe_work_item_kind(find_task_group("S1"), 1)

See also `get_work_item_identifier`.
"""
function describe_work_item_kind end

"""
    stop_work_item!(item) -> nothing

Stop the work of `item`, and keep its row in the list: a group stops its tasks,
and a search keeps what it found and reads nothing more. A close of the row
(`remove_task_group!`) is another step.

Use it to stop a work item of the task list, whatever its kind.

# Example

    stop_work_item!(find_task_group("S1"))

See also `describe_work_item` and `remove_task_group!`.
"""
function stop_work_item! end

"""
    describe_work_item(item; limit = 20) -> Text

What `item` did, in lines for a person: its state and what it found, at most
`limit` lines of its parts. A group says how its tasks went, and a search names
its matches with their places.

Use it to tell the person how a work item of the task list went.

# Example

    describe_work_item(find_task_group("S1"); limit = 5)

See also `stop_work_item!` and `get_work_item_identifier`.
"""
function describe_work_item end

get_work_item_identifier(group::TaskGroupDocument) = getfield(group, :identifier)[]
describe_work_item_kind(::TaskGroupDocument, count::Integer) = count == 1 ? "group" : "groups"
stop_work_item!(group::TaskGroupDocument) = (stop_task_group_document!(group); nothing)
describe_work_item(group::TaskGroupDocument; limit::Integer = 20) = _describe_task_group(group, :unexpected, limit)

# Whether the work of `item` goes on, as its decoration says. A group reads its
# status only.
_is_work_item_running(item) =
    any(condition -> condition.name === :running, get_document_decoration(item).conditions)
_is_work_item_running(group::TaskGroupDocument) = getfield(group, :status)[] in (:running, :stopping)
