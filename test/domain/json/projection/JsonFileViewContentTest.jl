# The view of a file that shows its file through views. The file view holds the view
# of what the file holds, in its field `content`: the view of the undo buffer of the
# file, which holds the view of the JSON document. The scroll pane of the file view
# shows that view. So the caret of a place is a path of the views, and the file, the
# undo buffer and the JSON document hold no caret. Two places that show one file keep
# two carets and share the undo steps. The helpers are those of
# `JsonViewNaturalRowTest.jl`.

const _FVC_TEXT = "{\"greeting\": \"hello\", \"list\": [1, 2]}"

# The print of `document` through the general renderer, in a place of 600 by 400.
function _fvc_print(renderer, document)
    print_document(renderer, nothing, document,
                   PrinterContext(EmptyReference(), Cell(600), Cell(400), Dict{Symbol,Any}()))
end

# `document` at a place, with a function that reads an event and runs the answer, and
# a function that gives the texts that the place draws now.
function _fvc_show(document; measure = FixedMeasure(10, 18, 6, 0))
    renderer = NaturalToGraphics(; measure)
    iomap = _fvc_print(renderer, document)
    editor = (; document)
    read!(event) = read_intent(renderer, iomap, event)
    press!(event) = begin
        operation = read!(event)
        operation === nothing || evaluate_operation(editor, operation)
        operation
    end
    drawn() = _vnr_drawn(get_iomap_output(iomap))
    (; document, renderer, iomap, read!, press!, drawn)
end

# The place where `shown` draws the text `text`, with a small step into it.
function _find_fvc_spot(shown, text)
    spot = first(drawn for drawn in shown.drawn() if drawn[1] == text)
    (spot[2] + 5, spot[3] + 5)
end

function test_json_file_view_content()
@testset "a file view shows its file through views" begin

stored(document) = strip_reference_types(get_stored_selection(document))
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
key(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...); time = 0.0)
click(spot) = MouseClick(:left, spot[1], spot[2], 1, ModifierKeys(); time = 0.0)
caret_text(document) = _json_keys_caret_text(get_stored_selection(document))

