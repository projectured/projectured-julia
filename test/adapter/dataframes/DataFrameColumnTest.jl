"""
    test_data_frame_columns()

A column of a view is a place in it: a press on a header selects the column, a
path names the column by its name, the menu of its header hides it, and the menu
of the view, which the corner reaches, shows it again.
"""
function test_data_frame_columns()
    @testset "a column of a view" begin
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)),
                                    height = Cell(Int32(300)))
        # A frame of 1000 rows, so the count in the corner is no text that a
        # row near the top shows.
        make_frame() = DataFrame(id = 1:1000, name = ["item $(i)" for i in 1:1000],
                                 price = collect(1.0:1000.0))
        texts_of(io) = _data_frame_texts(io.output)
        place_of(io, text) = only((t[1], t[2]) for t in texts_of(io) if t[3] == text)
        function press(io, x, y)
            change = read_intent(projection, nothing,
                                 Intent(MouseClick(:left, x, y, ModifierKeys(); time = 0.0), nothing), io)
            change isa Intent ? change.operation : change
        end
        table_of(io) = _data_frame_table_iomap(io).input
        header_reference(c) = ConcreteReference(FieldReferenceStep("column_headers"),
            ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
        module_ = ProjecturedDataFrames.DataFramesModule
        labels_of(menu) = [item.action.label for item in menu.elements]
        item_of(menu, label) = only(item for item in menu.elements if item.action.label == label)

        @testset "a press on a header selects its column, and the header shows it" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "name :: String")
            op = press(io, x + 2, y + 2)
            @test op isa ReplaceSelectionOperation
            @test strip_reference_types(op.path).head == DataFrameColumnReferenceStep("name")
            column = try_evaluate_reference(view, op.path)
            @test column isa DataFrameColumn && column.view === view && column.name == "name"
            # The table shows the selection of the view on the header of the column.
            getfield(view, :selection)[] = op.path
            @test strip_reference_types(table_of(io).selection) == header_reference(2)
        end

        @testset "a press on the corner selects the view" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "1000")
            op = press(io, x + 2, y + 2)
            @test op isa ReplaceSelectionOperation
            @test strip_reference_types(op.path) isa EmptyReference
        end

        @testset "the menu of a header hides its column, and the menu of the view shows it again" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            @test compute_context_menu(view) === nothing
            menu = compute_context_menu(DataFrameColumn(view, "name"))
            @test labels_of(menu) == ["Filter by values…", "Hide column"]
            @test item_of(menu, "Hide column").enabled
            evaluate_operation(nothing, module_._make_hide_column_operation(view, "name"))
            @test view.query.hidden_columns == ["name"]
            # The table that was printed follows the query.
            found = Set(t[3] for t in texts_of(io))
            @test "name :: String" ∉ found
            @test "item 1" ∉ found
            @test "price :: Float64" in found
            labels = [item.action.label for item in compute_context_menu(view).elements]
            @test labels == ["Show all columns", "Show name"]
            evaluate_operation(nothing, module_._make_show_column_operation(view, "name"))
            @test isempty(view.query.hidden_columns)
            @test "name :: String" in Set(t[3] for t in texts_of(io))
            @test compute_context_menu(view) === nothing
        end

        @testset "a right click on a header or on the corner answers its menu" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            # A container gives a right click to the view as to any child: the view
            # and its table answer nothing, and the documents under the point read
            # the click with their own gesture tables.
            function right(x, y)
                click = MouseClick(:right, x, y, ModifierKeys(); time = 0.0)
                answer = read_child_event(io, click)
                answer isa ReplaceViewStateOperation ?
                    get_wrapped_operation(answer) : answer
            end
            titles_of(opened) = [title for (title, _) in opened.layers]
            menu_labels(opened) = labels_of(only(opened.layers)[2])
            (x, y) = place_of(io, "name :: String")
            opened = right(x + 2, y + 2)
            @test opened isa OpenContextMenuOperation
            @test titles_of(opened) == ["name"]
            @test menu_labels(opened) == ["Filter by values…", "Hide column"]
            @test opened.point == (x + 2, y + 2)
            column = ConcreteReference(DataFrameColumnReferenceStep("name"),
                                       EmptyReference())
            @test strip_reference_types(opened.source) == column
            # The corner opens the menu of the view once a column is hidden, and a
            # header then gives its own menu first and the menu of the view after it.
            hide = module_._make_hide_column_operation(view, "price")
            evaluate_operation(nothing, hide)
            (x, y) = place_of(io, "1000")
            opened = right(x + 2, y + 2)
            @test titles_of(opened) == ["DataFrameView"]
            @test menu_labels(opened) == ["Show all columns", "Show price"]
            (x, y) = place_of(io, "name :: String")
            @test titles_of(right(x + 2, y + 2)) == ["name", "DataFrameView"]
        end

        @testset "the column and the view bind their menus to a right click" begin
            view = DataFrameView(make_frame())
            click = MouseClick(:right, 0, 0, ModifierKeys(); time = 0.0)
            column = DataFrameColumn(view, "name")
            opened = get_wrapped_operation(read_gesture(column, click))
            @test opened isa OpenContextMenuOperation
            labels = labels_of(last(only(opened.layers)))
            @test labels == ["Filter by values…", "Hide column"]
            # The view has no menu while every column shows.
            @test read_gesture(view, click) === nothing
        end

        @testset "the last column that the view shows can not be hidden" begin
            view = DataFrameView(DataFrame(id = 1:3))
            @test !item_of(compute_context_menu(DataFrameColumn(view, "id")), "Hide column").enabled
        end

        @testset "a path to a column that the frame does not have names nothing" begin
            view = DataFrameView(make_frame())
            missing_column = ConcreteReference(DataFrameColumnReferenceStep("none"), EmptyReference())
            @test try_evaluate_reference(view, missing_column) === nothing
        end

        @testset "in a frame of many columns, a press on a header names its column" begin
            wide = DataFrame([Symbol("c", j) => collect(1:3) for j in 1:200])
            view = DataFrameView(wide; column_anchor = 50)
            io = print_document(projection, nothing, view, context())
            (x, y) = place_of(io, "c51 :: Int64")
            op = press(io, x + 2, y + 2)
            @test strip_reference_types(op.path).head == DataFrameColumnReferenceStep("c51")
            getfield(view, :selection)[] = op.path
            @test strip_reference_types(table_of(io).selection) == header_reference(2)
        end
    end
end
