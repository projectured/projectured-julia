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

The table. One [`FrameMeasurement`](@ref) row per measurement, in the
first-seen order of the editor's sample store, and the number of frames the
summaries cover. Times are in seconds, over every frame since the editor
started.
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

Write every summary of `store` into the document and answer how many rows it
covers. A row whose measurement the table already shows is updated field by
field, so only the cells whose numbers changed invalidate; a measurement the
table has not seen appends a row. Row order is the store's first-seen order,
and the store only appends names, so the index alignment holds.

Runs on the editor task only — it writes cells.
"""
function flush_frame_statistics!(statistics::FrameStatistics, store::FrameSampleStore)
    names = get_measurement_names(store)
    rows = statistics.rows
    for (index, name) in enumerate(names)
        summary = find_measurement_summary(store, name)
        summary === nothing && continue
        deviation = compute_standard_deviation(summary)
        if index <= length(rows)
            row = rows[index]
            row.count = summary.count
            row.minimum = summary.minimum
            row.maximum = summary.maximum
            row.mean = summary.mean
            row.standard_deviation = deviation
            row.total = summary.total
        else
            push!(rows, FrameMeasurement(string(name), summary.count,
                                         summary.minimum, summary.maximum,
                                         summary.mean, deviation, summary.total))
        end
    end
    frame_time = find_measurement_summary(store, :frame_time)
    frame_time === nothing || (statistics.frame_count = frame_time.count)
    length(names)
end

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
