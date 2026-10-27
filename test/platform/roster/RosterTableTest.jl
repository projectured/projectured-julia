# The table of a roster in an editor: a press on a cell of a value selects the
# item of its row, a cell of a document shows that document, where a key edits it
# as one step of undo, the first cell of a row is a link that opens its item, here
# or in a new tab, a file keeps a roster with its source, its columns and its
# title, and no row, and a long roster scrolls in its tab. In a tab the table is a
# table of a list: a row that a filter keeps keeps its print, and a wheel far down
# moves the head of the list while the selection stays on its row.

# A note, whose text is a document that a row of a roster shows.
@document struct _RosterNote
    id::Int
    note::Any
end

# The first IO map of type `type` under `node`, through the fields of each IO map.
function _find_roster_iomap_of(node, type::Type, seen = IdDict{Any,Bool}())
    node isa AbstractCell && return _find_roster_iomap_of(node[], type, seen)
    node isa IoMap || return nothing
    haskey(seen, node) && return nothing
    seen[node] = true
    node isa type && return node
    for field in fieldnames(typeof(node))
        value = getfield(node, field)
        value = value isa AbstractCell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate isa Tuple && !isempty(candidate) && (candidate = last(candidate))
            found = _find_roster_iomap_of(candidate, type, seen)
            found === nothing || return found
        end
    end
    nothing
end

