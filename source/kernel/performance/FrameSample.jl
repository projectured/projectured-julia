# Fragment of `PerformanceModule` — the measurements of the recent frames. The
# store keeps the last frames in a ring of fixed size, one column for each
# measurement name, and computes a summary from the ring when a reader asks. It
# is a plain object outside the reactive graph, and one frame costs one store
# for each measurement.

"""
    FrameMeasurementSummary()

The summary of one frame measurement: how many values it saw, their minimum,
maximum, mean and sum, and the running sum of squared deviations that
[`compute_frame_standard_deviation`](@ref) reads. The fold is Welford's method:
one pass, and no value is stored.
"""
mutable struct FrameMeasurementSummary
    count::Int
    minimum::Float64
    maximum::Float64
    mean::Float64
    squared_deviation_sum::Float64
    total::Float64
end

FrameMeasurementSummary() = FrameMeasurementSummary(0, Inf, -Inf, 0.0, 0.0, 0.0)

# Fold one value into the summary.
function _record_frame_measurement!(summary::FrameMeasurementSummary, value::Real)
    sample = Float64(value)
    summary.count += 1
    sample < summary.minimum && (summary.minimum = sample)
    sample > summary.maximum && (summary.maximum = sample)
    delta = sample - summary.mean
    summary.mean += delta / summary.count
    summary.squared_deviation_sum += delta * (sample - summary.mean)
    summary.total += sample
    summary
end

"""
    compute_frame_standard_deviation(summary) -> Float64

The sample standard deviation of every value the summary saw, and `0.0` below
two values.
"""
compute_frame_standard_deviation(summary::FrameMeasurementSummary) =
    summary.count < 2 ? 0.0 :
    sqrt(summary.squared_deviation_sum / (summary.count - 1))

"""
    is_frame_time_measurement(name) -> Bool

Whether the measurement `name` is a time. A name that ends in `_time` is a time
in seconds, and every other measurement is a count. A view that shows a
measurement reads its unit here.
"""
is_frame_time_measurement(name::Symbol) = endswith(String(name), "_time")

"""
    FrameSampleStore(; capacity = 1000)

The measurements of the last `capacity` frames.

The store keeps a ring of `capacity` slots: one column of values for each
measurement name, in first-seen order, and one column of frame end times. A
frame that did not measure a name holds `NaN` in the column of that name. The
store also counts the frames since the start, and the frames since the last
flush. A store belongs to one editor, and only the task of that editor writes
it, so it needs no lock.

# Example

    store = FrameSampleStore()
    record_frame_sample!(store, [:frame_time => 0.016])
    summary = compute_frame_measurement_summary(store, :frame_time)

See also [`collect_recent_frame_samples`](@ref) and
[`write_frame_samples!`](@ref).
"""
mutable struct FrameSampleStore
    capacity::Int
    names::Vector{Symbol}
    columns::Dict{Symbol, Vector{Float64}}
    end_times::Vector{Float64}
    frame_count::Int
    unflushed::Int
end

function FrameSampleStore(; capacity::Integer = 1000)
    capacity >= 1 || throw(ArgumentError("a frame sample store holds at least one frame"))
    FrameSampleStore(Int(capacity), Symbol[], Dict{Symbol, Vector{Float64}}(),
                     fill(NaN, capacity), 0, 0)
end

# The slot of the ring that holds the frame with the number `frame`.
_get_frame_slot(store::FrameSampleStore, frame::Integer) = mod1(frame, store.capacity)

# The numbers of the frames that the ring holds, oldest first.
_get_frame_window(store::FrameSampleStore) =
    max(1, store.frame_count - store.capacity + 1):store.frame_count

"""
    record_frame_sample!(store, measurements; end_time = time()) -> store

Record the measurements of one frame, an iterable of `name => value` pairs, in
the next slot of the ring, and count the frame as not flushed. `end_time` is
the time at which the frame ended, in seconds.
"""
function record_frame_sample!(store::FrameSampleStore, measurements;
                              end_time::Real = time())
    store.frame_count += 1
    slot = _get_frame_slot(store, store.frame_count)
    for name in store.names
        store.columns[name][slot] = NaN
    end
    for (name, value) in measurements
        column = get(store.columns, name, nothing)
        if column === nothing
            column = fill(NaN, store.capacity)
            store.columns[name] = column
            push!(store.names, name)
        end
        column[slot] = Float64(value)
    end
    store.end_times[slot] = Float64(end_time)
    store.unflushed += 1
    store
