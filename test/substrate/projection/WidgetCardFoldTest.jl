# A collapsible WidgetCard shows its fold state. A chevron sits before the
# title, pointing down while the card is open and right while it is collapsed;
# the chevron's column is the fold target, and nothing else is; and a collapsed
# card draws its header and nothing else. A card that names its own padding
# draws with it. A WidgetAccordion opens and closes an item from its header.

_fold_font = font_ubuntu_monospace_regular_20
_fold_stub(t, f) = (length(t) * 10, 24)
_fold_proj() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(_fold_font; measure=_fold_stub).dispatch))

# Every GraphicsLine under a canvas, and the text of every GraphicsText.
function _fold_collect(canvas, lines = Any[], texts = String[])
    for elem in canvas.elements
        if elem isa GraphicsLine
            push!(lines, elem)
        elseif elem isa GraphicsText
            push!(texts, String(elem.text))
        elseif elem isa GraphicsCanvas
            _fold_collect(elem, lines, texts)
        end
    end
    (lines, texts)
end

# The direction of a two-line chevron: the point the two lines share is the
# lowest point of a `:down` mark and the rightmost point of a `:right` mark.
function _chevron_direction(lines)
    length(lines) == 2 || return nothing
    a, b = lines
    shared = (Int(a.x2), Int(a.y2))
    (Int(b.x1), Int(b.y1)) == shared || return nothing
    xs = (Int(a.x1), Int(a.x2), Int(b.x2))
    ys = (Int(a.y1), Int(a.y2), Int(b.y2))
    shared[1] == maximum(xs) && return :right
    shared[2] == maximum(ys) && return :down
    nothing
end

# Where each drawn text starts, in the frame the widget is placed in.
function _fold_text_positions(canvas, ox = 0, oy = 0, found = Dict{String,Tuple{Int,Int}}())
    x = ox + Int(canvas.x); y = oy + Int(canvas.y)
    for elem in canvas.elements
        if elem isa GraphicsText
            found[String(elem.text)] = (x + Int(elem.x), y + Int(elem.y))
        elseif elem isa GraphicsCanvas
            _fold_text_positions(elem, x, y, found)
        end
    end
    found
end

_fold_title() = WidgetLabel(Point2D(0, 0), "Details")
_fold_title_x(iomap) = getfield(iomap, :child_iomaps)[][1][1]

