"""
    test_data_frame_refresh()

A view reads its frame again after a program changed it in place: a written
value, a pushed row, a value that the table does not show but that a filter
reads, and a new column. A refresh with no change moves nothing, and F5 reads
the frame again in any case.
"""
function test_data_frame_refresh()
    @testset "the refresh of a view" begin
        module_ = ProjecturedDataFrames.DataFramesModule
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(900)),
                                    height = Cell(Int32(300)))
        texts_of(io) = Set(t[3] for t in _data_frame_texts(io.output))

        @testset "a refresh with no change moves nothing, after the first" begin
            view = DataFrameView(DataFrame(id = 1:10))
            refresh_document!(view)
            version = view.frame_version
            refresh_document!(view)
            @test view.frame_version == version
        end

        @testset "a value written in place shows after a refresh" begin
            frame = DataFrame(id = 1:10, name = ["item $(i)" for i in 1:10])
            view = DataFrameView(frame)
            io = print_document(projection, nothing, view, context())
            refresh_document!(view)
            # The table builds its rows when they are first read.
            @test "item 2" in texts_of(io)
            frame.name[2] = "changed"
            @test "changed" ∉ texts_of(io)
            refresh_document!(view)
            @test "changed" in texts_of(io)
            @test "item 2" ∉ texts_of(io)
        end

        @testset "a pushed row shows after a refresh" begin
            frame = DataFrame(id = 1:3, name = ["a", "b", "c"])
            view = DataFrameView(frame)
            io = print_document(projection, nothing, view, context())
            push!(frame, (id = 4, name = "d"))
            refresh_document!(view)
            @test view.kept_rows == 1:4
            @test "d" in texts_of(io)
        end

        @testset "a value that the table does not show changes which rows pass" begin
            frame = DataFrame(id = 1:10_000, price = zeros(10_000))
            view = DataFrameView(frame)
            getfield(module_._find_column_filter(view.query, "price"), :text)[] = "> 0"
            @test isempty(view.kept_rows)
            frame.price[9_000] = 1.0
            refresh_document!(view)
            @test view.kept_rows == [9_000]
        end

        @testset "a new column gets a header and a filter" begin
            frame = DataFrame(id = 1:3)
            view = DataFrameView(frame)
            io = print_document(projection, nothing, view, context())
            frame.extra = ["a", "b", "c"]
            refresh_document!(view)
            @test "extra :: String" in texts_of(io)
            @test module_._find_column_filter(view.query, "extra") !== nothing
        end

        @testset "the glyph at the right end of the top bar reads the frame again" begin
            view = DataFrameView(DataFrame(id = 1:3))
            io = print_document(projection, nothing, view, context())
            version = view.frame_version
            (x, y) = only((t[1], t[2]) for t in _data_frame_texts(io.output) if t[3] == string(Char(0xe145)))
            # It sits at the right end of the bar, past the field of the expression.
            @test x > 700
            change = read_intent(projection, nothing,
                                 Intent(MouseClick(:left, x + 2, y + 2, ModifierKeys(); time = 0.0), nothing), io)
            op = change isa Intent ? change.operation : change
            @test op isa RefreshDataFrameViewOperation
            evaluate_operation(nothing, op)
            @test view.frame_version == version + 1
        end

        @testset "F5 reads the frame again, also with no change" begin
            view = DataFrameView(DataFrame(id = 1:3))
            io = print_document(projection, nothing, view, context())
            version = view.frame_version
            change = read_intent(projection, nothing, Intent(KeyDown(:f5, ModifierKeys(); time = 0.0), nothing), io)
            op = change isa Intent ? change.operation : change
            @test op isa RefreshDataFrameViewOperation
            evaluate_operation(nothing, op)
            @test view.frame_version == version + 1
        end
    end
end
