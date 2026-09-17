# An Alt+click selects the widget under the pointer as a whole, and the widget
# that is selected draws a ring. A plain click keeps its meaning.
#
# Every press lands on a coordinate found in the drawn tree, by the text a
# widget draws, and every assertion names the node the selection resolves to.

_selection_font = font_ubuntu_monospace_regular_20
_selection_measure(t, f) = (length(t) * 10, 24)
_selection_projection() = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(_selection_font; measure = _selection_measure).dispatch)))

const _ALT = ModifierKeys(alt = true)

# A composite that holds a card, whose body lays out a button, a label and a
# text field. The button counts its presses.
function _selection_tree()
    count = Ref(0)
    button = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                          action = (_editor) -> (count[] += 1))
    label = WidgetLabel(Point2D(0, 0), "hello")
    field = WidgetText(Point2D(0, 0), "typed")
    layout = VerticalLayout(Any[button, label, field]; gap = 10)
    card = WidgetCard(Point2D(0, 0); title = "Title", content = layout)
    root = WidgetComposite(Point2D(0, 0), Any[card])
    (root = root, card = card, layout = layout, button = button, label = label,
     field = field, count = count)
end

# Walk the drawn tree with absolute offsets.
function _selection_walk(f, node, x = 0, y = 0)
    node isa ReactiveCell && return _selection_walk(f, node[], x, y)
    if node isa GraphicsCanvas
        nx, ny = x + Int(node.x), y + Int(node.y)
        f(node, nx, ny)
        for element in node.elements
            _selection_walk(f, element, nx, ny)
        end
    elseif node isa GraphicsViewport
        nx, ny = x + Int(node.x), y + Int(node.y)
        _selection_walk(f, node.content, nx, ny)
    else
        f(node, x, y)
    end
end

# Where a text is drawn, as the absolute coordinate of its first character.
function _selection_text_at(root, text)
    found = nothing
    _selection_walk(root) do node, x, y
        (found === nothing && node isa GraphicsText && String(node.text) == text) || return
        found = (x + Int(node.x), y + Int(node.y))
    end
    found === nothing && error("no text $(repr(text)) is drawn")
    found
end

_is_selection_ring(node) =
    node isa GraphicsRect &&
    (node.border_color.red, node.border_color.green, node.border_color.blue) ==
    (SELECTION_RING_COLOR.red, SELECTION_RING_COLOR.green, SELECTION_RING_COLOR.blue)

# The absolute box of every ring that draws.
function _selection_rings(root)
    rings = Tuple{Int,Int,Int,Int}[]
    _selection_walk(root) do node, x, y
        _is_selection_ring(node) || return
        Int(node.border_width) > 0 || return
        push!(rings, (x + Int(node.x), y + Int(node.y), Int(node.w), Int(node.h)))
    end
    rings
end

# The rings that exist, whether they draw or not.
function _selection_all_rings(root)
    rings = Any[]
    _selection_walk(root) do node, x, y
        _is_selection_ring(node) && push!(rings, node)
    end
    rings
end

_press(x, y, modifiers = ModifierKeys()) = MousePress(:left, x, y, modifiers)

