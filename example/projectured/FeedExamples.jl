# The feed demonstrations — one runnable example per feed, so a person can
# watch data flow into a shown document from outside the frame:
#
#     run_message_log_feed_example()      # lines arrive from another task, once a second
#     run_frame_statistics_feed_example() # the loop's own numbers, live while watched
#
# The inbox feed needs no example of its own: every driver that calls
# `post_operation!` — the omnet watch, the runners of the fault examples —
# demonstrates it. The fault store's wake shows in `fault_print_example`.

"""
    make_message_log_feed_projection_example(; measure = FontFileMeasure())

The `MessageLog` panel pipeline: the log as syntax, then text, then graphics.
"""
make_message_log_feed_projection_example(; measure = FontFileMeasure()) =
    ChainingProjection(
        MessageLogToSyntax(),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure),
    )

"""
    run_message_log_feed_example(; backend = nothing)

Watch the message log feed work: a producer task records one line per second
into a `MessageLogStore` — the thread-safe producer side, never the document —
and the registered `MessageLogFeed` moves the lines into the shown
`MessageLog` on the editor task, waking the editor for each. The window
updates once a second while nothing else happens at all.

The producer stops by itself after ten minutes; closing the window ends the
example.
"""
function run_message_log_feed_example(; backend = nothing)
    log = MessageLog()
    store = MessageLogStore()
    editor = make_example_editor([log], [make_message_log_feed_projection_example()],
                                 ["message_log_feed"];
                                 backend = something(backend, default_backend()),
                                 feeds = Feed[MessageLogFeed(store = store, log = log)])
    @async for tick in 1:600
        record_message!(store, "Info", "tick $(tick), from another task")
        sleep(1.0)
    end
    run_editor!(editor)
end

"""
    make_frame_statistics_feed_projection_example(; measure = FontFileMeasure())

The `FrameStatistics` pipeline: the renderer of a tab, which draws the
statistics as widgets, a summary table and a table of the recent frames, through
the row that the statistics register.
"""
make_frame_statistics_feed_projection_example(; measure = FontFileMeasure()) =
    NaturalToGraphics(measure = measure)

"""
    run_frame_statistics_feed_example(; backend = nothing)

Watch the frame statistics feed work: the loop folds one sample per frame
into the editor's store for free, and the registered `FrameStatisticsFeed`
flushes the summaries into the shown table — on its deadline, and only while
the view subscribes. The table refreshes four times a second while you watch
it, and every interaction moves the numbers; an editor nobody watches never
flushes at all.
"""
function run_frame_statistics_feed_example(; backend = nothing)
    statistics = FrameStatistics()
    run_example([statistics], [make_frame_statistics_feed_projection_example()],
                ["frame_statistics_feed"];
                backend = something(backend, default_backend()),
                feeds = Feed[FrameStatisticsFeed(statistics = statistics)])
end
