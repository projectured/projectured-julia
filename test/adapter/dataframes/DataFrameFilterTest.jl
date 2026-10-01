# An editor that holds only the document, as `evaluate_operation` reads it.
mutable struct _DataFrameFilterEditor
    document::Any
end

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

        function read_event(io, event)
            change = read_intent(projection, nothing, Intent(event, nothing), io)
            change isa Intent ? change.operation : change
        end
        filter_steps(i) = [FieldReferenceStep("query"), FieldReferenceStep("column_filters"),
                           RangeReferenceStep(i - 1, i), FieldReferenceStep("text")]

        @testset "a press in a field of the filter row puts the caret in the text of the filter" begin
            view = DataFrameView(make_frame())
            set_filter!(view, "name", "item")
            io = print_document(projection, nothing, view, context())
            (x, y) = only((t[1], t[2]) for t in _data_frame_texts(io.output) if t[3] == "item")
            op = read_event(io, MouseClick(:left, x + 1, y + 2, ModifierKeys(); time = 0.0))
            @test op isa ReplaceSelectionOperation
            steps = get_reference_steps(strip_reference_types(op.path))
            @test steps[1:4] == filter_steps(2)
            @test steps[5] isa RangeReferenceStep
        end

        @testset "a key in a field edits the filter, and the view shows the result from its start" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            getfield(view, :anchor)[] = 500
            set_selection!(view, module_._make_filter_text_reference(1, RangeReferenceStep(0, 0)))
            op = read_event(io, KeyPress('9', "9", ModifierKeys(); time = 0.0))
            @test op isa CompoundOperation
            edit = first(op.operations)
            @test edit isa ReplaceStringRangeOperation && edit.replacement == "9"
            @test get_reference_steps(strip_reference_types(edit.reference))[1:4] == filter_steps(1)
            evaluate_operation(_DataFrameFilterEditor(view), op)
            @test module_._find_column_filter(view.query, "id").text == "9"
            @test view.anchor == 1
            @test !isempty(view.kept_rows) && all(i -> occursin("9", string(i)), view.kept_rows)
            # The caret is after the 9, and a second key goes on from there.
            @test get_reference_steps(strip_reference_types(view.selection))[5] == RangeReferenceStep(1, 1)
            evaluate_operation(_DataFrameFilterEditor(view), read_event(io, KeyPress('9', "9", ModifierKeys();
                                                                                     time = 0.0)))
            @test module_._find_column_filter(view.query, "id").text == "99"
        end

        @testset "a text that does not parse colors its field, and says why" begin
            view = DataFrameView(make_frame())
            set_filter!(view, "id", "> x")
            io = print_document(projection, nothing, view, context())
            table = _data_frame_table_iomap(io).input
            field = table.column_headers[1].children[2]
            @test field.tooltip isa String
            @test field.style !== nothing
            set_filter!(view, "id", "> 3")
            @test field.tooltip === nothing && field.style === nothing
        end

        @testset "the list of the values of a column writes the ticked ones into its filter" begin
            view = DataFrameView(DataFrame(id = 1:6, kind = ["b", "a", "b", "c", missing, "a, b"]))
            rows_of(dialog) = dialog.content.content.children
            dialog, take = module_._make_value_list_dialog(view, "kind")
            # The values that are not missing, sorted, each with the count of its rows.
            @test [row.children[2].content for row in rows_of(dialog)] ==
                  ["a  (1)", "a, b  (1)", "b  (2)", "c  (1)"]
            boxes = [row.children[1] for row in rows_of(dialog)]
            @test all(box -> box.content, boxes)
            # Every value ticked is no filter.
            evaluate_operation(_DataFrameFilterEditor(view), take())
            @test module_._find_column_filter(view.query, "kind").text == ""
            getfield(boxes[3], :content)[] = false
            getfield(boxes[4], :content)[] = false
            evaluate_operation(_DataFrameFilterEditor(view), take())
            @test module_._find_column_filter(view.query, "kind").text == "= a, \"a, b\""
            @test view.kept_rows == [2, 6]
            # The next list starts from the filter, and no value ticked changes nothing.
            dialog, take = module_._make_value_list_dialog(view, "kind")
            @test [row.children[1].content for row in rows_of(dialog)] == [true, true, false, false]
            foreach(row -> getfield(row.children[1], :content)[] = false, rows_of(dialog))
            @test take() === nothing
        end

        @testset "a column of more than 1,000 distinct values has no list" begin
            view = DataFrameView(DataFrame(id = 1:2000))
            dialog, take = module_._make_value_list_dialog(view, "id")
            @test dialog.content isa AbstractString
            @test take() === nothing
        end

        @testset "the expression keeps the rows where it is true" begin
            frame = make_frame()
            evaluate(text, frame = frame) = module_._evaluate_expression(frame, text)
            pass, reason = evaluate("id > 995 && endswith(name, \"9\")")
            @test reason === nothing && findall(pass) == [999]
            # A symbol names the column too.
            @test findall(first(evaluate(":id > 995 && endswith(:name, \"9\")"))) == [999]
            @test evaluate("") == (nothing, nothing)
            # A missing hides its row.
            @test findall(first(evaluate("x > 0", DataFrame(x = Union{Int,Missing}[1, missing, 3])))) == [1, 3]
            # A symbol that names no column stays a symbol.
            @test findall(first(evaluate("id < 3 && :other == :other"))) == [1, 2]
            # A function of the session.
            Core.eval(Main, :(_data_frame_filter_test_is_even(n) = iseven(n)))
            @test findall(first(evaluate("_data_frame_filter_test_is_even(id) && id < 7"))) == [2, 4, 6]
            # A text that does not parse, an error, and a value that is not true
            # or false give a reason, and no rows.
            for text in ("id >", "startswith(id, 1)", "id + 1")
                pass, reason = evaluate(text)
                @test pass === nothing && reason isa String
            end
        end

        @testset "a name in the expression is a column, except where Julia names something else" begin
            evaluate(text, frame) = findall(first(module_._evaluate_expression(frame, text)))
            # The name before parentheses is the function.
            @test evaluate("abs(abs) > 1", DataFrame(abs = [-1, 2, -3])) == [2, 3]
            # The field after a dot.
            @test evaluate("point.x > x", DataFrame(point = [(x = 1,), (x = 5,)], x = [2, 2])) == [2]
            # The name of a keyword argument, after a comma or a semicolon.
            frame = DataFrame(price = [1.24, 5.68], digits = [9, 9])
            @test evaluate("round(price, digits = 1) == 5.7", frame) == [2]
            @test evaluate("round(price; digits = 1) == 1.2", frame) == [1]
            # A name that is no identifier.
            @test evaluate("var\"unit price\" > 2", DataFrame("unit price" => [1, 5])) == [2]
            # A column wins over a global of the same name, which `Main.name` reaches.
            Core.eval(Main, :(_data_frame_filter_test_limit = 3))
            frame = DataFrame(_data_frame_filter_test_limit = [1, 5], v = [4, 4])
            @test evaluate("v > _data_frame_filter_test_limit", frame) == [1]
            @test evaluate("v > Main._data_frame_filter_test_limit", frame) == [1, 2]
        end

        @testset "an expression that assigns to a column does not compile, and the frame stays" begin
            frame = DataFrame(id = [1, 2, 3])
            for text in ("id = 3", "id += 1", ":id = 3", "(id, x) = (1, 2)")
                pass, reason = module_._evaluate_expression(frame, text)
                @test pass === nothing && occursin("write == to compare", reason)
            end
            @test frame.id == [1, 2, 3]
            # A local of another name is no column.
            @test findall(first(module_._evaluate_expression(frame, "let n = 2; id > n end"))) == [3]
        end

        @testset "the empty expression field shows an example of the columns of the frame" begin
            example(frame) = module_._make_expression_example(frame)
            @test example(DataFrame(city = ["Berlin", "Rome"], age = [30, 40])) == "age > 30 && startswith(city, \"B\")"
            @test example(DataFrame("unit price" => Union{Float64,Missing}[missing, 2.5])) == "var\"unit price\" > 2.5"
            @test example(DataFrame("end" => [1])) == "var\"end\" > 1"
            @test example(DataFrame(flag = [true])) === nothing
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            field = _data_frame_grid_iomap(io).child_iomaps[1][3].input.children[2]
            @test field.placeholder == example(view.frame)
            # The example parses, and keeps rows.
            @test module_._evaluate_expression(view.frame, field.placeholder)[2] === nothing
        end

        @testset "a row passes the expression and the filters of the columns" begin
            view = DataFrameView(make_frame())
            getfield(view.query, :expression)[] = "price > 990"
            @test view.kept_rows == 991:1000
            set_filter!(view, "id", "< 995")
            @test view.kept_rows == 991:994
            # An expression that does not parse keeps every row.
            getfield(view.query, :expression)[] = "price >"
            @test view.kept_rows == 1:994
        end

        @testset "a key in the expression bar edits the expression, and the bar marks an error" begin
            view = DataFrameView(make_frame())
            io = print_document(projection, nothing, view, context())
            set_selection!(view, module_._make_expression_reference(RangeReferenceStep(0, 0)))
            op = read_event(io, KeyPress('q', "q", ModifierKeys(); time = 0.0))
            @test op isa CompoundOperation
            evaluate_operation(_DataFrameFilterEditor(view), op)
            @test view.query.expression == "q"
            # `q` names nothing in the session: the expression raises an error,
            # keeps every row, and the bar says why.
            @test last(view.expression_result) isa String
            @test length(view.kept_rows) == 1000
            bar = _data_frame_grid_iomap(io).child_iomaps[1][3].input
            @test bar.children[2].tooltip isa String
            @test bar.children[2].language === :julia
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
