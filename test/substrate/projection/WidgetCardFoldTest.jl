# A collapsible WidgetCard shows its fold state. A chevron sits before the
# title, pointing down while the card is open and right while it is collapsed;
# the chevron's column is the fold target, and nothing else is; and a collapsed
# card draws its header and nothing else. A card that names its own padding
# draws with it.

_fold_font = font_ubuntu_monospace_regular_20
_fold_stub(t, f) = (length(t) * 10, 24)
_fold_proj() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(_fold_font; measure=_fold_stub).dispatch))

# The text of every GraphicsText under a canvas, the fold mark's glyph among them.
function _fold_texts(canvas, texts = String[])
    for elem in canvas.elements
        if elem isa GraphicsText
            push!(texts, String(elem.text))
        elseif elem isa GraphicsCanvas
            _fold_texts(elem, texts)
        end
    end
    texts
end

# The direction of the fold mark: the chevron glyph among the drawn texts.
function _chevron_direction(texts)
    down = string(find_icon_character(:chevron_down)) in texts
    right = string(find_icon_character(:chevron_right)) in texts
    down == right && return nothing
    down ? :down : :right
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
        texts = _fold_texts(canvas)
        @test _chevron_direction(texts) === :down
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
        texts = _fold_texts(canvas)
        @test _chevron_direction(texts) === :right
        @test !(body in texts)
        @test "Details" in texts
    end

    @testset "a card that does not fold draws no chevron" begin
        card = WidgetCard(Point2D(0, 0); title = _fold_title(), content = "x")
        proj = _fold_proj()
        iomap = print_document(proj, proj, card, PrinterContext())
        texts = _fold_texts(iomap.output)
        @test _chevron_direction(texts) === nothing
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

    @testset "a card with its own padding" begin
        proj = _fold_proj()
        themed = print_document(proj, proj, WidgetCard(Point2D(0, 0); content = "abc", variant = :plain),
                                PrinterContext()).output
        bare = print_document(proj, proj, WidgetCard(Point2D(0, 0); content = "abc", variant = :plain,
                                                     padding = Inset(0, 0, 0, 0)),
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
