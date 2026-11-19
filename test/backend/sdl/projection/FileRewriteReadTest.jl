# A page that a tab shows reads its file again when another program rewrites it,
# while no input comes: the watch wakes the editor, a frame asks for the text, and
# the answer of the read wakes it again. The window runs on SDL, whose paint skips
# the parts that its guards find unchanged, and its frames come only as the loop of
# the editor runs them: after a wake, or at the time that the editor asks for. The
# page is a `.pred` page in a file view or the file document itself, and the focus is
# in its tab or in another pane. The test reads only the counts of the file, so no
# read of the page by the test asks for the text.

# Frames as the loop of the editor runs them: after a wake, or at the timeout that the
# editor asks for, until `done()` or the time `until`. Answers the count of frames.
function _frr_run_loop_frames!(editor, started, until, done)
    frames = 0
    while time() < until && !done()
        timeout = editor.wake_pending[] ? 0.0 : EditorModule.compute_wait_timeout(editor)
        deadline = min(time() + timeout, until)
        while time() < deadline && !editor.wake_pending[]
            sleep(0.005)
        end
        # No wake and no timeout of the editor: the loop would still wait.
        !editor.wake_pending[] && (isinf(timeout) || time() >= until) && break
        Threads.atomic_xchg!(editor.wake_pending, false)
        run_measured_frame!(editor, time() - started)
        frames += 1
    end
    frames
end

# The counts of the file of a page after a rewrite, `(read_count, loaded_count)`
# before and after it, in a window of two panes: the page, as `make_page(file)`
# gives it, and a composer beside it, with the focus in the pane of `focus`.
function _frr_read_after_rewrite(make_page, focus::Symbol)
    root = mktempdir()
    path = joinpath(root, "walk.pred")
    write_page(text) = write(path, print_pred_text(Dashboard("Walk", Any[DashboardCard("Step", PrimitiveString(text))])))
    write_page("first")
    file = make_file_tab(path)
    editor = build_editor(make_page(file), NaturalToGraphics(; measure = FontFileMeasure()); backend = SdlBackend(),
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "W", width = 1200, height = 800), tabs = true, appearance = false,
                          settings = false, file_change = true)
    try
        run_frame!(editor)
        open_pane!(WidgetTextarea("composer"); title = "Composer", side = :right, editor)
        drain_operations!(editor)
        run_frame!(editor)
        evaluate_operation(editor, AcquireDocumentOperation(editor.document))
        titles = [get_pane_tab_title_string(tab) for group in get_pane_groups(get_window_tree(; editor))
                  for tab in group.tabs]
        focused = focus === :page ? only(title for title in titles if title != "Composer") : "Composer"
        focus_pane!(find_pane_reference(focused; editor); editor)
        drain_operations!(editor)
        state = get_file_disk_state(file)
        started = time()
        run_measured_frame!(editor, 0.0)
        _frr_run_loop_frames!(editor, started, time() + 5, () -> false)
        watched = is_document_file_watched(file; store = get_session_file_change_store(; editor))
        before = (state.read_count, state.loaded_count)
        # A new time of the file, which the watch compares.
        sleep(1.2)
        write_page("second")
        _frr_run_loop_frames!(editor, started, time() + 15,
                              () -> state.read_count > before[1] && state.loaded_count == state.read_count)
        (; watched, before, after = (state.read_count, state.loaded_count))
    finally
        foreach(step -> step(editor), editor.stop_steps)
        rm(root; recursive = true, force = true)
    end
end

function test_file_rewrite_read()
    @testset "a shown page reads its rewritten file with frames that only wakes start" begin
        for (kind, make_page) in (("a file view", make_file_view), ("the file document", identity)),
            focus in (:page, :composer)
            @testset "$(kind), the focus in the $(focus === :page ? "tab of the page" : "other pane")" begin
                counts = _frr_read_after_rewrite(make_page, focus)
                @test counts.watched
                @test counts.before[1] == counts.before[2]
                @test counts.after[1] == counts.before[1] + 1
                @test counts.after[2] == counts.after[1]
            end
        end
    end
end
