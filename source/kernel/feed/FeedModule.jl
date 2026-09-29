"""
    FeedModule

The feed contract of the editor. A feed is one registered inflow of a running
editor. A producer on any task writes the feed's store and never blocks. The
editor moves what is new into a target document, once per frame, on its own
task. The target is a normal document: the embedder mounts it in the shown
tree, gives it a projection, and registers the feed when it creates the
editor.

This module holds only the contract. A concrete feed lives beside its store
and its target document: a feed that holds a queue of operations lives beside
that queue, and a feed of log lines beside the log.

The module lives in two fragments that share this namespace:

- [`FeedInterface.jl`](FeedInterface.jl) — the contract: the abstract `Feed`
  type and the open generics a concrete feed answers.
- [`FeedDefaults.jl`](FeedDefaults.jl) — the fallback behaviours the contract
  supplies itself, for the generics that a feed does not have to implement: no
  deadline, and no wake callback.
"""
module FeedModule

export Feed, drain_changes!, compute_wake_deadline, attach_wake_callback!

include("FeedInterface.jl")  # the feed contract (declaration-only)
include("FeedDefaults.jl")   # the fallback behaviours the contract supplies itself

end # module
