# Fragment of `FrameStatisticsModule` — the frame statistics document types:
# `FrameStatisticsRow`, the summary row of one measurement, `FrameStatistics`,
# the table of every measurement of one editor loop, and `FrameTimeSeries`, the
# frame times of the recent frames.

@document struct FrameStatisticsRow
    name::String
    unit::Symbol
    count::Int
    minimum::Float64
    maximum::Float64
    mean::Float64
    standard_deviation::Float64
    total::Float64
end

"""
    FrameStatistics()

The table. One [`FrameStatisticsRow`](@ref) row for each measurement, in the
first-seen order of the editor's measurement store. A row summarizes the recent
frames that the store keeps, and its `count` says how many. Its `unit` is
`:second` for a time, which the row holds in seconds, or `:count`.
`frame_count` is the number of frames since the editor started, as the table
last showed them.

`frames` holds the numbers of the recent frames, oldest first, and `columns`
the value of each of these frames: one column for each row, in the order of the
rows and in the unit of the row. A value is `NaN` where a frame did not measure
the name.

`paused` stops the flush, so the numbers stay while a person reads them. The
other three fields are the view state of the table of the frames: `anchor` is
the place of the row at the head of its list, counted from the newest frame,
`top_row` is the row at the top of the table, counted from that head, and
`scroll_position` is the offset of the table. The table shares the cells of
`top_row` and `scroll_position`.
"""
@document struct FrameStatistics
    rows::CellVector = CellVector()
    frame_count::Int = 0
    frames::Vector{Int} = Int[]
    columns::Vector{Vector{Float64}} = Vector{Float64}[]
    paused::Bool = false
    anchor::Int = 1
    top_row::Int = 1
    scroll_position::Point2D = Point2D(0, 0)
end

# The name the tab calls itself, and the name a person types into an empty
# tab to open one.
get_document_title(::FrameStatistics) = "Statistics"
get_insertion_aliases(::Type{FrameStatistics}) = ["statistics"]

# Last session's numbers are not this one's: a load starts an empty table.
pred_arguments(::FrameStatistics) = (), Pair{Symbol, Any}[]

"""
    flush_frame_statistics!(statistics, store) -> Int

Write the summary of the recent frames of `store` into the document, for each
measurement, and answer how many rows it covers. A row whose measurement the
table already shows gets only the fields whose numbers changed, so the other
cells keep their readers valid. A measurement the table has not seen appends a
row. Row order is the store's first-seen order, and the store only appends
names, so the index alignment holds.

The flush also writes the recent frames into `frames` and `columns`. These
change with each new frame, so they are written whole.

Runs on the editor task only, because it writes cells.
"""
function flush_frame_statistics!(statistics::FrameStatistics,
                                 store::FrameMeasurementStore)
    names = get_frame_measurement_names(store)
    rows = statistics.rows
    for (index, name) in enumerate(names)
        summary = compute_frame_measurement_summary(store, name)
        if index <= length(rows)
            row = rows[index]
            _write_changed_field!(row, :count, summary.count)
            _write_changed_field!(row, :minimum, summary.minimum)
            _write_changed_field!(row, :maximum, summary.maximum)
            _write_changed_field!(row, :mean, summary.mean)
            _write_changed_field!(row, :standard_deviation, summary.standard_deviation)
            _write_changed_field!(row, :total, summary.total)
        else
            push!(rows, FrameStatisticsRow(string(name), summary.unit, summary.count,
                                           summary.minimum, summary.maximum,
                                           summary.mean, summary.standard_deviation,
                                           summary.total))
        end
    end
    recent = collect_recent_frame_measurements(store)
    statistics.frames = recent.frames
    statistics.columns = [column.values for column in recent.columns]
    _write_changed_field!(statistics, :frame_count, get_frame_count(store))
    length(names)
end

# A write invalidates the readers of a cell even when the value is the same, so
# a field is written only when its number changed.
_write_changed_field!(document, field::Symbol, value) =
    isequal(getproperty(document, field), value) ||
        setproperty!(document, field, value)

# ── The session's statistics ─────────────────────────────────────────────────

# One table for the session, the same way the session has one message log:
# one program runs one editor a person watches.
const _SESSION_FRAME_STATISTICS = FrameStatistics()

"""
    get_session_frame_statistics() -> FrameStatistics

The one statistics table of the session. Every statistics view a person
opens is this document, so two of them show the same numbers.
"""
get_session_frame_statistics() = _SESSION_FRAME_STATISTICS

# A person who types `statistics` into an empty tab gets the session's
# table: a fresh one would never fill, because the feed flushes into the
# table it was registered with.
make_insertion_document(::Type{FrameStatistics}) = get_session_frame_statistics()

# ── The frame time series ────────────────────────────────────────────────────

"""
    FrameTimeSeries()

The frame times of the recent frames, as columns. `frames` holds the frame
numbers, and `names` and `columns` hold one column in seconds for each time
measurement of the editor's measurement store. A value is `NaN` where a frame did
not measure the name.

A column is one cell, not one cell for each frame: nothing selects a single
frame, and a view draws a whole column at once.
"""
@document struct FrameTimeSeries
    names::Vector{String} = String[]
    frames::Vector{Float64} = Float64[]
    columns::Vector{Vector{Float64}} = Vector{Float64}[]
end

get_document_title(::FrameTimeSeries) = "Frame times"
get_insertion_aliases(::Type{FrameTimeSeries}) = ["frame times"]

# Last session's frames are not this one's: a load starts an empty plot.
pred_arguments(::FrameTimeSeries) = (), Pair{Symbol, Any}[]

"""
    flush_frame_time_series!(series, store) -> Int

Write the recent frames of `store` into `series`, one column for each time
measurement, and answer how many columns it holds. The names are written only
when they changed, so a flush gives a view new columns and keeps its series.

Runs on the editor task only, because it writes cells.
"""
function flush_frame_time_series!(plot::FrameTimeSeries, store::FrameMeasurementStore)
    recent = collect_recent_frame_measurements(store)
    names = String[]
    columns = Vector{Float64}[]
    for column in recent.columns
        column.unit === :second || continue
        push!(names, String(column.name))
        push!(columns, column.values)
    end
    _write_changed_field!(plot, :names, names)
    plot.frames = Float64.(recent.frames)
    plot.columns = columns
    length(names)
end

# The number of the last frame that the plot shows, and 0 before its first
# flush. The frame numbers are the plot's own record of what it showed.
function _get_frame_time_series_count(plot::FrameTimeSeries)
    frames = plot.frames
    isempty(frames) ? 0 : Int(last(frames))
end

# One plot for the session, for the same reason as the one table above.
const _SESSION_FRAME_TIME_SERIES = FrameTimeSeries()

"""
    get_session_frame_time_series() -> FrameTimeSeries

The one frame time series of the session. Every view of it that a person opens
is this document, so two of them show the same frames.
"""
get_session_frame_time_series() = _SESSION_FRAME_TIME_SERIES

# A person who types `frame times` into an empty tab gets the session's series,
# for the same reason as the table.
make_insertion_document(::Type{FrameTimeSeries}) = get_session_frame_time_series()
