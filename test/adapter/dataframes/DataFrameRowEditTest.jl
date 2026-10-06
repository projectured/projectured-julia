"""
    test_data_frame_row_edits()

The menu of a row inserts a row above or below it, and deletes it. Each is one
step of undo, which the view makes with the selection, the entries that name a
later row, and the place of the view.
"""
function test_data_frame_row_edits()
    @testset "the insert and the delete of a row" begin
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        make_frame() = DataFrame(name = ["a", "b", "c"], price = [1.5, 2.5, 3.5], count = [10, 20, 30],
                                 ok = [true, false, true])
        labels_of(menu) = [item.action.label for item in menu.elements if item isa WidgetMenuItem]
        item_of(menu, label) = only(item for item in menu.elements
                                    if item isa WidgetMenuItem && item.action.label == label)
        whole_row(r) = ConcreteReference(FieldReferenceStep("rows"),
                                         ConcreteReference(RangeReferenceStep(r - 1, r), EmptyReference()))
        whole(r, c) = ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(r - 1, r),
            ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))
        row_of(view, r) = try_evaluate_reference(view, whole_row(r))

        @testset "the menu of a row inserts and deletes, and a SubDataFrame takes neither" begin
            view = DataFrameView(make_frame())
            menu = compute_context_menu(row_of(view, 2))
            @test labels_of(menu) == ["Open as a page", "Open in a new tab",
                                      "Insert row above", "Insert row below", "Delete row"]
            @test all(item.enabled for item in menu.elements if item isa WidgetMenuItem)
            above = item_of(menu, "Insert row above").operation
            @test above isa InsertDataFrameRowOperation && above.row == 2
            @test isequal(above.values, Any["", 0.0, 0, false])
            @test item_of(menu, "Insert row below").operation.row == 3
            @test item_of(menu, "Delete row").operation == DeleteDataFrameRowOperation(view, 2)
            sub = DataFrameView(@view make_frame()[1:2, :])
            # The open of the row stays; the insert and the delete are off.
            sub_menu = compute_context_menu(row_of(sub, 1))
            @test !any(item_of(sub_menu, label).enabled
                       for label in ("Insert row above", "Insert row below", "Delete row"))
            @test item_of(sub_menu, "Open as a page").enabled
            # A column of a type with no value for a new row and no `missing`
            # takes no insert.
            tagged = DataFrameView(DataFrame(tag = [:x, :y]))
            menu = compute_context_menu(row_of(tagged, 1))
            @test !item_of(menu, "Insert row above").enabled && item_of(menu, "Delete row").enabled
            # A column that allows `missing` gets it.
            optional = DataFrameView(DataFrame(tag = Union{Missing,Symbol}[:x, missing]))
            @test isequal(item_of(compute_context_menu(row_of(optional, 1)), "Insert row above").operation.values,
                          Any[missing])
        end

        @testset "an insert and a delete are each the inverse of the other, and move the entries" begin
            view = DataFrameView(make_frame())
            editor = _DataFrameFilterEditor(view)
            getfield(view, :edits)[] = Any[DataFrameCellEdit(3, "price", PrimitiveNumber(3.5), nothing)]
            version = view.frame_version
            inverse = evaluate_invertible_operation!(editor,
                InsertDataFrameRowOperation(view, 2, Any["x", 0.0, 0, false]))
            @test view.frame.name == ["a", "x", "b", "c"] && only(view.edits).row == 4
            @test view.frame_version > version
            evaluate_operation(editor, inverse)
            @test view.frame.name == ["a", "b", "c"] && only(view.edits).row == 3
            inverse = evaluate_invertible_operation!(editor, DeleteDataFrameRowOperation(view, 1))
            @test view.frame.name == ["b", "c"] && only(view.edits).row == 2
            evaluate_operation(editor, inverse)
            @test view.frame.name == ["a", "b", "c"] && view.frame[1, :price] == 1.5
            @test only(view.edits).row == 3
        end

        @testset "through a real editor, the menu of a row header inserts and deletes, and Ctrl+Z takes each back" begin
            view = DataFrameView(make_frame())
            backend = _ColumnWidthBackend()
            # The menu window draws with a renderer of its own, as in the display.
            opened = Pair{Type,Any}[Document => NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))]
            editor = build_editor(view, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                                  tabs = false, undo = true,
                                  window = (; title = "W", width = 600, height = 300,
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
            # A right click on the header of the row that shows `header`, and a
            # choice of `label` in its menu. The corner shows the count of the
            # rows above the headers, so the header is the lowest such text.
            function choose!(header, label, time)
                (x, y) = last(sort([(t[1], t[2]) for t in _data_frame_texts(force(first(windows()).content))
                                    if t[3] == header]; by = last))
                click!(:right, x + 2, y + 2, time, main)
                menu = only(window for window in windows() if window.id !== main)
                (x, y) = place_in(menu, label)
                click!(:left, x + 2, y + 2, time + 0.5, menu.id)
            end
            undo!(time) = send!(KeyDown(:z, ModifierKeys(ctrl = true); time), main)
            choose!("2", "Insert row above", 1.0)
            @test view.frame.name == ["a", "", "b", "c"] && view.frame[2, :count] == 0
            @test strip_reference_types(get_selection(view)) == whole(2, 1)
            undo!(2.0)
            @test view.frame.name == ["a", "b", "c"]
            choose!("2", "Insert row below", 3.0)
            @test view.frame.name == ["a", "b", "", "c"]
            @test strip_reference_types(get_selection(view)) == whole(3, 1)
            undo!(4.0)
            # The new row below the last row is a row that the selection names
            # only after the insert.
            choose!("3", "Insert row below", 4.5)
            @test view.frame.name == ["a", "b", "c", ""]
            @test strip_reference_types(get_selection(view)) == whole(4, 1)
            undo!(4.8)
            @test view.frame.name == ["a", "b", "c"]
            choose!("2", "Delete row", 5.0)
            @test view.frame.name == ["a", "c"]
            @test strip_reference_types(get_selection(view)) == whole_row(2)
            undo!(6.0)
            @test view.frame.name == ["a", "b", "c"] && view.frame[2, :count] == 20
        end
    end
end
