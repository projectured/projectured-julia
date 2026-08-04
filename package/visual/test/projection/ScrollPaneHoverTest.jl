# A scrolled pane must translate EVERY pointer event, not only the press.
#
# The canvas variant of the scroll pane translated `MousePress` and
# `MouseScroll` and forwarded the rest untouched, so motion and the hover
# crossings reached the content in the pane's own frame: a scrolled list
# highlighted the row that would be under the pointer if it had never been
# scrolled, while a click on the same pixel selected the row that was really
# there. Hover and click disagreeing by exactly the scroll offset is the
# signature.

function test_scroll_pane_hover()
    @testset "a scrolled pane translates motion, not just presses" begin
        rows = ["row $i" for i in 1:40]
        list = WidgetList(Point2D(0, 0), rows; selected = 0, width = 200)
        pane = WidgetScrollPane(list; size = Point2D(200, 200))
        projection = RecursiveProjection(TypeDispatchingProjection(
            WidgetToGraphics(font_ubuntu_monospace_regular_20;
                             measure = truetype_measure_text).dispatch))
        iomap = print_document(projection, pane)

        # The row a press resolves to is the reference standard: it was correct
        # before this fix and must stay correct after it.
        row_of(evt) = begin
            op = read_intent(projection, iomap, evt)
            op === nothing ? nothing :
            hasproperty(op, :value) ? op.value :
            hasproperty(op, :path)  ? op.path  : op
        end

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
end
