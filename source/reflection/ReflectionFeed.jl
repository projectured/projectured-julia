# Fragment of `ReflectionModule` — the feed that keeps a reflected tree in step
# with its value. A chevron only flags a marker, and a sync is what opens it, so
# something must run the sync; this feed runs it on the editor task, once per
# frame, where a document made of cells may be written.

"""
    ReflectionFeed(shadow, value; policy = DepthPolicy(1))

Register it when the editor is created, with the tree that
[`reflect_document`](@ref) made of `value` and the same `policy`:

    Editor(...; feeds = Feed[ReflectionFeed(shadow, value; policy = policy)])

Each frame syncs `shadow` against `value`, which writes only what changed. So a
node that a chevron opened fills one level deeper, and a value that changed
shows its new state on the next frame.

A marker that a click flagged asks for a frame at once, so the node opens
without a wait for the next input. A sync that throws does not ask again: the
request then waits for the next input, and does not make a frame for each
fault.
"""
mutable struct ReflectionFeed <: Feed
    shadow::AReflectedNode
    value::Any
    policy::SyncPolicy
    # The last drain threw before its sync ended.
    is_sync_unfinished::Bool
end

ReflectionFeed(shadow::AReflectedNode, value; policy::SyncPolicy = DepthPolicy(1)) =
    ReflectionFeed(shadow, value, policy, false)

"""
    drain_changes!(feed::ReflectionFeed, editor) -> Int

Sync the tree against its value, and answer how many requests of a chevron the
sync served.
"""
function drain_changes!(feed::ReflectionFeed, editor)
    requests = _count_sync_requests(feed.shadow)
    feed.is_sync_unfinished = true
    sync_reflection!(feed.shadow, feed.value, feed.policy)
    feed.is_sync_unfinished = false
    requests
end

compute_wake_deadline(feed::ReflectionFeed, editor) =
    !feed.is_sync_unfinished && _count_sync_requests(feed.shadow) > 0 ? 0.0 : nothing

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
