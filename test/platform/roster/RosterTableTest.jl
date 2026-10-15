# The table of a roster in an editor: a press on a cell of a value selects the
# item of its row, a cell of a document shows that document, where a key edits it
# as one step of undo, a file keeps a roster with its source, its columns and its
# title, and no row, and a long roster scrolls in its tab.

# A note, whose text is a document that a row of a roster shows.
@document struct _RosterNote
    id::Int
    note::Any
end

function test_roster_table()
@testset "the table of a roster in an editor" begin
    make_notes() = CellVector(Cell[Cell(_RosterNote(1, PrimitiveString("alpha"))),
                                   Cell(_RosterNote(2, PrimitiveString("beta")))])
    # The last steps of the selection of the editor, without their types.
    function selected_tail(editor, n)
        found = get_reference_steps(strip_reference_types(editor.document.selection))
        length(found) >= n ? found[(end - n + 1):end] : found
    end
    make_steps(parts...) = collect(get_reference_steps(extend_reference(EmptyReference(), parts...)))

    @testset "a press on a value selects the item of its row" begin
        notes = make_notes()
        roster = link_roster!(Roster(CollectionItems(notes); columns = ["id", "note"], title = "Notes"), notes)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(roster, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = false, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        press!(text) = begin
            (x, y) = _arrangement_place(backend, text)
            _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                                MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
            frame!()
        end
        @test all(text -> text in _arrangement_texts(backend), ["id", "note", "1", "2", "alpha", "beta"])
        press!("2")
        @test selected_tail(editor, 3) == make_steps(FieldReferenceStep("rows"), ElementReferenceStep(2),
                                                FieldReferenceStep("item"))

        @testset "a key in a cell of a document edits the item, as one step of undo" begin
            buffer = editor.document
            press!("alpha")
            selection = get_reference_steps(strip_reference_types(editor.document.selection))
            @test any(i -> selection[i:min(i + 3, end)] == make_steps(FieldReferenceStep("rows"), ElementReferenceStep(1),
                                                                 FieldReferenceStep("item"), FieldReferenceStep("note")),
                      1:length(selection))
            before = length(buffer.undo_entries)
            _arrangement_press!(editor, backend, KeyPress('x'; time = 0.0))
            frame!()
            @test occursin("x", notes[1].note.value) && length(notes[1].note.value) == 6
            @test length(buffer.undo_entries) == before + 1
            # The row shows the new text, as the item holds it.
            @test notes[1].note.value in _arrangement_texts(backend)
        end
    end

    @testset "a file keeps the source, the columns and the title of a roster" begin
        roster = Roster(StoreRecords(:log); columns = ["level", "message"], title = "Errors")
        text = print_pred_text(roster)
        @test occursin("StoreRecords", text) && occursin("Errors", text)
        read = parse_pred_text(text)
        @test read isa Roster && read.source == StoreRecords(:log) && read.columns == ["level", "message"] &&
              read.title == "Errors" && read.link === nothing
        within = Roster(ItemsWithin(StoreRecords(:tasks), PrimitiveString); columns = ["value"])
        read = parse_pred_text(print_pred_text(within))
        @test read.source == ItemsWithin(StoreRecords(:tasks), PrimitiveString)
    end

    # A tab gives its content the height of the tab as a slot, and the table of a
    # roster takes it and scrolls its rows there, so the last row of a long roster
    # comes into view under the wheel.
    @testset "a roster of 200 rows fills its tab, and the wheel brings its last row into view" begin
        runs = CellVector(Cell[Cell(_RosterRun(k, "done", 0.1)) for k in 1:200])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(PrimitiveString("start"), natural; backend,
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = true, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"], title = "Runs"),
                              editor.document)
        open_pane!(roster; title = "Runs", editor)
        drain_operations!(editor)
        run_frame!(editor)
        window = first(editor.iomap.output.windows)
        height = Int(window.content.h)
        place(text) = (drawn = _arrangement_drawn(window.content);
                       drawn[findlast(entry -> entry[1] == text, drawn)])
        @test place("200")[3] > height
        (_, x, y) = place("1")
        for _ in 1:100
            push_event!(backend, WindowInput(window.id, MouseScroll(0, -10, x + 2, y + 2; time = 0.0)))
            run_frame!(editor)
            place("200")[3] < height && break
        end
        @test 0 <= place("200")[3] < height
    end
end
end
