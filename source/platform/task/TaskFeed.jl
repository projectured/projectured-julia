# The feed of the slice `task`: what the executions of tasks say, carried to
# the documents that show them. The readers of a process write its
# `TaskExecution`; a drain copies what changed into the document that shows the
# task, on the task of the editor, a few times a second. So no reader of a
# process writes a cell, and a change of state is no edit: it goes into no undo
# list.
#
# A document that starts a task registers the execution here, with the function
# that writes a copy of it into the document. A window gives its editor a
# `TaskFeed` in its `feeds`. A caller with no window drains the store itself,
# with `drain_task_feed!`, on the one task that reads the documents.

# One execution, the function that writes a copy of it into its document, and what
# the document already shows: the version of the execution and the line counts of
# its two streams.
mutable struct TaskFeedEntry
    execution::TaskExecution
    write::Function
    version::Int
    output_count::Int
    error_output_count::Int
end

"""
    TaskFeedStore()

The executions of the tasks that run, each with the function that writes it into
the document that shows it. Any task registers an execution; a drain copies what
changed and lets an execution go once its end is copied.
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
    register_task_execution!(store, execution, write) -> execution

Watch `execution`: each drain that finds it changed calls `write(snapshot)` with a
copy from [`get_task_execution_snapshot`](@ref). The first drain writes it whatever
it holds.
"""
function register_task_execution!(store::TaskFeedStore, execution::TaskExecution, write::Function)
    lock(store.lock) do
        push!(store.entries, TaskFeedEntry(execution, write, -1, -1, -1))
    end
    execution
end

"""Whether the store watches an execution that has not had its end copied."""
has_task_feed_entries(store::TaskFeedStore = get_session_task_feed_store()) =
    lock(() -> !isempty(store.entries), store.lock)

"""
    drain_task_feed!(store = get_session_task_feed_store(); now = time()) -> Int

Copy into its document every execution that changed since the last drain, and
answer how many were copied. An execution whose process runs is sampled first, so
its processor load and its memory are fresh. An execution whose end is copied is
let go.

Call it on the task that reads the documents: the task of the editor, which a
[`TaskFeed`](@ref) does, or the one task of a caller with no window.
"""
# @optional: the store is what the call drains, and a caller with no window
# drains the store of the session.
function drain_task_feed!(store::TaskFeedStore = get_session_task_feed_store();
                          now::Real = time())
    entries = lock(() -> copy(store.entries), store.lock)
    written = 0
    ended = TaskFeedEntry[]
    for entry in entries
        sample_task_usage!(entry.execution; now = now)
        snapshot = get_task_execution_snapshot(entry.execution; output_count = entry.output_count,
                                             error_output_count = entry.error_output_count)
        snapshot.version == entry.version && continue
        entry.write(snapshot)
        entry.version = snapshot.version
        entry.output_count = snapshot.output_count
        entry.error_output_count = snapshot.error_output_count
        written += 1
        snapshot.result === nothing || push!(ended, entry)
    end
    isempty(ended) || lock(store.lock) do
        filter!(entry -> !any(e -> e === entry, ended), store.entries)
    end
    written
end

"""
    TaskFeed(; store = get_session_task_feed_store(), flush_interval = 0.25, now = time)

The feed of a window that shows tasks: give it to the editor in its `feeds`,
and each document that shows a task follows it. It copies at most once in each
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
