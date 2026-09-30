# A move of the pointer with no button held writes the part under the pointer.
# Each container gives the move first to the child that the pointer leaves, then
# to the child that it is on, and the answers write the chain of the mouse target:
# the root holds the whole path, each document on it its own tail, and a document
# off it holds nothing.

_mtm_measure() = FixedMeasure(10, 18, 6, 0)

_mtm_path(steps...) = extend_reference(EmptyReference(), steps...)
_mtm_elements(i) = (FieldReferenceStep("elements"), ElementReferenceStep(i))

# Write an answer at `root`: the mouse target by the chain write, and every other
# operation on its own document.
function _mtm_apply!(root, operation)
    operation === nothing && return
    if operation isa CompoundOperation
        foreach(member -> _mtm_apply!(root, member), operation.operations)
    elseif operation isa ReplaceMouseTargetOperation
        replace_mouse_target!(root, operation.path)
    else
        evaluate_operation(nothing, operation)
    end
    nothing
end

# A move to `(x, y)` of the output of `iomap`, read as a window reads its content.
_mtm_move!(root, iomap, x, y) =
    _mtm_apply!(root, read_child_move(iomap, MouseMove(x, y; time = 0.0)))

# A screen with the windows `windows`, each 400 by 200, drawn through the widget
# projection, and a function that reads an input of the screen and writes it.
function _mtm_screen(windows...)
    screen = ScreenDocument(collect(windows))
    projection = make_widget_popup_projection_example(measure = _mtm_measure())
    iomap = print_document(projection, screen)
    play!(input) = _mtm_apply!(screen, read_intent(projection, iomap, input))
    (screen, play!)
end

_mtm_window(id, x, content) =
    WindowDocument(; id, x, y = 0, width = 400, height = 200, content)

function test_mouse_target_move()
@testset "a move writes the part under the pointer" begin

projection = make_widget_projection_example(measure = _mtm_measure())

@testset "across a composite of buttons" begin
    one = WidgetButton("One"; size = Point2D(80, 30))
    two = WidgetButton("Two"; size = Point2D(80, 30), position = Point2D(0, 40))
    root = WidgetComposite(Any[one, two])
    iomap = print_document(projection, root)
    _mtm_move!(root, iomap, 5, 5)
    @test get_mouse_target(root) == _mtm_path(_mtm_elements(1)...)
    @test get_mouse_target(one) == EmptyReference()
    @test get_mouse_target(two) === nothing
    # Onto the other button: the old branch is cleared.
    _mtm_move!(root, iomap, 5, 45)
    @test get_mouse_target(root) == _mtm_path(_mtm_elements(2)...)
    @test get_mouse_target(one) === nothing
    @test get_mouse_target(two) == EmptyReference()
    # Off both buttons: the composite itself is under the pointer.
    _mtm_move!(root, iomap, 300, 300)
    @test get_mouse_target(root) == EmptyReference()
    @test get_mouse_target(two) === nothing
end

@testset "a button that the pointer leaves ends its press" begin
    one = WidgetButton("One"; size = Point2D(80, 30))
    two = WidgetButton("Two"; size = Point2D(80, 30), position = Point2D(0, 40))
    root = WidgetComposite(Any[one, two])
    iomap = print_document(projection, root)
    _mtm_move!(root, iomap, 5, 5)
    # A press that was released off the button leaves it pressed.
    one.pressed = true
    _mtm_move!(root, iomap, 10, 10)
    @test one.pressed == true
    _mtm_move!(root, iomap, 5, 45)
    @test one.pressed == false
end

