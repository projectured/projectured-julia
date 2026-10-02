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

        @testset "a duplicate opens no cell of its original" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "102")
            evaluate_operation(_DataFrameFilterEditor(view), press(io, x + 2, y + 2))
            @test isempty(copy_document(DuplicatePolicy(), view).edits)
        end
    end
end
