# The feed of the slice `task`: the executions of tasks, each brought into its
# shadow on the task of the editor, a few times a second. The readers of a process
# write the native layout of a `TaskExecution`; a drain syncs its shadow in the
# cell layout, which the views read. So no reader of a process writes a cell, and
# a change of state is no edit: it goes into no undo list.
#
# Each execution has an owner: the document that shows it. A drain tells the
# owner what it synced ([`record_task_execution_sync!`](@ref)), so a document
# that adds the shadow to its executions, or a group that counts the states of
# its tasks, follows it. A window gives its editor a `TaskFeed` in its `feeds`. A
# caller with no window drains the store itself, with `drain_task_feed!`, on the
# one task that reads the documents.

# One execution, its shadow, its owner, and the count of the writes of the
# execution that the shadow holds.
mutable struct TaskFeedEntry
    execution::TaskExecution
    shadow::Any
    owner::Any
    version::Int
end

"""
    TaskFeedStore()

The executions of the tasks that run, each with its shadow and its owner. Any
task registers an execution; a drain syncs what changed and lets an execution go
once its end is synced.
"""
struct TaskFeedStore
    lock::ReentrantLock
    entries::Vector{TaskFeedEntry}
end

TaskFeedStore() = TaskFeedStore(ReentrantLock(), TaskFeedEntry[])

"""The store of the session: every document that starts a task registers here."""
const SESSION_TASK_FEED_STORE = TaskFeedStore()

"""The store of the session, [`SESSION_TASK_FEED_STORE`](@ref)."""
get_session_task_feed_store() = SESSION_TASK_FEED_STORE

"""
    register_task_execution!(store, execution, owner; shadow = nothing) -> execution

Watch `execution` for `owner`. Each drain that finds it changed syncs its shadow
and calls [`record_task_execution_sync!`](@ref) with the owner. The first drain
makes the shadow when the caller gave none, and any task can register; a caller
on the editor task that made the shadow itself gives it.
"""
function register_task_execution!(store::TaskFeedStore, execution::TaskExecution, owner;
                                  shadow = nothing)
    lock(store.lock) do
        push!(store.entries, TaskFeedEntry(execution, shadow, owner, -1))
    end
    execution
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

"""Whether the store watches an execution that has not had its end synced."""
has_task_feed_entries(store::TaskFeedStore = get_session_task_feed_store()) =
    lock(() -> !isempty(store.entries), store.lock)

"""
    drain_task_feed!(store = get_session_task_feed_store(); now = time()) -> Int

Sync the shadow of every execution that changed since the last drain, and answer
how many were synced. An execution whose process runs is sampled first, so its
processor load and its memory are fresh. An execution whose end is synced is let
go.

Call it on the task that reads the documents: the task of the editor, which a
[`TaskFeed`](@ref) does, or the one task of a caller with no window.
"""
# @optional: the store is what the call drains, and a caller with no window
# drains the store of the session.
function drain_task_feed!(store::TaskFeedStore = get_session_task_feed_store();
                          now::Real = time())
    entries = lock(() -> copy(store.entries), store.lock)
    synced = 0
    ended = TaskFeedEntry[]
    for entry in entries
        sample_task_usage!(entry.execution; now = now)
        version = get_task_execution_version(entry.execution)
        version == entry.version && continue
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
    isempty(ended) || lock(store.lock) do
        filter!(entry -> !any(e -> e === entry, ended), store.entries)
    end
    synced
end

"""
    TaskFeed(; store = get_session_task_feed_store(), flush_interval = 0.25, now = time)

The feed of a window that shows tasks: give it to the editor in its `feeds`,
and each document that shows a task follows it. It syncs at most once in each
`flush_interval`, by the clock `now`, and asks for a frame at that interval
while it watches an execution, and never when it watches none, so an idle window
draws nothing.
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
    has_task_feed_entries(feed.store) || return 0
    feed.flushed_at = now
    drain_task_feed!(feed.store; now = now)
end

compute_wake_deadline(feed::TaskFeed, editor) =
    has_task_feed_entries(feed.store) ? feed.flush_interval : nothing

"""
    make_task_feeds() -> Vector{Feed}

The `feeds` of a window that shows tasks: one [`TaskFeed`](@ref) over the store
of the session. `build_editor(…; feeds = make_task_feeds())`.
"""
make_task_feeds() = Feed[TaskFeed()]