end

"""
    compute_frame_measurement_summary(store, name) -> FrameMeasurementSummary

The summary of the measurement `name` over the frames that the ring holds. A
frame that did not measure `name` does not count. A name that no frame measured
gives a summary with a count of zero.
"""
function compute_frame_measurement_summary(store::FrameSampleStore, name::Symbol)
    summary = FrameMeasurementSummary()
    column = get(store.columns, name, nothing)
    column === nothing && return summary
    for frame in _get_frame_window(store)
        value = column[_get_frame_slot(store, frame)]
        isnan(value) || _record_frame_measurement!(summary, value)
    end
    summary
end

"""
    get_frame_measurement_names(store) -> Vector{Symbol}

The measurement names in first-seen order. The answer is a copy, so a caller
can not change the store through it.
"""
get_frame_measurement_names(store::FrameSampleStore) = copy(store.names)

"""
    get_frame_count(store) -> Int

How many frames the store recorded since the start. The ring holds the last
`capacity` of them.
"""
get_frame_count(store::FrameSampleStore) = store.frame_count

"""
    collect_recent_frame_samples(store) -> (; frames, end_times, columns)

The frames that the ring holds, oldest first, as new vectors: the frame numbers,
the end times in seconds, and one `name => values` column for each measurement,
in first-seen order. A value is `NaN` where a frame did not measure the name.

Use it to look at single frames: to find a slow one, to write the frames to a
file, or to draw them.

# Example

    samples = collect_recent_frame_samples(editor.frame_samples)
    slowest = samples.frames[argmax(last(samples.columns[1]))]

See also [`write_frame_samples!`](@ref), which writes the same frames as CSV.
"""
function collect_recent_frame_samples(store::FrameSampleStore)
    frames = collect(_get_frame_window(store))
    slots = [_get_frame_slot(store, frame) for frame in frames]
    (frames = frames,
     end_times = store.end_times[slots],
     columns = [name => store.columns[name][slots] for name in store.names])
end

# One CSV field: nothing for `NaN`, an integer for a whole number, and the
# shortest text that reads back as the same number otherwise.
function _format_frame_sample_field(value::Float64)
    isnan(value) && return ""
    isinteger(value) && abs(value) < 1e15 && return string(Int(value))
    string(value)
end

"""
    write_frame_samples!(io, store) -> Int
    write_frame_samples!(path, store) -> Int

Write the frames that the ring holds as CSV, and answer how many frames it
wrote.

The columns are `frame`, the frame number since the start; `end_time_s`, the
seconds from the end of the first frame written; and one column for each
measurement. A time is in milliseconds and its column name ends in `_ms`. A
field is empty where a frame did not measure the name.

Use it to keep the frames of a session, or to plot them in another program.

# Example

    write_frame_samples!("frames.csv", editor.frame_samples)

See also [`collect_recent_frame_samples`](@ref), which gives the same frames as
vectors.
"""
function write_frame_samples!(io::IO, store::FrameSampleStore)
    samples = collect_recent_frame_samples(store)
    headers = ["frame", "end_time_s"]
    for (name, _) in samples.columns
        push!(headers, is_frame_time_measurement(name) ? "$(name)_ms" : String(name))
    end
    println(io, join(headers, ","))
    start = isempty(samples.end_times) ? 0.0 : first(samples.end_times)
    for (index, frame) in enumerate(samples.frames)
        fields = [string(frame),
                  _format_frame_sample_field(samples.end_times[index] - start)]
        for (name, values) in samples.columns
            scale = is_frame_time_measurement(name) ? 1000.0 : 1.0
            push!(fields, _format_frame_sample_field(values[index] * scale))
        end
        println(io, join(fields, ","))
    end
    length(samples.frames)
end

write_frame_samples!(path::AbstractString, store::FrameSampleStore) =
    open(io -> write_frame_samples!(io, store), path, "w")

"""
    count_unflushed_frame_samples(store) -> Int

How many frames were recorded since [`mark_frame_samples_flushed!`](@ref).
"""
count_unflushed_frame_samples(store::FrameSampleStore) = store.unflushed

"""
    mark_frame_samples_flushed!(store) -> store

Say that a flush showed everything recorded so far. The ring keeps its frames,
and only the count of frames that are not flushed resets.
"""
mark_frame_samples_flushed!(store::FrameSampleStore) = (store.unflushed = 0; store)
