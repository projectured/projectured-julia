# A WidgetFactGroup draws an optional title over rows of aligned label and value
# pairs. The labels stand in one column as wide as the widest label, the values in
# a column beside it, and every gap, font and colour comes from the theme.

_fact_stub = FixedMeasure(10, 18, 6, 0)      # every character is 10 wide, every line 18 tall
_fact_theme = get_theme_defaults(WidgetTheme)
_fact_proj() = RecursiveProjection(TypeDispatchingProjection(WidgetToGraphics(; measure = _fact_stub).dispatch))
_fact_line = compute_line_box(_fact_stub, "x", _fact_theme.font).height   # one line of the theme font

# Every GraphicsText under a canvas as (text, x, y, colour), in the frame of the canvas.
function _fact_texts(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int,StyleColor}[])
    x = ox + Int(canvas.x); y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y), element.color))
        elseif element isa GraphicsCanvas
            _fact_texts(element, x, y, found)
        end
    end
    found
end

_fact_find(texts, text) = only(entry for entry in texts if entry[1] == text)

# The caret before the character `c` of the field `name` of the fact `i`: `facts[i].name{c}`.
_fact_place(i, name, c) =
    ConcreteReference(FieldReferenceStep("facts"), ConcreteReference(RangeReferenceStep(i - 1, i),
        ConcreteReference(FieldReferenceStep(name), ConcreteReference(RangeReferenceStep(c, c), EmptyReference()))))

# The thin rectangles of a caret under the canvas of a group.
_fact_carets(canvas) = [element for element in (element isa Cell ? element[] : element for element in canvas.elements)
                        if element isa GraphicsRect && Int(element.w) == 2]

function _fact_print(group, ctx = PrinterContext())
    proj = _fact_proj()
    (proj, print_document(proj, nothing, group, ctx))
end

