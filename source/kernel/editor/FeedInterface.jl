# Fragment of `FeedModule` — the feed **contract**: the abstract `Feed` type
# every feed subtypes, and the open generics a concrete feed answers with a
# method for its own type. Nothing here carries a body — the fallback
# behaviours for the parts a feed may decline sit in `FeedDefaults.jl`.

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

There is deliberately no default method: a feed that cannot drain is a bug,
not a no-op, so an unimplemented feed raises a `MethodError`.
"""
function drain_changes! end

"""
    compute_wake_deadline(feed) -> Float64 or nothing

At most this many seconds until this feed needs a frame, or `nothing` when it
can wait forever. The editor sleeps at most the minimum deadline over its
feeds. A feed that rate-limits its flush answers its interval while it holds
unflushed data. The default answers `nothing`.
"""
function compute_wake_deadline end

"""
    attach_wake_callback!(feed, wake) -> Nothing

Hand `feed` the wake function of its editor, once, at registration. The feed
passes it to its producer-side store, so a producer wakes the editor without
naming it. The default does nothing — a feed whose producers never wake
declines the callback.
"""
function attach_wake_callback! end