@testset "through a card and a layout" begin
    a = WidgetButton("A"; size = Point2D(80, 30))
    b = WidgetButton("B"; size = Point2D(80, 30))
    layout = VerticalLayout(Any[a, b])
    card = WidgetCard(; title = "Card", content = layout)
    iomap = print_document(projection, card)
    children(i) = (FieldReferenceStep("children"), ElementReferenceStep(i))
    _mtm_move!(card, iomap, 20, 70)
    @test get_mouse_target(card) == _mtm_path(FieldReferenceStep("content"), children(1)...)
    @test get_mouse_target(layout) == _mtm_path(children(1)...)
    @test get_mouse_target(a) == EmptyReference()
    _mtm_move!(card, iomap, 20, 100)
    @test get_mouse_target(layout) == _mtm_path(children(2)...)
    @test get_mouse_target(a) === nothing
    @test get_mouse_target(b) == EmptyReference()
    _mtm_move!(card, iomap, 20, 400)
    @test get_mouse_target(card) == EmptyReference()
    @test get_mouse_target(layout) === nothing
end

@testset "a part that a pane clips or a sibling covers is not under the pointer" begin
    # The content of the scroll pane is taller than its view, so a point below
    # the pane lies on a button that the pane does not show.
    buttons = [WidgetButton("B$i"; size = Point2D(80, 30)) for i in 1:10]
    scroll = WidgetScrollPane(VerticalLayout(Any[buttons...]); size = Point2D(200, 100))
    root = WidgetComposite(Any[scroll])
    iomap = print_document(projection, root)
    _mtm_move!(root, iomap, 20, 5)
    @test get_mouse_target(buttons[1]) == EmptyReference()
    _mtm_move!(root, iomap, 20, 140)
    @test get_mouse_target(root) == EmptyReference()
    @test all(get_mouse_target(button) === nothing for button in buttons)

    # In a stack both children start at the origin, and the overlay lies over the
    # first button of the layout under it.
    first_button = WidgetButton("First"; size = Point2D(80, 30))
    second_button = WidgetButton("Second"; size = Point2D(80, 30))
    overlay = WidgetButton("Overlay"; size = Point2D(80, 30))
    stack = StackLayout(Any[VerticalLayout(Any[first_button, second_button]), overlay])
    iomap = print_document(projection, stack)
    _mtm_move!(stack, iomap, 20, 45)
    @test get_mouse_target(second_button) == EmptyReference()
    _mtm_move!(stack, iomap, 20, 5)
    @test get_mouse_target(stack) ==
          _mtm_path(FieldReferenceStep("children"), ElementReferenceStep(2))
    @test get_mouse_target(overlay) == EmptyReference()
    @test get_mouse_target(first_button) === nothing
    @test get_mouse_target(second_button) === nothing
end

@testset "a list names the row under the pointer" begin
    list = WidgetList(["one", "two", "three"]; width = 200)
    root = WidgetComposite(Any[list])
    iomap = print_document(projection, root)
    items(i) = (FieldReferenceStep("items"), ElementReferenceStep(i))
    _mtm_move!(root, iomap, 20, 5)
    @test get_mouse_target(list) == _mtm_path(items(1)...)
    _mtm_move!(root, iomap, 20, 55)
    @test get_mouse_target(root) == _mtm_path(_mtm_elements(1)..., items(2)...)
    @test get_mouse_target(list) == _mtm_path(items(2)...)
end

