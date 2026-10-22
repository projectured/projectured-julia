# Fragment of `EditorModule` — the feeds: their drain, the wait timeout, the frame times.

# ── The feeds ─────────────────────────────────────────────────────────
#
# The generalisation of the inbox: every registered inflow of this editor,
# drained at the same point of the frame the inbox is. The contract lives in
# `FeedModule`; the inbox is the one feed the editor always has.

"""
    InboxFeed

The built-in queue feed over the posts of the editor: the queue of its owner,
then its inbox. Always first in `editor.feeds`, so a posted operation applies
before any other feed writes its target document.
"""
struct InboxFeed <: Feed end

drain_changes!(::InboxFeed, editor::Editor) = drain_operations!(editor)

# How long the editor may sleep while something subscribes to its clock. One
# tick per sleep, so an animation draws at most 30 frames a second, and the
# tasks of the thread of the editor run in the sleep. With no subscriber the
# clock does not tick and the editor sleeps to the nearest feed deadline, or
# forever.
const FRAME_INTERVAL = 1 / 30

# How long a frame that does not wait gives the cooperative tasks of the thread
# of the editor and their I/O: one millisecond, the step of the timers of libuv.
const TASK_SHARE = 0.001

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
    timeout = has_clock_readers(editor.clock) ? FRAME_INTERVAL : Inf
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
    FRAME_PARTS

The parts of a frame that the record of a frame measures, in the order of the
loop:

- `:feed`, the drain of the feeds;
- `:report`, the report of the faults of the last frame;
- `:input`, the read of the input from the devices of the backend;
- `:reader`, the rest of the read stage: the reader of the projection;
- `:evaluate`, the operations;
- `:print`, the rest of the print stage: the print of the document and a retry;
- `:paint`, the write of the output to the devices, where the printer
  computations run while the backend reads the output;
- `:frame`, the whole frame.

The first seven do not overlap, and `:frame` holds them and the small work
between them.

Use it with [`FRAME_PART_MEASURES`](@ref) and
[`get_frame_part_measurement_name`](@ref) to read the measurements of each part
from `editor.frame_measurements`, for example to draw them as a table.

# Example

    for part in FRAME_PARTS
        name = get_frame_part_measurement_name(part, :time)
        println(part, ": ", compute_frame_measurement_summary(store, name).mean)
    end
"""
const FRAME_PARTS = (:feed, :report, :input, :reader, :evaluate, :print, :paint, :frame)

"""
    FRAME_PART_MEASURES

What the record of a frame measures of each part of [`FRAME_PARTS`](@ref):
`:time`, in seconds and in every build, and when the counters are compiled in,
the cell counts of the part: `:cell_reads`, `:cell_checks`, `:cell_computes`,
`:cell_stops`, `:cell_invalidations` and `:cell_writes`.

Use it to find which measures a store holds for the parts: a build without the
counters records only `:time`.

# Example

    names = get_frame_measurement_names(store)
    measures = filter(FRAME_PART_MEASURES) do measure
        get_frame_part_measurement_name(:frame, measure) in names
    end
"""
const FRAME_PART_MEASURES = (:time, :cell_reads, :cell_checks, :cell_computes, :cell_stops,
                             :cell_invalidations, :cell_writes)

const _FRAME_PART_MEASUREMENT_NAMES = Dict((part, measure) => Symbol(part, :_, measure)
                                           for part in FRAME_PARTS
                                           for measure in FRAME_PART_MEASURES)

"""
    get_frame_part_measurement_name(part, measure) -> Symbol

The name under which the record of a frame keeps the measure `measure` of the part
`part`, such as `:reader_time` or `:paint_cell_computes`. Throws a `KeyError` for a
part that is not in [`FRAME_PARTS`](@ref) or a measure that is not in
[`FRAME_PART_MEASURES`](@ref).

Use it to read one part of a frame from a `FrameMeasurementStore`, with no
knowledge of how the names are spelled.

# Example

    name = get_frame_part_measurement_name(:paint, :cell_computes)
    compute_frame_measurement_summary(editor.frame_measurements, name).total
"""
get_frame_part_measurement_name(part::Symbol, measure::Symbol) =
    _FRAME_PART_MEASUREMENT_NAMES[(part, measure)]

"""
    record_frame_performance!(editor, frame_seconds) -> Nothing

Record what this frame measured in `editor.frame_measurements`. Times are in
seconds. In every build, the frame records:

