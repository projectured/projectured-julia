# A group of tasks on the screen: the document that the pane of a group holds.
# It holds the `TaskGroup`, it writes what each task says into that task's own
# document, and it answers the questions that a pane asks of the whole group:
# how many are done, what each ended with, how far the group has come, and what
# to run again. Nothing here reads a `Cell` outside a projection, and nothing
# here starts a process on its own: a pane calls `start_task_group_document!`,
# and the tasks report back into the documents that the pane already shows.

"""
    TaskGroupDocument

A group of tasks as one document: what was started, how far each task has
got, and what it ended with.

Use it to hold what a person or a client asked to run. It is what the pane of a
group shows, and what the verbs that start, stop and repeat a group act on. One
entry stands for one task, in the order the group was made.

# Example

    document = wrap_task_group_document(TaskGroup(tasks; name = "builds", jobs = 4))
    start_task_group_document!(document)
    get_task_group_document_status(document)       # :running, then :finished

See also `start_task_group_document!`, `stop_task_group_document!` and
`build_task_group_document_counts`.

# Fields
- `title::String` — what the pane is called, such as the words that chose the
  tasks, or the name of the group.
- `jobs::Int` — how many tasks go at once.
- `status::Symbol` — `:pending`, `:running`, `:stopping` or `:finished`.
- `tasks::CellVector` — one [`TaskDocument`](@ref) for each task, in the order
  the group was made. The order never changes, so a run again adds an execution
  to an entry and renumbers nothing.
- `group` — the native `TaskGroup`: its name and its action, its codes, and the
  execution of each task once it starts; a start, a stop and a run again act on
  it.
- `shadow` — the shadow of the group ([`make_task_group_shadow`](@ref)), which
  the slot of each task syncs after the task: its summary, and its counts, the
  parts of the summary that change only when a task starts or ends
  ([`get_task_group_document_summary`](@ref),
  [`get_task_group_document_counts`](@ref)).
- `identifier::String` — `T1`, `T2`, …: the name of the group that never
  changes, whatever the title becomes.
- `selected::Int` — the task the detail of the pane shows, `-1` for the
  preparation of the group, or 0 for none.
- `groups` — the `TaskGroupDocument` of each task that is a group, by its place:
  the pane shows it in the detail of that task.
- `row_filter` — which rows the pane shows: `"all"`, `"running"` or
  `"unexpected"`, as a `PrimitiveString` that the choice of the pane writes.
- `preparation` — the document of the preparation of the group: a
  `TaskGroupDocument` when it is a group, a [`TaskDocument`](@ref) when it is
  one task, or `nothing` when the group has none.
"""
@document struct TaskGroupDocument <: Document
    title::String
    jobs::Int
    status::Symbol
    tasks::CellVector
    group::Any
    shadow::Any
    identifier::String
    selected::Int
    row_filter::Any
    groups::Any
    preparation::Any
end

const _TASK_GROUP_COUNT = Threads.Atomic{Int}(0)

"""
    make_task_group_identifier() -> String

A new identifier for a group: `T1`, `T2`, … in the order the groups of a session
are made.
"""
make_task_group_identifier() = "T" * string(Threads.atomic_add!(_TASK_GROUP_COUNT, 1) + 1)

"""The engine `TaskGroup` the document holds."""
get_task_group(doc::TaskGroupDocument) = getfield(doc, :group)[]

"""The `TaskGroupSummary` of the group at the last sync of its shadow."""
get_task_group_document_summary(doc::TaskGroupDocument) = getfield(doc, :shadow)[].summary

"""The counts of the summary of the group at the last sync of its shadow
([`get_task_group_counts`](@ref))."""
get_task_group_document_counts(doc::TaskGroupDocument) = getfield(doc, :shadow)[].counts

