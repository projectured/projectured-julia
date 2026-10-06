"""
    test_data_frame_paths()

A path of a view names a row and a column of the frame by their numbers:
`rows[r]`, `columns[c]` and `rows[r][c]`. The view maps them to its table, whose
rows count from the head of its list, and back, so a sort and a hidden column do
not change what a path names.
"""
function test_data_frame_paths()
    @testset "the paths of a view" begin
        module_ = ProjecturedDataFrames.DataFramesModule
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(900)),
                                    height = Cell(Int32(300)))
        # The ids are not row numbers, so a text names one place.
        make_frame() = DataFrame(id = 101:106, kind = ["b", "a", "b", "c", "a", "b"],
                                 price = [3.0, 1.0, 2.0, 5.0, 4.0, 1.0])
        element(field, i, tail = EmptyReference()) =
            ConcreteReference(FieldReferenceStep(field), ConcreteReference(RangeReferenceStep(i - 1, i), tail))
        cell(r, c) = element("rows", r, ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
        # A cell of the table, which names it by `cells`.
        table_cell(k, j) = element("cells", k, ConcreteReference(RangeReferenceStep(j - 1, j), EmptyReference()))
        table_of(io) = _data_frame_table_iomap(io).input
        table_selection(io) = (s = table_of(io).selection; s === nothing ? nothing : strip_reference_types(s))
        place_of(io, text) = only((t[1], t[2]) for t in _data_frame_texts(io.output) if t[3] == text)
        function press(io, x, y; alt = false)
            change = read_intent(projection, nothing,
                                 Intent(MouseClick(:left, x, y, ModifierKeys(; alt); time = 0.0), nothing), io)
            change isa Intent ? change.operation : change
        end
        sort!(view, name) =
            evaluate_operation(_DataFrameFilterEditor(view), module_._make_sort_operation(view, name, false))

        @testset "a row, a column and a cell of the frame evaluate on the view" begin
            view = DataFrameView(make_frame())
            @test try_evaluate_reference(view, element("rows", 2)) isa DataFrameViewRow
            @test try_evaluate_reference(view, cell(2, 3)) == 1.0
            column = try_evaluate_reference(view, element("columns", 2))
            @test column isa DataFrameColumn && column.name == "kind" && column.view === view
            @test try_evaluate_reference(view, element("rows", 7)) === nothing
            @test try_evaluate_reference(view, cell(2, 4)) === nothing
        end

        @testset "a press on a row header selects the row of the frame, which a sort keeps" begin
            view = DataFrameView(make_frame())
            sort!(view, "price")                 # the kept rows: 2, 6, 3, 1, 5, 4
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "1")           # the header of row 1 of the frame, fourth
            op = press(io, x + 2, y + 2)
            @test strip_reference_types(op.path) == element("rows", 1)
            getfield(view, :selection)[] = op.path
            @test table_selection(io) == element("rows", 4)
            sort!(view, "price")                 # the other order: 4, 5, 1, 3, 2, 6
            @test table_selection(io) == element("rows", 3)
        end

        @testset "an Alt+press on a cell selects the cell of the frame" begin
            view = DataFrameView(make_frame())
            sort!(view, "price")
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "102")         # the id of row 2 of the frame, first
            op = press(io, x + 2, y + 2; alt = true)
            @test strip_reference_types(op.path) == cell(2, 1)
            getfield(view, :selection)[] = op.path
            @test table_selection(io) == table_cell(1, 1)
        end

        @testset "a hidden column keeps its path, and the table shows it again with the column" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            getfield(view, :selection)[] = element("columns", 3)
            @test table_selection(io) == element("columns", 3)
            evaluate_operation(nothing, module_._make_hidden_columns_operation(view, ["kind"]))
            @test table_selection(io) == element("columns", 2)
            evaluate_operation(nothing, module_._make_hidden_columns_operation(view, ["price"]))
            @test table_selection(io) === nothing
            evaluate_operation(nothing, module_._make_hidden_columns_operation(view, String[]))
            @test table_selection(io) == element("columns", 3)
        end

        @testset "a duplicate steps through its own rows and columns" begin
            view = DataFrameView(make_frame())
            copy = copy_document(DuplicatePolicy(), view)
            @test getfield(copy, :rows)[].view === copy
            @test getfield(copy, :columns)[].view === copy
            @test try_evaluate_reference(copy, element("columns", 1)).view === copy
        end
    end
end
