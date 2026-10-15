# The sources of a roster that the slices give: the documents of the tabs of a
# window as they open, the records of a store as they come in, a store that no
# loaded slice offers, and the frames of the session, which flush only while a
# roster shows them.

function test_roster_sources()
@testset "the sources of the window and of the stores" begin
    @testset "the documents of the tabs of a window" begin
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        editor = build_editor(PrimitiveString("one"), natural; backend = HeadlessBackend(),
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        roster = link_roster!(Roster(TabDocuments(PrimitiveString); columns = ["value"]), editor.document)
        values() = [row.values[1] for row in roster.rows]
        @test values() == ["one"]
        open_pane!(PrimitiveNumber(2); title = "two", editor)
        frame!()
        open_pane!(PrimitiveString("three"); title = "three", editor)
        frame!()
        @test values() == ["one", "three"]
        every = link_roster!(Roster(TabDocuments(PrimitiveDocument); columns = ["value"]), editor.document)
        @test length(every.rows) == 3
        @test get_roster_item_type(TabDocuments(PrimitiveString)) === PrimitiveString
        read = parse_pred_text(print_pred_text(Roster(TabDocuments(PrimitiveString); columns = ["value"])))
        @test read.source == TabDocuments(PrimitiveString)
    end

    @testset "the records of a store" begin
        @test issubset([:faults, :frames, :log, :mcp_log, :tasks], get_roster_source_names())
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        editor = Editor(PrimitiveString("x"), natural; backend = HeadlessBackend(), devices = Device[])
        log = get_session_message_log(; editor)
        # A store is one of the session of the editor of the evaluation, as in a
        # frame of that editor.
        run_with_evaluation_editor(editor) do
            roster = link_roster!(Roster(StoreRecords(:log); columns = ["level", "message"]), log)
            before = length(roster.rows)
            @test before == length(log.entries)
            push!(log.entries, MessageLogEntry("Info", "a line for the roster"))
            @test length(roster.rows) == before + 1
            @test [value for value in roster.rows[end].values] == ["Info", "a line for the roster"]
            deleteat!(log.entries, length(log.entries))
            @test length(roster.rows) == before
            faults = link_roster!(Roster(StoreRecords(:faults); columns = ["message"]), log)
            push!(get_session_fault_log(; editor).entries,
                  FaultLogEntry(1, UInt64(1), :print, :Probe, "a fault for the roster", 1))
            @test length(faults.rows) == length(get_session_fault_log(; editor).entries) == 1
            calls = link_roster!(Roster(StoreRecords(:mcp_log); columns = ["name"]), log)
            @test length(calls.rows) == length(get_session_mcp_log(; editor).entries)
            tasks = link_roster!(Roster(StoreRecords(:tasks); columns = ["within.title"]), log)
            @test length(tasks.rows) == sum((length(group.tasks) for group in collect_task_group_documents(get_session_task_group_list())); init = 0)
            unknown = link_roster!(Roster(StoreRecords(:no_such_store); columns = ["x"]), log)
            @test_throws ArgumentError length(unknown.rows)
        end
    end

    @testset "the frames of the session flush while a roster shows them" begin
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        editor = Editor(PrimitiveString("x"), natural; backend = HeadlessBackend(), devices = Device[])
        store = editor.frame_measurements
        record_frame_measurements!(store; times = [:frame_time => 0.016, :read_time => 0.001], end_time = 1.0)
        record_frame_measurements!(store; times = [:frame_time => 0.020, :read_time => 0.002], end_time = 2.0)
        series = get_session_frame_time_series(; editor)
        feed = FrameStatisticsFeed(; now = () -> 100.0)
        GC.gc()
        # No roster shows the frames, so the feed asks for no frame for them.
        @test !has_dependent_cells(getfield(series, :names))
        run_with_evaluation_editor(editor) do
            roster = link_roster!(Roster(StoreRecords(:frames); columns = ["frame", "frame_time"]), series)
            length(roster.rows)
            @test has_dependent_cells(getfield(series, :names))
            @test compute_wake_deadline(feed, editor) !== nothing
            drain_changes!(feed, editor)
            @test [row.values[1] for row in roster.rows] == [1, 2]
            @test [row.values[2] for row in roster.rows] == [0.016, 0.020]
        end
    end
end
end
