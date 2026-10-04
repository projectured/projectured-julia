# An Alt+click selects the widget under the pointer as a whole, and the widget
# that is selected draws a ring. A plain click keeps its meaning.
#
# Every press lands on a coordinate found in the drawn tree, by the text a
# widget draws, and every assertion names the node the selection resolves to.

_selection_font = StyleFont("Ubuntu Mono", 20)
_selection_measure = FixedMeasure(10, 18, 6, 0)
_selection_projection() = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(_selection_font; measure = _selection_measure).dispatch)))

const _ALT = ModifierKeys(alt = true)

# A composite that holds a card, whose body lays out a button, a label and a
# text field. The button counts its presses.
function _selection_tree()
    count = Ref(0)
    button = WidgetButton("Go";
                          size = Point2D(120, 40), action = (_editor) -> (count[] += 1))
    label = WidgetLabel("hello")
    field = WidgetText("typed")
    layout = VerticalLayout(Any[button, label, field]; gap = 10)
    card = WidgetCard(; title = "Title", content = layout)
    root = WidgetComposite(Any[card])
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

function _is_selection_ring(node)
    ring = get_theme_defaults(GraphicsTheme).selection_ring
    node isa GraphicsRect &&
        (node.border_color.red, node.border_color.green, node.border_color.blue) ==
        (ring.red, ring.green, ring.blue)
end

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

_press(x, y, modifiers = ModifierKeys()) = MouseClick(:left, x, y, modifiers; time = 0.0)

# The first point, row by row, where a press writes the value of `control`. The
# reader says where the control is, so the test repeats no layout arithmetic.
function _selection_point_of(projection, iomap, control)
    for y in 0:3:400, x in 0:3:120
        answer = read_intent(projection, iomap, _press(x, y))
        answer isa ReplaceReferencedValueOperation && answer.document === control &&
            return (x, y)
    end
    error("no press reaches the control")
end

# A click as the gesture recognizer makes it: a down, an up, and the press that
# the two make. The editor evaluates the answer of each at the root.
function _selection_click!(projection, iomap, root, x, y; button = :left,
                           modifiers = ModifierKeys())
    for event in (MouseDown(button, x, y, modifiers; time = 0.0), MouseUp(button, x, y, modifiers; time = 0.0),
                  MouseClick(button, x, y, modifiers; time = 0.0))
        answer = read_intent(projection, iomap, event)
        answer === nothing || evaluate_operation((document = root,), answer)
    end
end

function _selection_space!(projection, iomap, root)
    answer = read_intent(projection, iomap, KeyDown(:space, ModifierKeys(); time = 0.0))
    answer === nothing || evaluate_operation((document = root,), answer)
    answer
end

# Two check boxes with a label between them, and the focus on the first one.
function _selection_boxes()
    first = WidgetCheckbox(false)
    second = WidgetCheckbox(false)
    layout = VerticalLayout(Any[first, WidgetLabel("between"), second]; gap = 10)
    set_selection!(layout, ConcreteReference(FieldReferenceStep("children"),
        ConcreteReference(RangeReferenceStep(0, 1), EmptyReference())))
    (layout = layout, first = first, second = second)
