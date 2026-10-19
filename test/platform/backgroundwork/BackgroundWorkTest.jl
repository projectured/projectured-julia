# The log of the background work: the feed of an editor copies the records of its
# store into the log of its session while a view shows the log, newest first; a
# row runs until its work ends, and says its failure; the page counts the works,
# and the row of the log in a tree runs while a work runs. A folder that an
# explorer opens leaves a row. A log that no view shows is not filled.

# A source that doubles each input, held at `gate` until a value is put into it.
_make_doubling_source(gate) =
    BackgroundSource(inputs -> (take!(gate); Any[2 * input for input in inputs]); description = "times two")

# Read `cell` as a computation of a frame of `editor` reads it, so it asks.
_ask_in_editor(editor, cell) = run_with_evaluation_editor(() -> Cell(@computation cell[])[], editor)

# Run frames of `editor` as its loop does, with a drain of its feeds before each,
# until `test()` holds, for at most four seconds.
function _wait_for_background_work(test, editor)
    deadline = time() + 4
    while time() < deadline
        drain_feeds!(editor)
        run_frame!(editor)
        test() && return true
        sleep(0.02)
    end
    false
end

function test_background_work()
@testset "the log of the background work" begin
    @testset "a view of the log fills it, newest first, and a row runs, ends and fails" begin
        content = ExplorerSection("Explorer", Any[])
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer; tabs = true, background_work = true)
        log = get_session_background_work_log(; editor)
        @test log === get_session_background_work_log(; editor) && isempty(log.rows)
        push!(content.entries, log)
        run_frame!(editor)
        gate = Channel{Bool}(1)
        doubled = make_background_cell(_make_doubling_source(gate), () -> 21; default = 0)
        broken = make_background_cell(BackgroundSource(inputs -> error("no disk"); description = "a broken read"),
                                      () -> 1)
        _ask_in_editor(editor, doubled)
        _ask_in_editor(editor, broken)
        ProjecturedKernel.EditorModule.start_background_cell_work!(editor)
        # The row of the log in the tree reads its rows, so the feed copies them.
        @test _wait_for_background_work(editor) do
            length(log.rows) == 2 && log.rows[1].state == "failed"
        end
        (held, failed) = (log.rows[2], log.rows[1])
        @test [row.source for row in log.rows] == ["a broken read", "times two"]
        @test held.state == "running" && held.took == "running" && held.values == 1 && held.inputs == "21"
        @test failed.state == "failed" && occursin("no disk", failed.failure)
        @test any(condition -> condition.name === :running, get_document_decoration(log).conditions)
        @test ProjecturedPlatform.BackgroundWorkModule._format_log_line(log) == "2 works · 1 running · 1 failed"
        # The end of the work ends its row, which keeps its document.
        put!(gate, true)
        @test _wait_for_background_work(() -> log.rows[2].state == "done", editor)
        @test log.rows[2] === held && endswith(held.took, " s")
        @test !any(condition -> condition.name === :running, get_document_decoration(log).conditions)
        # The page of the log counts the works above its table.
        _nav_press!(editor, backend, _explorer_click(backend, "Background work"))
        @test get_navigator_page(explorer.navigator) === log
        @test _wait_for_background_work(() -> _nav_has_text(backend, "2 works · 1 failed"), editor)
        @test _nav_has_text(backend, "times two") && _nav_has_text(backend, "a broken read")
    end

    @testset "a folder that an explorer opens leaves a row, and a log that no view shows stays empty" begin
        root = mktempdir()
        write(joinpath(root, "notes.txt"), "")
        workspace = Workspace([WorkspaceFolder("work", root)])
        content = ExplorerSection("Explorer", Any[workspace])
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer; tabs = true, background_work = true)
        log = get_session_background_work_log(; editor)
        for (label, shown) in (("Files", "work"), ("work", "notes.txt"))
            _nav_press!(editor, backend, _explorer_open_chevron(backend, label))
            @test _wait_for_background_work(() -> _nav_has_text(backend, shown), editor)
        end
        store = get_background_work_store(editor)
        @test any(record -> record.description == "the listings of folders", store.records)
        # No view shows the log, so the feed copies nothing.
        for _ in 1:10
            drain_feeds!(editor)
            run_frame!(editor)
            sleep(0.03)
        end
        @test isempty(log.rows) && log.change_count == -1
        # The log comes into the tree, and its rows follow.
        push!(content.entries, log)
        @test _wait_for_background_work(editor) do
            any(row -> row.source == "the listings of folders" && row.state == "done", collect(log.rows))
        end
        @test log.change_count == store.change_count
    end
end
end
