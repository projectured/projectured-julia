# The feed of the slice `task`: the executions of tasks, each brought into its
# shadow on the task of the editor, a few times a second. The readers and the
# sampler of a process write the native layout of a `TaskExecution`, off the loop,
# and each write notes the execution as changed in the store; a drain syncs the
# shadow of each execution that changed, in the cell layout, which the views read.
# So no reader of a process writes a cell, a drain reads no file, and a change of
# state is no edit: it goes into no undo list.
#
# Each execution has an owner: the document that shows it. A drain tells the
# owner what it synced ([`record_task_execution_sync!`](@ref)), so a document
# that adds the shadow to its executions, or a group that counts the states of
# its tasks, follows it.
#
# Each execution also belongs to an editor: the editor of the evaluation that
# started it, or none. The `TaskFeed` of an editor syncs only the executions of
# its editor, so each editor writes only its own documents. A caller with no
# window drains the executions of no editor itself, with `drain_task_feed!`, on
# the one task that reads the documents.

# One execution, its shadow, its owner, the editor that it belongs to, and the
# count of the writes of the execution that the shadow holds.
mutable struct TaskFeedEntry
    execution::TaskExecution
    shadow::Any
    owner::Any
    editor::Any             # ::Editor, or nothing for a caller with no window
    version::Int
end

"""
    TaskFeedStore()

The executions of the tasks that run, each with its shadow and its owner, and the
entries whose execution changed since the last drain. Any task registers an
execution; a drain syncs what changed and lets an execution go once its end is
synced.
"""
struct TaskFeedStore
    lock::ReentrantLock
    entries::Vector{TaskFeedEntry}
    changed::Vector{TaskFeedEntry}
end

TaskFeedStore() = TaskFeedStore(ReentrantLock(), TaskFeedEntry[], TaskFeedEntry[])

"""The store of the session: every document that starts a task registers here."""
const SESSION_TASK_FEED_STORE = TaskFeedStore()

"""The store of the session, [`SESSION_TASK_FEED_STORE`](@ref)."""
get_session_task_feed_store() = SESSION_TASK_FEED_STORE

"""
    register_task_execution!(store, execution, owner; shadow = nothing,
                             editor = find_evaluation_editor()) -> execution

Watch `execution` for `owner`, in the documents of `editor`. Each drain of
`editor` that finds it changed syncs its shadow and calls
[`record_task_execution_sync!`](@ref) with the owner. The first drain makes the
shadow when the caller gave none, and any task can register; a caller on the
editor task that made the shadow itself gives it. A task that a start of a group
starts inherits the editor of the evaluation, so the default names the editor of
the start. An editor that is not an `Editor`, such as the stand-in of a test, has
no feed, so its executions belong to no editor.
"""
function register_task_execution!(store::TaskFeedStore, execution::TaskExecution, owner;
                                  shadow = nothing, editor = find_evaluation_editor())
    entry = TaskFeedEntry(execution, shadow, owner, _get_task_feed_editor(editor), -1)
    lock(store.lock) do
        push!(store.entries, entry)
        push!(store.changed, entry)
    end
    attach_task_execution_listener!(execution, () -> _record_task_feed_change!(store, entry))
    execution
end

# Note that the execution of `entry` changed, once until the next drain.
function _record_task_feed_change!(store::TaskFeedStore, entry::TaskFeedEntry)
    lock(store.lock) do
        any(changed -> changed === entry, store.changed) || push!(store.changed, entry)
    end
    nothing
end

"""
    record_task_execution_sync!(owner, execution, shadow, before, made) -> nothing

What a drain tells the owner of an execution after it synced the shadow:
`before` is the status that the shadow had, or `:pending` when the drain `made`
the shadow just now. An owner that shows the execution adds a shadow that the
drain made to its executions; a group counts the change of the state. The
default does nothing.
"""
record_task_execution_sync!(owner, execution, shadow, before::Symbol, made::Bool) = nothing

# The step of the sample of the tree of the processes of the document that an
# owner stands for, at each drain. An owner that stands for no task document has
# none.
_drain_task_process_tree!(owner, now) = nothing

# @optional: the store is what the call asks, and a caller with no window asks
# the store of the session.
"""
    has_task_feed_entries(store = get_session_task_feed_store(); editor = find_evaluation_editor()) -> Bool

Whether the store watches an execution of `editor` that has not had its end
synced.
"""
has_task_feed_entries(store::TaskFeedStore = get_session_task_feed_store();
                      editor = find_evaluation_editor()) =
    (editor = _get_task_feed_editor(editor);
     lock(() -> any(entry -> entry.editor === editor, store.entries), store.lock))

