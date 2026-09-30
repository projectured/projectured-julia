# Fragment of `EditorModule` — the feeds: their drain, the wait timeout, the frame times.

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
# tick per sleep, so an animation advances every 10 milliseconds. With no
# subscriber the clock does not tick and the editor sleeps to the nearest feed
# deadline, or forever.
const FRAME_INTERVAL = 0.01

"""
    compute_wait_timeout(editor) -> Float64

How long the next wait may block: `FRAME_INTERVAL` while anything subscribes
to the editor's clock, bounded further by every feed's
`compute_wake_deadline` and by the earliest timer of `editor.timers`, and `Inf`
when nothing asks to come back. A stale
subscriber the collector has not swept yet keeps the animation bound for a
few more frames; each of them drains nothing and repaints nothing.

Each deadline is computed in an `:evaluate` barrier. A deadline that throws is
recorded with the type of its feed as the origin and counts as no deadline.
"""
function compute_wait_timeout(editor::Editor)
    timeout = has_dependent_cells(getfield(editor.clock, :time)) ? FRAME_INTERVAL : Inf
    for feed in editor.feeds
        deadline = _run_barrier(editor, :evaluate; origin = typeof(feed),
                                fallback = nothing) do
            compute_wake_deadline(feed, editor)
        end
        deadline === nothing && continue
        deadline < timeout && (timeout = deadline)
    end
    isempty(editor.timers) && return timeout
    now = time()
    for due in values(editor.timers)
        remaining = max(0.0, due - now)
        remaining < timeout && (timeout = remaining)
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
items moved in total. Runs once per frame on the editor task, before `read!` —
so the frame paints what its feeds just wrote.

Each drain runs in its own `:evaluate` barrier. A drain that throws is recorded
with the type of its feed as the origin and counts as no item, and the next feed
still drains.
"""
function drain_feeds!(editor::Editor)
    count = 0
    for feed in editor.feeds
        count += _run_barrier(editor, :evaluate; origin = typeof(feed), fallback = 0) do
            drain_changes!(feed, editor)
        end
    end
    count
end