mktempdir() do dir
    path = joinpath(dir, "people.json")
    make_file() = (write(path, _FVC_TEXT); make_file_tab(path, UndoBuffer))

    @testset "the file view holds the views of what the file holds" begin
        file = make_file()
        @test file isa JsonFile && file.content isa UndoBuffer && file.content.content isa JsonObject
        view = make_file_view(file; views = true)
        @test fieldnames(FileView)[1:3] == (:file, :scroll, :content)
        @test view.file === file
        @test view.content isa UndoBufferView && view.content.viewed === file.content
        @test view.content.content isa JsonObjectView && view.content.content.viewed === file.content.content
        @test view.content === view.content
        # The scroll pane shows the view, and a file view of today shows the file.
        @test view.scroll.content === view.content
        plain = make_file_view(file; views = false)
        @test plain.content === nothing && plain.scroll.content === file
        @test make_document_view(file; views = false).content === nothing
    end

    @testset "it draws what a file view of today draws" begin
        plain = _fvc_show(make_file_view(make_file(); views = false))
        shown = _fvc_show(make_file_view(make_file(); views = true))
        @test shown.drawn() == plain.drawn()
        @test any(text -> text[1] == "hello", shown.drawn())
    end

    @testset "the caret is a path of the views, and no content holds one" begin
        file = make_file()
        view = make_file_view(file; views = true)
        shown = _fvc_show(view)
        answer = shown.press!(click(_find_fvc_spot(shown, "hello")))
        @test answer isa ReplaceSelectionOperation
        @test occursin(r"^\.content\.content\.entries\[1\]\.value\.value\{\d+\}$", caret_text(view))
        @test get_stored_selection(file) === nothing
        @test get_stored_selection(file.content) === nothing
        @test _json_view_holds_no_caret(file.content.content)
        # A file view of today takes the caret of its file, which the file holds.
        plain_file = make_file()
        plain_view = make_file_view(plain_file; views = false)
        plain = _fvc_show(plain_view)
        plain.press!(click(_find_fvc_spot(plain, "hello")))
        @test occursin(r"^\.file\.content\.content\.entries\[1\]\.value\.value\{\d+\}$", caret_text(plain_view))
        @test get_stored_selection(plain_file) !== nothing
        # The two carets name the same place of the JSON document.
        @test replace(caret_text(plain_view), ".file.content.content" => "") ==
              replace(caret_text(view), ".content.content" => "")
    end

    @testset "an edit is a step of the undo buffer of the file, and Ctrl+Z takes it back" begin
        file = make_file()
        view = make_file_view(file; views = true)
        shown = _fvc_show(view)
        shown.press!(click(_find_fvc_spot(shown, "hello")))
        before = stored(view)
        @test shown.press!(typed('X')) isa RecordUndoOperation
        @test occursin('X', file.content.content.entries[1].value.value)
        @test length(file.content.undo_entries) == 1 && has_unsaved_edits(file.content)
        @test any(text -> occursin('X', text[1]), shown.drawn())
        @test shown.press!(key(:z; ctrl = true)) isa UndoOperation
        @test file.content.content.entries[1].value.value == "hello"
        @test stored(view) == before
        @test get_stored_selection(file) === nothing
    end

    @testset "two file views of one file keep two carets and share the undo steps" begin
        file = make_file()
        view_a = make_file_view(file; views = true)
        view_b = make_file_view(file; views = true)
        @test view_a.content !== view_b.content && view_a.content.viewed === view_b.content.viewed
        @test view_a.scroll !== view_b.scroll
        shown_a = _fvc_show(view_a)
        shown_b = _fvc_show(view_b)
        shown_a.press!(click(_find_fvc_spot(shown_a, "hello")))
        shown_b.press!(click(_find_fvc_spot(shown_b, "1")))
        @test occursin(".entries[1]", caret_text(view_a)) && occursin(".entries[2]", caret_text(view_b))
        @test shown_a.press!(typed('X')) isa RecordUndoOperation
        # The other place draws the edit, and its caret stays.
        @test any(text -> occursin('X', text[1]), shown_b.drawn())
        @test occursin(".entries[2]", caret_text(view_b))
        # Ctrl+Z at the other place takes the edit back.
        @test shown_b.press!(key(:z; ctrl = true)) isa UndoOperation
        @test file.content.content.entries[1].value.value == "hello"
        # A scroll of one place leaves the other where it is.
        view_a.scroll.scroll_position = Point2D(0, 20)
        scrolled(view) = (unwrap_cell(view.scroll.scroll_position.x), unwrap_cell(view.scroll.scroll_position.y))
        @test scrolled(view_a) == (0, 20) && scrolled(view_b) == (0, 0)
    end

    @testset "of two places in one window, the place of the caret is live" begin
        file = make_file()
        view_a = make_file_view(file; views = true)
        view_b = make_file_view(file; views = true)
        root = VerticalLayout([view_a, view_b])
        shown = _fvc_show(root)
        in_place(index, k) = strip_reference_types(
            @reference(root, children[index].content.content.entries[1].value.value{k}))
        replace_selection!(root, in_place(2, 2))
        replace_selection!(root, in_place(1, 1))
        @test is_live_selection(view_a) && !is_live_selection(view_b)
        @test occursin("value{1}", caret_text(view_a)) && occursin("value{2}", caret_text(view_b))
        @test _json_view_holds_no_caret(file.content.content) && get_stored_selection(file) === nothing
        shown.drawn()
        carets = _json_view_collect(shown.iomap, TextViewToGraphicsCanvasIoMap)
        @test length(carets) == 2 && count(_json_view_is_caret_live, carets) == 1
        replace_selection!(root, in_place(2, 3))
        @test !is_live_selection(view_a) && is_live_selection(view_b)
        @test count(_json_view_is_caret_live, carets) == 1
    end

    @testset "Ctrl+S saves the file, and F5 reads it again" begin
        file = make_file()
        view = make_file_view(file; views = true)
        shown = _fvc_show(view)
        shown.press!(click(_find_fvc_spot(shown, "hello")))
        shown.press!(typed('X'))
        save = shown.read!(key(:s; ctrl = true))
        @test save isa SaveFileOperation && save.file === file
        evaluate_operation(nothing, save)
        @test occursin('X', read(path, String))
        # A file view of today gives the same answer, through the printer of the file.
        plain = _fvc_show(make_file_view(make_file(); views = false))
        plain.press!(click(_find_fvc_spot(plain, "hello")))
        @test plain.read!(key(:s; ctrl = true)) isa SaveFileOperation
        # F5 reads the file again, and the view shows the view of the new document.
        write(path, "{\"greeting\": \"again\"}")
        reload = shown.read!(key(:f5))
        @test reload isa CompoundOperation
        first_view = view.content.content
        evaluate_operation(nothing, only(member for member in reload.operations if member isa ReloadFileOperation))
        @test view.content.content isa JsonObjectView && view.content.content !== first_view
        @test view.content.content.viewed === file.content.content
        @test any(text -> text[1] == "again", shown.drawn())
        # The rows of the file are in the list of the rows of the place.
        rows = read_intent(shown.renderer, nothing, Intent(CollectIntents()), shown.iomap).operation
        @test rows isa CollectedIntentsOperation
        @test any(intent -> intent.operation isa SaveFileOperation, rows.intents)
    end

    @testset "the band of the file shows above the views" begin
        file = make_file()
        view = make_file_view(file; views = true)
        shown = _fvc_show(view)
        get_file_disk_state(file).band = FileBand(; message = "people.json changed on disk.",
                                                    choices = ["Keep" => DoNothingOperation()])
        texts = shown.drawn()
        band_y = only(text[3] for text in texts if occursin("changed on disk", text[1]))
        @test band_y < only(text[3] for text in texts if text[1] == "hello")
        @test shown.press!(click(_find_fvc_spot(shown, "hello"))) isa ReplaceSelectionOperation
        @test occursin(r"^\.content\.content\.entries\[1\]\.value\.value\{\d+\}$", caret_text(view))
        get_file_disk_state(file).band = nothing
        @test !any(text -> occursin("changed on disk", text[1]), shown.drawn())
    end

    @testset "a file that holds a document with no view" begin
        # The undo buffer has a view, and its document has none: the document prints
        # as content, below the step `viewed` of the view of the buffer.
        file = get_file_type(find_file_format(path))(abspath(path), UndoBuffer(PrimitiveString("plain")))
        view = make_file_view(file; views = true)
        @test view.content isa UndoBufferView && view.content.content === nothing
        shown = _fvc_show(view)
        @test shown.press!(click(_find_fvc_spot(shown, "plain"))) isa ReplaceSelectionOperation
        @test occursin(r"^\.content\.viewed\.content\.value\{\d+\}$", caret_text(view))
        @test shown.press!(typed('Z')) isa RecordUndoOperation
        @test occursin('Z', file.content.content.value)
        # With no undo buffer, what the file holds has no view, and the place shows
        # the file as a file view of today does.
        bare = get_file_type(find_file_format(path))(abspath(path), PrimitiveString("plain"))
        bare_view = make_file_view(bare; views = true)
        @test bare_view.content === nothing && bare_view.scroll.content === bare
        bare_shown = _fvc_show(bare_view)
        @test bare_shown.press!(click(_find_fvc_spot(bare_shown, "plain"))) isa ReplaceSelectionOperation
        @test occursin(r"^\.file\.content\.value\{\d+\}$", caret_text(bare_view))
    end

    @testset "a file that is not read yet shows its views after the read" begin
        write(path, _FVC_TEXT)
        file = make_unread_file(path, UndoBuffer)
        state = get_file_disk_state(file)
        @test state.loaded_count < 0
        view = make_file_view(file; views = true)
        # Before the read the file holds the first document of its format, and the
        # view holds the view of that document.
        @test view.content isa UndoBufferView
        first_view = view.content.content
        @test first_view isa JsonView && first_view.viewed === file.content.content
        editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0));
                              backend = HeadlessBackend(), devices = Device[], window = false, tabs = false,
                              appearance = false, settings = false, file_change = true)
        try
            run_frame!(editor)
            evaluate_operation(editor, AcquireDocumentOperation(view))
            deadline = time() + 30
            while state.loaded_count < 0 && time() < deadline
                drain_operations!(editor)
                run_frame!(editor)
                sleep(0.02)
            end
            @test state.loaded_count >= 0
            @test file.content.content isa JsonObject
            @test view.content.content isa JsonObjectView && view.content.content !== first_view
            @test view.content.content.viewed === file.content.content
            evaluate_operation(editor, ReleaseDocumentOperation(view))
        finally
            foreach(step -> step(editor), editor.stop_steps)
        end
    end

    @testset "a file below itself in its JSON document shows as with no view" begin
        # A file in a JSON document is a part with no view, and it prints in the
        # syntax tree of the document. The two places draw the same texts.
        # The two files are read from one state of the disk, because the print of a
        # file in a JSON document shows the time of its file.
        write(path, _FVC_TEXT)
        make_loop() = begin
            file = make_file_tab(path, UndoBuffer)
            push!(file.content.content.entries, JsonObjectEntry("self", file))
            file
        end
        plain = _fvc_show(make_file_view(make_loop(); views = false))
        shown = _fvc_show(make_file_view(make_loop(); views = true))
        @test shown.drawn() == plain.drawn()
        @test count(drawn -> drawn[1] == "hello", shown.drawn()) == 2
        @test any(drawn -> occursin("cycle", drawn[1]), shown.drawn())
    end
end

end
end
