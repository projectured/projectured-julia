# Fragment of `FeedModule` — the fallback behaviours the feed contract
# supplies itself, for the generics that a feed does not have to implement. The
# contract is declared in `FeedInterface.jl`; the concrete feeds live beside their
# stores. `drain_changes!` has no counterpart here on purpose — an
# unimplemented drain must raise a `MethodError`, not quietly move nothing.

# No deadline: the feed can wait forever for its next frame.
compute_wake_deadline(::Feed, editor) = nothing

# No wake path: the feed's producers never ask for a frame.
attach_wake_callback!(::Feed, wake) = nothing
