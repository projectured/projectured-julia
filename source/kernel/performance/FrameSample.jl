# Fragment of `PerformanceModule` — what the editor loop measures about its own frames.
#
# What the editor loop measures about its own frames, folded so a statistics
# view can show it. `FrameSampleStore` is a plain object outside the reactive
# graph: the loop folds one sample per frame into it for the cost of a few
# arithmetic operations per measurement, and a statistics feed flushes the
# summaries into a document on its own deadline. Nothing here is a cell, and
# nothing here names a document — the store is the producer side of that feed,
# and the producer is the editor loop itself.

"""
    MeasurementSummary()

The running summary of one measurement: how many values it saw, their
minimum, maximum, mean, sum, and the running sum of squared deviations that
[`compute_standard_deviation`](@ref) reads (Welford's method, so one pass and
no stored samples).
"""
mutable struct MeasurementSummary
    count::Int
    minimum::Float64
    maximum::Float64
    mean::Float64
    squared_deviation_sum::Float64
    total::Float64
end

MeasurementSummary() = MeasurementSummary(0, Inf, -Inf, 0.0, 0.0, 0.0)

"""
    record_measurement!(summary, value) -> summary

Fold one value into the summary.
"""
function record_measurement!(summary::MeasurementSummary, value::Real)
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
    compute_standard_deviation(summary) -> Float64

The sample standard deviation of everything the summary saw, and `0.0` below
two values.
"""
compute_standard_deviation(summary::MeasurementSummary) =
    summary.count < 2 ? 0.0 :
    sqrt(summary.squared_deviation_sum / (summary.count - 1))

"""
    FrameSampleStore()

One summary per measurement name, in first-seen order, plus the number of
frames folded since the last flush. One per editor, written only by that
editor's loop, so no lock is needed.
"""
mutable struct FrameSampleStore
    summaries::Dict{Symbol, MeasurementSummary}
    names::Vector{Symbol}
    unflushed::Int
end

FrameSampleStore() = FrameSampleStore(Dict{Symbol, MeasurementSummary}(), Symbol[], 0)

"""
    record_frame_sample!(store, measurements) -> store

Fold one frame's measurements — an iterable of `name => value` pairs — and
count the frame as unflushed.
"""
function record_frame_sample!(store::FrameSampleStore, measurements)
    for (name, value) in measurements
        summary = get(store.summaries, name, nothing)
        if summary === nothing
            summary = MeasurementSummary()
            store.summaries[name] = summary
            push!(store.names, name)
        end
        record_measurement!(summary, value)
    end
    store.unflushed += 1
    store
end

"""
    find_measurement_summary(store, name) -> MeasurementSummary or nothing
"""
find_measurement_summary(store::FrameSampleStore, name::Symbol) =
    get(store.summaries, name, nothing)

"""
    get_measurement_names(store) -> Vector{Symbol}

The measurement names in first-seen order, for a stable display.
"""
get_measurement_names(store::FrameSampleStore) = store.names

"""
    count_unflushed_samples(store) -> Int

How many frames were folded since [`mark_samples_flushed!`](@ref).
"""
count_unflushed_samples(store::FrameSampleStore) = store.unflushed

"""
    mark_samples_flushed!(store) -> store

Say that a flush showed everything folded so far. The summaries keep
accumulating; only the unflushed count resets.
"""
mark_samples_flushed!(store::FrameSampleStore) = (store.unflushed = 0; store)
