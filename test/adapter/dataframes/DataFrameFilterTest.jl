"""
    test_data_frame_filter()

The filters of a view: the language of the text of a filter, the rows that pass
every filter, the table that shows them with their row numbers, and the pattern
that keeps the columns by their names.
"""
function test_data_frame_filter()
    @testset "the filters of a view" begin
        module_ = ProjecturedDataFrames.DataFramesModule
        parse(text, type) = module_._parse_column_filter(text, type)
        # The values of `values` that the text of a filter keeps.
        kept(text, values) = (condition = parse(text, eltype(values));
                              [value for value in values if condition(value)])
        numbers = collect(1:20)
        words = ["item 1", "Item 2", "item 12", "other", "a, b"]

        @testset "the language of a filter" begin
            @test parse("", Int) === nothing
            @test parse("   ", Int) === nothing
            @test kept("> 17", numbers) == [18, 19, 20]
            @test kept(">= 19", numbers) == [19, 20]
            @test kept("< 3", numbers) == [1, 2]
            @test kept("<= 2", numbers) == [1, 2]
            @test kept("5..7", numbers) == [5, 6, 7]
            @test kept("= 4, 9", numbers) == [4, 9]
            @test kept("!= 1", numbers[1:3]) == [2, 3]
            # A text with no operator: the printed value contains it, in any case.
            @test kept("1", numbers[1:12]) == [1, 10, 11, 12]
            @test kept("ITEM", words) == ["item 1", "Item 2", "item 12"]
            @test kept("/^item [0-9]\$/", words) == ["item 1"]
            @test kept("= item 1, other", words) == ["item 1", "other"]
            @test kept("= \"a, b\"", words) == ["a, b"]
            @test kept("= true", [true, false, true]) == [true, true]
        end

        @testset "missing passes only missing" begin
            values = Union{Int,Missing}[1, missing, 3]
            @test isequal(kept("missing", values), [missing])
            @test kept("!missing", values) == [1, 3]
            @test kept("> 0", values) == [1, 3]
            @test kept("!= 1", values) == [3]
        end

        @testset "a text that does not parse gives its reason" begin
            @test parse("> abc", Int) isa String
            @test parse("> 3", String) isa String
            @test parse("1..x", Int) isa String
            @test parse("/[/", String) isa String
            @test parse("=", String) isa String
            @test parse("= maybe", Bool) isa String
        end

        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)),
                                    height = Cell(Int32(300)))
        make_frame() = DataFrame(id = 1:1000, name = ["item $(i)" for i in 1:1000],
                                 price = collect(1.0:1000.0))
        texts_of(io) = Set(t[3] for t in _data_frame_texts(io.output))
        set_filter!(view, column, text) =
            getfield(module_._find_column_filter(view.query, column), :text)[] = text
        figure(text, width) = lpad(text, width, '\u2007')

        @testset "a row passes every filter, and the table shows it with its row number" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            @test view.kept_rows == 1:1000
            set_filter!(view, "id", "> 990")
            set_filter!(view, "name", "/[05]\$/")
            @test view.kept_rows == [995, 1000]
            found = texts_of(io)
            @test "item 995" in found && "item 1000" in found
            @test "item 1" ∉ found && "item 991" ∉ found
            # The row numbers are the numbers of the rows in the frame, and the
            # corner shows how many rows pass.
            heights(text) = [t[2] for t in _data_frame_texts(io.output) if t[3] == text]
            # The row number and the id of row 995, at the height of its name.
            @test heights("995") == fill(only(heights("item 995")), 2)
            @test figure("2", 4) in found
            # A text that does not parse keeps every row.
            set_filter!(view, "name", "/[/")
            @test view.kept_rows == 991:1000
        end

        @testset "Ctrl+End jumps to the last row that passes" begin
            view = DataFrameView(make_frame())
            set_filter!(view, "id", "< 100")
            io = print_document(projection, nothing, view, context())
            evaluate_operation(nothing, _read_data_frame_key(projection, io, :end))
            @test view.anchor == 99
        end

        @testset "a filter that keeps no row, at the first print, and rows later" begin
            view = DataFrameView(make_frame())
            set_filter!(view, "id", "> 5000")
            io = print_document(projection, nothing, view, context())
            found = texts_of(io)
            @test figure("0", 4) in found
            @test "name :: String" in found
            @test "item 1" ∉ found
            set_filter!(view, "id", "< 4")
            found = texts_of(io)
            @test "item 1" in found && "item 3" in found
            @test "item 4" ∉ found
        end

        @testset "the pattern keeps the columns whose names match it" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            getfield(view.query, :column_pattern)[] = "PRI"
            @test module_._get_shown_columns(view) == ["price"]
            found = texts_of(io)
            @test "price :: Float64" in found && "name :: String" ∉ found
            getfield(view.query, :column_pattern)[] = "/^(id|name)\$/"
            @test module_._get_shown_columns(view) == ["id", "name"]
            # A pattern that does not parse keeps every column.
            getfield(view.query, :column_pattern)[] = "/[/"
            @test module_._get_shown_columns(view) == ["id", "name", "price"]
        end
    end
end
