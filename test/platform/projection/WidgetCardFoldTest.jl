# A collapsible WidgetCard shows its fold state. A chevron sits before the
# title, pointing down while the card is open and right while it is collapsed;
# the chevron's column is the fold target, and nothing else is; and a collapsed
# card draws its header and nothing else. A card that names its own padding
# draws with it. A card takes a plain left click on its own area. A WidgetAccordion
# opens and closes an item from its header.

_fold_stub = FixedMeasure(10, 18, 6, 0)
# The padding of a card in the default theme: a click at `_fold_pad + 16` is on the title row.
_fold_pad = get_theme_defaults(WidgetTheme).container_padding
_fold_proj() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(; measure=_fold_stub).dispatch))

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

# A dispatch that prints a `PrimitiveString` as the editor's does: through the text
# domain, so a title that is a `PrimitiveString` has a printer to draw it.
_title_proj() = RecursiveProjection(TypeDispatchingProjection(vcat(
    WidgetToGraphics(; measure = _fold_stub).dispatch,
    Pair{Type,Any}[PrimitiveDocument => ChainingProjection(PrimitiveToText(),
                                                           TextToGraphics(; measure = _fold_stub))])))

# The card printer of the dispatch, whose `title_text` and `row_selected_color` a title draws with.
_title_printer() = WidgetCardToGraphicsCanvas(WidgetTheme(); measure = _fold_stub)

# The font of the first text `text` under a canvas, or `nothing`.
function _find_text_font(canvas, text)
    for elem in canvas.elements
        elem isa GraphicsText && String(elem.text) == text && return elem.font
        if elem isa GraphicsCanvas
            found = _find_text_font(elem, text)
            found === nothing || return found
        end
    end
    nothing
end

# The rects under a canvas that are filled with `color`.
function _find_rects_with_color(canvas, color, found = [])
    for elem in canvas.elements
        elem isa GraphicsRect && elem.color == color && push!(found, elem)
        elem isa GraphicsCanvas && _find_rects_with_color(elem, color, found)
    end
    found
