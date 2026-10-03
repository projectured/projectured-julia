"""
    test_data_frame_cells()

A cell of a view is the primitive document of its value, drawn as plain text: a
string with no quotes, a Bool, a number, and a `missing` value as an empty
type-in that shows `missing`. A value of another type is a label that takes no
key. A click in a cell that takes keys opens it: the view keeps an entry for the
cell, the caret goes into the document of the entry, and the table shows that
document in the cell.
"""
function test_data_frame_cells()
    @testset "the cells of a view" begin
        module_ = ProjecturedDataFrames.DataFramesModule
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(900)),
                                    height = Cell(Int32(300)))
        make_frame() = DataFrame(id = 101:103, name = ["alpha", "beta", "gamma"], ok = [true, false, true],
                                 tag = [:x1, :y1, :z1], price = [1.5, missing, 2.5])
        texts_of(io) = [t[3] for t in _data_frame_texts(io.output)]
        place_of(io, text) = only((t[1], t[2]) for t in _data_frame_texts(io.output) if t[3] == text)
        function press(io, x, y)
            change = read_intent(projection, nothing,
                                 Intent(MouseClick(:left, x, y, ModifierKeys(); time = 0.0), nothing), io)
            change isa Intent ? change.operation : change
        end
        table_of(io) = _data_frame_table_iomap(io).input
        # The document that the table shows in row `k` of its list and column `c`.
        shown(io, k, c) = collect(ProjecturedPlatform.CollectionModule.find_list_node(table_of(io).rows, k).value)[c]

        @testset "a cell is the primitive document of its value, and other values are labels" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            texts = texts_of(io)
            @test "alpha" in texts && !any(t -> occursin("\"alpha\"", t), texts)
            @test "true" in texts && "1.5" in texts && "missing" in texts && "x1" in texts
            @test shown(io, 1, 1) isa PrimitiveNumber && shown(io, 1, 2) isa PrimitiveString
            @test shown(io, 1, 3) isa PrimitiveBool
            @test shown(io, 2, 5) isa PrimitiveInsertion
            @test shown(io, 2, 5).allowed_types == (PrimitiveNumber,) && shown(io, 2, 5).placeholder == "missing"
            label = shown(io, 1, 4)
            @test label isa WidgetLabel && occursin("Symbol", label.tooltip)
        end

        @testset "a click in a cell opens it, and the caret goes into the document of its entry" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "102")
            op = press(io, x + 2, y + 2)
            @test op isa CompoundOperation
            evaluate_operation(_DataFrameFilterEditor(view), op)
            entry = only(view.edits)
            @test entry.row == 2 && entry.column == "id"
            @test entry.document isa PrimitiveNumber && entry.document.value == 102
            steps = get_reference_steps(strip_reference_types(get_selection(view)))
            @test steps[1:4] == [FieldReferenceStep("rows"), RangeReferenceStep(1, 2), RangeReferenceStep(0, 1),
                                 FieldReferenceStep("value")]
            @test find_value_range(entry.document) !== nothing
            @test shown(io, 2, 1) === entry.document
            @test try_evaluate_reference(view, ConcreteReference(FieldReferenceStep("rows"),
                ConcreteReference(RangeReferenceStep(1, 2), ConcreteReference(RangeReferenceStep(0, 1),
                                                                              EmptyReference())))) === entry.document
            # A second click in the open cell opens no second entry.
            op = press(io, x + 2, y + 2)
            @test op isa ReplaceSelectionOperation
            evaluate_operation(_DataFrameFilterEditor(view), op)
            @test length(view.edits) == 1
        end

        @testset "a click in a missing value opens an empty type-in" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "missing")
            evaluate_operation(_DataFrameFilterEditor(view), press(io, x + 2, y + 2))
            entry = only(view.edits)
            @test entry.row == 2 && entry.column == "price"
            @test entry.document isa PrimitiveInsertion && entry.document.placeholder == "missing"
        end

        @testset "a click on a label opens no cell, and selects the row" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "y1")
            op = press(io, x + 2, y + 2)
            @test op isa ReplaceSelectionOperation
            evaluate_operation(_DataFrameFilterEditor(view), op)
            @test isempty(view.edits)
            @test strip_reference_types(get_selection(view)) ==
                  ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(1, 2),
                                                                                  EmptyReference()))
        end

        # The path of the view of the caret at `k` in the cell in row `r` of the
        # frame and column `c`.
        caret(r, c, k) = ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(r - 1, r),
            ConcreteReference(RangeReferenceStep(c - 1, c), ConcreteReference(FieldReferenceStep("value"),
                ConcreteReference(RangeReferenceStep(k, k), EmptyReference())))))
        function key(io, event)
            change = read_intent(projection, nothing, Intent(event, nothing), io)
            change isa Intent ? change.operation : change
        end
        backspace() = KeyDown(:backspace, ModifierKeys(); time = 0.0)
        # A view with the cell of `102` open and the caret at its end.
        function open_view(frame = make_frame())
            view = DataFrameView(frame)
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "102")
            evaluate_operation(_DataFrameFilterEditor(view), press(io, x + 2, y + 2))
            set_selection!(view, caret(2, 1, 3))
            (view, io)
        end

        @testset "a key in an open cell edits the document of its entry, and the frame stays" begin
            view, io = open_view()
            editor = _DataFrameFilterEditor(view)
            evaluate_operation(editor, key(io, KeyPress('5'; time = 0.0)))
            entry = only(view.edits)
            @test entry.document.value == 1025
            @test view.frame[2, :id] == 102
            @test "1025" in texts_of(io)
            @test find_value_range(entry.document) == RangeReferenceStep(4, 4)
            # Undo takes a key back by the inverse of the edit.
            op = key(io, KeyPress('9'; time = 0.0))
            inverse = make_inverse_operation(view, op)
            evaluate_operation(editor, op)
            @test only(view.edits).document.value == 10259
            evaluate_operation(editor, inverse)
            @test only(view.edits).document.value == 1025
        end

        @testset "a key that the number of a cell can not show makes a type-in in the entry" begin
            view, io = open_view()
            editor = _DataFrameFilterEditor(view)
            for _ in 1:3
                evaluate_operation(editor, key(io, backspace()))
            end
            @test only(view.edits).document isa PrimitiveInsertion
            @test shown(io, 2, 1) === only(view.edits).document
            evaluate_operation(editor, key(io, KeyPress('-'; time = 0.0)))
            @test only(view.edits).document.value == "-"
            evaluate_operation(editor, key(io, KeyPress('7'; time = 0.0)))
            entry = only(view.edits)
            @test entry.document isa PrimitiveNumber && entry.document.value == -7
            @test shown(io, 2, 1) === entry.document
            @test "-7" in texts_of(io)
            @test view.frame[2, :id] == 102
        end

        @testset "an open cell and its caret stay over a jump far away and back" begin
            frame = DataFrame(id = 101:1100, price = collect(1.0:1000.0))
            view, io = open_view(frame)
            editor = _DataFrameFilterEditor(view)
            evaluate_operation(editor, key(io, KeyPress('5'; time = 0.0)))
            entry = only(view.edits)
            evaluate_operation(editor, jump_to_row(view, 500))
            @test !("1025" in texts_of(io))
            evaluate_operation(editor, jump_to_row(view, 1))
            @test only(view.edits) === entry
            @test shown(io, 2, 1) === entry.document
            @test "1025" in texts_of(io)
            @test find_value_range(entry.document) == RangeReferenceStep(4, 4)
            # The caret goes on in the same cell.
            evaluate_operation(editor, key(io, KeyPress('7'; time = 0.0)))
            @test entry.document.value == 10257
        end

        @testset "through a real editor, a click opens a cell, a key edits it, and Ctrl+Z takes it back" begin
            view = DataFrameView(make_frame())
            backend = _ColumnWidthBackend()
            editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend, devices = Device[Keyboard(), Mouse(), Display()], tabs = false,
                                  undo = true, window = (; title = "W", width = 900, height = 400))
            run_frame!(editor)
            send!(event) = (push!(backend.events, WindowInput(:W, event)); run_frame!(editor))
            drawn() = [t[3] for t in _data_frame_texts(last(backend.rendered).windows[1].content)]
            (x, y) = only((t[1], t[2]) for t in _data_frame_texts(last(backend.rendered).windows[1].content)
                          if t[3] == "102")
            # A press past the end of the text puts the caret at its end.
            send!(MouseDown(:left, x + 30, y + 2, ModifierKeys(); time = 1.0))
            send!(MouseUp(:left, x + 30, y + 2, ModifierKeys(); time = 1.05))
            @test length(view.edits) == 1
            send!(KeyPress('5'; time = 1.2))
            @test only(view.edits).document.value == 1025
            @test "1025" in drawn()
            send!(KeyDown(:z, ModifierKeys(ctrl = true); time = 1.3))
            @test only(view.edits).document.value == 102
            @test view.frame[2, :id] == 102
        end

        @testset "the table holds the cell open: Escape drops it, and a reason marks it" begin
            view, io = open_view()
            table = table_of(io)
            @test table.open_cells == Any[(row = 2, column = 1, reason = nothing)]
            # A reason of the entry is the mark of the cell.
            getfield(only(view.edits), :reason)[] = "not an Int"
            @test only(table.open_cells).reason == "not an Int"
            # Escape drops the entry and selects the whole cell.
            evaluate_operation(_DataFrameFilterEditor(view), key(io, KeyDown(:escape, ModifierKeys(); time = 0.0)))
            @test isempty(view.edits)
            @test isempty(table.open_cells)
            @test strip_reference_types(get_selection(view)) ==
                  ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(1, 2),
                      ConcreteReference(RangeReferenceStep(0, 1), EmptyReference())))
            @test shown(io, 2, 1) isa PrimitiveNumber && shown(io, 2, 1).value == 102
        end

        enter() = KeyDown(:return, ModifierKeys(); time = 0.0)
        whole(r, c) = ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(r - 1, r),
            ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))
        # Open the cell that shows `text` with the caret at the end of `text`.
        function open_cell!(view, io, text, r, c)
            (x, y) = place_of(io, text)
            evaluate_operation(_DataFrameFilterEditor(view), press(io, x + 2, y + 2))
            set_selection!(view, caret(r, c, length(text)))
        end

        @testset "Enter commits the value of an open cell into the frame, as one step of undo" begin
            view, io = open_view()
            editor = _DataFrameFilterEditor(view)
            evaluate_operation(editor, key(io, KeyPress('5'; time = 0.0)))
            version = view.frame_version
            commit = key(io, enter())
            @test is_undo_step(nothing, commit)
            inverse = evaluate_invertible_operation!(editor, commit)
            @test view.frame[2, :id] == 1025
            @test isempty(view.edits) && isempty(table_of(io).open_cells)
            @test view.frame_version > version
            @test strip_reference_types(get_selection(view)) == whole(2, 1)
            @test "1025" in texts_of(io) && shown(io, 2, 1).value == 1025
            # The undo puts the value back and opens the cell again with the text
            # of the edit, so the key before it takes back a key that shows.
            redo = evaluate_invertible_operation!(editor, inverse)
            @test view.frame[2, :id] == 102
            @test only(view.edits).document.value == 1025
            @test strip_reference_types(get_selection(view)) == caret(2, 1, 4)
            @test shown(io, 2, 1).value == 1025 && only(table_of(io).open_cells).row == 2
            evaluate_operation(editor, redo)
            @test view.frame[2, :id] == 1025 && isempty(view.edits)
            @test strip_reference_types(get_selection(view)) == whole(2, 1)
        end

        @testset "Escape after a key is a step of undo, and Escape with no change is none" begin
            view, io = open_view()
            editor = _DataFrameFilterEditor(view)
            escape = KeyDown(:escape, ModifierKeys(); time = 0.0)
            @test !is_undo_step(nothing, key(io, escape))
            evaluate_operation(editor, key(io, KeyPress('5'; time = 0.0)))
            drop = key(io, escape)
            @test is_undo_step(nothing, drop)
            inverse = evaluate_invertible_operation!(editor, drop)
            @test isempty(view.edits) && view.frame[2, :id] == 102
            evaluate_operation(editor, inverse)
            @test only(view.edits).document.value == 1025
            @test strip_reference_types(get_selection(view)) == caret(2, 1, 4)
        end

        @testset "a value that does not convert keeps the cell open, with the reason as its mark" begin
            view, io = open_view()
            editor = _DataFrameFilterEditor(view)
            for character in ('.', '5')
                evaluate_operation(editor, key(io, KeyPress(character; time = 0.0)))
            end
            evaluate_operation(editor, key(io, enter()))
            @test view.frame[2, :id] == 102
            entry = only(view.edits)
            @test entry.reason == "102.5 is not a value of type Int64"
            @test only(table_of(io).open_cells).reason == entry.reason
            # An empty text in a column of no missing value has a reason too.
            for _ in 1:5
                evaluate_operation(editor, key(io, backspace()))
            end
            evaluate_operation(editor, key(io, enter()))
            @test only(view.edits).reason == "A column of type Int64 takes no missing value"
            @test view.frame[2, :id] == 102
        end

        @testset "an empty text writes missing where the column allows it" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            editor = _DataFrameFilterEditor(view)
            open_cell!(view, io, "1.5", 1, 5)
            for _ in 1:3
                evaluate_operation(editor, key(io, backspace()))
            end
            evaluate_operation(editor, key(io, enter()))
            @test ismissing(view.frame[1, :price])
            @test isempty(view.edits)
        end

        @testset "a move out of an open cell commits it, and Tab commits a string" begin
            view, io = open_view()
            editor = _DataFrameFilterEditor(view)
            (x, y) = place_of(io, "alpha")
            @test !is_undo_step(nothing, press(io, x + 2, y + 2))
            evaluate_operation(editor, key(io, KeyPress('5'; time = 0.0)))
            move = press(io, x + 2, y + 2)
            @test is_undo_step(nothing, move)
            inverse = evaluate_invertible_operation!(editor, move)
            @test view.frame[2, :id] == 1025
            entry = only(view.edits)
            @test entry.row == 1 && entry.column == "name"
            # The undo opens the cell that the move left, and closes the cell
            # that it opened.
            redo = evaluate_invertible_operation!(editor, inverse)
            @test view.frame[2, :id] == 102
            @test only(view.edits).row == 2 && only(view.edits).document.value == 1025
            @test strip_reference_types(get_selection(view)) == caret(2, 1, 4)
            evaluate_operation(editor, redo)
            @test view.frame[2, :id] == 1025
            entry = only(view.edits)
            @test entry.row == 1 && entry.column == "name"
            set_selection!(view, caret(1, 2, 5))
            evaluate_operation(editor, key(io, KeyPress('x'; time = 0.0)))
            evaluate_operation(editor, key(io, KeyDown(:tab, ModifierKeys(); time = 0.0)))
            @test view.frame[1, :name] == "alphax"
            @test isempty(view.edits)
        end

        @testset "a Bool commits the value that its keys give, and an unchanged value writes nothing" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            editor = _DataFrameFilterEditor(view)
            (x, y) = place_of(io, "false")
            evaluate_operation(editor, press(io, x + 2, y + 2))
            evaluate_operation(editor, key(io, KeyPress('t'; time = 0.0)))
            evaluate_operation(editor, key(io, enter()))
            @test view.frame[2, :ok] == true
            version = view.frame_version
            open_cell!(view, io, "103", 3, 1)
            evaluate_operation(editor, key(io, enter()))
            @test view.frame_version == version && isempty(view.edits)
        end

        @testset "a view of a SubDataFrame writes through to its parent" begin
            parent = make_frame()
            view = DataFrameView(@view parent[2:3, :])
            io = print_document(projection, nothing, view, context())
            editor = _DataFrameFilterEditor(view)
            open_cell!(view, io, "102", 1, 1)
            evaluate_operation(editor, key(io, KeyPress('7'; time = 0.0)))
            evaluate_operation(editor, key(io, enter()))
            @test parent[2, :id] == 1027
        end

        @testset "through a real editor, Enter commits and Ctrl+Z takes the commit back" begin
            view = DataFrameView(make_frame())
            backend = _ColumnWidthBackend()
            editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend, devices = Device[Keyboard(), Mouse(), Display()], tabs = false,
                                  undo = true, window = (; title = "W", width = 900, height = 400))
            run_frame!(editor)
            send!(event) = (push!(backend.events, WindowInput(:W, event)); run_frame!(editor))
            (x, y) = only((t[1], t[2]) for t in _data_frame_texts(last(backend.rendered).windows[1].content)
                          if t[3] == "102")
            send!(MouseDown(:left, x + 30, y + 2, ModifierKeys(); time = 1.0))
            send!(MouseUp(:left, x + 30, y + 2, ModifierKeys(); time = 1.05))
            send!(KeyPress('5'; time = 1.2))
            send!(KeyDown(:return, ModifierKeys(); time = 1.3))
            @test view.frame[2, :id] == 1025 && isempty(view.edits)
            # The first Ctrl+Z takes the commit back and opens the cell with the
            # text of the edit; the second takes the key back.
            send!(KeyDown(:z, ModifierKeys(ctrl = true); time = 1.4))
            @test view.frame[2, :id] == 102 && only(view.edits).document.value == 1025
            send!(KeyDown(:z, ModifierKeys(ctrl = true); time = 1.5))
            @test only(view.edits).document.value == 102
            send!(KeyDown(:y, ModifierKeys(ctrl = true); time = 1.6))
            send!(KeyDown(:y, ModifierKeys(ctrl = true); time = 1.7))
            @test view.frame[2, :id] == 1025 && isempty(view.edits)
        end

        @testset "a duplicate opens no cell of its original" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "102")
            evaluate_operation(_DataFrameFilterEditor(view), press(io, x + 2, y + 2))
            @test isempty(copy_document(DuplicatePolicy(), view).edits)
        end
    end
end
