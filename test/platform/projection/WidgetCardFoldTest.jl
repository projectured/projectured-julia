# A collapsible WidgetCard shows its fold state. A chevron sits before the
# title, pointing down while the card is open and right while it is collapsed;
# the chevron's column is the fold target, and nothing else is; and a collapsed
# card draws its header and nothing else. A card that names its own padding
# draws with it. A card takes a plain left click on its own area. A WidgetAccordion
# opens and closes an item from its header.

_fold_font = StyleFont("Ubuntu Mono", 20)
_fold_stub = FixedMeasure(10, 18, 6, 0)
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

_fold_title() = WidgetLabel("Details")
_fold_title_x(iomap) = getfield(iomap, :child_iomaps)[][1][1]

function test_widget_card_fold()
    @testset "a collapsible card shows its fold state" begin
        body = "the body of the card"
        card = WidgetCard(; title = _fold_title(), content = body, collapsible = true)
        proj = _fold_proj()
        iomap = print_document(proj, proj, card, PrinterContext())
        canvas = iomap.output
        texts = _fold_texts(canvas)
        @test _chevron_direction(texts) === :down
        @test body in texts
        @test "Details" in texts

        # The title moved right, by the column the chevron takes, and the body
        # moved with it: the body lines up under the title's word.
        plain = WidgetCard(; title = _fold_title(), content = body)
        plain_iomap = print_document(proj, proj, plain, PrinterContext())
        @test _fold_title_x(iomap) > _fold_title_x(plain_iomap)
        document_body = WidgetCard(; title = _fold_title(),
                                   content = WidgetLabel(body), collapsible = true)
        entries = getfield(print_document(proj, proj, document_body, PrinterContext()), :child_iomaps)[]
        @test length(entries) == 2
        @test entries[2][1] == entries[1][1]

        # A click on the chevron folds, and so does one at the right edge of its
        # column. A click on the title does not.
        title_x = _fold_title_x(iomap)
        on_chevron = read_intent(proj, iomap, MouseClick(:left, 20, 28, ModifierKeys(); time = 0.0))
        @test on_chevron isa ToggleCollapseOperation && on_chevron.target === card
        on_column = read_intent(proj, iomap, MouseClick(:left, title_x - 1, 28, ModifierKeys(); time = 0.0))
        @test on_column isa ToggleCollapseOperation && on_column.target === card
        on_title = read_intent(proj, iomap, MouseClick(:left, title_x + 2, 28, ModifierKeys(); time = 0.0))
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
        card = WidgetCard(; title = _fold_title(), content = "x")
        proj = _fold_proj()
        iomap = print_document(proj, proj, card, PrinterContext())
        texts = _fold_texts(iomap.output)
        @test _chevron_direction(texts) === nothing
        # A click left of the title is a click on the padding, not a fold, and a
        # click on the title is not a fold either: a card that draws no chevron
        # does not fold from a click.
        @test !(read_intent(proj, iomap, MouseClick(:left, 4, 28, ModifierKeys(); time = 0.0)) isa ToggleCollapseOperation)
        title_x = _fold_title_x(iomap)
        @test !(read_intent(proj, iomap, MouseClick(:left, title_x + 2, 28, ModifierKeys(); time = 0.0)) isa ToggleCollapseOperation)
    end

    # A container routes a press to a card only over something the card drew. A
    # `:plain` card draws no panel, and the two strokes of the mark leave most of
    # the chevron's column empty, so the column carries a hit target of its own.
    @testset "a plain card folds from anywhere in its chevron's column" begin
        proj = _fold_proj()
        make_card() = WidgetCard(; title = _fold_title(), content = "x",
                                 variant = :plain, collapsible = true)
        title_x = _fold_title_x(print_document(proj, proj, make_card(), PrinterContext()))
        card = make_card()
        iomap = print_document(proj, proj, WidgetComposite(Any[card]), PrinterContext())
        on_column = read_intent(proj, iomap, MouseClick(:left, title_x - 1, 28, ModifierKeys(); time = 0.0))
        @test on_column isa ToggleCollapseOperation && on_column.target === card
        on_title = read_intent(proj, iomap, MouseClick(:left, title_x + 2, 28, ModifierKeys(); time = 0.0))
        @test !(on_title isa ToggleCollapseOperation)
    end

    @testset "a press on the header of an accordion item opens or closes it" begin
        accordion = WidgetAccordion([("First", "the first body"),
                                                      ("Second", "the second body")]; position = Point2D(20, 10), expanded = 1)
        proj = _fold_proj()
        iomap = print_document(proj, proj, accordion, PrinterContext())
        texts = _fold_texts(iomap.output)
        @test "the first body" in texts && !("the second body" in texts)
        at = _fold_text_positions(iomap.output)
        second = at["Second"]
        # The test is the window: it gives the accordion a press in the frame of
        # its own canvas, the drawn place less the place of the canvas.
        press(x, y; button = :left) =
            read_intent(proj, iomap, MouseClick(button, x - Int(iomap.output.x), y - Int(iomap.output.y),
                                                ModifierKeys(); time = 0.0))

        # A press on the title of a closed item opens it, and the other one closes.
        # It is view state, so a history does not record it.
        opened = press(second[1] + 2, second[2] + 2)
        @test opened isa ReplaceViewStateOperation
        @test get_wrapped_operation(opened).document === accordion &&
              get_wrapped_operation(opened).value == 2
        evaluate_operation(nothing, opened)
        texts = _fold_texts(iomap.output)
        @test "the second body" in texts && !("the first body" in texts)

        # The whole header row is the target, the chevron at its right end too, and
        # a press on the open item closes it.
        right = Int(iomap.output.x) + Int(iomap.output.w) - 3
        second = _fold_text_positions(iomap.output)["Second"]
        closed = press(right, second[2] + 2)
        @test closed isa ReplaceViewStateOperation && get_wrapped_operation(closed).value == 0
        evaluate_operation(nothing, closed)
        texts = _fold_texts(iomap.output)
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
        box = WidgetCheckbox(false)
        body = VerticalLayout(Any[WidgetLabel("inner body"), box]; gap = 4)
        accordion = WidgetAccordion([(WidgetLabel("Document title"), body),
                                     ("Plain title", "the plain body")]; expanded = 1)
        proj = RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            WidgetToGraphics(_fold_font; measure = _fold_stub).dispatch)))
        iomap = print_document(proj, proj, accordion, PrinterContext())
        texts = _fold_texts(iomap.output)
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
            answer = read_intent(proj, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
            if answer isa ReplaceReferencedValueOperation && answer.document === box
                toggled = answer
                break
            end
        end
        @test toggled !== nothing && toggled.value === true
        # A press on the header of the item still closes it.
        title = at["Document title"]
        closed = read_intent(proj, iomap, MouseClick(:left, title[1] + 2, title[2] + 2, ModifierKeys(); time = 0.0))
        @test closed isa ReplaceViewStateOperation &&
              get_wrapped_operation(closed).document === accordion &&
              get_wrapped_operation(closed).value == 0
        evaluate_operation(nothing, closed)
        texts = _fold_texts(iomap.output)
        @test "Document title" in texts && !("inner body" in texts)
    end

    @testset "a card with its own padding" begin
        proj = _fold_proj()
        themed = print_document(proj, proj, WidgetCard(; content = "abc", variant = :plain),
                                PrinterContext()).output
        bare = print_document(proj, proj, WidgetCard(; content = "abc", variant = :plain,
                                                     padding = Inset(0, 0, 0, 0)),
                              PrinterContext()).output
        # The themed padding is 12 on each side; the bare card has none.
        @test Int(bare.w[]) == Int(themed.w[]) - 24
        @test Int(bare.h[]) == Int(themed.h[]) - 24
        # An Inset names each side: this one indents and does nothing else.
        indented = print_document(proj, proj, WidgetCard(; content = "abc", variant = :plain,
                                                         padding = Inset(0, 0, 12, 0)),
                                  PrinterContext()).output
        @test Int(indented.w[]) == Int(bare.w[]) + 12
        @test Int(indented.h[]) == Int(bare.h[])
    end

    # A card is a solid surface, so a plain left click on it that nothing inside it
    # uses ends at the card. A right click and an Alt+click go on, to the menus of
    # the parts around the card and to a whole selection.
    @testset "a card takes a plain left click on its own area" begin
        proj = _fold_proj()
        iomap = print_document(proj, proj, WidgetCard(; content = "abc", variant = :plain), PrinterContext())
        click(button, x, y; modifiers = ModifierKeys()) =
            read_intent(proj, iomap, MouseClick(button, x, y, modifiers; time = 0.0))
        @test click(:left, 4, 4) isa DoNothingOperation          # the padding
        @test !(click(:right, 4, 4) isa DoNothingOperation)
        @test !(click(:left, 4, 4; modifiers = ModifierKeys(alt = true)) isa DoNothingOperation)
        @test click(:left, 500, 500) === nothing                  # off the card
    end
end