end

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
        # A place a projection introduced names the node it was printed for.
        place = ProjecturedKernel.ProjectionModule.ProjectionReferenceStep(nothing, EmptyReference())
        bracket = ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("content"),
                      ConcreteReference(place, EmptyReference())))
        cut = convert_to_whole_selection(bracket, t.card)
        @test evaluate_reference(t.card, cut.path) === t.layout
        @test convert_to_whole_selection(ReplaceSelectionOperation(
                  ConcreteReference(place, EmptyReference())), t.card).path isa EmptyReference

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
        @test !is_whole_selection_press(MouseClick(:right, 1, 1, _ALT; time = 0.0))
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

    @testset "an Alt+click selects a shape that a layout holds bare" begin
        # A layout sizes a bare shape by its own size, and routes a press to it by
        # the same box.
        circle = GraphicsCircle(10, 10, 10)
        layout = HorizontalLayout(Any[WidgetLabel("a"), circle]; gap = 10)
        projection = RecursiveProjection(TypeDispatchingProjection(vcat(
            _selection_projection().child.dispatch, Pair{Type,Any}[GraphicsDocument => GraphicsToGraphics()])))
        iomap = print_document(projection, projection, layout, PrinterContext())
        centre = nothing
        _selection_walk(iomap.output) do node, x, y
            node isa GraphicsCircle && (centre = (x + Int(node.cx), y + Int(node.cy)))
        end
        op = read_intent(projection, iomap, _press(centre..., _ALT))
        @test op isa ReplaceSelectionOperation
        @test evaluate_reference(layout, op.path) === circle
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
    @testset "a selection can name a widget a projection drew for a document" begin
        focus = ProjecturedPlatform.FocusModule
        owner = PrimitiveString("form")
        t = _selection_tree()
        output_path = ConcreteReference(FieldReferenceStep("elements"),
                          ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))
        path = focus.make_output_reference(owner, t.card, output_path)
        @test evaluate_reference(owner, path) === t.card
        @test is_valid_reference(owner, path)
        @test is_whole_selection(owner, path)
        # Another document does not reach it.
        @test try_evaluate_reference(PrimitiveString("other"), path, missing) === missing
        @test focus.find_output_path(path, owner) == output_path
        @test focus.find_output_path(path, PrimitiveString("other")) === nothing
        # The drawn tree follows the path: each node holds its own part, and the
        # composite rings the card.
        focus.follow_output_selection!(t.root, () -> output_path)
        @test find_whole_selected_index(t.root.selection, "elements") == 1
        @test t.card.selection isa EmptyReference
        @test t.layout.selection === nothing
        iomap = print_document(_selection_projection(), t.root)
        rings = _selection_rings(iomap.output)
        @test length(rings) == 1
        at = _selection_text_at(iomap.output, "Title")
        (rx, ry, rw, rh) = only(rings)
        @test rx <= at[1] < rx + rw && ry <= at[2] < ry + rh
    end

    @testset "a text box selected as a whole rings in the selection's colour" begin
        t = _selection_tree()
        iomap = print_document(_selection_projection(), t.root)
        at = _selection_text_at(iomap.output, "typed")
        t.field.selection = EmptyReference()
        rings = _selection_rings(iomap.output)
        @test length(rings) == 1
        (rx, ry, rw, rh) = only(rings)
        @test rx <= at[1] < rx + rw && ry <= at[2] < ry + rh
        # A caret in it is the focus, and its ring keeps the theme's colour.
        t.field.selection = ConcreteReference(RangeReferenceStep(0, 0), EmptyReference())
        @test isempty(_selection_rings(iomap.output))
    end

    @testset "a press on a control gives it the focus, and a key goes to it" begin
        projection = _selection_projection()
        b = _selection_boxes()
        iomap = print_document(projection, projection, b.layout, PrinterContext())
        (x, y) = _selection_point_of(projection, iomap, b.second)
        _selection_click!(projection, iomap, b.layout, x, y)
        @test b.second.content === true
        @test find_whole_selected_index(b.layout.selection, "children") == 3
        # Space goes to the box that was pressed, and not to the first one.
        @test _selection_space!(projection, iomap, b.layout) !== nothing
        @test b.second.content === false
        @test b.first.content === false
    end

    @testset "only a plain left down moves the focus" begin
        projection = _selection_projection()
        focus = ProjecturedPlatform.FocusModule
        box = WidgetCheckbox(false)
        down = MouseDown(:left, 1, 1, ModifierKeys(); time = 0.0)
        @test focus.is_focusing_press(down)
        @test !focus.is_focusing_press(MouseDown(:right, 1, 1, ModifierKeys(); time = 0.0))
        @test !focus.is_focusing_press(MouseDown(:left, 1, 1, ModifierKeys(alt = true); time = 0.0))
        @test !focus.is_focusing_press(_press(1, 1))
        # A focusable control that answered nothing is selected as a whole.
        @test focus.convert_to_focus_selection(nothing, box).path isa EmptyReference
        # A control that answers the down keeps its answer.
        pressed = ReplaceReferencedValueOperation(box, "content", true)
        @test focus.convert_to_focus_selection(pressed, box) === pressed
        # Not a control, a disabled control, and a control that holds the focus.
        @test focus.convert_to_focus_selection(nothing, WidgetLabel("x")) === nothing
        @test focus.convert_to_focus_selection(nothing,
                  WidgetCheckbox(false; enabled = false)) === nothing
        box.selection = EmptyReference()
        @test focus.convert_to_focus_selection(nothing, box) === nothing

        # A right click and an Alt click leave the focus where it is.
        b = _selection_boxes()
        iomap = print_document(projection, projection, b.layout, PrinterContext())
        (x, y) = _selection_point_of(projection, iomap, b.second)
        _selection_click!(projection, iomap, b.layout, x, y; button = :right)
        @test find_whole_selected_index(b.layout.selection, "children") == 1
        @test read_intent(projection, iomap,
                          MouseDown(:left, x, y, ModifierKeys(alt = true); time = 0.0)) === nothing
        @test find_whole_selected_index(b.layout.selection, "children") == 1
    end

    @testset "a press under a shell gives the focus to the control under the pointer" begin
        projection = _selection_projection()
        b = _selection_boxes()
        shell = WidgetShell(b.layout;
                            menu_bar = WidgetMenu(Any[WidgetMenuItem("File")];
                                                  orientation = :horizontal))
        iomap = print_document(projection, projection, shell, PrinterContext())
        (x, y) = _selection_point_of(projection, iomap, b.second)
        # The content is below the menu bar, so a down must reach it in its own frame.
        @test y >= 24
        _selection_click!(projection, iomap, shell, x, y)
        @test b.second.content === true
        @test find_whole_selected_index(b.layout.selection, "children") == 3
        @test _selection_space!(projection, iomap, shell) !== nothing
        @test b.second.content === false
        @test b.first.content === false
    end

    # A toolbar item answers the down with its pressed look, so a click on it runs
    # the action and the focus stays on the control of the content.
    @testset "a press on a toolbar item of a shell leaves the focus in the content" begin
        projection = _selection_projection()
        b = _selection_boxes()
        count = Ref(0)
        item = WidgetToolbarItem("Run"; icon = :play, action = (_editor) -> (count[] += 1))
        shell = WidgetShell(b.layout; toolbar = WidgetToolbar(Any[item]))
        iomap = print_document(projection, projection, shell, PrinterContext())
        (x, y) = first((x, y) for y in 0:2:60, x in 0:2:120
                       if read_intent(projection, iomap, _press(x, y)) isa InvokeActionOperation)
        down = read_intent(projection, iomap, MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
        @test down isa ReplaceViewStateOperation
        _selection_click!(projection, iomap, shell, x, y)
        @test count[] == 1
        @test item.pressed == false
        @test find_whole_selected_index(b.layout.selection, "children") == 1
    end

    @testset "a press in a transformed pane gives the focus to the control under the pointer" begin
        projection = _selection_projection()
        b = _selection_boxes()
        pane = WidgetTransformPane(b.layout; size = Point2D(300, 400),
                                   transform = make_affine_translate(40.0, 30.0) ∘
                                               make_affine_scale(2.0, 2.0))
        iomap = print_document(projection, projection, pane, PrinterContext())
        (x, y) = _selection_point_of(projection, iomap, b.second)
        # The pane draws its content at twice its size and 30 lower, so each pointer
        # event must reach the content through the inverse of the transform.
        plain = _selection_boxes()
        plain_iomap = print_document(projection, projection, plain.layout, PrinterContext())
        @test y >= 2 * last(_selection_point_of(projection, plain_iomap, plain.second))
        _selection_click!(projection, iomap, pane, x, y)
        @test b.second.content === true
        @test find_whole_selected_index(b.layout.selection, "children") == 3
        @test _selection_space!(projection, iomap, pane) !== nothing
        @test b.second.content === false
        @test b.first.content === false
    end
end