function test_widget_fact_group()
    @testset "WidgetFactGroup" begin
        column_gap = Int(_fact_theme.form_column_gap)
        row_gap = Int(_fact_theme.form_row_gap)
        title_gap = Int(_fact_theme.title_gap)

        @testset "a pair becomes a fact, and the rows draw in order" begin
            group = WidgetFactGroup(["configuration" => "Fifo1", "run" => "#0", "exit code" => 0])
            @test all(fact -> fact isa WidgetFact, group.facts)
            @test group.facts[3].value == 0
            _, iomap = _fact_print(group)
            texts = _fact_texts(iomap.output)
            @test [entry[1] for entry in sort(texts; by = entry -> entry[3])] ==
                  ["configuration", "Fifo1", "run", "#0", "exit code", "0"]
        end

        @testset "labels start at one x and values at one x past the widest label" begin
            group = WidgetFactGroup(["configuration" => "Fifo1", "run" => "#0", "exit code" => "0"]; title = "Run")
            _, iomap = _fact_print(group)
            texts = _fact_texts(iomap.output)
            label_x = [_fact_find(texts, label)[2] for label in ("configuration", "run", "exit code")]
            value_x = [_fact_find(texts, value)[2] for value in ("Fifo1", "#0", "0")]
            @test allequal(label_x)
            @test allequal(value_x)
            @test value_x[1] == label_x[1] + 10 * length("configuration") + column_gap
            # The rows are one line each, `row_gap` apart.
            ys = [_fact_find(texts, label)[3] for label in ("configuration", "run", "exit code")]
            @test diff(ys) == [_fact_line + row_gap, _fact_line + row_gap]
            # The title stands above the first row, `title_gap` over it, in the bold title colour.
            title = _fact_find(texts, "Run")
            @test title[2] == label_x[1]
            @test ys[1] - title[3] == _fact_line + title_gap
            @test is_color_equal(title[4], _fact_theme.foreground)
        end

        @testset "a label is muted and a value has the text colour" begin
            group = WidgetFactGroup(["run" => "#0"])
            _, iomap = _fact_print(group)
            texts = _fact_texts(iomap.output)
            @test is_color_equal(_fact_find(texts, "run")[4], _fact_theme.muted_foreground)
            @test is_color_equal(_fact_find(texts, "#0")[4], _fact_theme.foreground)
            @test !is_color_equal(_fact_theme.muted_foreground, _fact_theme.foreground)
        end

        @testset "a long string wraps in the value column of a narrow offer" begin
            group = WidgetFactGroup(["note" => "alpha beta gamma delta"])
            offer = with_bounded_size(PrinterContext(); width = Cell(Int32(150)))
            _, iomap = _fact_print(group, offer)
            texts = _fact_texts(iomap.output)
            # The value column is 150 - 40 - column_gap wide: at most that many characters of 10.
            room = (150 - 40 - column_gap) ÷ 10
            lines = sort([entry for entry in texts if entry[1] != "note"]; by = entry -> entry[3])
            @test length(lines) >= 2
            @test all(entry -> length(entry[1]) <= room, lines)
            @test join((entry[1] for entry in lines), " ") == "alpha beta gamma delta"
            @test allequal(entry[2] for entry in lines)
            @test diff([entry[3] for entry in lines]) == fill(_fact_line, length(lines) - 1)
            @test Int(iomap.output.w[]) <= 150
        end

        @testset "a value that is a document answers a press at its place" begin
            clicked = Ref(0)
            button = WidgetButton("Go"; action = (_editor) -> (clicked[] += 1))
            group = WidgetFactGroup(["state" => "ok", "action" => button])
            proj, iomap = _fact_print(group)
            texts = _fact_texts(iomap.output)
            go = _fact_find(texts, "Go")
            operation = read_intent(proj, iomap, MouseClick(:left, go[2] + 2, go[3] + 2, ModifierKeys(); time = 0.0))
            @test operation isa InvokeActionOperation
            @test operation.action === button.action
            # A press on a label is no press on a value: it puts the caret into the label.
            label = _fact_find(texts, "action")
            caret = read_intent(proj, iomap, MouseClick(:left, label[2] + 2, label[3] + 2, ModifierKeys(); time = 0.0))
            @test caret isa ReplaceSelectionOperation
            @test strip_reference_types(caret.path) == _fact_place(2, "label", 0)
            # The value sits in the value column, on the row of its label.
            @test go[2] > _fact_find(texts, "ok")[2]
            @test abs(go[3] - _fact_find(texts, "action")[3]) <= 2 * _fact_line
        end

        @testset "a reference into facts[i].value maps to the document and back" begin
            badge = WidgetBadge("Done")
            group = WidgetFactGroup(["state" => badge])
            proj, iomap = _fact_print(group)
            reference = annotate_reference_types(group,
                ConcreteReference(FieldReferenceStep("facts"),
                    ConcreteReference(RangeReferenceStep(0, 1),
                        ConcreteReference(FieldReferenceStep("value"), EmptyReference()))))
            image = map_reference_forward(proj, iomap, reference)
            @test image !== nothing
            done = _fact_find(_fact_texts(iomap.output), "Done")
            back = map_reference_backward(proj, iomap, PointReferenceStep(done[2] + 1, done[3] + 1))
            @test back !== nothing
            steps = get_reference_steps(strip_reference_types(back))
            @test steps[1] == FieldReferenceStep("facts")
            @test any(step -> step == FieldReferenceStep("value"), steps)
        end

        @testset "a plain click on a text puts the caret there, and the group draws it" begin
            group = WidgetFactGroup(["run" => "#0", "exit code" => 0]; title = "Run")
            proj, iomap = _fact_print(group)
            texts = _fact_texts(iomap.output)
            click(x, y; count = 1, modifiers = ModifierKeys()) =
                read_intent(proj, iomap, MouseClick(:left, x, y, count, modifiers; time = 0.0))
            run = _fact_find(texts, "run")
            value = _fact_find(texts, "#0")
            title = _fact_find(texts, "Run")
            # The caret goes before the character nearest the point: 10 per character.
            @test strip_reference_types(click(run[2] + 12, run[3] + 2).path) == _fact_place(1, "label", 1)
            @test strip_reference_types(click(value[2] + 18, value[3] + 2).path) == _fact_place(1, "value", 2)
            title_caret = strip_reference_types(click(title[2] + 22, title[3] + 2).path)
            @test title_caret == ConcreteReference(FieldReferenceStep("title"),
                                                   ConcreteReference(RangeReferenceStep(2, 2), EmptyReference()))
            # An Alt+click answers the caret too, which the container makes the label as a
            # whole. A value that is a number takes the caret as a string does, and a
            # double click is left to the widget around the group.
            @test strip_reference_types(click(run[2] + 12, run[3] + 2; modifiers = ModifierKeys(alt = true)).path) ==
                  _fact_place(1, "label", 1)
            @test strip_reference_types(click(_fact_find(texts, "0")[2] + 2, _fact_find(texts, "0")[3] + 2).path) ==
                  _fact_place(2, "value", 0)
            @test click(run[2] + 12, run[3] + 2; count = 2) === nothing
            # A move names the caret under the pointer.
            move = read_intent(proj, iomap, MouseMove(run[2] + 12, run[3] + 2; time = 0.0))
            @test move isa ReplaceMouseTargetOperation
            @test strip_reference_types(move.path) == _fact_place(1, "label", 1)
            # The caret maps to its line and back, and a point on the text maps to the caret.
            caret = annotate_reference_types(group, _fact_place(1, "value", 1))
            place = map_reference_forward(proj, iomap, caret)
            @test place !== nothing
            @test strip_reference_types(map_reference_backward(proj, iomap, place)) == _fact_place(1, "value", 1)
            @test strip_reference_types(map_reference_backward(proj, iomap, PointReferenceStep(value[2] + 8, value[3] + 2))) ==
                  _fact_place(1, "value", 1)
            # A point on the rest of a row maps to the fact, and an Alt+double click there selects
            # the fact; a plain click there is left to the widget around the group. The
            # label column is as wide as "exit code", so it is empty right of "run".
            fact = ConcreteReference(FieldReferenceStep("facts"),
                                     ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))
            @test strip_reference_types(map_reference_backward(proj, iomap, PointReferenceStep(run[2] + 60, run[3] + 2))) ==
                  fact
            @test strip_reference_types(click(run[2] + 60, run[3] + 2; count = 2, modifiers = ModifierKeys(alt = true)).path) ==
                  fact
            @test click(run[2] + 60, run[3] + 2) === nothing
            # The group draws the caret that the selection holds, at its character.
            @test isempty(_fact_carets(iomap.output))
            evaluate_operation((document = group,), ReplaceSelectionOperation(_fact_place(1, "value", 1)))
            drawn = _fact_carets(iomap.output)
            @test length(drawn) == 1
            @test Int(only(drawn).x) == value[2] + 10
            # A label selected as a whole draws a band behind its line, in the colour of a
            # selected part, and no caret.
            band = iomap.projection.selected_color
            bands() = [element for element in (element isa Cell ? element[] : element for element in iomap.output.elements)
                       if element isa GraphicsRect && is_color_equal(element.color, band)]
            label = ConcreteReference(FieldReferenceStep("facts"), ConcreteReference(RangeReferenceStep(0, 1),
                                      ConcreteReference(FieldReferenceStep("label"), EmptyReference())))
            evaluate_operation((document = group,), ReplaceSelectionOperation(label))
            @test isempty(_fact_carets(iomap.output))
            @test length(bands()) == 1
            @test (Int(only(bands()).x), Int(only(bands()).w)) == (run[2], 10 * length("run"))
            # A fact selected as a whole draws the band over its row.
            evaluate_operation((document = group,), ReplaceSelectionOperation(fact))
            @test length(bands()) == 1
            @test (Int(only(bands()).x), Int(only(bands()).h)) == (run[2], _fact_line)
            set_selection!(group, nothing)
            @test isempty(_fact_carets(iomap.output))
            @test isempty(bands())
        end

        @testset "each line of a wrapped value starts at its character" begin
            group = WidgetFactGroup(["note" => "alpha beta gamma delta"])
            offer = with_bounded_size(PrinterContext(); width = Cell(Int32(150)))
            proj, iomap = _fact_print(group, offer)
            lines = sort([entry for entry in _fact_texts(iomap.output) if entry[1] != "note"]; by = entry -> entry[3])
            second = lines[2]
            start = length(lines[1][1]) + 1
            operation = read_intent(proj, iomap, MouseClick(:left, second[2] + 2, second[3] + 2, 1, ModifierKeys();
                                                            time = 0.0))
            @test strip_reference_types(operation.path) == _fact_place(1, "value", start)
        end

        @testset "an invisible group draws nothing" begin
            group = WidgetFactGroup(["run" => "#0"]; visible = false)
            _, iomap = _fact_print(group)
            @test isempty(_fact_texts(iomap.output))
        end
    end
end
