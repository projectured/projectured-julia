# A collapsible WidgetCard shows its fold state. A chevron sits before the
# title, pointing down while the card is open and right while it is collapsed;
# the whole header band is the fold target; and a collapsed card draws its
# header and nothing else. A card that names its own padding draws with it.

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

        # A click on the chevron folds, and so does one on the title.
        on_chevron = read_intent(proj, iomap, MousePress(:left, 20, 28, ModifierKeys()))
        @test on_chevron isa ToggleCollapseOperation && on_chevron.target === card
        on_title = read_intent(proj, iomap, MousePress(:left, 40, 28, ModifierKeys()))
        @test on_title isa ToggleCollapseOperation && on_title.target === card

        # Folded: the mark points right, and the body is not drawn.
        evaluate_operation(nothing, on_title)
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
        # A click left of the title is a click on the padding, not a fold.
        @test !(read_intent(proj, iomap, MousePress(:left, 4, 28, ModifierKeys())) isa ToggleCollapseOperation)
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
