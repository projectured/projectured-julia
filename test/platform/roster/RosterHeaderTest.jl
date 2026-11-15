# The header of a roster table in an arrangement: the field under each key shows
# and edits the condition of its column, the glyph sorts, and "Filter by values…"
# lists the values of the column over every row. A roster with no arrangement has
# a plain header.

function test_roster_header()
@testset "the header of a roster table in an arrangement" begin
    make_runs() = CellVector(Cell[Cell(_RosterRun(1, "done", 0.31)), Cell(_RosterRun(2, "failed", 0.12)),
                                  Cell(_RosterRun(3, "done", 0.54)), Cell(_RosterRun(4, "error", 0.2))])
    function make_editor(; window = false)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(PrimitiveString("start"), natural; backend,
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        (editor, backend)
    end
    frame!(editor) = (drain_operations!(editor); run_frame!(editor))
    # The ids of the rows that the roster shows, in their order.
    shown_ids(rows) = [parse(Int, first(split(line, " | "))) for line in split(string(describe_roster(rows)), '\n')[3:end]]
    entry_of(rows) = find_arranged_collection(get_document(rows).link,
                                              extend_reference(get_reference(rows), FieldReferenceStep("rows"))).entry
    key_of(column) = extend_reference(EmptyReference(), FieldReferenceStep(column))
    filters_of(rows) = [(condition.key, condition.operator, condition.value)
                        for description in entry_of(rows).projections if description isa ArrangementFilter
                        for condition in description.conditions]
    sort_of(rows) = [(key.key, key.direction) for description in entry_of(rows).projections
                     if description isa ArrangementSort for key in description.keys]
    # The place under a drawn label where the filter field of its header is.
    function field_place(backend, label)
        (x, y) = _arrangement_place(backend, label)
        (x + 10, y + 30)
    end
    # The places of the sort glyphs of the headers, from the left.
    glyphs(backend) = sort([(x + 2, y + 2) for (text, x, y) in _arrangement_drawn(last(rendered_output(backend)))
                            if text in string.(Char.((0xe37d, 0xe04a, 0xe042)))])
    function setup(; filter = Any["id" => >=(1)], sort = Any[])
        (editor, backend) = make_editor()
        rows = show_roster!(CollectionItems(make_runs()); title = "Runs", columns = ["id", "status", "delay"],
                            filter, sort, editor)
        frame!(editor)
        (editor, backend, rows)
    end
    press!(editor, backend, x, y; button = :left, shift = false) = begin
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(button, x, y, 1, ModifierKeys(; shift); time = 0.0))
        frame!(editor)
    end
    # A named key is a KeyDown, and a character a KeyPress.
    key!(editor, backend, key::Symbol; ctrl = false) =
        (_arrangement_press!(editor, backend, KeyDown(key, ModifierKeys(; ctrl); time = 0.0)); frame!(editor))
    type!(editor, backend, text) = for char in text
        _arrangement_press!(editor, backend, KeyPress(char; time = 0.0))
        frame!(editor)
    end

    @testset "a key in the field of a column writes a :matches condition, and an empty field takes it away" begin
        (editor, backend, rows) = setup()
        @test shown_ids(rows) == [1, 2, 3, 4]
        @test ">= 1" in _arrangement_texts(backend)
        press!(editor, backend, field_place(backend, "status")...)
        type!(editor, backend, "= done")
        @test filters_of(rows) == [(key_of("id"), :at_least, 1), (key_of("status"), :matches, "= done")]
        @test shown_ids(rows) == [1, 3]
        @test "= done" in _arrangement_texts(backend)
        # The caret stays in the field while the filter changes the rows.
        type!(editor, backend, ", failed")
        @test filters_of(rows)[2] == (key_of("status"), :matches, "= done, failed")
        @test shown_ids(rows) == [1, 2, 3]
        for _ in 1:length("= done, failed")
            key!(editor, backend, :backspace)
        end
        @test filters_of(rows) == [(key_of("id"), :at_least, 1)]
        @test shown_ids(rows) == [1, 2, 3, 4]
    end

    @testset "a text that does not parse keeps every row and the field says why" begin
        (editor, backend, rows) = setup()
        press!(editor, backend, field_place(backend, "status")...)
        type!(editor, backend, "> x")
        @test shown_ids(rows) == [1, 2, 3, 4]
        @test filters_of(rows)[2] == (key_of("status"), :matches, "> x")
    end

    @testset "the field of a column shows the condition that another operator wrote" begin
        (editor, backend, rows) = setup(; filter = Any["status" => ==("failed"), "delay" => >(0.1)])
        @test all(text -> text in _arrangement_texts(backend), ["= failed", "> 0.1"])
        @test !(">= 1" in _arrangement_texts(backend))
        # An edit of the field of the column writes in the place of that condition.
        press!(editor, backend, field_place(backend, "status")...)
        key!(editor, backend, :end)
        type!(editor, backend, ", error")
        @test filters_of(rows) == [(key_of("status"), :matches, "= failed, error"), (key_of("delay"), :greater, 0.1)]
        @test shown_ids(rows) == [2, 4]
    end

    @testset "a click on the glyph sorts, and a Shift+click adds a key" begin
        (editor, backend, rows) = setup(; filter = Any["id" => >=(1)])
        press!(editor, backend, glyphs(backend)[3]...)
        @test sort_of(rows) == [(key_of("delay"), :ascending)]
        @test shown_ids(rows) == [2, 4, 1, 3]
        press!(editor, backend, glyphs(backend)[3]...)
        @test sort_of(rows) == [(key_of("delay"), :descending)]
        @test shown_ids(rows) == [3, 1, 4, 2]
        press!(editor, backend, glyphs(backend)[2]...; shift = true)
        @test sort_of(rows) == [(key_of("delay"), :descending), (key_of("status"), :ascending)]
        # A click on a descending key turns the sort off.
        press!(editor, backend, glyphs(backend)[3]...)
        @test isempty(sort_of(rows))
        @test shown_ids(rows) == [1, 2, 3, 4]
    end

    @testset "a sort that the assistant made shows in the glyph" begin
        (editor, backend, rows) = setup(; sort = Any["delay" => :descending])
        @test string(Char(0xe042)) in _arrangement_texts(backend)
        @test shown_ids(rows) == [3, 1, 4, 2]
    end

    @testset "Filter by values lists the values of every row, ticked by the filter, and Apply writes the list" begin
        (editor, backend) = make_editor(; window = true)
        rows = show_roster!(CollectionItems(make_runs()); title = "Runs", columns = ["id", "status", "delay"],
                            filter = ["status" => "= done"], editor)
        frame!(editor)
        @test shown_ids(rows) == [1, 3]
        windows() = editor.iomap.output.windows
        # A right click on the key opens the menu of the column in a window of its own.
        window = first(windows())
        drawn = _arrangement_drawn(window.content)
        (_, x, y) = drawn[findlast(entry -> entry[1] == "status", drawn)]
        push_event!(backend, WindowInput(window.id, MouseMove(x + 2, y + 2; time = 0.0)))
        push_event!(backend, WindowInput(window.id, MouseClick(:right, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)))
        frame!(editor)
        @test length(windows()) == 2
        item = only(last(windows()).content.elements)
        @test item.action.label == "Filter by values…"
        # The window of the dialog is not drawn by the headless backend: its boxes
        # and its button take the presses.
        item.action.callback(editor)
        frame!(editor)
        dialog = last(windows()).content
        @test dialog isa WidgetDialog
        boxes = dialog.content.content.children
        # The list holds the values of the rows that the filter hides too, and the
        # box of "done" is ticked by the filter.
        @test [(box.label, box.content) for box in boxes] ==
              [("done  (2)", true), ("error  (1)", false), ("failed  (1)", false)]
        boxes[1].content = false
        boxes[3].content = true
        apply = last(collect(dialog.buttons))
        apply.action.callback(nothing)
        frame!(editor)
        @test filters_of(rows) == [(key_of("status"), :matches, "= failed")]
        @test shown_ids(rows) == [2]
        @test "= failed" in first.(_arrangement_drawn(first(windows()).content))
    end

    @testset "a field of an arrangement with no entry makes the first entry" begin
        (editor, backend) = make_editor()
        roster = link_roster!(Roster(CollectionItems(make_runs()); columns = ["id", "status", "delay"], title = "Runs"),
                              editor.document)
        arranged = ArrangementDocument(roster, ArrangementEntry[])
        show_document!(arranged; title = "Runs", editor)
        frame!(editor)
        @test "failed" in _arrangement_texts(backend)
        press!(editor, backend, field_place(backend, "status")...)
        type!(editor, backend, "= failed")
        entry = only(arranged.entries)
        @test [(c.key, c.operator, c.value) for c in only(entry.projections).conditions] ==
              [(key_of("status"), :matches, "= failed")]
        texts = _arrangement_texts(backend)
        @test "failed" in texts && !("done" in texts) && "= failed" in texts
    end

    @testset "one undo takes back an edit of the header" begin
        (editor, backend, rows) = setup()
        press!(editor, backend, field_place(backend, "status")...)
        type!(editor, backend, "= done")
        @test shown_ids(rows) == [1, 3]
        key!(editor, backend, :z; ctrl = true)
        @test filters_of(rows) == [(key_of("id"), :at_least, 1)]
        @test shown_ids(rows) == [1, 2, 3, 4]
    end

    @testset "a roster that is not in an arrangement has a plain header" begin
        (editor, backend, rows) = setup(; filter = Any[])
        iomap = _find_roster_iomap_of(editor.iomap, RosterRowsToWidgetIoMap)
        @test iomap !== nothing && !iomap.is_filtering
        @test all(text -> text in _arrangement_texts(backend), ["id", "status", "delay"])
        @test isempty(glyphs(backend))
    end
end
end
