# The menu of a value: the nearest collection that holds it, the edits that
# filter or sort that collection by the value, the binding that opens the menu
# of an arranged document, the last entry that takes the arrangement away, and
# the first arrangement that the menu of a tab puts around its content. In an
# editor, a right click opens the menu and a press on Show all takes the
# arrangement away. The context menu window is not in these editors, so a test
# takes the menu from the answer of the click, as the window does.

import ProjecturedKernelExample: HeadlessBackend, rendered_output, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display

# Each text of a canvas, at its place, also inside the viewport of a pane. The
# elements of a canvas of a list are its nodes, from the first to the last.
function _arrangement_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        element = element isa ListNode ? element.value : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _arrangement_drawn(element, x, y, found)
        elseif element isa GraphicsViewport
            _arrangement_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                               y + Int(element.y) + round(Int, element.transform.f), found)
        end
    end
    found
end

_arrangement_texts(backend) = first.(_arrangement_drawn(last(rendered_output(backend))))

# The place of the last drawn text `text`.
function _arrangement_place(backend, text)
    drawn = _arrangement_drawn(last(rendered_output(backend)))
    (_, x, y) = drawn[findlast(entry -> entry[1] == text, drawn)]
    (x + 2, y + 2)
end

_arrangement_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

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
                                "Sort by this, ascending", "Sort by this, descending", "Filter by text…"]
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
        # A page that holds the arrangement in its field `table` keeps it with no
        # entry: the edit that takes it away there removes its entries instead.
        table = FieldReferenceStep("table")
        rooted = ReplaceReferencedValueOperation(nothing, extend_reference(EmptyReference(), table), study)
        kept = keep_held_arrangement(CompoundOperation(Any[rooted]), arranged, table)
        @test only(kept.operations) isa ReplaceReferencedValueOperation && only(kept.operations).document === arranged
        evaluate_operation(nothing, kept)
        @test isempty(arranged.entries)
        # An edit at another field, or of another value, stays as it is.
        other = ReplaceReferencedValueOperation(nothing, extend_reference(EmptyReference(), FieldReferenceStep("rows")),
                                                study)
        @test keep_held_arrangement(other, arranged, table) === other
        @test keep_held_arrangement(show_all, arranged, table) === show_all
    end

    @testset "a right click on an arranged document opens the menu of the value under the pointer" begin
        study = make_study()
        arranged = ArrangementDocument(study, ArrangementEntry[])
        getfield(arranged, :mouse_target)[] = ConcreteReference(FieldReferenceStep("document"),
                                                                 path(runs, ElementReferenceStep(2), status))
        open = get_wrapped_operation(read_gesture(arranged, right_click))
        @test open isa OpenContextMenuOperation
        @test menu_labels(only(open.layers)[2]) == ["Show only items like this", "Hide items like this",
                                                   "Sort by this, ascending", "Sort by this, descending",
                                                   "Filter by text…"]
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

    @testset "in an editor, a right click arranges the content of a tab and Show all takes it away" begin
        fruits = CellVector(Cell[Cell(PrimitiveString(name)) for name in ["pear", "apple", "fig", "grape"]])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(fruits, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        tab = only(editor.document.root.tabs)
        @test tab.content === fruits
        # The item `label` of the menu that a right click on the drawn text `text`
        # opens, chosen as the context menu window chooses it: lifted from the
        # part of its menu.
        function choose!(text, label)
            (x, y) = _arrangement_place(backend, text)
            _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
            click = MouseClick(:right, x, y, 1, ModifierKeys(); time = 0.0)
            open = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
            open isa WrappingOperation && (open = get_wrapped_operation(open))
            @test open isa OpenContextMenuOperation
            open isa OpenContextMenuOperation || return
            items = [item for (_, menu) in open.layers for item in menu.elements
                     if item isa WidgetMenuItem && item.action.label == label]
            @test length(items) == 1
            part = annotate_reference_types(editor.document, find_menu_item_part(open, only(items).operation))
            evaluate_operation(editor, read_rooted_operation(editor, part, only(items).operation))
            drain_operations!(editor)
            run_frame!(editor)
        end
        choose!("fig", "Hide items like this")
        @test tab.content isa ArrangementDocument && tab.content.document === fruits
        drawn = _arrangement_texts(backend)
        @test "3 of 4" in drawn && "Show all" in drawn
        @test !("fig" in drawn) && "pear" in drawn && "grape" in drawn
        # The arranged content has the menu of its arrangement. The third drawn
        # item is the fourth of the source, and the condition reads the source.
        choose!("grape", "Hide items like this")
        @test length(only(only(tab.content.entries).projections).conditions) == 2
        drawn = _arrangement_texts(backend)
        @test "2 of 4" in drawn && !("grape" in drawn) && "pear" in drawn && "apple" in drawn
        # A press on Show all removes the last entry, and the reader of the
        # arrangement puts the document back in its place.
        (x, y) = _arrangement_place(backend, "Show all")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0),
                            MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
        drain_operations!(editor)
        run_frame!(editor)
        @test tab.content === fruits
        drawn = _arrangement_texts(backend)
        @test "fig" in drawn && !("Show all" in drawn)
    end
end
end
