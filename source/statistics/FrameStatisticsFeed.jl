# Fragment of `FrameStatisticsModule` — the feed. The kernel folds one
# sample per frame into `editor.frame_samples` for free; this feed flushes
# the summaries into the document, at a bounded rate, and only while a view
# shows them.

"""
    FrameStatisticsFeed(; statistics = get_session_frame_statistics(),
                          flush_interval = 0.25)

Register it when the editor is created —
`Editor(...; feeds = Feed[FrameStatisticsFeed()])` — and a statistics tab
shows the loop's numbers live.

The feed never wakes the editor: its data arrives only with frames, so a
wake would make frames feed themselves. It answers a deadline instead, and
only while something shows the document — the probe is `has_dependents` on
the document's `frame_count` cell, which every view reads. So a watched
table refreshes at the flush interval, an unwatched editor folds for free
and flushes nothing, and a view that closes goes quiet once the collector
sweeps its subscription.
"""
struct FrameStatisticsFeed <: Feed
    statistics::FrameStatistics
    flush_interval::Float64
end

FrameStatisticsFeed(; statistics::FrameStatistics = get_session_frame_statistics(),
                      flush_interval::Real = 0.25) =
    FrameStatisticsFeed(statistics, Float64(flush_interval))

_is_frame_statistics_watched(feed::FrameStatisticsFeed) =
    has_dependents(getfield(feed.statistics, :frame_count))

function drain_changes!(feed::FrameStatisticsFeed, editor)
    store = editor.frame_samples
    count_unflushed_frame_samples(store) > 0 || return 0
    _is_frame_statistics_watched(feed) || return 0
    written = flush_frame_statistics!(feed.statistics, store)
    mark_frame_samples_flushed!(store)
    written
end

compute_wake_deadline(feed::FrameStatisticsFeed, editor) =
    count_unflushed_frame_samples(editor.frame_samples) > 0 &&
    _is_frame_statistics_watched(feed) ? feed.flush_interval : nothing
