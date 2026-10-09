# Find in an arranged collection: the order in which the items show, and in an
# editor Ctrl+F in a content that nobody arranged, the text of the find, Return,
# F3 and Shift+F3 in the order of a sort, the × of the field, and Ctrl+F in an
# entry that has no find.

function test_arrangement_find()
@testset "find moves the selection to the next item that holds its text" begin
    names = ["pear", "apple", "fig", "grape", "papaya"]
    make_fruits() = CellVector(Cell[Cell(PrimitiveString(name)) for name in names])
    by_value(direction) = ArrangementSort(Any[ArrangementSortKey(EmptyReference(), direction)])

    @testset "the order in which the items show" begin
        fruits = make_fruits()
        keep_p = ArrangementFilter(Any[ArrangementCondition(EmptyReference(), :contains, "p")])
        entry = ArrangementEntry(EmptyReference(), Any[keep_p, by_value(:descending), ArrangementFind("")])
        @test compute_shown_rows(entry, fruits) == [1, 5, 4, 2]
    end

    @testset "in an editor, the keys of find" begin
        fruits = make_fruits()
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(fruits, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        tab = only(editor.document.root.tabs)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        key!(key; ctrl = false, shift = false) =
            (_arrangement_press!(editor, backend, KeyDown(key, ModifierKeys(; ctrl, shift); time = 0.0)); frame!())
        # The item that the selection names, by its index in the source.
        function selected()
            steps = get_reference_steps(strip_reference_types(editor.document.selection))
            (length(steps) >= 2 && steps[end - 1] == FieldReferenceStep("document") &&
             steps[end] isa RangeReferenceStep) ? steps[end].stop : nothing
        end
        find() = only(d for d in only(tab.content.entries).projections if d isa ArrangementFind)
        # A press on an item, then Ctrl+F: the first arrangement of the content
        # with an empty find, and the caret in its field.
        (x, y) = _arrangement_place(backend, "apple")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        frame!()
        key!(:f; ctrl = true)
        @test tab.content isa ArrangementDocument && tab.content.document === fruits
        @test is_in_find_field(tab.content)
        @test "5 of 5" in _arrangement_texts(backend)
        # The text of the find hides no item.
        foreach(c -> _arrangement_press!(editor, backend, KeyPress(c; time = 0.0)), "ap")
        frame!()
        @test find().text == "ap"
        @test filter(in(names), _arrangement_texts(backend)) == names
        # Return in the field moves to the first item that holds the text, and F3
        # and Shift+F3 to the next and the previous one, round the end.
        key!(:return)
        @test selected() == 2
        key!(:f3)
        @test selected() == 4
        key!(:f3)
        @test selected() == 5
        key!(:f3)
        @test selected() == 2
        key!(:f3; shift = true)
        @test selected() == 5
        # In the order of a sort: papaya, grape, apple.
        sort = read_rooted_operation(editor, @reference(editor.document, root.tabs[1].content.document),
                                     ArrangeCollectionOperation(EmptyReference(), by_value(:descending)))
        evaluate_operation(editor, sort)
        frame!()
        key!(:f3)
        @test selected() == 4
        key!(:f3)
        @test selected() == 2
        # The × of the field takes the find away and keeps the sort.
        (x, y) = _arrangement_place(backend, "×")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        frame!()
        @test only(only(tab.content.entries).projections) isa ArrangementSort
        # Ctrl+F in an entry that has no find adds one after its projections.
        (x, y) = _arrangement_place(backend, "fig")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        frame!()
        key!(:f; ctrl = true)
        @test only(tab.content.entries).projections[end] isa ArrangementFind
        @test is_in_find_field(tab.content)
    end
end
end