function test_widget_selection()
    @testset "a whole selection names a document, and a caret does not" begin
        text = PrimitiveString("abc")
        @test is_whole_selection(text, EmptyReference())
        # `[1:2]` of a string is the letter "b", which is not a document.
        letter = ConcreteReference(RangeReferenceStep(1, 2), EmptyReference())
        @test !is_whole_selection(text, letter)
        @test !is_whole_selection(text, nothing)
        t = _selection_tree()
        # A path that does not resolve is not a whole selection either.
        @test !is_whole_selection(t.root, ConcreteReference(FieldReferenceStep("nowhere"), EmptyReference()))

        # A child's whole selection is kept; anything else selects the child.
        inside = ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("content"), EmptyReference()))
        @test convert_to_whole_selection(inside, t.card) === inside
        for (answer, child) in ((nothing, t.card), (InvokeActionOperation(Action("go")), t.card),
                                (ReplaceSelectionOperation(letter), text))
            converted = convert_to_whole_selection(answer, child)
            @test converted isa ReplaceSelectionOperation
            @test converted.path isa EmptyReference
        end
        # A path the child's document does not have is the container's own
        # spelling, and the level above maps it: it is kept.
        own = ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("nowhere"), EmptyReference()))
        @test convert_to_whole_selection(own, t.card) === own

        # The container's own view of a whole selection.
        second = ConcreteReference(FieldReferenceStep("children"),
                     ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))
        @test find_whole_selected_index(second, "children") == 2
        @test find_whole_selected_index(second, "elements") === nothing
        deeper = ConcreteReference(FieldReferenceStep("children"),
                     ConcreteReference(RangeReferenceStep(1, 2),
                         ConcreteReference(FieldReferenceStep("content"), EmptyReference())))
        @test find_whole_selected_index(deeper, "children") === nothing
        @test is_whole_selected_field(ConcreteReference(FieldReferenceStep("content"), EmptyReference()), "content")
        @test !is_whole_selected_field(deeper, "children")

        # Only a left press with Alt alone is the gesture.
        @test is_whole_selection_press(_press(1, 1, _ALT))
        @test !is_whole_selection_press(_press(1, 1))
        @test !is_whole_selection_press(_press(1, 1, ModifierKeys(alt = true, ctrl = true)))
        @test !is_whole_selection_press(MousePress(:right, 1, 1, _ALT))
    end

    @testset "an Alt+click selects the widget under the pointer" begin
        t = _selection_tree()
        projection = _selection_projection()
        iomap = print_document(projection, projection, t.root, PrinterContext())
        out = iomap.output

        (bx, by) = _selection_text_at(out, "Go")
        (lx, ly) = _selection_text_at(out, "hello")
        (fx, fy) = _selection_text_at(out, "typed")
        (tx, ty) = _selection_text_at(out, "Title")

        # A plain press on the button still answers its action.
        @test read_intent(projection, iomap, _press(bx + 2, by + 2)) isa InvokeActionOperation

        # An Alt+press names the innermost widget, whole, and nothing acts.
        for ((x, y), wanted) in (((bx + 2, by + 2), t.button),
                                 ((lx + 2, ly + 2), t.label),
                                 ((fx + 2, fy + 2), t.field),
                                 ((tx + 2, ty + 2), t.card))
            op = read_intent(projection, iomap, _press(x, y, _ALT))
            @test op isa ReplaceSelectionOperation
            @test evaluate_reference(t.root, op.path) === wanted
        end
        @test t.count[] == 0

        # Outside every widget, an Alt+press names nothing.
        @test read_intent(projection, iomap, _press(900, 900, _ALT)) === nothing
    end

    @testset "the selected widget draws a ring, and only while it is selected" begin
        t = _selection_tree()
        projection = _selection_projection()
        iomap = print_document(projection, projection, t.root, PrinterContext())
        out = iomap.output

        # At rest a ring exists in each container and draws nothing.
        rings = _selection_all_rings(out)
        @test length(rings) >= 3
        @test all(r -> Int(r.w) == 0 && Int(r.h) == 0 && Int(r.border_width) == 0, rings)
        @test isempty(_selection_rings(out))

        # A control that takes the focus draws its own focus ring when it is
        # selected, so the container adds none.
        (bx, by) = _selection_text_at(out, "Go")
        op = read_intent(projection, iomap, _press(bx + 2, by + 2, _ALT))
        evaluate_operation((document = t.root,), op)
        @test isempty(_selection_rings(out))

        # The label is not a control: its container draws the ring on its box.
        (lx, ly) = _selection_text_at(out, "hello")
        op = read_intent(projection, iomap, _press(lx + 2, ly + 2, _ALT))
        evaluate_operation((document = t.root,), op)
        drawn = _selection_rings(out)
        @test length(drawn) == 1
        (x, y, w, h) = only(drawn)
        @test (x, y) == (lx, ly)
        @test (w, h) == (length("hello") * 10, 24)

        # The card as a whole: the composite draws the ring around it.
        (tx, ty) = _selection_text_at(out, "Title")
        op = read_intent(projection, iomap, _press(tx + 2, ty + 2, _ALT))
        evaluate_operation((document = t.root,), op)
        drawn = _selection_rings(out)
        @test length(drawn) == 1
        (x, y, w, h) = only(drawn)
        @test (x, y) == (0, 0)
        @test x <= tx < x + w && y <= ty < y + h

        clear_selection!(t.root)
        @test isempty(_selection_rings(out))
    end

    @testset "a plain press on a selected widget still reaches it" begin
        t = _selection_tree()
        projection = _selection_projection()
        iomap = print_document(projection, projection, t.root, PrinterContext())
        (bx, by) = _selection_text_at(iomap.output, "Go")
        op = read_intent(projection, iomap, _press(bx + 2, by + 2, _ALT))
        evaluate_operation((document = t.root,), op)
        @test read_intent(projection, iomap, _press(bx + 2, by + 2)) isa InvokeActionOperation
    end
end
