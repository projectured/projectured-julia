# Fragment of `FrameStatisticsModule` — the feed. The kernel records the
# measurements of each frame in `editor.frame_samples` for free; this feed
# flushes them into the table and the plot, at a bounded rate, and only while a
# view shows one of them.

"""
    FrameStatisticsFeed(; statistics = get_session_frame_statistics(),
                          plot = get_session_frame_plot(),
                          flush_interval = 0.25)

Register it when the editor is created —
`Editor(...; feeds = Feed[FrameStatisticsFeed()])` — and a statistics tab and a
frame plot tab show the loop's numbers live.

The feed never wakes the editor: its data arrives only with frames, so a wake
would make frames feed themselves. It answers a deadline instead, and only
while a document is due. A document is due when the frame count that it last
showed differs from the count of the store, and something shows the document.
Each document keeps its own count, so the table and the plot flush apart, and a
store that starts again at zero still refreshes a session document. The probe for a view is `has_dependents` on a cell that every
view of the document reads: `frame_count` of the table, and `names` of the
plot. So a watched document refreshes at the flush interval, an unwatched
editor records for free and flushes nothing, and a view that closes goes quiet
once the collector sweeps its subscription.
"""
struct FrameStatisticsFeed <: Feed
    statistics::FrameStatistics
    plot::FramePlot
    flush_interval::Float64
end

FrameStatisticsFeed(; statistics::FrameStatistics = get_session_frame_statistics(),
                      plot::FramePlot = get_session_frame_plot(),
                      flush_interval::Real = 0.25) =
    FrameStatisticsFeed(statistics, plot, Float64(flush_interval))

_is_frame_statistics_due(feed::FrameStatisticsFeed, store::FrameSampleStore) =
    feed.statistics.frame_count != get_frame_count(store) &&
    has_dependents(getfield(feed.statistics, :frame_count))

_is_frame_plot_due(feed::FrameStatisticsFeed, store::FrameSampleStore) =
    _get_frame_plot_count(feed.plot) != get_frame_count(store) &&
    has_dependents(getfield(feed.plot, :names))

function drain_changes!(feed::FrameStatisticsFeed, editor)
    store = editor.frame_samples
    written = 0
    _is_frame_statistics_due(feed, store) &&
        (written += flush_frame_statistics!(feed.statistics, store))
    _is_frame_plot_due(feed, store) && (written += flush_frame_plot!(feed.plot, store))
    written
end

compute_wake_deadline(feed::FrameStatisticsFeed, editor) =
    _is_frame_statistics_due(feed, editor.frame_samples) ||
    _is_frame_plot_due(feed, editor.frame_samples) ? feed.flush_interval : nothing