"""
    wrap_task_group_document(group; title = group.name, identifier = make_task_group_identifier())

Wrap a `TaskGroup` as a document, with one [`TaskDocument`](@ref) for each of
its tasks. Nothing runs yet.
"""
function wrap_task_group_document(group::TaskGroup; title::AbstractString = group.name,
                                  identifier::AbstractString = make_task_group_identifier())
    documents = TaskDocument[TaskDocument(task) for task in group.tasks]
    # An inner group is a document of its own, named by its place in the group.
    groups = Dict{Int,Any}(index => wrap_task_group_document(task; title = task.name,
                                                             identifier = string(identifier, ".", index))
                           for (index, task) in enumerate(group.tasks) if task isa TaskGroup)
    # The preparation has the place 0, before the first task.
    preparation = group.preparation === nothing ? nothing :
                  group.preparation isa TaskGroup ?
                      wrap_task_group_document(group.preparation; title = group.preparation.name,
                                               identifier = string(identifier, ".0")) :
                      TaskDocument(group.preparation)
    doc = TaskGroupDocument(Cell(String(title)), Cell(group.jobs), Cell(:pending),
                            CellVector(Cell[Cell(d) for d in documents]),
                            Cell(group), Cell(make_task_group_shadow(group)),
                            Cell(String(identifier)), Cell(0),
                            Cell(PrimitiveString("all")), Cell(groups), Cell(preparation))
    group.runtime.on_start = _make_task_group_wiring(doc)
    preparation === nothing ||
        (group.runtime.on_preparation = _make_preparation_wiring(preparation))
    doc
end

"""
    find_task_group_document(doc, index) -> TaskGroupDocument or nothing

The document of task `index` of the group when that task is a group itself, or
`nothing` when it is not.
"""
find_task_group_document(doc::TaskGroupDocument, index::Integer) =
    get(getfield(doc, :groups)[], Int(index), nothing)

# The task documents, in the order the group was made. The field holds a
# `CellVector`, so the cell is read first and its elements after.
_task_documents(doc::TaskGroupDocument) =
    TaskDocument[document for document in getfield(doc, :tasks)[]]

# Each task of the group is watched from the moment it starts: the session
# `TaskFeedStore` syncs the shadow of its execution, and tells the slot of the
# task in the group, on the task that reads the documents. The pool names the
# task by its place, and the place is the same in both lists for the whole life
# of the group. The group calls this at each start of a task, whoever started the
# group, so the tasks of an inner group reach their documents too.
_make_task_group_wiring(doc::TaskGroupDocument) =
    (index, execution) -> register_task_execution!(get_session_task_feed_store(), execution,
                                                   _TaskGroupSlot(doc, index))

# The owner of the execution of task `index` of a group.
struct _TaskGroupSlot
    group::TaskGroupDocument
    index::Int
end

# The first sync of an execution adds its shadow to the document of the task. A
# task that is a group starts its own tasks again: that first sync also puts the
# tasks of its document back to waiting, before their own syncs come. Each sync
# then syncs the shadow of the group, whose counts the status reads. A sync of an
# execution that the document no longer shows changes nothing.
function record_task_execution_sync!(slot::_TaskGroupSlot, execution, shadow,
                                     before::Symbol, made::Bool)
    doc = slot.group
    document = _task_documents(doc)[slot.index]
    if made
        add_task_execution!(document, execution, shadow)
        inner = find_task_group_document(doc, slot.index)
        if inner !== nothing
            _reset_tasks!(inner, eachindex(get_task_group(inner).tasks))
            _sync_task_group_shadow!(inner)
        end
    elseif get_current_task_execution(document) !== shadow
        return nothing
    end
    _sync_task_group_shadow!(doc)
    nothing
end

# The preparation is watched as a task is, into its own document, and the tally
# of the group does not count it. A group runs its preparation at each start and
# each run again. A preparation that is one task is owned by its document, which
# starts afresh with each execution. A preparation that is a group writes its own
# tasks; the first sync of its execution puts them back to waiting, as for an
# inner group.
function _make_preparation_wiring(document)
    owner = document isa TaskGroupDocument ? _TaskGroupPreparation(document) : document
    execution -> register_task_execution!(get_session_task_feed_store(), execution, owner)
