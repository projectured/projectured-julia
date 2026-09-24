# Fragment of `PerformanceModule` — the measurements of the recent frames. The
# store keeps the last frames in a ring of fixed size, one column and one unit
# for each measurement name, and computes a summary from the ring when a reader
# asks. It is a plain object outside the reactive graph, and one frame costs
# one lookup and one store for each measurement.

"""
    FrameMeasurementSummary

The summary of one measurement over the frames that a store holds: its `unit`,
`:second` or `:count`; the `count` of frames that measured it; and the
`minimum`, `maximum`, `mean`, `standard_deviation` and `total` of their values.
With no value, the minimum, the maximum and the mean are `NaN`. Below two
values, the standard deviation is `0.0`.

See also [`compute_frame_measurement_summary`](@ref), which makes one.
"""
struct FrameMeasurementSummary
    unit::Symbol
    count::Int
    minimum::Float64
    maximum::Float64
    mean::Float64
    standard_deviation::Float64
    total::Float64
end

"""
    FrameMeasurementStore(; capacity = 1000)

The measurements of the last `capacity` frames.

The store keeps a ring of `capacity` slots: one column of values for each
measurement name, in first-seen order, and one column of frame end times. A
frame that did not measure a name holds `NaN` in the column of that name. Each
name has a unit, `:second` for a time and `:count` for a count, from the group
that first gave it. The store also counts the frames since the start. A store
belongs to one editor, and only the task of that editor writes it, so it needs
no lock.

# Example

    store = FrameMeasurementStore()
    record_frame_measurements!(store; times = [:frame_time => 0.016])
    summary = compute_frame_measurement_summary(store, :frame_time)

See also [`collect_recent_frame_measurements`](@ref) and
[`write_frame_measurements!`](@ref).
"""
mutable struct FrameMeasurementStore
    capacity::Int
    names::Vector{Symbol}
    units::Dict{Symbol, Symbol}
    columns::Dict{Symbol, Vector{Float64}}
    end_times::Vector{Float64}
    frame_count::Int
end

function FrameMeasurementStore(; capacity::Integer = 1000)
    capacity >= 1 ||
        throw(ArgumentError("a frame measurement store holds at least one frame"))
    FrameMeasurementStore(Int(capacity), Symbol[], Dict{Symbol, Symbol}(),
                     Dict{Symbol, Vector{Float64}}(), fill(NaN, capacity), 0)
end

# The slot of the ring that holds the frame with the number `frame`.
_get_frame_slot(store::FrameMeasurementStore, frame::Integer) =
    mod1(frame, store.capacity)

# The numbers of the frames that the ring holds, oldest first.
_get_frame_window(store::FrameMeasurementStore) =
    max(1, store.frame_count - store.capacity + 1):store.frame_count

"""
    record_frame_measurements!(store; times = (), counts = (), end_time = time()) -> store

Record the measurements of one frame in the next slot of the ring. `times` and
`counts` are iterables of `name => value` pairs: a time is in seconds, and a
count is a number of things. `end_time` is the time at which the frame ended,
in seconds.

A name keeps the unit of the group that first gave it. A name given later in
the other group is an error, because its column would mix two units.
"""
function record_frame_measurements!(store::FrameMeasurementStore; times = (), counts = (),
                              end_time::Real = time())
    _check_frame_units(store, times, :second)
    _check_frame_units(store, counts, :count)
    store.frame_count += 1
    slot = _get_frame_slot(store, store.frame_count)
    for name in store.names
        store.columns[name][slot] = NaN
    end
    _record_frame_values!(store, slot, times, :second)
    _record_frame_values!(store, slot, counts, :count)
    store.end_times[slot] = Float64(end_time)
    store
end

# A name keeps its unit. The check runs before the frame changes the store, so a
# wrong call leaves the store as it was.
function _check_frame_units(store::FrameMeasurementStore, measurements, unit::Symbol)
    for (name, _) in measurements
        known = get(store.units, name, unit)
        known === unit ||
            throw(ArgumentError("the frame measurement $(name) has the unit $(known), " *
                                "not $(unit)"))
    end
end

function _record_frame_values!(store::FrameMeasurementStore, slot::Int, measurements,
                               unit::Symbol)
    for (name, value) in measurements
        column = get(store.columns, name, nothing)
        if column === nothing
            column = fill(NaN, store.capacity)
            store.columns[name] = column
            store.units[name] = unit
            push!(store.names, name)
        elseif store.units[name] !== unit
            # One call gave the name in both groups.
            throw(ArgumentError("the frame measurement $(name) is in both groups"))
        end
        column[slot] = Float64(value)
    end
end

