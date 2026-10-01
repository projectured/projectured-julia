mutable struct _DataFrameDuplicateEditor
    document::Any
end

"""
    test_data_frame_duplicate()

The duplicate of a view, which the "+" of its tab makes: a second view of the
same frame, which owns a copy of the query and of its place, so a filter or a
jump in one does not move the other, and both read a change of the frame.
"""
function test_data_frame_duplicate()
    @testset "the duplicate of a view" begin
        module_ = ProjecturedDataFrames.DataFramesModule
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(900)),
                                    height = Cell(Int32(300)))
        texts_of(io) = Set(t[3] for t in _data_frame_texts(io.output))
        set_filter!(view, column, text) =
            getfield(module_._find_column_filter(view.query, column), :text)[] = text

        @testset "the duplicate shares the frame and owns its query and its place" begin
            frame = DataFrame(id = 1:10, name = ["item $(i)" for i in 1:10])
            view = DataFrameView(frame; anchor = 2)
            getfield(view.query, :expression)[] = "id > 5"
            @test has_document_duplicate(view)
            duplicate = make_document_duplicate(view)
            @test duplicate isa DataFrameView
            @test duplicate.frame === frame
            @test duplicate.query !== view.query
            @test duplicate.query.expression == "id > 5"
            @test duplicate.kept_rows == 6:10
            @test duplicate.anchor == 2
            # A filter and a jump in the duplicate leave the original as it is.
            getfield(duplicate.query, :expression)[] = "id > 8"
            set_filter!(duplicate, "name", "item 1")
            duplicate.anchor = 1
            @test duplicate.kept_rows == [10]
            @test view.kept_rows == 6:10
            @test module_._find_column_filter(view.query, "name").text == ""
            @test view.anchor == 2
            # Each draws its own rows.
            @test "item 10" in texts_of(print_document(projection, nothing, duplicate, context()))
            @test "item 7" ∉ texts_of(print_document(projection, nothing, duplicate, context()))
            # Both read a change of the frame in place after a refresh.
            push!(frame, (11, "item 11"))
            refresh_document!(view)
            refresh_document!(duplicate)
            @test view.kept_rows == 6:11
            @test duplicate.kept_rows == [10, 11]
        end

        @testset "the tab of a view duplicates into the next tab" begin
            view = DataFrameView(DataFrame(id = 1:3))
            group = PaneGroup(PaneTab[PaneTab("frame", view)])
            tree = PaneTree(group)
            operation = make_pane_duplicate_tab_operation(tree, group, 1)
            @test operation !== nothing
            evaluate_operation(_DataFrameDuplicateEditor(tree), operation)
            @test length(group.tabs) == 2
            @test get_pane_tab_title_string(group.tabs[2]) == "frame (2)"
            @test group.tabs[2].content isa DataFrameView
            @test group.tabs[2].content !== view
            @test group.tabs[2].content.frame === view.frame
        end
    end
end
