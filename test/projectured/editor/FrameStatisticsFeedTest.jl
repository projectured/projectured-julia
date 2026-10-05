# The frame statistics feed — the loop records for free, the feed flushes on
# a deadline, and only while a view subscribes to a document. Its data arrives
# only with frames, so it never wakes: a wake would make frames feed
# themselves. The table summarizes the recent frames, and the plot draws them.

# The parts that the widget projection draws: the head line, the title and the
# table of the summary, and the title and the table of the frames.
function _print_frame_statistics(statistics)
    p = FrameStatisticsToWidget()
    iomap = print_document(p, p, statistics, PrinterContext())
    (p, iomap, iomap.output)
end

_get_frame_statistics_head(root) = root.children[1].children[1].content
_get_frame_table(root) = root.children[5].child
_get_row_texts(row) = [row[index].content for index in 1:length(row)]
_get_header_texts(table) = [table.column_headers[index].content for index in 1:length(table.column_headers)]

# A table with two measurements over three frames; the counter did not measure
# the first frame.
function _make_frame_statistics_example()
    statistics = FrameStatistics()
    push!(statistics.rows,
          FrameStatisticsRow("frame_time", :second, 3, 0.01, 0.03, 0.02, 0.01, 0.06))
    push!(statistics.rows,
          FrameStatisticsRow("reads", :count, 2, 120.0, 5000.0, 812.3, 900.14, 2436.7))
    statistics.frame_count = 3
    statistics.frames = [1, 2, 3]
    statistics.columns = [[0.01, 0.02, 0.03], [NaN, 120.0, 5000.0]]
    statistics
end

# Every text that a canvas draws, as `(x, y, text)`. A list of elements is
# walked at most `limit` nodes each way from its head.
function _get_drawn_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[]; limit = 50)
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            for link in (:next, :prev)
                current = link === :next ? elements : elements.prev
                seen = 0
                while current !== nothing && seen < limit
                    _get_drawn_texts(current.value, ox + Int(node.x), oy + Int(node.y), found; limit)
                    current = getproperty(current, link)
                    seen += 1
                end
            end
        else
            for element in elements
                _get_drawn_texts(element, ox + Int(node.x), oy + Int(node.y), found; limit)
            end
        end
    elseif node isa GraphicsViewport
        _get_drawn_texts(node.content, ox + Int(node.x), oy + Int(node.y), found; limit)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end

# A backend that takes the events that a test queues, and draws nothing.
mutable struct _FrameStatisticsBackend <: ProjecturedAll.BackendModule.Backend
    events::Vector{Any}
end
_FrameStatisticsBackend() = _FrameStatisticsBackend(Any[])
ProjecturedAll.BackendModule.initialize_backend!(::_FrameStatisticsBackend) = nothing
ProjecturedAll.BackendModule.quit_backend!(::_FrameStatisticsBackend) = nothing
ProjecturedAll.BackendModule.take_from_devices!(backend::_FrameStatisticsBackend, devices) =
    isempty(backend.events) ? nothing : popfirst!(backend.events)
ProjecturedAll.BackendModule.write_to_devices!(::_FrameStatisticsBackend, devices, output) = nothing

