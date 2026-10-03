"""
    test_data_frame_column_edits()

The menu of the header of a column inserts a column of text before or after it,
moves it past the shown column on its left or on its right, and deletes it. Each
is one step of undo, which the view makes with the selection of the column that
the change leaves.
"""
function test_data_frame_column_edits()
    @testset "the insert, the delete and the move of a column" begin
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        make_frame() = DataFrame(name = ["a", "b", "c"], price = [1.5, 2.5, 3.5], count = [10, 20, 30])
        module_ = ProjecturedDataFrames.DataFramesModule
        item_of(menu, label) =
            only(item for item in menu.elements if item isa WidgetMenuItem && item.action.label == label)
        column(c) = ConcreteReference(FieldReferenceStep("columns"),
                                      ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
        menu_of(view, name) = compute_context_menu(DataFrameColumn(view, name))

        @testset "the items of the menu of a header, and what they take" begin
            view = DataFrameView(make_frame())
            menu = menu_of(view, "name")
            @test item_of(menu, "Insert column before").operation ==
                  InsertDataFrameColumnOperation(view, 1, "column 4", item_of(menu, "Insert column before").operation.vector)
            @test eltype(item_of(menu, "Insert column after").operation.vector) == Union{Missing,String}
            @test item_of(menu, "Insert column after").operation.index == 2
            @test !item_of(menu, "Move column left").enabled
            @test item_of(menu, "Move column right").operation == MoveDataFrameColumnOperation(view, "name", 2)
            @test item_of(menu_of(view, "count"), "Move column left").operation ==
                  MoveDataFrameColumnOperation(view, "count", 2)
            @test !item_of(menu_of(view, "count"), "Move column right").enabled
            # A move goes past a hidden column to the shown one.
            evaluate_operation(nothing, module_._make_hidden_columns_operation(view, ["price"]))
            @test item_of(menu_of(view, "name"), "Move column right").operation ==
                  MoveDataFrameColumnOperation(view, "name", 3)
            @test !item_of(menu_of(DataFrameView(DataFrame(x = [1])), "x"), "Delete column").enabled
            sub = DataFrameView(@view make_frame()[1:2, :])
            @test !any(item -> item isa WidgetMenuItem && item.enabled &&
                               item.action.label in ("Insert column before", "Delete column"), menu_of(sub, "name").elements)
        end

        @testset "each operation has its inverse, and the undo of a delete puts back the same vector" begin
            view = DataFrameView(make_frame())
            editor = _DataFrameFilterEditor(view)
            version = view.frame_version
            inverse = evaluate_invertible_operation!(editor,
                InsertDataFrameColumnOperation(view, 2, "column 4", Union{Missing,String}[missing, missing, missing]))
            @test names(view.frame) == ["name", "column 4", "price", "count"] && view.frame_version > version
            evaluate_operation(editor, inverse)
            @test names(view.frame) == ["name", "price", "count"]
            vector = view.frame[!, :price]
            inverse = evaluate_invertible_operation!(editor, DeleteDataFrameColumnOperation(view, "price"))
            @test names(view.frame) == ["name", "count"]
            evaluate_operation(editor, inverse)
            @test names(view.frame) == ["name", "price", "count"] && view.frame[!, :price] === vector
            inverse = evaluate_invertible_operation!(editor, MoveDataFrameColumnOperation(view, "name", 3))
            @test names(view.frame) == ["price", "count", "name"]
            evaluate_operation(editor, inverse)
            @test names(view.frame) == ["name", "price", "count"]
        end

        @testset "through a real editor, the menu of a header changes the columns, and Ctrl+Z takes each back" begin
            view = DataFrameView(make_frame())
            backend = _ColumnWidthBackend()
            # The menu window draws with a renderer of its own, as in the display.
            opened = Pair{Type,Any}[Document => NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))]
            editor = build_editor(view, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                                  tabs = false, undo = true,
                                  window = (; title = "W", width = 900, height = 300,
                                            opened_window_projections = opened))
            run_frame!(editor)
            force(value) = value isa AbstractCell ? force(value[]) : value
            send!(event, window) = (push!(backend.events, WindowInput(window, event)); run_frame!(editor))
            function click!(button, x, y, time, window)
                send!(MouseDown(button, x, y, ModifierKeys(); time), window)
                send!(MouseUp(button, x, y, ModifierKeys(); time = time + 0.05), window)
            end
            windows() = collect(force(force(get_iomap_output(editor.iomap)).windows))
            place_in(window, text) =
                only((t[1], t[2]) for t in _data_frame_texts(force(window.content)) if t[3] == text)
            main = first(windows()).id
            function choose!(header, label, time)
                (x, y) = place_in(first(windows()), header)
                click!(:right, x + 2, y + 2, time, main)
                menu = only(window for window in windows() if window.id !== main)
                (x, y) = place_in(menu, label)
                click!(:left, x + 2, y + 2, time + 0.5, menu.id)
            end
            undo!(time) = send!(KeyDown(:z, ModifierKeys(ctrl = true); time), main)
            choose!("price :: Float64", "Insert column after", 1.0)
            @test names(view.frame) == ["name", "price", "column 4", "count"]
            @test strip_reference_types(get_selection(view)) == column(3)
            undo!(2.0)
            @test names(view.frame) == ["name", "price", "count"]
            choose!("count :: Int64", "Insert column after", 3.0)
            @test names(view.frame) == ["name", "price", "count", "column 4"]
            @test strip_reference_types(get_selection(view)) == column(4)
            undo!(4.0)
            choose!("name :: String", "Move column right", 5.0)
            @test names(view.frame) == ["price", "name", "count"]
            @test strip_reference_types(get_selection(view)) == column(2)
            undo!(6.0)
            @test names(view.frame) == ["name", "price", "count"]
            vector = view.frame[!, :price]
            choose!("price :: Float64", "Delete column", 7.0)
            @test names(view.frame) == ["name", "count"]
            @test strip_reference_types(get_selection(view)) == column(2)
            undo!(8.0)
            @test names(view.frame) == ["name", "price", "count"] && view.frame[!, :price] === vector
        end
    end
end
