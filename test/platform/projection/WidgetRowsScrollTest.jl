# A list and a tree that get a slot on the vertical axis fill it and scroll their
# rows there, inside their border: each prints itself again, as its rows alone,
# in a scroll pane of its own. A path of that pane is a path of the widget.

_make_rows_test_list() = WidgetList(["row $i" for i in 1:40]; selected = 0, width = 200)

_make_rows_test_offer() =
    with_exact_size(PrinterContext(); width = Cell(Int32(200)), height = Cell(Int32(150)))

# The pane of the rows of a widget printed through `iomap`.
_get_rows_test_pane(iomap) = get_content_iomap(iomap.pane)

# A point on the track of the vertical bar of a widget that scrolls itself, `dy`
# pixels from its top, in the frame of the widget, and the bar.
function _find_rows_test_bar(iomap, dy)
    bar = only(b for b in _get_rows_test_pane(iomap).bars if b.field == "vertical_scroll_bar")
    ((iomap.place[1] + Int(bar.place.x) + 2, iomap.place[2] + Int(bar.place.y) + dy), bar)
end

"""
    test_widget_rows_scroll()

A `WidgetList` and a `WidgetTree` that get a slot on the vertical axis fill it
and scroll their rows there, and with no slot they are as tall as their rows.
The wheel scrolls the rows, and a click selects the row that is drawn under it.
The pointer on a row lights the row; on the bar it names the bar of the widget.
The drag of the thumb comes back to the widget. A chevron of a tree still opens
its node.
"""
function test_widget_rows_scroll()
    projection = _scroll_pane_projection()
    plain = ModifierKeys()

    @testset "a list in a slot fills it and scrolls its rows inside its border" begin
        list = _make_rows_test_list()
        iomap = print_document(projection, nothing, list, _make_rows_test_offer())
        @test iomap isa WidgetModule.WidgetRowsPaneIoMap
        @test (Int(iomap.output.w), Int(iomap.output.h)) == (200, 150)
        rows = _get_rows_test_pane(iomap).content_iomap
        @test rows.input === list
        @test rows.bare
        # The rows are taller than the view, so the bar shows.
        (_, bar) = _find_rows_test_bar(iomap, 0)
        @test Int(bar.place.w) > 0
        # With no slot the list is as tall as its rows.
        free = print_document(projection, nothing, list, PrinterContext())
        @test free isa WidgetModule.WidgetListToGraphicsCanvasIoMap
        @test Int(free.output.h) > 150
    end

    @testset "the wheel scrolls the rows, and a click selects the row under it" begin
        list = _make_rows_test_list()
        iomap = print_document(projection, nothing, list, _make_rows_test_offer())
        rows = _get_rows_test_pane(iomap).content_iomap
        step = Int(rows.row_height)
        row_of(op) = WidgetModule._widget_element_selected(strip_reference_types(op.path), "items")
        before = read_intent(projection, iomap, MouseClick(:left, 20, 60; time = 0.0))
        @test before isa ReplaceSelectionOperation
        wheel = read_intent(projection, iomap, MouseScroll(0, -3, 20, 60; time = 0.0))
        @test wheel !== nothing
        evaluate_operation(nothing, wheel)
        offset = Int(list.scroll_position.y[])
        @test offset > 0
        after = read_intent(projection, iomap, MouseClick(:left, 20, 60; time = 0.0))
        top = WidgetModule._content_offset(iomap.projection, list)[2]
        @test row_of(before) == 1 + (60 - top) ÷ step
        @test row_of(after) == 1 + (60 - top + offset) ÷ step
    end

    @testset "the pointer lights the row under it, and the bar is a part of the list" begin
        list = _make_rows_test_list()
        driver = MttDriver(projection, list, print_document(projection, nothing, list, _make_rows_test_offer()))
        _mtt_move!(driver, 20, 30, 1.0)
        @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") > 0
        ((x, y), bar) = _find_rows_test_bar(driver.iomap, 75)
        _mtt_move!(driver, x, y, 1.1)
        @test get_mouse_target(list) ==
              ConcreteReference(FieldReferenceStep("vertical_scroll_bar"), EmptyReference())
        @test get_mouse_target(bar.document) == EmptyReference()
        @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 0
    end

    @testset "the drag of the thumb comes to the list" begin
        list = _make_rows_test_list()
        iomap = print_document(projection, nothing, list, _make_rows_test_offer())
        ((x, y), bar) = _find_rows_test_bar(iomap, 2)
        press = read_intent(projection, iomap, MouseDown(:left, x, y, plain; time = 0.0))
        start = only(o for o in _bar_test_writes(press) if o isa StartDragOperation)
        @test strip_reference_types(start.path) isa EmptyReference
        _bar_test_apply!(press)
        @test bar.document.thumb_drag !== nothing
        _bar_test_apply!(read_intent(projection, iomap, DragMove(x, y + 40, plain; time = 0.0)))
        @test Int(list.scroll_position.y[]) > 0
        _bar_test_apply!(read_intent(projection, iomap, DragEnd(x, y + 40, plain; time = 0.0)))
        @test bar.document.thumb_drag === nothing
    end

    @testset "a tree in a slot scrolls its rows, and a chevron still opens a node" begin
        tree = WidgetTree(Any[("node $i", Any["leaf $i.$j" for j in 1:3]) for i in 1:40])
        iomap = print_document(projection, nothing, tree, _make_rows_test_offer())
        @test iomap isa WidgetModule.WidgetRowsPaneIoMap
        @test Int(iomap.output.h) == 150
        @test _get_rows_test_pane(iomap).content_iomap.bare
        free = print_document(projection, nothing, tree, PrinterContext())
        @test free isa WidgetModule.WidgetTreeToGraphicsCanvasIoMap
        @test Int(free.output.h) > 150
        evaluate_operation(nothing, read_intent(projection, iomap, MouseScroll(0, -3, 80, 60; time = 0.0)))
        @test Int(tree.scroll_position.y[]) > 0
        # A click on a row selects its node, a root of the tree.
        click = read_intent(projection, iomap, MouseClick(:left, 120, 60; time = 0.0))
        @test click isa ReplaceSelectionOperation
        @test strip_reference_types(click.path).head == FieldReferenceStep("roots")
        # A click on the chevron of a row opens its node.
        toggle = read_intent(projection, iomap, MouseClick(:left, iomap.place[1] + 3, 60; time = 0.0))
        evaluate_operation(nothing, toggle)
        @test length(tree.expanded) == 1
    end
end
