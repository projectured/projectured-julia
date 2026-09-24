# Fragment of `EditorModule` — the feeds of the loop: the built-in inbox feed, the per-frame drain, the wait timeout and the frame measurements.

# ── The feeds ─────────────────────────────────────────────────────────
#
# The generalisation of the inbox: every registered inflow of this editor,
# drained at the same point of the frame the inbox is. The contract lives in
# `FeedModule`; the inbox is the one feed the editor always has.

"""
    InboxFeed

The built-in queue feed over `editor.inbox`. Always first in `editor.feeds`,
so a posted operation applies before any other feed writes its target
document.
"""
struct InboxFeed <: Feed end

drain_changes!(::InboxFeed, editor::Editor) = drain_operations!(editor)

# How long the editor may sleep while something subscribes to its clock. One
# tick per sleep, so an animation advances at the cadence the polling loop
# had. With no subscriber the clock does not tick and the editor sleeps to
# the nearest feed deadline, or forever.
const FRAME_INTERVAL = 0.01

"""
    compute_wait_timeout(editor) -> Float64

How long the next wait may block: `FRAME_INTERVAL` while anything subscribes
to the editor's clock, bounded further by every feed's
`compute_wake_deadline`, and `Inf` when nothing asks to come back. A stale
subscriber the collector has not swept yet keeps the animation bound for a
few more frames; each of them drains nothing and repaints nothing.
"""
function compute_wait_timeout(editor::Editor)
    timeout = has_dependents(getfield(editor.clock, :time)) ? FRAME_INTERVAL : Inf
    for feed in editor.feeds
        deadline = compute_wake_deadline(feed, editor)
        deadline === nothing && continue
        deadline < timeout && (timeout = deadline)
    end
    timeout
end

"""
    record_frame_performance!(editor, frame_seconds) -> Nothing

Record what this frame measured in `editor.frame_measurements`: the frame time
always, and every performance count and time when the counters are compiled
in. Runs at the end of each frame of `run_editor!`, inside the counter scope,
so the counters of this frame are still bound. Times are in seconds.
"""
function record_frame_performance!(editor::Editor, frame_seconds::Float64)
    times = Pair{Symbol, Float64}[:frame_time => frame_seconds]
    counts = Pair{Symbol, Float64}[]
    if PERFORMANCE_COUNTERS_ENABLED
        # Every key, in name order, so a new counter reaches the store with no
        # change here.
        counters = get_performance_counters()
        for key in sort!(collect(keys(counters.times)))
            push!(times, key => counters.times[key] / 1e9)
        end
        for key in sort!(collect(keys(counters.counts)))
            push!(counts, key => Float64(counters.counts[key]))
        end
    end
    record_frame_measurements!(editor.frame_measurements; times, counts)
    nothing
end

"""
    drain_feeds!(editor) -> Int

Drain every registered feed, in registration order, and answer how many
items moved in total. Runs once per frame on the editor task, inside the
`:evaluate` barrier of [`run_editor!`](@ref), before `read!` — so the frame
paints what its feeds just wrote.
"""
function drain_feeds!(editor::Editor)
    count = 0
    for feed in editor.feeds
        count += drain_changes!(feed, editor)
    end
    count
end
