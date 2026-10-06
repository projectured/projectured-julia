# A table draws the bars of its cells: the pane of the cells draws them, so the
# vertical bar starts under the header row, and the headers have none. The table
# gives a press on a bar and the drag of a thumb to that pane, and a point on a
# bar maps to the field of the bar in the table.

# A table of sixty rows in a slot of 300 by 200 pixels.
function _print_bar_test_table(projection; vertical_scroll_bar = :auto)
    table = WidgetTable(; column_headers = Any["name", "value"],
                        cells = Any[Any["row $i", string(i)] for i in 1:60],
                        vertical_scroll_bar)
    offer = with_exact_size(PrinterContext(); width = Cell(Int32(300)), height = Cell(Int32(200)))
    (table, print_document(projection, nothing, table, offer))
end

# The pane of the cells of a table printed through `iomap`, its place in the
# table, and its vertical bar.
function _find_table_test_bar(iomap)
    pane = iomap.parts.cells_pane
    place = WidgetModule._get_wt_cells_place(iomap.projection, iomap)
    bar = only(b for b in pane.bars if b.field == "vertical_scroll_bar")
    (pane, place, bar)
end

# A point on the track of the vertical bar of the cells, `dy` pixels from its
# top, in the frame of the table.
function _get_table_test_bar_point(iomap, dy)
    _, place, bar = _find_table_test_bar(iomap)
    (place[1] + Int(bar.place.x) + 2, place[2] + Int(bar.place.y) + dy)
end

"""
    test_widget_table_bar()

The pane of the cells of a `WidgetTable` draws its bars: the vertical bar starts
under the header row, and the panes of the headers draw none. A click on the
track scrolls the table, the drag of the thumb comes to the table and scrolls it,
and a point on the bar maps to `vertical_scroll_bar` of the table, so the pointer
there lights the bar. A `WidgetScrollBar` of an owner is drawn as it is and keeps
its writes.
"""
function test_widget_table_bar()
    projection = _scroll_pane_projection()
    plain = ModifierKeys()

    @testset "the bar of the cells starts under the header row" begin
        table, iomap = _print_bar_test_table(projection)
        pane, place, bar = _find_table_test_bar(iomap)
        @test Int(bar.place.w) > 0
        # The bar ends at the edge of the table and starts under the header row.
        header_h = Int(iomap.parts.header_height[])
        @test header_h > 0
        @test place[2] + Int(bar.place.y) >= header_h
        @test place[1] + Int(bar.place.x) + Int(bar.place.w) <= 300
        @test place[2] + Int(bar.place.y) + Int(bar.place.h) <= 200
        # The header row has no bar, and the cells fit across.
        @test isempty(iomap.parts.column_header_pane.bars)
        across = only(b for b in pane.bars if b.field == "horizontal_scroll_bar")
        @test Int(across.place.w) == 0
    end

    @testset "a click on the track scrolls the table" begin
        table, iomap = _print_bar_test_table(projection)
        x, y = _get_table_test_bar_point(iomap, 150)
        click = read_intent(projection, iomap, MouseClick(:left, x, y, 1, plain; time = 0.0))
        written = only(o for o in _bar_test_writes(click) if o isa ReplaceReferencedValueOperation)
        _bar_test_apply!(click)
        # The pane of the cells shares the offset of the table.
        @test Int(table.scroll_position.y[]) > 0
        @test written.document === iomap.parts.cells_pane.input
    end

    @testset "the drag of the thumb comes to the table" begin
        table, iomap = _print_bar_test_table(projection)
        _, _, bar = _find_table_test_bar(iomap)
        x, y = _get_table_test_bar_point(iomap, 2)
        press = read_intent(projection, iomap, MouseDown(:left, x, y, plain; time = 0.0))
        start = only(o for o in _bar_test_writes(press) if o isa StartDragOperation)
        @test start.path isa EmptyReference
        _bar_test_apply!(press)
        @test bar.document.thumb_drag !== nothing
        moved = read_intent(projection, iomap, DragMove(x, y + 40, plain; time = 0.0))
        _bar_test_apply!(moved)
        @test Int(table.scroll_position.y[]) > 0
        # A move far off the table takes the cells to their end.
        far = read_intent(projection, iomap, DragMove(x, 5000, plain; time = 0.0))
        _bar_test_apply!(far)
        @test bar.document.value == 1.0
        _bar_test_apply!(read_intent(projection, iomap, DragEnd(x, 5000, plain; time = 0.0)))
        @test bar.document.thumb_drag === nothing
    end

    @testset "the pointer on the bar names it in the table and lights it" begin
        table, iomap = _print_bar_test_table(projection)
        _, _, bar = _find_table_test_bar(iomap)
        x, y = _get_table_test_bar_point(iomap, 100)
        path = ConcreteReference(FieldReferenceStep("vertical_scroll_bar"), EmptyReference())
        @test strip_reference_types(compute_part_at_point(iomap, x, y)) == path
        replace_mouse_target!(table, compute_part_at_point(iomap, x, y))
        @test get_mouse_target(bar.document) == EmptyReference()
        replace_mouse_target!(table, nothing)
        @test get_mouse_target(bar.document) === nothing
    end

    @testset "the bar of an owner keeps its writes" begin
        mine = WidgetScrollBar(:vertical; value = 0.0, thumb_size = 0.25)
        table, iomap = _print_bar_test_table(projection; vertical_scroll_bar = mine)
        _, _, bar = _find_table_test_bar(iomap)
        @test bar.document === mine
        x, y = _get_table_test_bar_point(iomap, Int(bar.place.h) - 2)
        click = read_intent(projection, iomap, MouseClick(:left, x, y, 1, plain; time = 0.0))
        @test _bar_test_written(click, mine, "value") ≈ 1 / 3
        @test Int(table.scroll_position.y[]) == 0
    end
end
