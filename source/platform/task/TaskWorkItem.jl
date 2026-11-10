# Fragment of `TaskModule` — a work item of the task list: a group of tasks, a
# task alone, or any other work that a person starts and watches there, such as a
# search below a node of an explorer. The list, its rows and the verbs of tasks
# read a work item through the four functions below and through its decoration,
# which says its state (`get_document_decoration`, with `work_item = true`) and its
# line of detail. Each row records who started it, a `WorkStarter`.

# ── Who started a work item ──────────────────────────────────────────────────

"""
    WorkStarter(kind; identifier = "", name = "", tool_call = "")

Who started a work item of the task list: the person (`kind = :person`), an
assistant (`:assistant`) with the tool call of its model that started it, or a
client over MCP (`:client`). `identifier` names the assistant and does not change
while the assistant lives, so the work page of an assistant finds the rows that it
started. `name` is what the Tasks pane shows, such as "Assistant 2" or "MCP
client", and `tool_call` is the id of the call of the model, or an empty string. It
is a plain value: it holds no editor and no document.

A row records it when its work starts. The start takes it from the evaluation
([`get_work_starter`](@ref)), so no verb names it.

Use it to tell the work of the person from the work of an assistant.

# Example

    get_work_item_starter(find_task_group("T3")).kind

See also `get_work_item_starter` and `describe_work_starter`.
"""
struct WorkStarter
    kind::Symbol
    identifier::String
    name::String
    tool_call::String
end

"""
    WORK_STARTER_KINDS

The kinds of a [`WorkStarter`](@ref): `:person`, `:assistant` and `:client`.
"""
const WORK_STARTER_KINDS = (:person, :assistant, :client)

function WorkStarter(kind::Symbol; identifier::AbstractString = "", name::AbstractString = "",
                     tool_call::AbstractString = "")
    kind in WORK_STARTER_KINDS ||
        throw(ArgumentError(string("the kind of a starter is one of ", WORK_STARTER_KINDS, ", not ", repr(kind))))
    WorkStarter(kind, String(identifier), String(name), String(tool_call))
end

"""
    get_work_starter() -> WorkStarter

Who starts work in the current evaluation: the starter that a tool call of an
assistant or a call of a client binds ([`find_evaluation_starter`](@ref)), else the
person. The loop of an editor binds none for the operations that it reads from the
gestures of the person, and a call that code posts to the loop keeps the starter of
that code. The start of a row takes it as the default of its keyword `started_by`.
"""
function get_work_starter()
    starter = find_evaluation_starter()
    starter isa WorkStarter ? starter : WorkStarter(:person)
end

"""
    describe_work_starter(starter) -> String

Who started a row, in the words that the Tasks pane shows: "the person", the name
of an assistant, such as "Assistant 2", or the name of a client; an empty string for
`nothing`, a row that did not start.
"""
function describe_work_starter end

describe_work_starter(::Nothing) = ""
describe_work_starter(starter::WorkStarter) =
    starter.kind === :person ? "the person" : isempty(starter.name) ? String(starter.kind) : starter.name

# A table shows who started a row in words, and its filter and its sort read the
# same words.
format_roster_value(starter::WorkStarter) = describe_work_starter(starter)
get_arrangement_value(starter::WorkStarter) = describe_work_starter(starter)

"""
    get_work_item_starter(item) -> WorkStarter or nothing

Who started the work item `item`, as its field `started_by` holds it, or `nothing`
for an item that did not start and for a kind of item that records none.

Use it to tell who started a row of the task list.

# Example

    get_work_item_starter(find_task_group("T3"))

See also `WorkStarter`.

For the assistant.
"""
function get_work_item_starter end

get_work_item_starter(item) = nothing
get_work_item_starter(item::ReferencedDocument) = get_work_item_starter(get_document(item))
get_work_item_starter(group::TaskGroupDocument) = getfield(group, :started_by)[]
get_work_item_starter(document::TaskDocument) = getfield(document, :started_by)[]

