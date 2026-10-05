# The frame statistics feed — the loop records for free, the feed flushes on
# a deadline, and only while a view subscribes to a document. Its data arrives
# only with frames, so it never wakes: a wake would make frames feed
# themselves. The table summarizes the recent frames, and the plot draws them.

# The text of each line that the table printer draws.
function _get_frame_statistics_lines(statistics)
    p = FrameStatisticsToSyntax()
    node = print_document(p, p, statistics, PrinterContext()).output
    [node.children[index].value.content for index in 1:length(node.children)]
end

function test_frame_statistics_feed()
@testset "the frame statistics feed" begin
    @testset "unwatched, the feed neither flushes nor asks for a deadline" begin
        statistics = FrameStatistics()
        feed = FrameStatisticsFeed(statistics = statistics, plot = FrameTimeSeries())
        editor = Editor(statistics, FrameStatisticsToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        EditorModule.record_frame_performance!(editor, 0.016)
        @test compute_wake_deadline(feed, editor) === nothing
        @test drain_feeds!(editor) == 0
        @test length(statistics.rows) == 0
    end

    @testset "a subscribed view turns the flush on, and off once flushed" begin
        statistics = FrameStatistics()
        clock = Ref(0.0)
        feed = FrameStatisticsFeed(statistics = statistics, plot = FrameTimeSeries(),
                                   now = () -> clock[])
        editor = Editor(statistics, FrameStatisticsToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        # Subscribe the way a view does: read `frame_count` in a computation.
        view = Cell(@computation statistics.frame_count)
        view[]
        EditorModule.record_frame_performance!(editor, 0.016)
        @test compute_wake_deadline(feed, editor) == 0.25
        @test drain_feeds!(editor) >= 1
        @test statistics.frame_count == 1
        @test statistics.rows[1].name == "frame_time"
        @test statistics.rows[1].count == 1
        # Flushed means flushed: no deadline and no work until the next fold.
        @test compute_wake_deadline(feed, editor) === nothing
        @test drain_feeds!(editor) == 0
        # A second fold updates the row in place, once the interval has passed.
        EditorModule.record_frame_performance!(editor, 0.020)
        clock[] += 0.25
        drain_feeds!(editor)
        @test statistics.rows[1].count == 2
        @test statistics.rows[1].maximum >= 0.020
        # Keep the subscription alive across every assertion above.
        @test view[] == 2
    end

    @testset "a document flushes at most once per interval" begin
        # A flush changes the display, and the frame that the display event makes
        # must not flush again, or the frames would feed themselves.
        statistics = FrameStatistics()
        clock = Ref(10.0)
        feed = FrameStatisticsFeed(statistics = statistics, plot = FrameTimeSeries(),
                                   now = () -> clock[])
        editor = Editor(statistics, FrameStatisticsToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        view = Cell(@computation statistics.frame_count)
        view[]
        EditorModule.record_frame_performance!(editor, 0.016)
        @test drain_feeds!(editor) >= 1
        EditorModule.record_frame_performance!(editor, 0.016)
        clock[] += 0.1
        # Due, but flushed less than an interval ago: nothing now, and a deadline.
        @test drain_feeds!(editor) == 0
        @test statistics.frame_count == 1
        @test compute_wake_deadline(feed, editor) == 0.25
        clock[] += 0.2
        @test drain_feeds!(editor) >= 1
        @test statistics.frame_count == 2
        @test view[] == 2
    end

    @testset "the printer shows times in milliseconds, with a unit" begin
        statistics = FrameStatistics()
        push!(statistics.rows,
              FrameStatisticsRow("frame_time", :second, 3, 0.01, 0.03, 0.02, 0.01, 0.06))
        push!(statistics.rows,
              FrameStatisticsRow("reads", :count, 3, 120.0, 5000.0, 812.3, 900.14,
                                 2436.7))
        statistics.frame_count = 3
        lines = _get_frame_statistics_lines(statistics)
        @test lines[1] == "3 frames"
        @test split(lines[2]) ==
              ["measurement", "unit", "frames", "minimum", "maximum", "mean",
               "deviation", "total"]
        @test split(lines[3]) ==
              ["frame_time", "ms", "3", "10.00", "30.00", "20.00", "10.00", "60"]
        @test split(lines[4]) == ["reads", "3", "120", "5000", "812.3", "900.1", "2437"]
    end

    @testset "the table summarizes the recent frames" begin
        store = FrameMeasurementStore(capacity = 2)
        for seconds in (0.010, 0.020, 0.030)
            record_frame_measurements!(store; times = [:frame_time => seconds])
        end
        statistics = FrameStatistics()
        flush_frame_statistics!(statistics, store)
        @test statistics.frame_count == 3
        @test statistics.rows[1].count == 2
        @test statistics.rows[1].minimum == 0.020
        @test first(_get_frame_statistics_lines(statistics)) ==
              "3 frames, the rows cover the last 2"
    end

    @testset "the table holds the recent frames, one column for each row" begin
        store = FrameMeasurementStore(capacity = 3)
        record_frame_measurements!(store; times = [:frame_time => 0.010])
        record_frame_measurements!(store; times = [:frame_time => 0.020], counts = [:reads => 7])
        record_frame_measurements!(store; times = [:frame_time => 0.030], counts = [:reads => 9])
        statistics = FrameStatistics()
        flush_frame_statistics!(statistics, store)
        @test statistics.frames == [1, 2, 3]
        @test [statistics.rows[index].name for index in 1:length(statistics.rows)] ==
              ["frame_time", "reads"]
        @test statistics.columns[1] ≈ [0.010, 0.020, 0.030]
        # The counter starts at the second frame: the first holds no value of it.
        @test isnan(statistics.columns[2][1])
        @test statistics.columns[2][2:3] == [7.0, 9.0]
        # The ring keeps the last three frames, oldest first.
        record_frame_measurements!(store; times = [:frame_time => 0.040], counts = [:reads => 11])
        flush_frame_statistics!(statistics, store)
        @test statistics.frames == [2, 3, 4]
        @test statistics.columns[2] == [7.0, 9.0, 11.0]
    end

    @testset "the plot follows the recent frames" begin
        plot = FrameTimeSeries()
        p = FrameTimeSeriesToChart()
        chart = print_document(p, p, plot, PrinterContext()).output
        @test length(chart.series) == 0
        store = FrameMeasurementStore(capacity = 3)
        record_frame_measurements!(store; times = [:frame_time => 0.010],
                                   counts = [:reads => 5])
        record_frame_measurements!(store; times = [:frame_time => 0.020],
                                   counts = [:reads => 7])
        @test flush_frame_time_series!(plot, store) == 1
        @test length(chart.series) == 1
        series = chart.series[1]
        @test series.label == "frame_time"
        @test series.x == [1.0, 2.0]
        @test series.y ≈ [10.0, 20.0]
        # A new frame gives the line new columns, and the line stays one object.
        record_frame_measurements!(store; times = [:frame_time => 0.030],
                                   counts = [:reads => 9])
        flush_frame_time_series!(plot, store)
        @test chart.series[1] === series
        @test series.y ≈ [10.0, 20.0, 30.0]
    end

    @testset "a watched plot turns the flush on, and the table stays alone" begin
        statistics = FrameStatistics()
        plot = FrameTimeSeries()
        feed = FrameStatisticsFeed(statistics = statistics, plot = plot)
        editor = Editor(statistics, FrameStatisticsToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        # Subscribe the way a plot view does: read `names` in a computation.
        view = Cell(@computation length(plot.names))
        view[]
        EditorModule.record_frame_performance!(editor, 0.016)
        @test compute_wake_deadline(feed, editor) == 0.25
        @test drain_feeds!(editor) == 1
        @test plot.names == ["frame_time"]
        @test plot.frames == [1.0]
        @test isempty(statistics.rows)
        @test view[] == 1
    end

    @testset "a plot opened after the table flushed shows the frames at once" begin
        statistics = FrameStatistics()
        plot = FrameTimeSeries()
        feed = FrameStatisticsFeed(statistics = statistics, plot = plot)
        editor = Editor(statistics, FrameStatisticsToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        table_view = Cell(@computation statistics.frame_count)
        table_view[]
        EditorModule.record_frame_performance!(editor, 0.016)
        @test drain_feeds!(editor) == 1
        # The plot opens now, and no frame comes after it: the plot keeps its own
        # count, so it is due all the same.
        plot_view = Cell(@computation length(plot.names))
        plot_view[]
        @test compute_wake_deadline(feed, editor) == 0.25
        @test drain_feeds!(editor) == 1
        @test plot.frames == [1.0]
        @test compute_wake_deadline(feed, editor) === nothing
        @test (table_view[], plot_view[]) == (1, 1)
    end
end
end
