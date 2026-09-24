# Fragment of `FrameStatisticsModule` — the frame statistics document types:
# `FrameMeasurement`, the summary row of one measurement, and
# `FrameStatistics`, the table of every measurement of one editor loop.

@document struct FrameMeasurement
    name::String
    count::Int
    minimum::Float64
    maximum::Float64
    mean::Float64
    standard_deviation::Float64
    total::Float64
end

"""
    FrameStatistics()

The table. One [`FrameMeasurement`](@ref) row for each measurement, in the
first-seen order of the editor's sample store. A row summarizes the recent
frames that the store keeps, and its `count` says how many. `frame_count` is
the number of frames since the editor started. Times are in seconds.
"""
@document struct FrameStatistics
    rows::CellVector = CellVector()
    frame_count::Int = 0
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

Runs on the editor task only, because it writes cells.
"""
function flush_frame_statistics!(statistics::FrameStatistics, store::FrameSampleStore)
    names = get_frame_measurement_names(store)
    rows = statistics.rows
    for (index, name) in enumerate(names)
        summary = compute_frame_measurement_summary(store, name)
        deviation = compute_frame_standard_deviation(summary)
        if index <= length(rows)
            row = rows[index]
            _write_changed_field!(row, :count, summary.count)
            _write_changed_field!(row, :minimum, summary.minimum)
            _write_changed_field!(row, :maximum, summary.maximum)
            _write_changed_field!(row, :mean, summary.mean)
            _write_changed_field!(row, :standard_deviation, deviation)
            _write_changed_field!(row, :total, summary.total)
        else
            push!(rows, FrameMeasurement(string(name), summary.count,
                                         summary.minimum, summary.maximum,
                                         summary.mean, deviation, summary.total))
        end
    end
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
