# The quick text field of a bar: a condition whose key is any value inside an
# item, and in an editor the item of the menu that makes the field, a press that
# puts the caret in it, typed keys that filter the items, and the × of the field.

function test_arrangement_quick_text()
@testset "the quick text field of a bar keeps the items that contain its text" begin
    vector(values) = CellVector(Cell[Cell(v) for v in values])
    contains_text(text) = ArrangementCondition(nothing, :contains, text)

    @testset "a condition on any value inside an item" begin
        run = _ArrangementRun(1, "done", 0.31, vector(["alpha", "beta"]))
        @test is_quick_text_condition(contains_text("x"))
        @test !is_quick_text_condition(ArrangementCondition(EmptyReference(), :contains, "x"))
        @test is_condition_holding(contains_text("BET"), run)
        @test is_condition_holding(contains_text("0.3"), run)
        @test is_condition_holding(contains_text("don"), run)
        @test is_condition_holding(contains_text(""), _ArrangementRun(2, "", 0.0, vector(String[])))
        @test !is_condition_holding(contains_text("gamma"), run)
    end

    @testset "in an editor, a field that a person types in" begin
        names = ["pear", "apple", "fig", "grape"]
        fruits = CellVector(Cell[Cell(PrimitiveString(name)) for name in names])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(fruits, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        tab = only(editor.document.root.tabs)
        shown() = filter(in(names), _arrangement_texts(backend))
        frame!() = (drain_operations!(editor); run_frame!(editor))
        # The range of the caret in the field: the last step of the path that the
        # introduced step of the bar holds.
        function caret()
            steps = get_reference_steps(strip_reference_types(editor.document.selection))
            step = only(step for step in steps if step isa ProjectionReferenceStep)
            last = get_reference_steps(strip_reference_types(step.output_path))[end]
            (last.start, last.stop)
        end
        # The item of the menu of a value makes the field.
        (x, y) = _arrangement_place(backend, "fig")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
        click = MouseClick(:right, x, y, 1, ModifierKeys(); time = 0.0)
        open = get_wrapped_operation(read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation)
        item = only(item for (_, menu) in open.layers for item in menu.elements
                    if item isa WidgetMenuItem && item.action.label == "Filter by text…")
        evaluate_operation(editor, read_rooted_operation(editor, open.source, item.operation))
        frame!()
        @test tab.content isa ArrangementDocument
        condition = only(only(only(tab.content.entries).projections).conditions)
        @test is_quick_text_condition(condition) && condition.value == ""
        @test "4 of 4" in _arrangement_texts(backend) && shown() == names
        # A press in the field puts the caret in the value of the condition, a
        # path in the entry below the introduced step of the bar.
        (x, y) = _arrangement_place(backend, "Filter by text")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        frame!()
        selection = strip_reference_types(editor.document.selection)
        @test has_introduced_step(selection)
        # Typed keys write the text, and the items follow it.
        foreach(c -> _arrangement_press!(editor, backend, KeyPress(c; time = 0.0)), "pe")
        frame!()
        @test condition.value == "pe"
        @test shown() == ["pear", "grape"] && "2 of 4" in _arrangement_texts(backend)
        @test "pe" in _arrangement_texts(backend)
        @test caret() == (2, 2)
        _arrangement_press!(editor, backend, KeyDown(:backspace, ModifierKeys(); time = 0.0))
        frame!()
        @test condition.value == "p"
        @test shown() == ["pear", "apple", "grape"]
        # The × of the field takes the condition away, and with its last
        # condition the arrangement.
        (x, y) = _arrangement_place(backend, "×")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        frame!()
        @test tab.content === fruits
        @test shown() == names
    end
end
end
