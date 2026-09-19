# The frame statistics feed — the loop folds for free, the feed flushes on
# a deadline, and only while a view subscribes to the document. Its data
# arrives only with frames, so it never wakes: a wake would make frames feed
# themselves.

function test_frame_statistics_feed()
@testset "the frame statistics feed" begin
    @testset "unwatched, the feed neither flushes nor asks for a deadline" begin
        statistics = FrameStatistics()
        feed = FrameStatisticsFeed(statistics = statistics)
        editor = Editor(HeadlessBackend(), statistics, FrameStatisticsToSyntax(),
                        Device[]; feeds = Feed[feed])
        EditorModule.record_frame_measurements!(editor, 0.016)
        @test compute_wake_deadline(feed, editor) === nothing
        @test drain_feeds!(editor) == 0
        @test length(statistics.rows) == 0
    end

    @testset "a subscribed view turns the flush on, and off once flushed" begin
        statistics = FrameStatistics()
        feed = FrameStatisticsFeed(statistics = statistics)
        editor = Editor(HeadlessBackend(), statistics, FrameStatisticsToSyntax(),
                        Device[]; feeds = Feed[feed])
        # Subscribe the way a view does: read `frame_count` in a computation.
        view = ComputedCell(() -> statistics.frame_count)
        view[]
        EditorModule.record_frame_measurements!(editor, 0.016)
        @test compute_wake_deadline(feed, editor) == 0.25
        @test drain_feeds!(editor) >= 1
        @test statistics.frame_count == 1
        @test statistics.rows[1].name == "frame_time"
        @test statistics.rows[1].count == 1
        # Flushed means flushed: no deadline and no work until the next fold.
        @test compute_wake_deadline(feed, editor) === nothing
        @test drain_feeds!(editor) == 0
        # A second fold updates the row in place.
        EditorModule.record_frame_measurements!(editor, 0.020)
        drain_feeds!(editor)
        @test statistics.rows[1].count == 2
        @test statistics.rows[1].maximum >= 0.020
        # Keep the subscription alive across every assertion above.
        @test view[] == 2
    end

    @testset "the printer shows the table" begin
        statistics = FrameStatistics()
        push!(statistics.rows, FrameMeasurement("frame_time", 3, 0.01, 0.03, 0.02, 0.01, 0.06))
        statistics.frame_count = 3
        p = FrameStatisticsToSyntax()
        iomap = print_document(p, p, statistics, PrinterContext())
        @test iomap.output isa SyntaxNode
    end
end
end
