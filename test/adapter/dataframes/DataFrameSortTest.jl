"""
    test_data_frame_sort()

The order of the rows of a view: the keys after a click and a Shift+click on the
glyph of a header, the kept rows in the order of the keys, and the glyph that
shows the order.
"""
function test_data_frame_sort()
    @testset "the order of the rows of a view" begin
        module_ = ProjecturedDataFrames.DataFramesModule
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        # Wide enough that the three headers, each with its glyph, show whole.
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(900)),
                                    height = Cell(Int32(300)))
        make_frame() = DataFrame(id = 1:6, kind = ["b", "a", "b", "c", "a", "b"],
                                 price = [3.0, 1.0, 2.0, 5.0, 4.0, 1.0])
        keys_of(view) = [(key.column, key.descending) for key in view.query.sort_keys]
        click!(view, name; adding = false) =
            evaluate_operation(_DataFrameFilterEditor(view), module_._make_sort_operation(view, name, adding))

        @testset "a click sorts by the column alone and turns its order, and a Shift+click adds a key" begin
            view = DataFrameView(make_frame())
            click!(view, "price")
            @test keys_of(view) == [("price", false)]
            @test view.kept_rows == [2, 6, 3, 1, 5, 4]
            click!(view, "price")
            @test keys_of(view) == [("price", true)]
            @test view.kept_rows == [4, 5, 1, 3, 2, 6]
            click!(view, "price")
            @test isempty(keys_of(view))
            @test view.kept_rows == 1:6
            click!(view, "kind")
            click!(view, "price"; adding = true)
            @test keys_of(view) == [("kind", false), ("price", false)]
            @test view.kept_rows == [2, 5, 6, 3, 1, 4]
            click!(view, "price"; adding = true)
            @test keys_of(view) == [("kind", false), ("price", true)]
            click!(view, "price"; adding = true)
            @test keys_of(view) == [("kind", false)]
            # A plain click on another column sorts by it alone.
            click!(view, "id")
            @test keys_of(view) == [("id", false)]
        end

        @testset "the filters and the order work together" begin
            view = DataFrameView(make_frame())
            getfield(module_._find_column_filter(view.query, "kind"), :text)[] = "= b"
            click!(view, "price")
            @test view.kept_rows == [6, 3, 1]
        end

        @testset "the glyph of a header shows the order, and a click on it sorts" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            unsorted, up = string(Char(0xe37d)), string(Char(0xe04a))
            # The glyphs of the headers, from the left: id, kind, price.
            glyphs(text) = sort([(t[1], t[2]) for t in _data_frame_texts(io.output) if t[3] == text])
            function press(x, y; shift = false)
                change = read_intent(projection, nothing,
                                     Intent(MouseClick(:left, x + 2, y + 2, ModifierKeys(; shift); time = 0.0),
                                            nothing), io)
                evaluate_operation(_DataFrameFilterEditor(view), change isa Intent ? change.operation : change)
            end
            @test length(glyphs(unsorted)) == 3
            press(glyphs(unsorted)[3]...)
            @test keys_of(view) == [("price", false)]
            @test length(glyphs(up)) == 1 && length(glyphs(unsorted)) == 2
            # A Shift+click on the glyph of kind adds it, and each sorted header
            # shows the place of its key.
            press(glyphs(unsorted)[2]...; shift = true)
            @test keys_of(view) == [("price", false), ("kind", false)]
            found = Set(t[3] for t in _data_frame_texts(io.output))
            @test "1" in found && "2" in found
        end
    end
end