# ── The functions of a work item ─────────────────────────────────────────────

"""
    get_work_item_identifier(item) -> String

The identifier of the work item `item` in the task list of its session: `T3` for
a group of tasks or a task alone, `S1` for a search. It never changes, and the
closed row of the item keeps it.

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
group of tasks, "task" or "tasks" for a task alone, "search" or "searches" for a
search.

Use it to say what a work item is, as the heading of the Tasks pane does
("2 groups · 1 search").

# Example

    describe_work_item_kind(find_task_group("S1"), 1)

See also `get_work_item_identifier`.
"""
function describe_work_item_kind end

"""
    stop_work_item!(item) -> nothing

Stop the work of `item`, and keep its row in the list: a group stops its tasks, a
task alone stops its process, and a search keeps what it found and reads nothing
more. A close of the row
(`remove_task_group!`) is another step.

Use it to stop a work item of the task list, whatever its kind.

# Example

    stop_work_item!(find_task_group("S1"))

See also `describe_work_item` and `remove_task_group!`.
"""
function stop_work_item! end

"""
    describe_work_item(item; limit = 20) -> String

What `item` did, in lines for a person: its state and what it found, at most
`limit` lines of its parts. A group says how its tasks went, a task alone says
how it went and the last lines that it printed, and a search names its matches
with their places.

Use it to tell the person how a work item of the task list went.

# Example

    describe_work_item(find_task_group("S1"); limit = 5)

See also `describe_task_group` and `find_task_group`.

For the assistant.
"""
function describe_work_item end

get_work_item_identifier(group::TaskGroupDocument) = getfield(group, :identifier)[]
describe_work_item_kind(::TaskGroupDocument, count::Integer) = count == 1 ? "group" : "groups"
stop_work_item!(group::TaskGroupDocument) = (stop_task_group_document!(group); nothing)
describe_work_item(group::TaskGroupDocument; limit::Integer = 20) = _describe_task_group(group, :unexpected, limit)
describe_work_item(item::ReferencedDocument; keywords...) =
    describe_work_item(get_document(item); keywords...)

# A task with no group is a row of its own, named `T…` from the counter of the groups.
get_work_item_identifier(document::TaskDocument) = getfield(document, :identifier)[]
describe_work_item_kind(::TaskDocument, count::Integer) = count == 1 ? "task" : "tasks"
stop_work_item!(document::TaskDocument) = (stop_task!(document); nothing)
describe_work_item(document::TaskDocument; limit::Integer = 20) = _describe_task_document(document, limit)

# Whether the work of `item` goes on, as its decoration says. A group reads its
# status only.
_is_work_item_running(item) =
    any(condition -> condition.name === :running, get_document_decoration(item).conditions)
_is_work_item_running(group::TaskGroupDocument) = getfield(group, :status)[] in (:running, :stopping)

# ── A task alone ─────────────────────────────────────────────────────────────

"""
    StartTaskOperation(document)

Start the task of `document`, a task alone, as [`start_task!`](@ref) does for the
editor that evaluates the operation. A row of the task list joins the list of the
session of that editor, or goes back into its place when a person closed it, and
keeps who started it first. A task that runs goes on as it is. The page of a task
alone makes it for Run again, and `run_tasks!` makes it for a task.
"""
struct StartTaskOperation <: Operation
    document::TaskDocument
end

function evaluate_operation(editor, operation::StartTaskOperation)
    document = operation.document
    get_task_document_status(document) in (:running, :cancelling) && return nothing
    start_task!(document; editor)
    nothing
end

describe_operation(operation::StartTaskOperation) = string("Start the task ", get_document_title(operation.document))

# A process that ran can not be undone, and the operation names its document.
make_inverse_operation(document, ::StartTaskOperation) = DoNothingOperation()
is_self_contained_operation(::StartTaskOperation) = true