end

# The owner of the execution of a preparation that is a group.
struct _TaskGroupPreparation
    group::TaskGroupDocument
end

function record_task_execution_sync!(preparation::_TaskGroupPreparation, execution, shadow,
                                     before::Symbol, made::Bool)
    doc = preparation.group
    made && _reset_tasks!(doc, eachindex(get_task_group(doc).tasks))
    _sync_task_group_shadow!(doc)
    nothing
end

"""
    get_task_group_preparation(doc) -> TaskGroupDocument, TaskDocument or nothing

The document of the preparation of the group, or `nothing` when it has none.
"""
get_task_group_preparation(doc::TaskGroupDocument) = getfield(doc, :preparation)[]

"""
    describe_task_group_preparation(doc) -> (text, state, expected)

The preparation of a group in words, such as `Before the tasks: building inet —
ERROR: …`, with its `state`: `:waiting`, `:running`, or the result code it ended
with; and whether that end was expected. The group must have a preparation.
"""
function describe_task_group_preparation(doc::TaskGroupDocument)
    preparation = get_task_group_preparation(doc)
    words = "Before the tasks: " * _describe_preparation(get_task_group(doc).preparation)
    if preparation isa TaskGroupDocument
        status = getfield(preparation, :status)[]
        status === :pending && return (words * " — waiting", :waiting, true)
        status in (:running, :stopping) && return (words * " — running", :running, true)
        summary = get_task_group_document_summary(preparation)
        summary.is_expected && return (words * " — " * summary.result, summary.result, true)
        return (words * " — " * summary.result * (summary.reason === nothing ? "" : ": " * summary.reason),
                summary.result, false)
    end
    result = get_task_document_result(preparation)
    if result === nothing
        waiting = get_task_document_status(preparation) === :pending
        return (words * (waiting ? " — waiting" : " — running"), waiting ? :waiting : :running, true)
    end
    is_expected(result) && return (words * " — " * result.result, result.result, true)
    (words * " — " * format_task_result(result), result.result, false)
end

# Sync the shadow of the group, and the status that its counts give, on the
# task that reads the documents.
function _sync_task_group_shadow!(doc::TaskGroupDocument)
    sync_document!(getfield(doc, :shadow)[], get_task_group(doc))
    _refresh_status!(doc)
    doc
end

# The tasks that are about to start again wait, with no current execution.
function _reset_tasks!(doc::TaskGroupDocument, indices)
    documents = _task_documents(doc)
    for index in indices
        reset_task_document!(documents[index])
    end
    doc
end

# Called whenever a task starts or ends, so it must not count the tasks. It reads
# the counts of the shadow of the group, which the tally of the scheduler makes
# without a walk. A count is one walk of every task per change: on 18,500 tasks,
# 13 ms a walk and 2 walks a task, about eight minutes in which the window
# answers nothing, because this runs on the task of the driver, and the driver
# shares the thread that draws.
#
# A group that was told to stop starts no task that waits, so its waiting tasks
# do not keep it running: it is finished once nothing runs.
function _refresh_status!(doc::TaskGroupDocument)
    counts = get_task_group_document_counts(doc)
    running = counts.running
    pending = counts.pending
    current = getfield(doc, :status)[]
    stopping = current === :stopping || get_task_group(doc).stopping
    next = running > 0 ? (stopping ? :stopping : :running) :
           pending > 0 && !stopping ? :running :
           :finished
    next === current || set_cell_value!(getfield(doc, :status), next)
    doc
end