function test_widget_card_fold()
    @testset "a collapsible card shows its fold state" begin
        body = "the body of the card"
        card = WidgetCard(Point2D(0, 0); title = _fold_title(), content = body, collapsible = true)
        proj = _fold_proj()
        iomap = print_document(proj, proj, card, PrinterContext())
        canvas = iomap.output
        lines, texts = _fold_collect(canvas)
        @test _chevron_direction(lines) === :down
        @test body in texts
        @test "Details" in texts

        # The title moved right, by the column the chevron takes, and the body
        # moved with it: the body lines up under the title's word.
        plain = WidgetCard(Point2D(0, 0); title = _fold_title(), content = body)
        plain_iomap = print_document(proj, proj, plain, PrinterContext())
        @test _fold_title_x(iomap) > _fold_title_x(plain_iomap)
        document_body = WidgetCard(Point2D(0, 0); title = _fold_title(),
                                   content = WidgetLabel(Point2D(0, 0), body), collapsible = true)
        entries = getfield(print_document(proj, proj, document_body, PrinterContext()), :child_iomaps)[]
        @test length(entries) == 2
        @test entries[2][1] == entries[1][1]

        # A click on the chevron folds, and so does one at the right edge of its
        # column. A click on the title does not.
        title_x = _fold_title_x(iomap)
        on_chevron = read_intent(proj, iomap, MousePress(:left, 20, 28, ModifierKeys()))
        @test on_chevron isa ToggleCollapseOperation && on_chevron.target === card
        on_column = read_intent(proj, iomap, MousePress(:left, title_x - 1, 28, ModifierKeys()))
        @test on_column isa ToggleCollapseOperation && on_column.target === card
        on_title = read_intent(proj, iomap, MousePress(:left, title_x + 2, 28, ModifierKeys()))
        @test !(on_title isa ToggleCollapseOperation)

        # Folded: the mark points right, and the body is not drawn.
        evaluate_operation(nothing, on_chevron)
        @test card.collapsed == true
        lines, texts = _fold_collect(canvas)
        @test _chevron_direction(lines) === :right
        @test !(body in texts)
        @test "Details" in texts
    end

    @testset "a card that does not fold draws no chevron" begin
        card = WidgetCard(Point2D(0, 0); title = _fold_title(), content = "x")
        proj = _fold_proj()
        iomap = print_document(proj, proj, card, PrinterContext())
        lines, _ = _fold_collect(iomap.output)
        @test isempty(lines)
        # A click left of the title is a click on the padding, not a fold, and a
        # click on the title is not a fold either: a card that draws no chevron
        # does not fold from a click.
        @test !(read_intent(proj, iomap, MousePress(:left, 4, 28, ModifierKeys())) isa ToggleCollapseOperation)
        title_x = _fold_title_x(iomap)
        @test !(read_intent(proj, iomap, MousePress(:left, title_x + 2, 28, ModifierKeys())) isa ToggleCollapseOperation)
    end

    # A container routes a press to a card only over something the card drew. A
    # `:plain` card draws no panel, and the two strokes of the mark leave most of
    # the chevron's column empty, so the column carries a hit target of its own.
    @testset "a plain card folds from anywhere in its chevron's column" begin
        proj = _fold_proj()
        make_card() = WidgetCard(Point2D(0, 0); title = _fold_title(), content = "x",
                                 variant = :plain, collapsible = true)
        title_x = _fold_title_x(print_document(proj, proj, make_card(), PrinterContext()))
        card = make_card()
        iomap = print_document(proj, proj, WidgetComposite(Point2D(0, 0), Any[card]), PrinterContext())
        on_column = read_intent(proj, iomap, MousePress(:left, title_x - 1, 28, ModifierKeys()))
        @test on_column isa ToggleCollapseOperation && on_column.target === card
        on_title = read_intent(proj, iomap, MousePress(:left, title_x + 2, 28, ModifierKeys()))
        @test !(on_title isa ToggleCollapseOperation)
    end

    @testset "a press on the header of an accordion item opens or closes it" begin
        accordion = WidgetAccordion(Point2D(20, 10), [("First", "the first body"),
                                                      ("Second", "the second body")]; expanded = 1)
        proj = _fold_proj()
        iomap = print_document(proj, proj, accordion, PrinterContext())
        _, texts = _fold_collect(iomap.output)
        @test "the first body" in texts && !("the second body" in texts)
        at = _fold_text_positions(iomap.output)
        second = at["Second"]
        press(x, y; button = :left) = read_intent(proj, iomap, MousePress(button, x, y, ModifierKeys()))

        # A press on the title of a closed item opens it, and the other one closes.
        opened = press(second[1] + 2, second[2] + 2)
        @test opened isa ReplaceReferencedValueOperation
        @test opened.document === accordion && opened.value == 2
        evaluate_operation(nothing, opened)
        _, texts = _fold_collect(iomap.output)
        @test "the second body" in texts && !("the first body" in texts)

        # The whole header row is the target, the chevron at its right end too, and
        # a press on the open item closes it.
        right = Int(iomap.output.x) + Int(iomap.output.w) - 3
        second = _fold_text_positions(iomap.output)["Second"]
        closed = press(right, second[2] + 2)
        @test closed isa ReplaceReferencedValueOperation && closed.value == 0
        evaluate_operation(nothing, closed)
        _, texts = _fold_collect(iomap.output)
        @test !("the first body" in texts) && !("the second body" in texts)

        # A press on a body, a right press and a press outside answer nothing.
        evaluate_operation(nothing, ReplaceReferencedValueOperation(accordion, "expanded", 1))
        body = _fold_text_positions(iomap.output)["the first body"]
        @test press(body[1] + 2, body[2] + 2) === nothing
        first = _fold_text_positions(iomap.output)["First"]
        @test press(first[1] + 2, first[2] + 2; button = :right) === nothing
        @test press(first[1] + 2, 5) === nothing
    end

    @testset "an accordion draws a title and a body that are documents through the recursion" begin
        box = WidgetCheckbox(Point2D(0, 0), false)
        body = VerticalLayout(Any[WidgetLabel(Point2D(0, 0), "inner body"), box]; gap = 4)
        accordion = WidgetAccordion(Point2D(0, 0),
                                    [(WidgetLabel(Point2D(0, 0), "Document title"), body),
                                     ("Plain title", "the plain body")]; expanded = 1)
        proj = RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            WidgetToGraphics(_fold_font; measure = _fold_stub).dispatch)))
        iomap = print_document(proj, proj, accordion, PrinterContext())
        _, texts = _fold_collect(iomap.output)
        # Each document draws its own text, and no document is drawn as its string.
        @test "Document title" in texts
        @test "inner body" in texts
        @test "Plain title" in texts
        @test !any(text -> occursin("Widget", text) || occursin("Layout", text), texts)
        at = _fold_text_positions(iomap.output)
        # The body is below the header of its item, and the next item below the body.
        @test at["Document title"][2] < at["inner body"][2] < at["Plain title"][2]

        # A press on a control in the open body reaches the control.
        toggled = nothing
        for y in at["inner body"][2]:2:(at["Plain title"][2] - 1), x in 0:2:60
            answer = read_intent(proj, iomap, MousePress(:left, x, y, ModifierKeys()))
            if answer isa ReplaceReferencedValueOperation && answer.document === box
                toggled = answer
                break
            end
        end
        @test toggled !== nothing && toggled.value === true
        # A press on the header of the item still closes it.
        title = at["Document title"]
        closed = read_intent(proj, iomap, MousePress(:left, title[1] + 2, title[2] + 2, ModifierKeys()))
        @test closed isa ReplaceReferencedValueOperation && closed.document === accordion &&
              closed.value == 0
        evaluate_operation(nothing, closed)
        _, texts = _fold_collect(iomap.output)
        @test "Document title" in texts && !("inner body" in texts)
    end

    @testset "a card with its own padding" begin
        proj = _fold_proj()
        themed = print_document(proj, proj, WidgetCard(Point2D(0, 0); content = "abc", variant = :plain),
                                PrinterContext()).output
        bare = print_document(proj, proj, WidgetCard(Point2D(0, 0); content = "abc", variant = :plain, padding = 0),
                              PrinterContext()).output
        # The themed padding is 16 on each side; the bare card has none.
        @test Int(bare.w[]) == Int(themed.w[]) - 32
        @test Int(bare.h[]) == Int(themed.h[]) - 32
        # An Inset names each side: this one indents and does nothing else.
        indented = print_document(proj, proj, WidgetCard(Point2D(0, 0); content = "abc", variant = :plain,
                                                         padding = Inset(0, 0, 12, 0)),
                                  PrinterContext()).output
        @test Int(indented.w[]) == Int(bare.w[]) + 12
        @test Int(indented.h[]) == Int(bare.h[])
    end
end