- the time of each part of [`FRAME_PARTS`](@ref), by its name from
  [`get_frame_part_measurement_name`](@ref): `:frame_time`, the time of the whole
  frame, with its held frames, and `:feed_time` to `:paint_time`, the time of
  each part without its held frames;
- `:held_time`, the time of the held frames of code units;
- `:garbage_collection_time` and `:compile_time`, the time that the garbage
  collector and the compiler took in the process;
- `:yielded_time`, the time that the task of the frame did not run, only when
  the process keeps the running time of its tasks (`--task-metrics=yes`);
- `:allocated_bytes`, a count: the bytes that the process allocated.

When the counters are compiled in, it also records the cell counts of each part,
such as `:reader_cell_reads` or `:paint_cell_computes`, and every other
performance count and time. It runs at the end of each frame of
[`run_measured_frame!`](@ref), inside the counter scope, so the counters of this
frame are still bound.
"""
function record_frame_performance!(editor::Editor, frame_seconds::Float64)
    stages = editor.frame_stages
    part_seconds, part_counts = _compute_frame_part_measures(stages)
    times = Pair{Symbol, Float64}[:frame_time => frame_seconds]
    for (part, seconds) in part_seconds
        push!(times, get_frame_part_measurement_name(part, :time) => seconds)
    end
    append!(times, [
        :held_time => stages.held_seconds,
        :garbage_collection_time => (Base.gc_time_ns() - stages.started_collection_ns) / 1e9,
        :compile_time =>
            (first(Base.cumulative_compile_time_ns()) - stages.started_compile_ns) / 1e9])
    running_ns = Base.Experimental.task_running_time_ns(current_task())
    if running_ns !== nothing && stages.started_running_ns !== nothing
        running = (running_ns - stages.started_running_ns) / 1e9
        push!(times, :yielded_time => max(0.0, frame_seconds - running))
    end
    counts = Pair{Symbol, Float64}[:allocated_bytes => Float64(Base.gc_bytes() - stages.started_bytes)]
    if PERFORMANCE_COUNTERS_ENABLED
        counters = get_performance_counters()
        frame_counts = map(key -> get(counters.counts, key, 0), _CELL_COUNT_KEYS)
        for (part, cell_counts) in (part_counts..., :frame => frame_counts)
            for (measure, count) in zip(FRAME_PART_MEASURES[2:end], cell_counts)
                name = get_frame_part_measurement_name(part, measure)
                push!(counts, name => Float64(count))
            end
        end
        # Every other key, in name order, so a new counter reaches the store with no
        # change here. A key that the frame records already keeps the value of the
        # frame.
        for key in sort!(collect(keys(counters.times)))
            any(pair -> first(pair) === key, times) && continue
            push!(times, key => counters.times[key] / 1e9)
        end
        for key in sort!(collect(keys(counters.counts)))
            key in _CELL_COUNT_KEYS && continue
            any(pair -> first(pair) === key, counts) && continue
            push!(counts, key => Float64(counters.counts[key]))
        end
    end
    record_frame_measurements!(editor.frame_measurements; times, counts)
    nothing
end

# The time and the cell counts of each part of `FRAME_PARTS` but the whole frame,
# as `part => value` in the order of the parts. The reader is the read stage less
# the input, and the print is the print stage less the paint. A read or a print
# that ran outside its stage, as a playback runs them, leaves a part at zero and
# never below.
function _compute_frame_part_measures(stages::_FrameStages)
    seconds(part) = stages.part_seconds[_get_measured_part_index(part)]
    counts(part) = stages.part_counts[_get_measured_part_index(part)]
    less(whole, part) = (max(0.0, seconds(whole) - seconds(part)),
                         max.(0, counts(whole) .- counts(part)))
    reader = less(:read, :input)
    print = less(:print, :paint)
    part_seconds = (:feed => seconds(:feed), :report => seconds(:report),
                    :input => seconds(:input), :reader => first(reader),
                    :evaluate => seconds(:evaluate), :print => first(print),
                    :paint => seconds(:paint))
    part_counts = (:feed => counts(:feed), :report => counts(:report),
                   :input => counts(:input), :reader => last(reader),
                   :evaluate => counts(:evaluate), :print => last(print),
                   :paint => counts(:paint))
    (part_seconds, part_counts)
end

"""
    drain_feeds!(editor) -> Int

