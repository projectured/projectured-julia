# A scrolled pane must translate EVERY pointer event, not only the press.
#
# The canvas variant of the scroll pane translated `MousePress` and
# `MouseScroll` and forwarded the rest untouched, so motion and the hover
# crossings reached the content in the pane's own frame: a scrolled list
# highlighted the row that would be under the pointer if it had never been
# scrolled, while a click on the same pixel selected the row that was really
# there. Hover and click disagreeing by exactly the scroll offset is the
# signature.
#
# The offset a pane translates by is the one it draws with. A pane that follows
# the end draws its end whatever `scroll_position` holds, so a press there must
# go to the row drawn at the end.

_scroll_pane_projection() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(font_ubuntu_monospace_regular_20;
                     measure = measure_truetype_text).dispatch))

_scroll_pane_list() =
    WidgetList(Point2D(0, 0), ["row $i" for i in 1:40]; selected = 0, width = 200)

# The row a pointer event resolves to, whatever form the answer takes.
function _scroll_pane_row(projection, iomap, evt)
    op = read_intent(projection, iomap, evt)
    op isa ReplaceViewStateOperation && (op = get_wrapped_operation(op))
    op === nothing ? nothing :
    hasproperty(op, :value) ? op.value :
    hasproperty(op, :path)  ? op.path  : op
end

# The viewport a pane draws its content in, and so the offset it draws with.
_scroll_pane_viewport(iomap) = only(e for e in iomap.output.elements if e isa GraphicsViewport)

function test_scroll_pane_hover()
    @testset "a scrolled pane translates motion, not just presses" begin
        list = _scroll_pane_list()
        pane = WidgetScrollPane(list; size = Point2D(200, 200))
        projection = _scroll_pane_projection()
        iomap = print_document(projection, pane)

        # The row a press resolves to is the reference standard: it was correct
        # before this fix and must stay correct after it.
        row_of(evt) = _scroll_pane_row(projection, iomap, evt)

        y = 100
        getfield(pane, :scroll_position)[] = Point2D(0, 0)
        press_unscrolled = row_of(MousePress(:left, 20, y))
        hover_unscrolled = row_of(MouseMove(20, y))
        @test hover_unscrolled !== nothing

        # Scroll by whole rows and ask again at the SAME pixel.
        getfield(pane, :scroll_position)[] = Point2D(0, 120)
        press_scrolled = row_of(MousePress(:left, 20, y))
        hover_scrolled = row_of(MouseMove(20, y))

        # Scrolling has to change what is under the pointer …
        @test hover_scrolled != hover_unscrolled
        # … and hover must agree with the press, which is what broke.
        @test hover_scrolled isa Integer
        @test press_scrolled != press_unscrolled
    end

    # A pane that follows the end draws its end, and its `scroll_position`
    # still holds zero. A press must go to the row drawn under it, which is the
    # row a pane scrolled to the same offset by hand selects.
    @testset "a pane that follows the end routes a press to what it draws" begin
        projection = _scroll_pane_projection()
        following = print_document(projection,
            WidgetScrollPane(_scroll_pane_list(); size = Point2D(200, 200), follow_end = true))
        room = Int(following.content_iomap.output.h) - 200
        @test room > 0
        @test Int(_scroll_pane_viewport(following).content.y) == -room
        scrolled = print_document(projection,
            WidgetScrollPane(_scroll_pane_list(); size = Point2D(200, 200),
                             scroll_position = Point2D(0, room)))
        unscrolled = print_document(projection,
            WidgetScrollPane(_scroll_pane_list(); size = Point2D(200, 200)))
        for y in (10, 100, 190)
            press = MousePress(:left, 20, y)
            row = _scroll_pane_row(projection, following, press)
            @test row == _scroll_pane_row(projection, scrolled, press)
            @test row != _scroll_pane_row(projection, unscrolled, press)
        end
        # The bottom of the pane is the last row.
        @test string(_scroll_pane_row(projection, following, MousePress(:left, 20, 190))) ==
              ".content.items[40]"
    end

    # A card that opens makes the content taller than the pane. The pane that
    # drew it shows the new end, and a press there goes to the row drawn under
    # it.
    @testset "a pane that follows the end follows a content that grows" begin
        projection = _scroll_pane_projection()
        make_card(collapsed) = WidgetCard(Point2D(0, 0); title = WidgetLabel(Point2D(0, 0), "rows"),
                                          content = _scroll_pane_list(), collapsible = true,
                                          collapsed = collapsed)
        card = make_card(true)
        following = print_document(projection,
            WidgetScrollPane(card; size = Point2D(200, 200), follow_end = true))
        # Folded, the card fits, and the pane does not scroll it.
        @test Int(_scroll_pane_viewport(following).content.y) == 0

        evaluate_operation(nothing, ToggleCollapseOperation(card))
        @test card.collapsed == false
        room = Int(following.content_iomap.output.h) - 200
        @test room > 0
        @test Int(_scroll_pane_viewport(following).content.y) == -room
        scrolled = print_document(projection,
            WidgetScrollPane(make_card(false); size = Point2D(200, 200),
                             scroll_position = Point2D(0, room)))
        # The press lands past the card's padding and chevron column, on the
        # last row of the list.
        press = MousePress(:left, 60, 160)
        @test string(_scroll_pane_row(projection, following, press)) ==
              ".content.content.items[40]"
        @test _scroll_pane_row(projection, following, press) ==
              _scroll_pane_row(projection, scrolled, press)
    end

    # A document that owns whether its view follows its end hands the pane its
    # own cell. A wheel that leaves the end writes the document's flag, and the
    # document's owner writing it back brings the end into view again.
    @testset "a pane follows a cell a document owns" begin
        projection = _scroll_pane_projection()
        owned = Cell(true)
        pane = WidgetScrollPane(_scroll_pane_list(); size = Point2D(200, 200),
                                follow_end = owned)
        @test getfield(pane, :follow_end) === owned
        iomap = print_document(projection, pane)
        room = Int(iomap.content_iomap.output.h) - 200
        @test room > 0
        @test Int(_scroll_pane_viewport(iomap).content.y) == -room
        # Up one notch: the pane leaves the end, and the owner's cell says so.
        up = read_intent(projection, iomap, MouseScroll(0, 1, 100, 100))
        @test up !== nothing
        evaluate_operation(nothing, up)
        @test owned[] == false
        @test Int(_scroll_pane_viewport(iomap).content.y) > -room
        # The owner asks for the end, and the pane draws it.
        owned[] = true
        @test Int(_scroll_pane_viewport(iomap).content.y) == -room
    end
end