end

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
        on_chevron = read_intent(proj, iomap, MouseClick(:left, _fold_pad + 8, _fold_pad + 16, ModifierKeys(); time = 0.0))
        @test on_chevron isa ToggleCollapseOperation && on_chevron.target === card
        on_column = read_intent(proj, iomap, MouseClick(:left, title_x - 1, _fold_pad + 16, ModifierKeys(); time = 0.0))
        @test on_column isa ToggleCollapseOperation && on_column.target === card
        on_title = read_intent(proj, iomap, MouseClick(:left, title_x + 2, _fold_pad + 16, ModifierKeys(); time = 0.0))
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
        @test !(read_intent(proj, iomap, MouseClick(:left, 4, _fold_pad + 16, ModifierKeys(); time = 0.0)) isa ToggleCollapseOperation)
        title_x = _fold_title_x(iomap)
        @test !(read_intent(proj, iomap, MouseClick(:left, title_x + 2, _fold_pad + 16, ModifierKeys(); time = 0.0)) isa ToggleCollapseOperation)
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
        on_column = read_intent(proj, iomap, MouseClick(:left, title_x - 1, _fold_pad + 16, ModifierKeys(); time = 0.0))
        @test on_column isa ToggleCollapseOperation && on_column.target === card
        on_title = read_intent(proj, iomap, MouseClick(:left, title_x + 2, _fold_pad + 16, ModifierKeys(); time = 0.0))
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
            WidgetToGraphics(; measure = _fold_stub).dispatch)))
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
        # The themed padding is `container_padding` on each side; the bare card has none.
        side = get_theme_defaults(WidgetTheme).container_padding
        @test Int(bare.w[]) == Int(themed.w[]) - 2side
        @test Int(bare.h[]) == Int(themed.h[]) - 2side
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

    # A binding of the card answers a plain left click that nothing inside the
    # card uses, before the card takes it as a solid surface.
    @testset "a binding of a card answers a plain left click on its own area" begin
        proj = _fold_proj()
        selected = (_, _) -> ReplaceSelectionOperation(
            ConcreteReference(FieldReferenceStep("content"), EmptyReference()))
        binding = GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), selected;
                                 description = "Select the content", domain = "test")
        card = WidgetCard(; content = "abc", variant = :plain, gestures = GestureBinding[binding])
        iomap = print_document(proj, proj, card, PrinterContext())
        click(x, y) = read_intent(proj, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        answer = click(4, 4)                                      # the padding
        @test answer isa ReplaceSelectionOperation
        @test strip_reference_types(answer.path) ==
              ConcreteReference(FieldReferenceStep("content"), EmptyReference())
        @test click(500, 500) === nothing                         # off the card
    end

    @testset "a String title draws in the title style, folds, and is selected as the part title" begin
        printer = _title_printer()
        title_font = printer.title_text.font
        proj = _title_proj()
        label_font = _find_text_font(print_document(proj, proj,
            WidgetCard(; title = WidgetLabel("Details"), content = "x"), PrinterContext()).output, "Details")
        @test label_font != title_font
        card = WidgetCard(; title = "Details", content = "the body", collapsible = true)
        iomap = print_document(proj, proj, card, PrinterContext())
        @test _find_text_font(iomap.output, "Details") == title_font
        @test _find_text_font(iomap.output, "the body") != title_font

        # The chevron folds the card, as it does for a document title.
        press(x, y; modifiers = ModifierKeys(), button = :left) =
            read_intent(proj, iomap, MouseClick(button, x, y, modifiers; time = 0.0))
        title_x = iomap.header.title_box[1]
        on_chevron = press(_fold_pad + 8, _fold_pad + 8)
        @test on_chevron isa ToggleCollapseOperation && on_chevron.target === card
        @test !(press(title_x + 2, _fold_pad + 8) isa ToggleCollapseOperation)
        @test iomap.header.height > 0

        # An Alt+press on the title selects its field, a plain press puts the caret
        # in it, and a right press selects neither.
        title = ConcreteReference(FieldReferenceStep("title"), EmptyReference())
        selected = press(title_x + 2, _fold_pad + 8; modifiers = ModifierKeys(alt = true))
        @test selected isa ReplaceSelectionOperation && strip_reference_types(selected.path) == title
        @test strip_reference_types(press(title_x + 2, _fold_pad + 8).path) ==
              ConcreteReference(FieldReferenceStep("title"), ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
        @test !(press(title_x + 2, _fold_pad + 8; button = :right,
                      modifiers = ModifierKeys(alt = true)) isa ReplaceSelectionOperation &&
                strip_reference_types(press(title_x + 2, _fold_pad + 8; button = :right,
                                            modifiers = ModifierKeys(alt = true)).path) == title)

        # The selected title draws the band of a selected part over its box, and no band before.
        band = printer.row_selected_color
        @test isempty(_find_rects_with_color(iomap.output, band))
        evaluate_operation((document = card,), selected)
        bands = _find_rects_with_color(iomap.output, band)
        @test length(bands) == 1
        box = iomap.header.title_box
        @test (Int(bands[1].x), Int(bands[1].y), Int(bands[1].w), Int(bands[1].h)) == box
        # A card that holds no selection of its title draws no band.
        set_selection!(card, nothing)
        @test isempty(_find_rects_with_color(iomap.output, band))
    end

    @testset "a plain click on a String title puts the caret at the character, and the caret is drawn" begin
        proj = _title_proj()
        card = WidgetCard(; title = "Details", content = "the body")
        iomap = print_document(proj, proj, card, PrinterContext())
        x0, y0, _, height = iomap.header.title_box
        caret = ConcreteReference(FieldReferenceStep("title"),
                    ConcreteReference(RangeReferenceStep(3, 3), EmptyReference()))
        # Each character of the stub measure is 10 wide, so 32 is nearest the place after "Det".
        answer = read_intent(proj, iomap, MouseClick(:left, x0 + 32, y0 + height ÷ 2, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation && strip_reference_types(answer.path) == caret
        # A point there maps back to the same caret, and the caret maps forward to its
        # place on the line, which has a box.
        @test strip_reference_types(map_reference_backward(iomap.projection, iomap,
                                                           PointReferenceStep(x0 + 32, y0 + 2))) == caret
        place = map_reference_forward(iomap.projection, iomap, caret)
        @test place !== nothing && find_reference_box(iomap.output, place; measure = _fold_stub) !== nothing
        # The card draws the caret, and no caret before.
        mark() = [e for e in iomap.output.elements if e isa GraphicsRect && Int(e.w) == 2]
        @test isempty(mark())
        evaluate_operation((document = card,), answer)
        @test length(mark()) == 1 && Int(only(mark()).x) == x0 + 30
    end

    @testset "a PrimitiveString title draws in the title style, and its Alt+press selects it" begin
        title_font = _title_printer().title_text.font
        proj = _title_proj()
        text = PrimitiveString("Details")
        card = WidgetCard(; title = text, content = PrimitiveString("the body"), collapsible = true)
        iomap = print_document(proj, proj, card, PrinterContext())
        @test _find_text_font(iomap.output, "Details") == title_font
        # The property is in the context of the title only: the content keeps the style of its own printer.
        @test _find_text_font(iomap.output, "the body") != title_font
        # The card folds from the height of the canvas of the title.
        title_x = _fold_title_x(iomap)
        folds = read_intent(proj, iomap, MouseClick(:left, _fold_pad + 8, _fold_pad + 8, ModifierKeys(); time = 0.0))
        @test folds isa ToggleCollapseOperation
        @test iomap.header.height == Int(iomap.child_iomaps[1][3].output.h)
        # Its own printer reads a press with Alt: the answer names the innermost
        # part, the `String` that the title holds.
        selected = read_intent(proj, iomap, MouseClick(:left, title_x + 2, _fold_pad + 8,
                                                       ModifierKeys(alt = true); time = 0.0))
        @test selected isa ReplaceSelectionOperation
        @test evaluate_reference(card, selected.path) === text.value
    end

    @testset "a title that is a WidgetLabel keeps the style of the label" begin
        proj = _title_proj()
        label = WidgetLabel("Details")
        alone = _find_text_font(print_document(proj, proj, label, PrinterContext()).output, "Details")
        card = WidgetCard(; title = label, content = "x")
        @test _find_text_font(print_document(proj, proj, card, PrinterContext()).output, "Details") == alone
    end

    @testset "an Alt+press on a PrimitiveString title inside a container selects the string" begin
        proj = _title_proj()
        text = PrimitiveString("Details")
        card = WidgetCard(; title = text, content = "x")
        composite = WidgetComposite(Any[card])
        iomap = print_document(proj, proj, composite, PrinterContext())
        answer = read_intent(proj, iomap, MouseClick(:left, _fold_pad + 8, _fold_pad + 8,
                                                     ModifierKeys(alt = true); time = 0.0))
        @test answer isa ReplaceSelectionOperation
        @test evaluate_reference(composite, answer.path) === text.value
    end

    @testset "an Alt+press on a String title inside a container selects the title of the card" begin
        printer = _title_printer()
        proj = _title_proj()
        card = WidgetCard(; title = "Details", content = "x")
        composite = WidgetComposite(Any[card])
        iomap = print_document(proj, proj, composite, PrinterContext())
        answer = read_intent(proj, iomap, MouseClick(:left, _fold_pad + 8, _fold_pad + 8,
                                                     ModifierKeys(alt = true); time = 0.0))
        @test answer isa ReplaceSelectionOperation
        @test strip_reference_types(answer.path) ==
              ConcreteReference(FieldReferenceStep("elements"),
                  ConcreteReference(RangeReferenceStep(0, 1),
                      ConcreteReference(FieldReferenceStep("title"), EmptyReference())))
        # The selection reaches the card, which draws the band over its title.
        band = printer.row_selected_color
        @test isempty(_find_rects_with_color(iomap.output, band))
        evaluate_operation((document = composite,), answer)
        @test length(_find_rects_with_color(iomap.output, band)) == 1
    end
end
