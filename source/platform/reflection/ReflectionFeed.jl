# Fragment of `ReflectionModule` — the feed that keeps a reflected tree in step
# with its value. A chevron only flags a marker, and a sync is what opens it, so
# something must run the sync; this feed reads the value on a task of its own, at
# most once per interval, and writes what it read into the tree on the editor
# task, where a document made of cells may be written.

"""
    ReflectionFeed(shadow, value; policy = DepthPolicy(1), interval = 0.25, now = time)

Register it when the editor is created, with the tree that
[`reflect_document`](@ref) made of `value` and the same `policy`:

    Editor(...; feeds = Feed[ReflectionFeed(shadow, value; policy = policy)])

A drain starts a read of `value` on a task of the default pool, along the nodes
that are open, with the methods of the type of the value. The read wakes the
editor when it ends, and the next drain writes what it read into `shadow`, only
what changed. So a node that a chevron opened fills one level deeper, and a
value that changed shows its new state, and no method of the value runs on the
loop. A document made of cells inside the value is read on the loop, when the
drain writes it. A node that opened or closed during the read keeps what it
shows, and the next read fills it.

A sync runs at most once per `interval`, by the clock `now`. A sync that writes
changes what the display shows, and the display event of that frame makes one
more frame; a value that changes all the time would otherwise sync on every one
of them, and the frames would feed themselves. A frame inside the interval skips
the sync and asks for a frame at the end of the interval, so a change that it
skipped is shown then.

A marker that a click flagged asks for a frame at once and starts a read at once,
so the node opens without a wait for the next input. A read that throws goes to
the drain that would write it, which throws it, and it does not ask again: the
request then waits for the next input, and does not make a frame for each fault.
"""
mutable struct ReflectionFeed <: Feed
    shadow::AReflectedNode
    value::Any
    policy::SyncPolicy
    # The last drain threw before its sync ended.
    is_sync_unfinished::Bool
    # The shortest time between two syncs, its clock, when the last one ran, and
    # whether a frame inside the interval skipped one.
    interval::Float64
    now::Function
    synced_at::Float64
    is_sync_skipped::Bool
    # The task of the read that runs, the snapshot or the exception that the last
    # read answered, under the lock, and the wake function of the editor.
    reading::Union{Task,Nothing}
    lock::ReentrantLock
    read::Any
    wake::Any
end

ReflectionFeed(shadow::AReflectedNode, value; policy::SyncPolicy = DepthPolicy(1),
               interval::Real = 0.25, now::Function = time) =
    ReflectionFeed(shadow, value, policy, false, Float64(interval), now, -Inf, false,
                   nothing, ReentrantLock(), nothing, nothing)

# What a read that threw answers, so the drain throws it on the loop.
struct _ReflectionReadFailure
    exception::Any
    backtrace::Any
end

"""
    drain_changes!(feed::ReflectionFeed, editor) -> Int

Write the read that ended into the tree, and answer how many requests of a
chevron it served; or start a read of the value, and answer `0`. A drain less
than an interval after the last read, with no request, starts none. A drain while
a read runs does nothing.
"""
function drain_changes!(feed::ReflectionFeed, editor)
    read = lock(() -> (read = feed.read; feed.read = nothing; read), feed.lock)
    read === nothing || return _write_reflection_read!(feed, read)
    feed.reading === nothing || return 0
    requests = _count_sync_requests(feed.shadow)
    if requests == 0 && _is_sync_early(feed)
        feed.is_sync_skipped = true
        return 0
    end
    feed.synced_at = feed.now()
    feed.is_sync_skipped = false
    open = _make_reflection_open_state(feed.shadow, feed.policy, 0)
    feed.reading = errormonitor(Threads.@spawn :default _read_reflection!(feed, open))
    0
end

# Read the value along `open` into a snapshot, keep it for the next drain, and
# wake the editor.
function _read_reflection!(feed::ReflectionFeed, open::_ReflectionOpenState)
    read = try
        _take_reflection_snapshot(feed.value, open, feed.policy, 0)
    catch exception
        _ReflectionReadFailure(exception, catch_backtrace())
    end
    lock(() -> (feed.read = read), feed.lock)
    wake = feed.wake
    wake === nothing || wake()
    nothing
end

# Write what a read answered into the tree, and answer how many requests of a
# chevron it served. A read that threw is thrown here, so the editor records it.
function _write_reflection_read!(feed::ReflectionFeed, read)
    feed.reading = nothing
    if read isa _ReflectionReadFailure
        feed.is_sync_unfinished = true
        throw(CapturedException(read.exception, read.backtrace))
    end
    requests = _count_sync_requests(feed.shadow)
    feed.is_sync_unfinished = true
    _sync_reflection!(feed.shadow, read, feed.policy, 0)
    feed.is_sync_unfinished = false
    max(0, requests - _count_sync_requests(feed.shadow))
end

attach_wake_callback!(feed::ReflectionFeed, wake) = (feed.wake = wake; nothing)

function compute_wake_deadline(feed::ReflectionFeed, editor)
    lock(() -> feed.read !== nothing, feed.lock) && return 0.0
    # A read that runs wakes the editor when it ends.
    feed.reading === nothing || return nothing
    feed.is_sync_unfinished && return nothing
    _count_sync_requests(feed.shadow) > 0 && return 0.0
    # A frame inside the interval skipped the sync: come back at its end.
    feed.is_sync_skipped || return nothing
    max(0.0, feed.synced_at + feed.interval - feed.now())
end

# Whether the last sync ran less than an interval ago.
_is_sync_early(feed::ReflectionFeed) = feed.now() - feed.synced_at < feed.interval

# The flagged markers in the tree below `node`: a closed node, or the tail of a
# capped collection. The walk visits only what is open, which is what the
# screen shows.
function _count_sync_requests(node::AReflectedNode)
    children = node.children
    children isa AUnsyncedDocument && return children.requested ? 1 : 0
    children isa CellVector || return 0
    count = 0
    for index in 1:length(children)
        child = children[index]
        count += child isa AUnsyncedDocument ? (child.requested ? 1 : 0) :
                                               _count_sync_requests(child)
    end
    count
end