Drain every registered feed, in registration order, and answer how many
items moved in total. Runs once per frame on the editor task, before `run_read_stage!` —
so the frame paints what its feeds just wrote.

Each drain runs in its own `:evaluate` barrier. A drain that throws is recorded
with the type of its feed as the origin and counts as no item, and the next feed
still drains. The drains run with the editor as the editor of the evaluation, as
a frame does.
"""
function drain_feeds!(editor::Editor)
    run_with_evaluation_editor(editor) do
        count = 0
        for feed in editor.feeds
            count += _time_frame_stage(editor, :feed, typeof(feed)) do
                _run_barrier(editor, :evaluate; origin = typeof(feed), fallback = 0) do
                    drain_changes!(feed, editor)
                end
            end
        end
        count
    end
end

# ── A slow frame ──────────────────────────────────────────────────────

# A frame that takes longer than this, without the time of its held frames, is
# reported in the log with its slowest stage. The printer, the reader and the
# gestures are fast by design, so such a frame shows work that belongs elsewhere.
const SLOW_FRAME_SECONDS = 1.0

# Time `body` as the stage `stage` of the frame, with `work` for its report:
# measure it as a part, and keep it when it is the slowest stage so far.
function _time_frame_stage(body, editor::Editor, stage::Symbol, work)
    stages = editor.frame_stages
    index = _get_measured_part_index(stage)
    before = stages.part_seconds[index]
    try
        _measure_frame_part(body, editor, stage)
    finally
        seconds = stages.part_seconds[index] - before
        if seconds > stages.seconds
            stages.seconds = seconds
            stages.stage = stage
            stages.work = work
        end
    end
end

# Run `body` as the part `part` of `_MEASURED_FRAME_PARTS`, and answer its value:
# add its time and the cell counts that it added to the part. The time of the held
# frames of a code unit inside `body` does not count: the window answered
# meanwhile. The input and the paint are parts of a stage, so they are never the
# slowest stage of a slow frame.
function _measure_frame_part(body, editor::Editor, part::Symbol)
    stages = editor.frame_stages
    index = _get_measured_part_index(part)
    held = stages.held_seconds
    counts = _get_cell_counts()
    started = time_ns()
    try
        body()
    finally
        seconds = (time_ns() - started) / 1e9 - (stages.held_seconds - held)
        added = _get_cell_counts() .- counts
        stages.part_seconds =
            Base.setindex(stages.part_seconds, stages.part_seconds[index] + seconds, index)
        stages.part_counts =
            Base.setindex(stages.part_counts, stages.part_counts[index] .+ added, index)
    end
end

function _get_measured_part_index(part::Symbol)
    index = findfirst(==(part), _MEASURED_FRAME_PARTS)
    index === nothing &&
        throw(ArgumentError("the frame measures no part $(repr(part))"))
    index
end

# The cell counts of the counter scope now; zero while the counters are compiled out.
function _get_cell_counts()
    PERFORMANCE_COUNTERS_ENABLED || return map(_ -> 0, _CELL_COUNT_KEYS)
    counts = get_performance_counters().counts
    map(key -> get(counts, key, 0), _CELL_COUNT_KEYS)
end

# A new record of the stages for the frame that starts, with the counters of the
# process at its start.
_reset_frame_stages!(editor::Editor) = (editor.frame_stages = _FrameStages(); nothing)

# One line in the log for a frame that took longer than `SLOW_FRAME_SECONDS`
# without its held frames, naming its slowest stage and the work in it.
function _report_slow_frame!(editor::Editor, frame_seconds::Float64)
    # A precompile workload runs frames that compile as they go, so it reports none.
    Base.generating_output() && return nothing
    stages = editor.frame_stages
    seconds = frame_seconds - stages.held_seconds
    seconds > SLOW_FRAME_SECONDS || return nothing
    @warn string("[frame] a frame took ", round(seconds; digits = 2), " s, ",
                 round(stages.seconds; digits = 2), " s of it in ",
                 _describe_frame_stage(stages))
    nothing
end

function _describe_frame_stage(stages::_FrameStages)
    stages.stage === :feed && return string("the drain of ", nameof(stages.work))
    stages.stage === :read && return "the read of the input"
    stages.stage === :evaluate && return stages.work === nothing ? "an operation" :
        string("the operation ", describe_operation(stages.work))
    stages.stage === :print && return "the print and the paint"
    stages.stage === :report && return "the report of the faults"
    "the frame"
end
