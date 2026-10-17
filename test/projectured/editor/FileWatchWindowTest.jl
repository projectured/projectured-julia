# The application window watches the files that its tabs show. A change of a file
# on disk reaches its tab; a change under edits that are not saved keeps them, and
# the page of the file shows its band; "Keep mine" lets the next save write over
# the file, and "Load it" takes the file. The window is built as `run_application`
# builds it, on a headless backend, and each gesture goes through its loop.

using Test

# The window of `run_application` over `paths`, on a headless backend.
function _fw_make_window(paths, root)
    settings = make_settings()
    document = make_application_document(paths; root, settings)
    backend = HeadlessBackend()
    editor = build_editor(document, make_application_projection(); backend, settings,
                          window = (; title = "ProjecturEd", width = 1600, height = 1000,
                                    opened_window_projections = make_opened_window_projections()),
                          make_application_wrappers(; root, document)...)
    # The tabs enter the window at the first drain, as in `run_application`. The
    # loop does not run, so the test drains what the start posted.
    start_application!(editor)
    drain_operations!(editor)
    run_frame!(editor)
    (editor, backend)
end

# Each text that the window draws, at its place.
_fw_drawn(editor) = _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)

# Press `events` in the window, in one frame.
_fw_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, WindowInput(:ProjecturEd, event)), events); run_frame!(editor))

function _fw_click!(editor, backend, (x, y), time)
    none = ModifierKeys()
    _fw_press!(editor, backend, MouseDown(:left, x + 3, y + 3, none; time),
               MouseUp(:left, x + 3, y + 3, none; time), MouseClick(:left, x + 3, y + 3, 1, none; time))
end

# Run frames until `holds()`, for at most `seconds`: a watcher reads a change on its
# own task. Each frame drains the feeds first, as a frame of the loop does.
function _fw_wait_until(holds, editor; seconds::Real = 10.0)
    deadline = time() + seconds
    while time() < deadline
        drain_feeds!(editor)
        run_frame!(editor)
        holds() && return true
        sleep(0.05)
    end
    false
end

function test_file_watch_window()
@testset "the window watches the files of its tabs" begin
    mktempdir() do dir
        path = joinpath(dir, "a.json")
        write(path, "{\"name\": \"Alice\"}")
        (editor, backend) = _fw_make_window([path], dir)
        page = only(search_documents(editor.document, node -> node isa FilePage))
        file = find_page_file(page)
        @test is_document_file_watched(file; store = get_session_file_change_store(; editor))
        @test only(get_session_file_change_store(; editor).files).receiver === page
        shows(text) = any(entry -> occursin(text, entry[1]), _fw_drawn(editor))
        # A text of the page of the file: below the tab strip, whose first tab is
        # the Explorer.
        strip_y = only(y for (t, x, y) in _fw_drawn(editor) if t == "Explorer")
        place(text) = only((x, y) for (t, x, y) in _fw_drawn(editor) if occursin(text, t) && y > strip_y)
        @test shows("Alice")

        # Another program writes the file: a file with no edits takes it.
        write(path, "{\"name\": \"Bob\"}")
        @test _fw_wait_until(() -> shows("Bob"), editor)
        @test page.band === nothing && page.file_hash == compute_file_text_hash(path)

        # A typed character is an edit that is not saved. A change on disk keeps it,
        # and the page shows its band.
        _fw_click!(editor, backend, place("Bob"), 1.0)
        _fw_press!(editor, backend, KeyPress('x'; time = 2.0))
        @test shows("x")
        @test has_unsaved_edits(get_file_content(file)) === true
        edited = compute_file_text(file)
        write(path, "{\"name\": \"Carol\"}")
        @test _fw_wait_until(() -> shows("a.json changed on disk."), editor)
        @test !shows("Carol") && compute_file_text(file) == edited

        # Keep mine: the band goes, and the next save writes over the file.
        _fw_click!(editor, backend, place("Keep mine"), 3.0)
        @test page.band === nothing && !shows("changed on disk")
        _fw_press!(editor, backend, KeyDown(:s, ModifierKeys(ctrl = true); time = 4.0))
        @test read(path, String) == edited
        @test page.file_hash == hash(edited)

        # Load it: the page takes the file on disk, and the edit goes.
        _fw_click!(editor, backend, place("x"), 5.0)
        _fw_press!(editor, backend, KeyPress('y'; time = 6.0))
        @test has_unsaved_edits(get_file_content(file)) === true
        write(path, "{\"name\": \"Dave\"}")
        @test _fw_wait_until(() -> shows("a.json changed on disk."), editor)
        _fw_click!(editor, backend, place("Load it"), 7.0)
        @test shows("Dave") && page.band === nothing
        @test page.file_hash == compute_file_text_hash(path)
        foreach(step -> step(editor), editor.stop_steps)
    end
end
end
