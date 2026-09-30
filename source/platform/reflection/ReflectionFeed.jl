# Fragment of `ReflectionModule` — the feed that keeps a reflected tree in step
# with its value. A chevron only flags a marker, and a sync is what opens it, so
# something must run the sync; this feed runs it on the editor task, at most once
# per interval, where a document made of cells may be written.

"""
    ReflectionFeed(shadow, value; policy = DepthPolicy(1), interval = 0.25, now = time)

Register it when the editor is created, with the tree that
[`reflect_document`](@ref) made of `value` and the same `policy`:

    Editor(...; feeds = Feed[ReflectionFeed(shadow, value; policy = policy)])

A frame syncs `shadow` against `value`, which writes only what changed. So a
node that a chevron opened fills one level deeper, and a value that changed
shows its new state.

A sync runs at most once per `interval`, by the clock `now`. A sync that writes
changes what the display shows, and the display event of that frame makes one
more frame; a value that changes all the time would otherwise sync on every one
of them, and the frames would feed themselves. A frame inside the interval skips
the sync and asks for a frame at the end of the interval, so a change that it
skipped is shown then.

A marker that a click flagged asks for a frame at once and syncs at once, so the
node opens without a wait for the next input. A sync that throws does not ask
again: the request then waits for the next input, and does not make a frame for
each fault.
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
end

ReflectionFeed(shadow::AReflectedNode, value; policy::SyncPolicy = DepthPolicy(1),
               interval::Real = 0.25, now::Function = time) =
    ReflectionFeed(shadow, value, policy, false, Float64(interval), now, -Inf, false)

"""
    drain_changes!(feed::ReflectionFeed, editor) -> Int

Sync the tree against its value, and answer how many requests of a chevron the
sync served. A drain less than an interval after the last sync, with no request,
skips the sync and answers `0`.
"""
function drain_changes!(feed::ReflectionFeed, editor)
    requests = _count_sync_requests(feed.shadow)
    if requests == 0 && _is_sync_early(feed)
        feed.is_sync_skipped = true
        return 0
    end
    feed.synced_at = feed.now()
    feed.is_sync_skipped = false
    feed.is_sync_unfinished = true
    sync_reflection!(feed.shadow, feed.value, feed.policy)
    feed.is_sync_unfinished = false
    requests
end

function compute_wake_deadline(feed::ReflectionFeed, editor)
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
