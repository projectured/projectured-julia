# Fragment of `PerformanceModule` — the measurements of each frame, folded into
# one running summary for each measurement name. The store is a plain object
# outside the reactive graph, and one frame costs a few arithmetic operations
# for each measurement.

"""
    FrameMeasurementSummary()

The running summary of one frame measurement: how many values it saw, their
minimum, maximum, mean and sum, and the running sum of squared deviations that
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
    FrameSampleStore()

One summary for each measurement name, in first-seen order, and the number of
frames recorded since the last flush. A store belongs to one editor, and only
the task of that editor writes it, so it needs no lock.
"""
mutable struct FrameSampleStore
    summaries::Dict{Symbol, FrameMeasurementSummary}
    names::Vector{Symbol}
    unflushed::Int
end

FrameSampleStore() =
    FrameSampleStore(Dict{Symbol, FrameMeasurementSummary}(), Symbol[], 0)

"""
    record_frame_sample!(store, measurements) -> store

Fold the measurements of one frame, an iterable of `name => value` pairs, and
count the frame as not flushed.
"""
function record_frame_sample!(store::FrameSampleStore, measurements)
    for (name, value) in measurements
        summary = get(store.summaries, name, nothing)
        if summary === nothing
            summary = FrameMeasurementSummary()
            store.summaries[name] = summary
            push!(store.names, name)
        end
        _record_frame_measurement!(summary, value)
    end
    store.unflushed += 1
    store
end

"""
    find_frame_measurement_summary(store, name) -> FrameMeasurementSummary or nothing

The summary of the measurement `name`, or `nothing` when no frame measured it.
"""
find_frame_measurement_summary(store::FrameSampleStore, name::Symbol) =
    get(store.summaries, name, nothing)

"""
    get_frame_measurement_names(store) -> Vector{Symbol}

The measurement names in first-seen order. The answer is a copy, so a caller
can not change the store through it.
"""
get_frame_measurement_names(store::FrameSampleStore) = copy(store.names)

"""
    count_unflushed_frame_samples(store) -> Int

How many frames were recorded since [`mark_frame_samples_flushed!`](@ref).
"""
count_unflushed_frame_samples(store::FrameSampleStore) = store.unflushed

"""
    mark_frame_samples_flushed!(store) -> store

Say that a flush showed everything recorded so far. The summaries keep their
values, and only the count of frames that are not flushed resets.
"""
mark_frame_samples_flushed!(store::FrameSampleStore) = (store.unflushed = 0; store)