@testset "in the panes of a window" begin
    left = WidgetButton("L"; size = Point2D(80, 30))
    right = WidgetButton("R"; size = Point2D(80, 30))
    split_pane = WidgetSplitPane(:horizontal, Any[left, right]; sizes = [150, 150])
    (screen, play!) = _mtm_screen(_mtm_window(:w, 0, split_pane))
    play!(WindowInput(:w, MouseMove(5, 5; time = 0.0)))
    @test get_mouse_target(split_pane) == _mtm_path(_mtm_elements(1)...)
    @test get_mouse_target(left) == EmptyReference()
    # In the left slot but off its button: the split pane itself.
    play!(WindowInput(:w, MouseMove(100, 10; time = 0.1)))
    @test get_mouse_target(split_pane) == EmptyReference()
    @test get_mouse_target(left) === nothing
    play!(WindowInput(:w, MouseMove(210, 10; time = 0.2)))
    @test get_mouse_target(right) == EmptyReference()

    tab_one = WidgetButton("T1"; size = Point2D(80, 30))
    tab_two = WidgetButton("T2"; size = Point2D(80, 30))
    page_one = WidgetComposite(Any[tab_one])
    tabs = WidgetTabbedPane([("One", page_one), ("Two", tab_two)])
    (screen, play!) = _mtm_screen(_mtm_window(:w, 0, tabs))
    page(i) = (FieldReferenceStep("selector_element_pairs"), ElementReferenceStep(i))
    play!(WindowInput(:w, MouseMove(60, 10; time = 0.0)))
    @test get_mouse_target(tabs) == _mtm_path(page(2)..., FieldReferenceStep("selector"))
    # A page that is a widget holds the rest of the path.
    play!(WindowInput(:w, MouseMove(20, 60; time = 0.1)))
    @test get_mouse_target(tabs) ==
          _mtm_path(page(1)..., FieldReferenceStep("element"), _mtm_elements(1)...)
    @test get_mouse_target(page_one) == _mtm_path(_mtm_elements(1)...)
    @test get_mouse_target(tab_one) == EmptyReference()
    play!(WindowInput(:w, MouseMove(10, 10; time = 0.2)))
    @test get_mouse_target(page_one) === nothing
    @test get_mouse_target(tab_one) === nothing

    content = WidgetButton("C"; size = Point2D(80, 30))
    tool = WidgetButton("X"; size = Point2D(40, 24))
    shell = WidgetShell(content; toolbar = WidgetToolbar(Any[tool]))
    (screen, play!) = _mtm_screen(_mtm_window(:w, 0, shell))
    play!(WindowInput(:w, MouseMove(10, 10; time = 0.0)))
    @test get_mouse_target(shell) ==
          _mtm_path(FieldReferenceStep("toolbar"), _mtm_elements(1)...)
    @test get_mouse_target(tool) == EmptyReference()
    play!(WindowInput(:w, MouseMove(10, 50; time = 0.1)))
    @test get_mouse_target(shell) == _mtm_path(FieldReferenceStep("content"))
    @test get_mouse_target(tool) === nothing
end

@testset "across two windows" begin
    a = WidgetButton("A"; size = Point2D(80, 30))
    b = WidgetButton("B"; size = Point2D(80, 30))
    window_a = _mtm_window(:a, 0, WidgetComposite(Any[a]))
    window_b = _mtm_window(:b, 500, WidgetComposite(Any[b]))
    (screen, play!) = _mtm_screen(window_a, window_b)
    window(i) = (FieldReferenceStep("windows"), ElementReferenceStep(i))
    in_content = (FieldReferenceStep("content"), _mtm_elements(1)...)
    play!(WindowInput(:a, MouseMove(5, 5; time = 0.0)))
    @test get_mouse_target(screen) == _mtm_path(window(1)..., in_content...)
    @test get_mouse_target(a) == EmptyReference()
    # A move in the other window clears the branch of the first.
    play!(WindowInput(:b, MouseMove(5, 5; time = 0.1)))
    @test get_mouse_target(screen) == _mtm_path(window(2)..., in_content...)
    @test get_mouse_target(window_a) === nothing
    @test get_mouse_target(a) === nothing
    @test get_mouse_target(b) == EmptyReference()
    # A late leave of the first window changes nothing.
    play!(WindowInput(:a, WindowLeave(; time = 0.2)))
    @test get_mouse_target(b) == EmptyReference()
    # The leave of the window that the pointer is in: the screen itself.
    play!(WindowInput(:b, WindowLeave(; time = 0.3)))
    @test get_mouse_target(screen) == EmptyReference()
    @test get_mouse_target(window_b) === nothing
    @test get_mouse_target(b) === nothing
end

end # @testset
end # test_mouse_target_move
