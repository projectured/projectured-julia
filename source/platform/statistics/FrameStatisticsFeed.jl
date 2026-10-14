# Fragment of `FrameStatisticsModule` — the feed. The kernel records the
# measurements of each frame in `editor.frame_measurements` for free; this feed
# flushes them into the table and the plot, at a bounded rate, and only while a
# view shows one of them.

"""
    FrameStatisticsFeed(; statistics = nothing, plot = nothing,
                          flush_interval = 0.25, now = time)

Register it when the editor is created —
`Editor(...; feeds = Feed[FrameStatisticsFeed()])` — and a statistics tab and a
frame times tab show the loop's numbers live. With no `statistics` or `plot`, the
feed flushes into the table and the plot of the session of its editor
([`get_session_frame_statistics`](@ref)), so each editor shows its own frames.

The feed never wakes the editor: its data arrives only with frames, so a wake
would make frames feed themselves. It answers a deadline instead, and only
while a document is due. A document is due when the frame count that it last
showed differs from the count of the store, and something shows the document.
Each document keeps its own count, so the table and the plot flush apart, and a
store that starts again at zero still refreshes a session document. The probe
for a view is `has_dependent_cells` on a cell that every view of the document reads:
`frame_count` of the table, and `names` of the plot. So a watched document
refreshes at the flush interval, an unwatched editor records for free and
flushes nothing, and a view that closes goes quiet once the collector sweeps its
subscription. A table whose `paused` is true is never due, so its numbers stay
while a person reads them, and the plot goes on.

Each document flushes at most once per `flush_interval`, by the clock `now`. A
flush changes what the display shows, and the display event of that frame makes
one more frame; that frame finds the document flushed less than an interval ago
and leaves it, so the loop sleeps again.
"""
mutable struct FrameStatisticsFeed <: Feed
    statistics::Union{Nothing,FrameStatistics}
    plot::Union{Nothing,FrameTimeSeries}
    flush_interval::Float64
    # The clock of the interval, and when each document flushed last.
    now::Function
    statistics_flushed_at::Float64
    plot_flushed_at::Float64
end

FrameStatisticsFeed(; statistics::Union{Nothing,FrameStatistics} = nothing,
                      plot::Union{Nothing,FrameTimeSeries} = nothing,
                      flush_interval::Real = 0.25, now::Function = time) =
    FrameStatisticsFeed(statistics, plot, Float64(flush_interval), now, -Inf, -Inf)

# The table and the plot of the feed: the ones that it was given, or else those of
# the session of `editor`.
_get_feed_statistics(feed::FrameStatisticsFeed, editor) =
    something(feed.statistics, get_session_frame_statistics(; editor))
_get_feed_plot(feed::FrameStatisticsFeed, editor) =
    something(feed.plot, get_session_frame_time_series(; editor))

_is_frame_statistics_due(statistics::FrameStatistics, store::FrameMeasurementStore) =
    !statistics.paused &&
    statistics.frame_count != get_frame_count(store) &&
    has_dependent_cells(getfield(statistics, :frame_count))

_is_frame_time_series_due(plot::FrameTimeSeries, store::FrameMeasurementStore) =
    _get_frame_time_series_count(plot) != get_frame_count(store) &&
    has_dependent_cells(getfield(plot, :names))

# A document that flushed less than an interval ago waits. A flush changes what
# the display shows, so a display event makes one more frame; that frame must not
# flush again, or the frames would feed themselves.
_is_flush_allowed(feed::FrameStatisticsFeed, flushed_at::Float64) =
    feed.now() - flushed_at >= feed.flush_interval

function drain_changes!(feed::FrameStatisticsFeed, editor)
    store = editor.frame_measurements
    statistics = _get_feed_statistics(feed, editor)
    plot = _get_feed_plot(feed, editor)
    written = 0
    if _is_frame_statistics_due(statistics, store) &&
       _is_flush_allowed(feed, feed.statistics_flushed_at)
        feed.statistics_flushed_at = feed.now()
        written += flush_frame_statistics!(statistics, store)
    end
    if _is_frame_time_series_due(plot, store) && _is_flush_allowed(feed, feed.plot_flushed_at)
        feed.plot_flushed_at = feed.now()
        written += flush_frame_time_series!(plot, store)
    end
    written
end

compute_wake_deadline(feed::FrameStatisticsFeed, editor) =
    _is_frame_statistics_due(_get_feed_statistics(feed, editor), editor.frame_measurements) ||
    _is_frame_time_series_due(_get_feed_plot(feed, editor), editor.frame_measurements) ?
        feed.flush_interval : nothing

"""
    frame_statistics = true

The wrapper of `build_editor` that gives the editor a
[`FrameStatisticsFeed`](@ref), so the statistics and the frame times of the
session follow the frames of the window. It is off by default.
"""
function wrap_editor!(::Val{:frame_statistics}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.feeds, FrameStatisticsFeed())
    parts
end

get_wrapper_layers(::Val{:frame_statistics}) = (:screen => 20,)