"""
    compute_frame_measurement_summary(store, name) -> FrameMeasurementSummary

The summary of the measurement `name` over the frames that the ring holds. A
frame that did not measure `name` does not count. The store must know `name`.
"""
function compute_frame_measurement_summary(store::FrameMeasurementStore, name::Symbol)
    column = store.columns[name]
    unit = store.units[name]
    count = 0
    smallest = Inf
    largest = -Inf
    mean = 0.0
    squared_deviation_sum = 0.0
    total = 0.0
    # Welford's method: one pass, and no value is stored.
    for frame in _get_frame_window(store)
        value = column[_get_frame_slot(store, frame)]
        isnan(value) && continue
        count += 1
        smallest = min(smallest, value)
        largest = max(largest, value)
        delta = value - mean
        mean += delta / count
        squared_deviation_sum += delta * (value - mean)
        total += value
    end
    count == 0 && return FrameMeasurementSummary(unit, 0, NaN, NaN, NaN, 0.0, 0.0)
    deviation = count < 2 ? 0.0 : sqrt(squared_deviation_sum / (count - 1))
    FrameMeasurementSummary(unit, count, smallest, largest, mean, deviation, total)
end

"""
    get_frame_measurement_names(store) -> Vector{Symbol}

The measurement names in first-seen order. The answer is a copy, so a caller
can not change the store through it.
"""
get_frame_measurement_names(store::FrameMeasurementStore) = copy(store.names)

"""
    get_frame_count(store) -> Int

How many frames the store recorded since the start. The ring holds the last
`capacity` of them. A reader that shows the frames can keep the count that it
last showed, and show them again when this count is larger.
"""
get_frame_count(store::FrameMeasurementStore) = store.frame_count

"""
    collect_recent_frame_measurements(store) -> (; frames, end_times, columns)

The frames that the ring holds, oldest first, as new vectors: the frame numbers,
the end times in seconds, and one `(; name, unit, values)` column for each
measurement, in first-seen order. A value is `NaN` where a frame did not
measure the name.

Use it to look at single frames: to find a slow one, to write the frames to a
file, or to draw them.

# Example

    recent = collect_recent_frame_measurements(editor.frame_measurements)
    slowest = recent.frames[argmax(recent.columns[1].values)]

See also [`write_frame_measurements!`](@ref), which writes the same frames as CSV.
"""
function collect_recent_frame_measurements(store::FrameMeasurementStore)
    frames = collect(_get_frame_window(store))
    slots = [_get_frame_slot(store, frame) for frame in frames]
    (frames = frames,
     end_times = store.end_times[slots],
     columns = [(name = name, unit = store.units[name],
                 values = store.columns[name][slots]) for name in store.names])
end

# One CSV field: nothing for `NaN`, and otherwise the number rounded to `digits`
# decimals, written as an integer when it is a whole number.
function _format_frame_measurement_field(value::Float64; digits::Integer)
    isnan(value) && return ""
    rounded = round(value; digits)
    isinteger(rounded) && abs(rounded) < 1e15 && return string(Int(rounded))
    string(rounded)
end

"""
    write_frame_measurements!(io, store) -> Int
    write_frame_measurements!(path, store) -> Int

Write the frames that the ring holds as CSV, and answer how many frames it
wrote.

The columns are `frame`, the frame number since the start; `end_time_s`, the
seconds from the end of the first frame written; and one column for each
measurement. A time is in milliseconds and its column name ends in `_ms`. Every
time is rounded to a microsecond. A field is empty where a frame did not
measure the name.

Use it to keep the frames of a session, or to plot them in another program.

# Example

    write_frame_measurements!("frames.csv", editor.frame_measurements)

See also [`collect_recent_frame_measurements`](@ref), which gives the same frames as
vectors.
"""
function write_frame_measurements!(io::IO, store::FrameMeasurementStore)
    recent = collect_recent_frame_measurements(store)
    headers = ["frame", "end_time_s"]
    for column in recent.columns
        name = String(column.name)
        push!(headers, column.unit === :second ? "$(name)_ms" : name)
    end
    println(io, join(headers, ","))
    start = isempty(recent.end_times) ? 0.0 : first(recent.end_times)
    for (index, frame) in enumerate(recent.frames)
        seconds = recent.end_times[index] - start
        fields = [string(frame), _format_frame_measurement_field(seconds; digits = 6)]
        for column in recent.columns
            value = column.values[index]
            push!(fields, column.unit === :second ?
                          _format_frame_measurement_field(1000 * value; digits = 3) :
                          _format_frame_measurement_field(value; digits = 6))
        end
        println(io, join(fields, ","))
    end
    length(recent.frames)
end

write_frame_measurements!(path::AbstractString, store::FrameMeasurementStore) =
    open(io -> write_frame_measurements!(io, store), path, "w")
