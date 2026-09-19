"""
    FeedModule

The feed contract of the editor. A feed is one registered inflow of a running
editor. A producer on any task writes the feed's store and never blocks. The
editor moves what is new into a target document, once per frame, on its own
task. The target is a normal document: the embedder mounts it in the shown
tree, gives it a projection, and registers the feed when it creates the
editor.

This module holds only the contract. A concrete feed lives beside its store
and its target document: the inbox feed in `EditorModule`, the message log
feed in `ProjecturedLog`.
"""
module FeedModule

export Feed, drain_changes!, compute_wake_deadline, attach_wake_callback!

"""
    Feed

Abstract supertype for the registered inflows of an editor. A concrete feed
holds two ends: a producer-side store that any task writes without blocking,
and a target document that only the editor task writes.
"""
abstract type Feed end

"""
    drain_changes!(feed, editor) -> Int

Move everything new from the feed's store into its target document, and
answer how many items moved. The editor calls it once per frame, on its own
task, before `read!`. A feed must write only what is new: an empty store
writes no cell, so an idle feed repaints nothing. A feed must not block —
a producer waits for the editor through its store, never the other way.

There is no default method. A feed that cannot drain is a bug, not a no-op.
"""
function drain_changes! end

"""
    compute_wake_deadline(feed) -> Float64 or nothing

At most this many seconds until this feed needs a frame, or `nothing` when it
can wait forever. The editor sleeps at most the minimum deadline over its
feeds. A feed that rate-limits its flush answers its interval while it holds
unflushed data. The default answers `nothing`.
"""
compute_wake_deadline(::Feed) = nothing

"""
    attach_wake_callback!(feed, wake) -> Nothing

Hand `feed` the wake function of its editor, once, at registration. The feed
passes it to its producer-side store, so a producer wakes the editor without
naming it. The default does nothing — a feed whose producers never wake
declines the callback.
"""
attach_wake_callback!(::Feed, wake) = nothing

end # module