function test_frame_statistics_feed()
@testset "the frame statistics feed" begin
    @testset "unwatched, the feed neither flushes nor asks for a deadline" begin
        statistics = FrameStatistics()
        feed = FrameStatisticsFeed(statistics = statistics, plot = FrameTimeSeries())
        editor = Editor(statistics, FrameStatisticsToWidget(); backend = HeadlessBackend(),
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
        editor = Editor(statistics, FrameStatisticsToWidget(); backend = HeadlessBackend(),
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
        editor = Editor(statistics, FrameStatisticsToWidget(); backend = HeadlessBackend(),
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

    @testset "a paused table neither flushes nor asks for a deadline, and the plot goes on" begin
        statistics = FrameStatistics()
        plot = FrameTimeSeries()
        clock = Ref(0.0)
        feed = FrameStatisticsFeed(statistics = statistics, plot = plot, now = () -> clock[])
        editor = Editor(statistics, FrameStatisticsToWidget(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        table_view = Cell(@computation statistics.frame_count)
        plot_view = Cell(@computation length(plot.names))
        (table_view[], plot_view[])
        EditorModule.record_frame_performance!(editor, 0.016)
        drain_feeds!(editor)
        @test statistics.frame_count == 1
        statistics.paused = true
        EditorModule.record_frame_performance!(editor, 0.020)
        clock[] += 0.25
        # Only the plot is due, and it flushes.
        @test compute_wake_deadline(feed, editor) == 0.25
        @test drain_feeds!(editor) == 1
        @test plot.frames == [1.0, 2.0]
        @test statistics.frame_count == 1
        @test statistics.frames == [1]
        # Nothing is due now: the paused table asks for no deadline.
        @test compute_wake_deadline(feed, editor) === nothing
        # Unpaused, the table is due again at once, with no new frame.
        statistics.paused = false
        @test compute_wake_deadline(feed, editor) == 0.25
        clock[] += 0.25
        @test drain_feeds!(editor) == 1
        @test statistics.frame_count == 2
        @test statistics.frames == [1, 2]
        @test (table_view[], plot_view[]) == (2, 1)
    end

    @testset "the printer shows a summary table and a table of the frames, newest first" begin
        statistics = _make_frame_statistics_example()
        _, _, root = _print_frame_statistics(statistics)
        @test _get_frame_statistics_head(root) == "3 frames"
        @test root.children[1].children[2] isa WidgetToggle
        @test root.children[2].content == "Summary"
        summary = root.children[3]
        @test _get_header_texts(summary) ==
              ["measurement", "unit", "frames", "minimum", "maximum", "mean", "deviation", "total"]
        @test _get_row_texts(summary.rows[1]) ==
              ["frame_time", "ms", "3", "10.00", "30.00", "20.00", "10.00", "60"]
        @test _get_row_texts(summary.rows[2]) ==
              ["reads", "", "2", "120", "5000", "812.3", "900.1", "2437"]
        @test root.children[4].content == "Frames, newest first"
        frames = _get_frame_table(root)
        @test _get_header_texts(frames) == ["frame_time (ms)", "reads"]
        @test frames.corner.content == "frame"
        @test _get_row_texts(frames.rows.value) == ["30.00", "5000"]
        @test frames.row_headers.value.content == "3"
        # The oldest frame did not measure the counter, and it ends the list.
        oldest = frames.rows.next.next
        @test _get_row_texts(oldest.value) == ["10.00", "-"]
        @test oldest.next === nothing
        @test frames.row_headers.next.next.value.content == "1"
    end

    @testset "a flush changes the numbers and keeps the parts" begin
        statistics = _make_frame_statistics_example()
        _, _, root = _print_frame_statistics(statistics)
        summary = root.children[3]
        frames = _get_frame_table(root)
        statistics.rows[1].count = 4
        statistics.frame_count = 4
        statistics.frames = [2, 3, 4]
        statistics.columns = [[0.02, 0.03, 0.04], [120.0, 5000.0, 7.0]]
        @test root.children[3] === summary
        @test _get_frame_table(root) === frames
        @test summary.rows[1][3].content == "4"
        @test _get_frame_statistics_head(root) == "4 frames"
        @test _get_row_texts(frames.rows.value) == ["40.00", "7"]
        @test frames.row_headers.value.content == "4"
    end

    @testset "an empty table shows its head line and no table" begin
        _, _, root = _print_frame_statistics(FrameStatistics())
        @test _get_frame_statistics_head(root) == "0 frames"
        @test length(root.children) == 2
        @test root.children[2].content == "no frame yet"
    end

    @testset "a move of the head of the frames moves the anchor, and Pause is view state" begin
        statistics = _make_frame_statistics_example()
        p, iomap, root = _print_frame_statistics(statistics)
        frames = _get_frame_table(root)
        # The answer of a table that moves the head of its list to its second row.
        move = CompoundOperation(Any[
            ReplaceViewStateOperation(ReplaceReferencedValueOperation(frames, "rows", frames.rows.next)),
            ReplaceViewStateOperation(ReplaceReferencedValueOperation(frames, "scroll_position", Point2D(0, 4))),
            ReplaceViewStateOperation(ReplaceReferencedValueOperation(frames, "top_row", 1)),
            ReplaceViewStateOperation(ReplaceReferencedValueOperation(frames, "row_headers",
                                                                      frames.row_headers.next))])
        answer = read_intent(p, iomap, move)
        @test answer isa CompoundOperation
        @test length(answer.operations) == 4
        anchor = answer.operations[1]
        @test anchor isa ReplaceViewStateOperation
        @test get_wrapped_operation(anchor).document === statistics
        @test get_wrapped_operation(anchor).value == 2
        # The scroll writes the cells that the table shares with the document.
        @test get_wrapped_operation(answer.operations[2]).document === frames
        @test answer.operations[4] isa DoNothingOperation
        # The list starts again from the anchor.
        statistics.anchor = 2
        @test _get_row_texts(frames.rows.value) == ["20.00", "120"]
        @test frames.row_headers.value.content == "2"
        @test getfield(frames, :top_row) === getfield(statistics, :top_row)
        # A press on Pause writes the document, and the undo does not record it.
        toggle = root.children[1].children[2]
        press = ReplaceReferencedValueOperation(toggle, "pressed", true)
        answer = read_intent(p, iomap, press)
        @test answer isa ReplaceViewStateOperation
        @test get_wrapped_operation(answer) === press
        @test getfield(toggle, :pressed) === getfield(statistics, :paused)
    end

    @testset "in a tab, a turn far down moves the anchor, the rows stay, and Pause pauses" begin
        store = FrameMeasurementStore()
        for frame in 1:1000
            record_frame_measurements!(store; times = [:frame_time => frame / 1e6])
        end
        statistics = FrameStatistics()
        flush_frame_statistics!(statistics, store)
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context = with_exact_size(PrinterContext(); width = Cell(Int32(800)),
                                  height = Cell(Int32(400)))
        io = print_document(projection, nothing, statistics, context)
        # A row header is a frame number at the left edge; the summary shows its
        # numbers further right.
        y_of(frame; limit = 50) = only(t[2] for t in _get_drawn_texts(io.output; limit)
                                       if t[3] == string(frame) && t[1] < 80)
        wheel(dy) = read_intent(projection, nothing,
                                Intent(MouseScroll(0, dy, 400, 300; time = 0.0), nothing), io).operation
        @test y_of(999) > y_of(1000)
        step = y_of(999) - y_of(1000)
        # A turn near the head moves the rows by one turn of the wheel.
        near = y_of(999)
        evaluate_operation(nothing, wheel(-1))
        turn = near - y_of(999)
        @test turn > 0
        @test statistics.anchor == 1
        # Three hundred rows down, a turn moves the anchor to the row at the top,
        # and every row moves by one turn as before.
        getfield(statistics, :scroll_position)[] = Point2D(0, 300 * step)
        before = y_of(696; limit = 400)       # the row 305 from the head
        evaluate_operation(nothing, wheel(-1))
        @test statistics.anchor == 301
        @test y_of(696) == before - turn
        # A press on Pause pauses the table.
        x, y, _ = only(t for t in _get_drawn_texts(io.output) if t[3] == "Pause")
        press = read_intent(projection, nothing,
                            Intent(MouseClick(:left, x + 2, y + 2, ModifierKeys(); time = 0.0), nothing), io)
        evaluate_operation(nothing, press.operation)
        @test statistics.paused
    end

    @testset "an editor draws the frames that it records, and a press on Pause holds them" begin
        statistics = FrameStatistics()
        clock = Ref(0.0)
        feed = FrameStatisticsFeed(statistics = statistics, plot = FrameTimeSeries(),
                                   now = () -> clock[])
        backend = _FrameStatisticsBackend()
        editor = build_editor(statistics, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                              backend, devices = Device[Keyboard(), Mouse(), Display()],
                              tabs = false, feeds = Feed[feed],
                              window = (; title = "Statistics", width = 800, height = 400))
        force(value) = value isa AbstractCell ? force(value[]) : value
        window() = first(force(force(get_iomap_output(editor.iomap)).windows))
        drawn() = _get_drawn_texts(force(window().content))
        # One turn of the loop of `run_editor!`: drain the feeds, run the frame,
        # and record it, so the next turn flushes it.
        function frames!(count)
            for _ in 1:count
                clock[] += 0.25
                drain_feeds!(editor)
                run_frame!(editor)
                EditorModule.record_frame_performance!(editor, 0.01)
            end
        end
        frames!(1)
        @test "no frame yet" in [t[3] for t in drawn()]
        frames!(3)
        @test statistics.frame_count == 3
        @test "3 frames" in [t[3] for t in drawn()]
        # The frame numbers are the row headers of the table of the frames.
        @test all(string(frame) in [t[3] for t in drawn()] for frame in 1:3)
        # A press on Pause, as the window sends it.
        x, y, _ = only(t for t in drawn() if t[3] == "Pause")
        for event in (MouseDown(:left, x + 2, y + 2, ModifierKeys(); time = 1.0),
                      MouseUp(:left, x + 2, y + 2, ModifierKeys(); time = 1.05))
            push!(backend.events, WindowInput(window().id, event))
            run_frame!(editor)
        end
        @test statistics.paused
        held = statistics.frame_count
        frames!(3)
        @test statistics.frame_count == held
        @test "$(held) frames" in [t[3] for t in drawn()]
        @test string(held + 2) ∉ [t[3] for t in drawn()]
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
        _, _, root = _print_frame_statistics(statistics)
        @test _get_frame_statistics_head(root) == "3 frames, the tables cover the last 2"
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
        editor = Editor(statistics, FrameStatisticsToWidget(); backend = HeadlessBackend(),
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
        editor = Editor(statistics, FrameStatisticsToWidget(); backend = HeadlessBackend(),
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
