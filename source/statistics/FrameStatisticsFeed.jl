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
while something shows one of its documents. The probe is `has_dependents` on
a cell that every view of the document reads: `frame_count` of the table, and
`names` of the plot. So a watched document refreshes at the flush interval, an
unwatched editor records for free and flushes nothing, and a view that closes
goes quiet once the collector sweeps its subscription.
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

_is_frame_statistics_watched(feed::FrameStatisticsFeed) =
    has_dependents(getfield(feed.statistics, :frame_count))

_is_frame_plot_watched(feed::FrameStatisticsFeed) =
    has_dependents(getfield(feed.plot, :names))

function drain_changes!(feed::FrameStatisticsFeed, editor)
    store = editor.frame_samples
    count_unflushed_frame_samples(store) > 0 || return 0
    statistics_watched = _is_frame_statistics_watched(feed)
    plot_watched = _is_frame_plot_watched(feed)
    statistics_watched || plot_watched || return 0
    written = 0
    statistics_watched && (written += flush_frame_statistics!(feed.statistics, store))
    plot_watched && (written += flush_frame_plot!(feed.plot, store))
    mark_frame_samples_flushed!(store)
    written
end

compute_wake_deadline(feed::FrameStatisticsFeed, editor) =
    count_unflushed_frame_samples(editor.frame_samples) > 0 &&
    (_is_frame_statistics_watched(feed) || _is_frame_plot_watched(feed)) ?
        feed.flush_interval : nothing