# Each drawn text by its string, the last one where a string is drawn twice. The
# elements of a canvas of a list are its nodes, from the first to the last.
function _roster_drawn_texts(node, found = Dict{String,Any}())
    if node isa GraphicsCanvas
        for element in node.elements
            element = element isa Cell ? element[] : element
            _roster_drawn_texts(element isa ListNode ? element.value : element, found)
        end
    elseif node isa GraphicsViewport
        _roster_drawn_texts(node.content, found)
    elseif node isa GraphicsText
        found[string(node.text)] = node
    end
    found
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
        # The first column holds a document, so it shows that document and is no
        # link; the id is a label.
        roster = link_roster!(Roster(CollectionItems(notes); columns = ["note", "id"], title = "Notes"), notes)
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

    @testset "the first cell of a row is a link: a click opens its item, here or in a new tab" begin
        runs = CellVector(Cell[Cell(_RosterRun(k, "done", 0.1)) for k in 1:3])
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"], title = "Runs"), runs)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(roster, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = false, appearance = false, settings = false)
        run_frame!(editor)
        # The answer of a click on the drawn text `text`, after a move there.
        function answer(text; ctrl = false)
            (x, y) = _arrangement_place(backend, text)
            _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
            click = MouseClick(:left, x, y, 1, ModifierKeys(ctrl = ctrl); time = 0.0)
            operation = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
            operation isa WrappingOperation ? get_wrapped_operation(operation) : operation
        end
        opened = answer("2")
        @test opened isa OpenPageOperation && opened.document === nothing && opened.place === :here
        steps = get_reference_steps(strip_reference_types(opened.reference))
        @test steps[max(1, end - 2):end] == make_steps(FieldReferenceStep("rows"), ElementReferenceStep(2),
                                                      FieldReferenceStep("item"))
        @test answer("2"; ctrl = true).place === :new_tab
        # A click on a cell after the first selects the item of its row, and opens
        # nothing.
        @test !(answer("done") isa OpenPageOperation)
    end

    @testset "the pointer on the link of a row draws the line under it, and the item stays under the pointer" begin
        runs = CellVector(Cell[Cell(_RosterRun(k, k == 2 ? "failed" : "done", 0.1)) for k in 1:3])
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"], title = "Runs"), runs)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(roster, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = false, appearance = false, settings = false)
        run_frame!(editor)
        drawing() = last(rendered_output(backend))
        move!(text, time) = _arrangement_press!(editor, backend, MouseMove(_arrangement_place(backend, text)...; time))
        @test !is_link_text_underlined(drawing(), "2")
        move!("2", 0.0)
        @test is_link_text_underlined(drawing(), "2")
        @test !is_link_text_underlined(drawing(), "1")
        # The row holds the item, and below it the cell, as a part that the rows draw.
        row = roster.rows[2]
        @test get_reference_steps(strip_reference_types(get_mouse_target(row)))[1] == FieldReferenceStep("item")
        # The pointer on another cell of the row draws no line under the link.
        move!("failed", 0.1)
        @test !is_link_text_underlined(drawing(), "2")
        @test get_mouse_target(row) !== nothing
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
        show_pane!(open_pane!(roster; title = "Runs", editor); editor)
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

    # A filter answers a new list of rows. The table of a list keeps the print of
    # each row that stays, so the text that it draws is the same object.
    @testset "a row that a filter keeps keeps the drawn text of its cells" begin
        runs = CellVector(Cell[Cell(_RosterRun(k, "done", 0.1)) for k in 1:8])
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"]), runs)
        rows_at = extend_reference(EmptyReference(), FieldReferenceStep("rows"))
        status = extend_reference(EmptyReference(), FieldReferenceStep("status"))
        arranged = ArrangementDocument(roster, ArrangementEntry[ArrangementEntry(rows_at,
            Any[ArrangementFilter(Any[ArrangementCondition(status, :equal, "done")])])])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(400)))
        io = print_document(natural, nothing, arranged, context)
        @test _find_roster_iomap_of(io, RosterRowsToWidgetIoMap).view !== nothing
        before = _roster_drawn_texts(io.output)
        @test all(id -> haskey(before, string(id)), 1:8)
        runs[3].status = "failed"
        after = _roster_drawn_texts(io.output)
        @test !haskey(after, "3")
        @test all(id -> after[string(id)] === before[string(id)], [1, 2, 4, 5, 6, 7, 8])
        runs[3].status = "done"
        again = _roster_drawn_texts(io.output)
        @test haskey(again, "3") && again["5"] === before["5"]
        # A filter that keeps no row at the print gives a list with no rows, and
        # the rows that it keeps later are drawn.
        foreach(run -> run.status = "failed", runs)
        @test !haskey(_roster_drawn_texts(io.output), "5")
        empty_roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"]), runs)
        empty_arranged = ArrangementDocument(empty_roster, ArrangementEntry[ArrangementEntry(rows_at,
            Any[ArrangementFilter(Any[ArrangementCondition(status, :equal, "done")])])])
        empty_io = print_document(natural, nothing, empty_arranged, context)
        @test !haskey(_roster_drawn_texts(empty_io.output), "5")
        runs[5].status = "done"
        @test haskey(_roster_drawn_texts(empty_io.output), "5")
    end

    # The table moves the head of its list to the row at the top when that row is
    # far from the head; the roster keeps the head as the anchor of its view, and
    # the selection of the rows names the same row.
    @testset "a wheel far down moves the head of the rows, and the selection stays on its row" begin
        runs = CellVector(Cell[Cell(_RosterRun(k, "done", 0.1)) for k in 1:400])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(PrimitiveString("start"), natural; backend,
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = true, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        # The first column is a link, so the press that selects a row is on its id.
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["status", "id"], title = "Runs"),
                              editor.document)
        show_pane!(open_pane!(roster; title = "Runs", editor); editor)
        drain_operations!(editor)
        run_frame!(editor)
        window = first(editor.iomap.output.windows)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        place(text) = (drawn = _arrangement_drawn(window.content);
                       drawn[findlast(entry -> entry[1] == text, drawn)])
        view = _find_roster_iomap_of(editor.iomap, RosterRowsToWidgetIoMap).view
        @test view !== nothing && view.anchor == 1
        (_, x, y) = place("3")
        push_event!(backend, WindowInput(window.id, MouseMove(x + 2, y + 2; time = 0.0)))
        push_event!(backend, WindowInput(window.id, MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)))
        frame!()
        selected = selected_tail(editor, 3)
        @test selected == make_steps(FieldReferenceStep("rows"), ElementReferenceStep(3), FieldReferenceStep("item"))
        for _ in 1:200
            push_event!(backend, WindowInput(window.id, MouseScroll(0, -10, x + 2, y + 2; time = 0.0)))
            frame!()
            view.anchor > 1 && break
        end
        @test view.anchor > 200
        @test selected_tail(editor, 3) == selected
        frame!()
        @test 0 <= place(string(view.anchor))[3] < Int(window.content.h)
    end
end
end