# The editor whose feed syncs an execution: an `Editor`, or nothing.
_get_task_feed_editor(editor) = editor isa Editor ? editor : nothing

# An entry whose editor ended: no drain syncs it again, so the store lets it go.
_is_task_feed_entry_orphan(entry::TaskFeedEntry) =
    entry.editor isa Editor && entry.editor.has_loop_ended

# @optional: the store is what the call drains, and a caller with no window
# drains the store of the session.
"""
    drain_task_feed!(store = get_session_task_feed_store(); editor = find_evaluation_editor()) -> Int

Sync the shadow of every execution of `editor` that changed since the last
drain, and answer how many were synced. The executions of another editor wait
for the drain of their editor. The sampler of a process that runs writes its
processor load and its memory, so a drain reads no file. An execution whose end
is synced is let go, and so is an execution whose editor ended. The tree of the
processes of the document of each execution that changed, while a view reads it,
takes its step here too ([`drain_system_process_tree!`](@ref)), and its read
runs off the loop. The sampler writes the execution of a process that runs at
each sample, so the tree of a running task takes its step at each drain.

Call it on the task that reads the documents of `editor`: the task of the
editor, which its [`TaskFeed`](@ref) does, or the one task of a caller with no
window, where the default is no editor.
"""
function drain_task_feed!(store::TaskFeedStore = get_session_task_feed_store();
                          editor = find_evaluation_editor())
    editor = _get_task_feed_editor(editor)
    entries = lock(store.lock) do
        filter!(!_is_task_feed_entry_orphan, store.entries)
        changed = filter(entry -> entry.editor === editor, store.changed)
        filter!(entry -> entry.editor !== editor && !_is_task_feed_entry_orphan(entry),
                store.changed)
        changed
    end
    synced = 0
    ended = TaskFeedEntry[]
    now = time()
    for entry in entries
        version = get_task_execution_version(entry.execution)
        if version != entry.version
            made = entry.shadow === nothing
            before = made ? :pending : entry.shadow.status
            if made
                entry.shadow = make_task_execution_shadow(entry.execution)
            else
                sync_document!(entry.shadow, entry.execution)
            end
            entry.version = version
            record_task_execution_sync!(entry.owner, entry.execution, entry.shadow, before, made)
            synced += 1
            entry.shadow.result === nothing || push!(ended, entry)
        end
        _drain_task_process_tree!(entry.owner, now)
    end
    isempty(ended) || lock(store.lock) do
        filter!(entry -> !any(e -> e === entry, ended), store.entries)
    end
    synced
end

"""
    TaskFeed(; store = get_session_task_feed_store(), flush_interval = 0.25, now = time)

The feed of a window that shows tasks: each document of its editor that shows a
task follows it. The wrapper `task` of `build_editor` gives it, and is on by
default. It syncs only the executions of its editor, at most once in each
`flush_interval`, by the clock `now`, and asks for a frame at that interval
while it watches an execution of its editor, and never when it watches none, so
an idle window draws nothing.
"""
mutable struct TaskFeed <: Feed
    store::TaskFeedStore
    flush_interval::Float64
    now::Function
    flushed_at::Float64
end

TaskFeed(; store::TaskFeedStore = get_session_task_feed_store(), flush_interval::Real = 0.25,
           now::Function = time) =
    TaskFeed(store, Float64(flush_interval), now, -Inf)

function drain_changes!(feed::TaskFeed, editor)
    now = feed.now()
    now - feed.flushed_at >= feed.flush_interval || return 0
    has_task_feed_entries(feed.store; editor) || return 0
    feed.flushed_at = now
    drain_task_feed!(feed.store; editor)
end

compute_wake_deadline(feed::TaskFeed, editor) =
    has_task_feed_entries(feed.store; editor) ? feed.flush_interval : nothing

"""
    task = true

The wrapper of `build_editor` that gives the editor a [`TaskFeed`](@ref), so each
document of the editor that shows a task follows it. It is on by default: a feed
that watches no execution asks for no frame.
"""
function wrap_editor!(::Val{:task}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.feeds, TaskFeed())
    parts
end

get_wrapper_layers(::Val{:task}) = (:screen => 20,)
is_wrapper_default(::Val{:task}) = true

"""
    make_task_feeds() -> Vector{Feed}

The `feeds` of an editor that shows tasks and is made with no wrappers, as
`Editor(…; feeds = make_task_feeds())` makes it: one [`TaskFeed`](@ref) over the
store of the session. `build_editor` gives the feed with its wrapper `task`.
"""
make_task_feeds() = Feed[TaskFeed()]