"""
    start_task_group_document!(doc) -> doc

Start every task of the group, `doc.jobs` at a time, and answer at once. Each
task reports into its own document while it goes. The group goes to the top of
the list of the session that the Tasks pane shows.
"""
function start_task_group_document!(doc::TaskGroupDocument)
    group = get_task_group(doc)
    # A group that runs goes on as it is: its Run is off while it goes.
    group.runtime.scheduler !== nothing && !istaskdone(group.runtime.scheduler) && return doc
    group.jobs = max(1, getfield(doc, :jobs)[])
    set_cell_value!(getfield(doc, :status), :running)
    _reset_tasks!(doc, eachindex(group.tasks))
    start_task_group!(group)
    _sync_task_group_shadow!(doc)
    add_task_group!(get_session_task_group_list(), doc)
    doc
end

"""
    rerun_task_group_document!(doc, which = :failed) -> doc

Run part of the group again, in place. `which` is what
[`compute_task_group_indices`](@ref) understands: `:all`, `:failed`,
`:unexpected`, `:unfinished`, or the places of the tasks to repeat. A group whose
row was closed in the Tasks pane gets its row back.
"""
function rerun_task_group_document!(doc::TaskGroupDocument, which = :failed)
    group = get_task_group(doc)
    group.start_time === nothing && return start_task_group_document!(doc)
    indices = compute_task_group_indices(group, which)
    isempty(indices) && return doc
    set_cell_value!(getfield(doc, :status), :running)
    _reset_tasks!(doc, indices)
    rerun_task_group!(group, indices)
    _sync_task_group_shadow!(doc)
    add_task_group!(get_session_task_group_list(), doc)
    doc
end

"""Stop every task of the group. A task that runs is interrupted rather than
killed, so it can end in order and still write what it writes at its end."""
function stop_task_group_document!(doc::TaskGroupDocument)
    group = get_task_group(doc)
    group.start_time === nothing && return doc
    set_cell_value!(getfield(doc, :status), :stopping)
    stop_task_group!(group)
    # A group whose tasks all ended is finished now; no task writes again to say so.
    _sync_task_group_shadow!(doc)
    doc
end

"""
    wait_task_group_document(doc) -> doc

Wait for the group to end, and copy what its tasks said into their documents.
For a caller with no window, on the task that reads the documents.
"""
function wait_task_group_document(doc::TaskGroupDocument)
    wait_task_group(get_task_group(doc))
    drain_task_feed!()
    _sync_task_group_shadow!(doc)
    doc
end

"""
    select_task_document!(doc, index) -> doc

Show task `index` in the detail of the pane, or none with 0.
"""
select_task_document!(doc::TaskGroupDocument, index::Integer) =
    (set_cell_value!(getfield(doc, :selected), Int(index)); doc)

"""
    build_task_group_document_counts(doc) -> Dict{Symbol,Int}

How many tasks are in each state, and `:total`. A pane reads this inside its own
cell, so it follows every task that reports.
"""
function build_task_group_document_counts(doc::TaskGroupDocument)
    counts = Dict{Symbol,Int}(:pending => 0, :running => 0, :done => 0,
                              :error => 0, :cancelled => 0, :skipped => 0, :total => 0)
    for document in _task_documents(doc)
        state = get_task_document_status(document)
        counts[state] = get(counts, state, 0) + 1
        counts[:total] += 1
    end
    counts
end

"""
    measure_task_group_document_progress(doc) -> Float64

How much of the group is done, between 0 and 1. A finished task counts whole,
and a task that runs counts the fraction it reports, or nothing when it reports
none.
"""
function measure_task_group_document_progress(doc::TaskGroupDocument)
    documents = _task_documents(doc)
    isempty(documents) && return 1.0
    done = 0.0
    for document in documents
        state = get_task_document_status(document)
        if state in (:done, :error, :cancelled, :skipped)
            done += 1.0
        elseif state === :running
            progress = get_current_task_execution(document).progress
            progress === nothing || (done += progress)
        end
    end
    clamp(done / length(documents), 0.0, 1.0)
end

"""The state of the whole group, as its own cell holds it."""
get_task_group_document_status(doc::TaskGroupDocument) = getfield(doc, :status)[]

# A group drives a pool of processes. A pasted document replaces neither the
# group nor anything in it.
accepts_pasted_document(::TaskGroupDocument) = false
