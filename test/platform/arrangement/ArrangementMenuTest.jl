# The menu of a value: the nearest collection that holds it, the edits that
# filter or sort that collection by the value, the binding that opens the menu
# of an arranged document, the last entry that takes the arrangement away, and
# the first arrangement that the menu of a tab puts around its content.

function test_arrangement_menu()
@testset "the menu of a value filters and sorts its collection" begin
    vector(values) = CellVector(Cell[Cell(v) for v in values])
    make_study() = _ArrangementStudy(Any[_ArrangementRun(1, "done", 0.31, vector(["a", "b"])),
                                         _ArrangementRun(2, "failed", 0.12, vector(["c"])),
                                         _ArrangementRun(3, "done", 0.54, vector(["d"]))])
    path(steps...) = extend_reference(EmptyReference(), steps...)
    runs, status, delay = FieldReferenceStep("runs"), FieldReferenceStep("status"), FieldReferenceStep("delay")
    labels(edits) = [label for (label, _) in edits]
    edit_of(edits, label) = only(operation for (name, operation) in edits if name == label)
    right_click = MouseClick(:right, 0, 0, ModifierKeys(); time = 0.0)
    menu_labels(menu) = [item.action.label for item in menu.elements]

    @testset "the nearest collection that holds a value" begin
        study = make_study()
        item = find_arranged_item(study, path(runs, ElementReferenceStep(2), status))
        @test (item.at, item.index, item.key, item.value) == (path(runs), 2, path(status), "failed")
        events = find_arranged_item(study, path(runs, ElementReferenceStep(1), FieldReferenceStep("events"),
                                                ElementReferenceStep(2)))
        @test (events.at, events.index, events.value) ==
              (path(runs, ElementReferenceStep(1), FieldReferenceStep("events")), 2, "b")
        @test find_arranged_item(study, path(runs)) === nothing
    end

    @testset "the edits of an arrangement" begin
        study = make_study()
        arranged = ArrangementDocument(study, ArrangementEntry[])
        on_status = find_arranged_item(study, path(runs, ElementReferenceStep(2), status))
        edits = make_arrangement_edits(arranged, on_status)
        @test labels(edits) == ["Show only items like this", "Hide items like this",
                                "Sort by this, ascending", "Sort by this, descending"]
        evaluate_operation(nothing, edit_of(edits, "Hide items like this"))
        entry = only(arranged.entries)
        @test entry.at == path(runs)
        condition = only(only(entry.projections).conditions)
        @test (condition.key, condition.operator, condition.value) == (path(status), :not_equal, "failed")
        # A number offers greater and less, and a second condition joins the filter.
        on_delay = find_arranged_item(study, path(runs, ElementReferenceStep(1), delay))
        edits = make_arrangement_edits(arranged, on_delay)
        @test "Show only items greater than this" in labels(edits) && "Show all" in labels(edits)
        evaluate_operation(nothing, edit_of(edits, "Show only items greater than this"))
        @test length(only(entry.projections).conditions) == 2
        # A sort comes after the filter, and sorts by one key.
        evaluate_operation(nothing, edit_of(make_arrangement_edits(arranged, on_delay), "Sort by this, descending"))
        evaluate_operation(nothing, edit_of(make_arrangement_edits(arranged, on_delay), "Sort by this, ascending"))
        @test entry.projections[2] isa ArrangementSort
        @test [key.direction for key in entry.projections[2].keys] == [:ascending]
        # Show all of the last entry takes the arrangement away: the reader of the
        # arrangement turns it into the edit that puts the document in its place.
        show_all = edit_of(make_arrangement_edits(arranged, on_delay), "Show all")
        away = ArrangementModule._take_away_when_empty(arranged, show_all)
        @test away isa ReplaceReferencedValueOperation && away.document === nothing && away.value === study
    end

    @testset "a right click on an arranged document opens the menu of the value under the pointer" begin
        study = make_study()
        arranged = ArrangementDocument(study, ArrangementEntry[])
        getfield(arranged, :mouse_target)[] = ConcreteReference(FieldReferenceStep("document"),
                                                                 path(runs, ElementReferenceStep(2), status))
        open = get_wrapped_operation(read_gesture(arranged, right_click))
        @test open isa OpenContextMenuOperation
        @test menu_labels(only(open.layers)[2]) == ["Show only items like this", "Hide items like this",
                                                   "Sort by this, ascending", "Sort by this, descending"]
    end

    @testset "the menu of a tab puts the first arrangement around its content" begin
        study = make_study()
        tab = PaneTab("runs", study)
        getfield(tab, :mouse_target)[] = ConcreteReference(FieldReferenceStep("content"),
                                                            path(runs, ElementReferenceStep(2), status))
        open = get_wrapped_operation(read_gesture(tab, right_click))
        menu = only(open.layers)[2]
        hide = only(item for item in menu.elements if item.action.label == "Hide items like this")
        evaluate_operation(nothing, hide.operation)
        @test tab.content isa ArrangementDocument && tab.content.document === study
        @test only(only(only(tab.content.entries).projections).conditions).value == "failed"
        # An arranged content has the menu of its arrangement, and the tab has none.
        @test read_gesture(tab, right_click) === nothing
    end
end
end
