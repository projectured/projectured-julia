# A scrolled pane must give the light and the press the same row.
#
# The light under the pointer comes from the mouse target that a move writes:
# the point maps backward through the pane to the row it draws there. The press
# is translated by the pane. A scrolled list that lit the row that would be under
# the pointer if it had never been scrolled, while a click on the same pixel
# selected the row that was really there, is the signature of a pane that does
# not map by its scroll offset.
#
# The offset a pane translates by is the one it draws with. A pane that follows
# the end draws its end whatever `scroll_position` holds, so a press there must
# go to the row drawn at the end.

_scroll_pane_projection() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(StyleFont("Ubuntu Mono", 20);
                     measure = FontFileMeasure()).dispatch))

_scroll_pane_list() =
    WidgetList(["row $i" for i in 1:40]; selected = 0, width = 200)

# A content of rows that the pane scrolls: a list in a stack, which gives the list
# no slot, so the list is as tall as its rows and does not scroll itself.
_scroll_pane_rows(list = _scroll_pane_list()) = VerticalLayout(Any[list])

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
    @testset "a list that scrolls under a still pointer lights the row now under it" begin
        list = _scroll_pane_list()
        pane = WidgetScrollPane(_scroll_pane_rows(list); size = Point2D(200, 200))
        projection = _scroll_pane_projection()
        iomap = print_document(projection, pane)
        driver = MttDriver(projection, pane)

        # The row a press resolves to is the reference standard.
        row_of(evt) = _scroll_pane_row(projection, iomap, evt)
        last_row(path) = last(collect(get_reference_steps(strip_reference_types(path))))

        y = 100
        getfield(pane, :scroll_position)[] = Point2D(0, 0)
        press_unscrolled = row_of(MouseClick(:left, 20, y; time = 0.0))
        _mtt_move!(driver, 20, y, 1.0)
        hover_unscrolled = WidgetModule._widget_element_selected(get_mouse_target(list), "items")
        @test hover_unscrolled > 0
        @test last_row(press_unscrolled) == ElementReferenceStep(hover_unscrolled)

        # Scroll by whole rows under the still pointer: the new frame finds the
        # row that is now under it (D41). After a frame that changed a window,
        # the backend sends a move at the point where the pointer is.
        getfield(pane, :scroll_position)[] = Point2D(0, 120)
        _mtt_move!(driver, 20, y, 1.1)
        press_scrolled = row_of(MouseClick(:left, 20, y; time = 0.0))
        hover_scrolled = WidgetModule._widget_element_selected(get_mouse_target(list), "items")

        # Scrolling has to change what is under the pointer …
        @test hover_scrolled > hover_unscrolled
        @test press_scrolled != press_unscrolled
        # … and the light must agree with the press.
        @test last_row(press_scrolled) == ElementReferenceStep(hover_scrolled)
    end

    # A pane that follows the end draws its end, and its `scroll_position`
    # still holds zero. A press must go to the row drawn under it, which is the
    # row a pane scrolled to the same offset by hand selects.
    @testset "a pane that follows the end routes a press to what it draws" begin
        projection = _scroll_pane_projection()
        following = print_document(projection,
            WidgetScrollPane(_scroll_pane_rows(); size = Point2D(200, 200), follow_end = true))
        room = Int(following.content_iomap.output.h) - 200
        @test room > 0
        @test Int(_scroll_pane_viewport(following).content.y) == -room
        scrolled = print_document(projection,
            WidgetScrollPane(_scroll_pane_rows(); size = Point2D(200, 200),
                             scroll_position = Point2D(0, room)))
        unscrolled = print_document(projection,
            WidgetScrollPane(_scroll_pane_rows(); size = Point2D(200, 200)))
        for y in (10, 100, 190)
            press = MouseClick(:left, 20, y; time = 0.0)
            row = _scroll_pane_row(projection, following, press)
            @test row == _scroll_pane_row(projection, scrolled, press)
            @test row != _scroll_pane_row(projection, unscrolled, press)
        end
        # The bottom of the pane is the last row.
        @test endswith(string(strip_reference_types(
                           _scroll_pane_row(projection, following, MouseClick(:left, 20, 190; time = 0.0)))),
                       ".items[40]")
    end

    # A card that opens makes the content taller than the pane. The pane that
    # drew it shows the new end, and a press there goes to the row drawn under
    # it.
    @testset "a pane that follows the end follows a content that grows" begin
        projection = _scroll_pane_projection()
        make_card(collapsed) = WidgetCard(; title = WidgetLabel("rows"),
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
        press = MouseClick(:left, 60, 160; time = 0.0)
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
        pane = WidgetScrollPane(_scroll_pane_rows(); size = Point2D(200, 200),
                                follow_end = owned)
        @test getfield(pane, :follow_end) === owned
        iomap = print_document(projection, pane)
        room = Int(iomap.content_iomap.output.h) - 200
        @test room > 0
        @test Int(_scroll_pane_viewport(iomap).content.y) == -room
        # Up one notch: the pane leaves the end, and the owner's cell says so.
        up = read_intent(projection, iomap, MouseScroll(0, 1, 100, 100; time = 0.0))
        @test up !== nothing
        evaluate_operation(nothing, up)
        @test owned[] == false
        @test Int(_scroll_pane_viewport(iomap).content.y) > -room
        # The owner asks for the end, and the pane draws it.
        owned[] = true
        @test Int(_scroll_pane_viewport(iomap).content.y) == -room
    end
end
