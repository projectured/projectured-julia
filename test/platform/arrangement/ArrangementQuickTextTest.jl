# The quick text field of a bar: a condition whose key is any value inside an
# item, and in an editor the item of the menu that makes the field and puts the
# caret in it, typed keys that filter the items, the × of the field, the item of
# the menu of an arranged content, and a press that puts the caret in the field.

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
        # The item of the menu `label` that a right click on the drawn text
        # `text` opens, chosen as the context menu window chooses it: lifted
        # from the part of its menu.
        function choose!(text, label)
            (x, y) = _arrangement_place(backend, text)
            _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
            click = MouseClick(:right, x, y, 1, ModifierKeys(); time = 0.0)
            open = get_wrapped_operation(read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation)
            item = only(item for (_, menu) in open.layers for item in menu.elements
                        if item isa WidgetMenuItem && item.action.label == label)
            part = annotate_reference_types(editor.document, find_menu_item_part(open, item.operation))
            evaluate_operation(editor, read_rooted_operation(editor, part, item.operation))
            frame!()
        end
        press!(text) = begin
            (x, y) = _arrangement_place(backend, text)
            _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                                MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
            frame!()
        end
        type!(text) = (foreach(c -> _arrangement_press!(editor, backend, KeyPress(c; time = 0.0)), text); frame!())
        # The item of the menu of a value in a tab makes the field and puts the
        # caret in it, a path in the entry below the introduced step of the bar,
        # so the keys that follow write the text, and the items follow it.
        choose!("fig", "Filter by text…")
        @test tab.content isa ArrangementDocument
        condition = only(only(only(tab.content.entries).projections).conditions)
        @test is_quick_text_condition(condition) && condition.value == ""
        @test has_introduced_step(strip_reference_types(editor.document.selection)) && caret() == (0, 0)
        type!("pe")
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
        press!("×")
        @test tab.content === fruits
        @test shown() == names
        # The item of the menu of an arranged content adds the condition to the
        # filter of the entry, and puts the caret in its field.
        choose!("fig", "Hide items like this")
        choose!("pear", "Filter by text…")
        conditions = only(only(tab.content.entries).projections).conditions
        @test length(conditions) == 2 && is_quick_text_condition(conditions[2])
        type!("a")
        @test shown() == ["pear", "apple", "grape"] && "3 of 4" in _arrangement_texts(backend)
        # A press in an item takes the caret out of the field, and a press at the
        # start of the text of the field puts it back there.
        press!("pear")
        @test !has_introduced_step(strip_reference_types(editor.document.selection))
        press!("a")
        @test has_introduced_step(strip_reference_types(editor.document.selection)) && caret() == (0, 0)
        type!("p")
        @test conditions[2].value == "pa"
        @test isempty(shown()) && "0 of 4" in _arrangement_texts(backend)
    end
end
end
