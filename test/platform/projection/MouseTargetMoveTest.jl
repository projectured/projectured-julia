# A move of the pointer with no button held writes the part under the pointer.
# Each container gives the move first to the child that the pointer leaves, then
# to the child that it is on, and the answers write the chain of the mouse target:
# the root holds the whole path, each document on it its own tail, and a document
# off it holds nothing. A widget lights from its own mouse target, and a view that
# makes widgets maps the part under the pointer forward into them.

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

# A view of a domain: the people as the rows of a list, and a button of the view
# under them. A row maps back to its person, and the button, which shows no part
# of the input, to an introduced reference of the view.
@document struct MtmPerson
    name::String = ""
end
@document struct MtmContacts
    people::Vector{MtmPerson} = MtmPerson[]
end

struct MtmContactsToWidgets <: Projection end

function ProjectionModule.print_document(p::MtmContactsToWidgets, recursion, input::MtmContacts, ctx)
    list = WidgetList(Any[person.name for person in input.people]; width = 200)
    button = WidgetButton("Delete"; size = Point2D(80, 30), position = Point2D(0, 150))
    composite = WidgetComposite(Any[list, button])
    iomap = SimpleIoMap(p, input, composite)
    # The view maps the part under the pointer forward into what it makes, as a view
    # maps its selection: a person to its row, and the button of the view to the
    # button.
    follow_output_mouse_target!(composite,
        () -> map_mouse_target_forward(input, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# The steps of the path of a row, `elements[1].items[k]`, before its index.
const _MTM_ROW_STEPS = (FieldReferenceStep("elements"), ElementReferenceStep(1),
                        FieldReferenceStep("items"))

function ProjectionModule.map_reference_backward(p::MtmContactsToWidgets, iomap::SimpleIoMap,
                                                 reference)
    if reference isa Reference
        steps = collect(get_reference_steps(strip_reference_types(reference)))
        length(steps) == 4 && Tuple(steps[1:3]) == _MTM_ROW_STEPS &&
            return extend_reference(EmptyReference(), FieldReferenceStep("people"), steps[4])
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function ProjectionModule.map_reference_forward(p::MtmContactsToWidgets, iomap::SimpleIoMap,
                                                reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    reference isa Reference || return nothing
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    length(steps) == 2 && steps[1] == FieldReferenceStep("people") || return nothing
    extend_reference(EmptyReference(), _MTM_ROW_STEPS..., steps[2])
end

# The place and the size of every canvas under `canvas`, in the order of a walk.
function _mtm_collect_canvas_boxes(canvas)
    found = Any[]
    walk(c) = for element in c.elements
        element = unwrap_cell(element)
        element isa GraphicsCanvas || continue
        push!(found, Int.(unwrap_cell.((element.x, element.y, element.w, element.h))))
        walk(element)
    end
    walk(canvas)
    found
end

# A view that puts its input, a reflected object, whole into a scroll pane of a
# card, as the inspector of a simulation does, and a later stage that draws the
# object with `ReflectionToWidget`. The view maps a path of the object through the
# pane that holds it.
mutable struct MtmHeldInner
    a::Int
    b::String
end
mutable struct MtmHeldOuter
    name::String
    inner::MtmHeldInner
end

struct MtmHeldObjectView <: Projection end

function ProjectionModule.print_document(p::MtmHeldObjectView, recursion, shadow, ctx)
    pane = WidgetScrollPane(shadow; size = Point2D(240, 200))
    card = WidgetCard(; title = "Form", content = VerticalLayout(Any[pane]; gap = 6, child_width = Fill))
    iomap = SimpleIoMap(p, shadow, card)
    follow_output_mouse_target!(card, () ->
        map_mouse_target_forward(shadow, path -> map_reference_forward(p, iomap, path));
        is_followed = node -> node isa WidgetDocument || node isa LayoutDocument)
    iomap
end

function ProjectionModule.map_reference_forward(p::MtmHeldObjectView, iomap::SimpleIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return annotate_reference_types(iomap.output, introduced)
    map_held_node_forward(iomap.output, iomap.input, reference)
end

function ProjectionModule.map_reference_backward(p::MtmHeldObjectView, iomap::SimpleIoMap, reference)
    held = map_held_node_backward(iomap.output, iomap.input, reference)
    held === nothing || return held
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

ProjectionModule.read_intent(p::MtmHeldObjectView, iomap::SimpleIoMap, op::CompoundOperation) =
    has_mouse_target(op) ? read_move_answer(p, iomap, op) : op

# The widget stage, where a reflected object goes through `ReflectionToWidget`.
function _mtm_reflection_stage()
    base = vcat(LayoutToGraphics().dispatch,
                WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _mtm_measure()).dispatch)
    RecursiveProjection(TypeDispatchingProjection(vcat(base, Pair{Type,Any}[
        AReflectedNode => ChainingProjection(ReflectionToWidget(),
                                             RecursiveProjection(TypeDispatchingProjection(base)))])))
end

function test_mouse_target_move()
@testset "a move writes the part under the pointer" begin

projection = make_widget_projection_example(measure = _mtm_measure())

@testset "a row of a lazy list takes its part from the head, and the walk builds no row" begin
    built = Ref(0)
    function make_row_node(k)
        built[] += 1
        node = ListNode(CellVector(Cell[Cell(WidgetButton("row $k"))]))
        set_cell_computation!(getfield(node, :next), () -> begin
            following = make_row_node(k + 1)
            set_cell_value!(getfield(following, :prev), node)
            following
        end)
        node
    end
    table = WidgetTable(; column_headers = Any["row"], cells = make_row_node(1))
    path = Cell(nothing)
    follow_output_mouse_target!(table, () -> path[])
    @test built[] == 1
    head = getfield(table, :cells)[]
    # The pointer is on the button of the third row: the list builds the rows up
    # to it, and the button takes its part.
    set_cell_value!(path, _mtm_path(FieldReferenceStep("cells"), ElementReferenceStep(3),
                                    ElementReferenceStep(1)))
    third = find_list_node(head, 3)
    @test built[] == 3
    @test get_mouse_target(third.value[1]) == EmptyReference()
    @test get_mouse_target(head.value[1]) === nothing
    # The pointer moves to the first row: the third row loses its part.
    set_cell_value!(path, _mtm_path(FieldReferenceStep("cells"), ElementReferenceStep(1),
                                    ElementReferenceStep(1)))
    @test get_mouse_target(head.value[1]) == EmptyReference()
    @test get_mouse_target(third.value[1]) === nothing
    # The table scrolls one row: the same path counts from the new head.
    second = find_list_node(head, 2)
    set_cell_value!(getfield(table, :cells), second)
    @test get_mouse_target(second.value[1]) == EmptyReference()
    @test get_mouse_target(head.value[1]) === nothing
    @test built[] == 3
end

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

@testset "a widget that a view makes lights: a row of a part, and a button of the view" begin
    people = [MtmPerson(name = name) for name in ("Ann", "Bob", "Cy")]
    driver = MttDriver(ChainingProjection(MtmContactsToWidgets(), projection),
                       MtmContacts(people = people))
    composite = driver.iomap.step_iomaps[1][].output
    list, button = composite.elements[1], composite.elements[2]
    # Down the rows: the part under the pointer is the person, and the row that
    # shows it lights.
    ys = collect(2:2:100)
    rows = Int[]
    for (k, y) in enumerate(ys)
        _mtt_move!(driver, 20, y, 1.0 + k / 100)
        push!(rows, WidgetModule._widget_element_selected(get_mouse_target(list), "items"))
    end
    @test unique(filter(>(0), rows)) == [1, 2, 3]
    _mtt_move!(driver, 20, ys[findfirst(==(2), rows)], 2.0)
    @test get_mouse_target(driver.document) ==
          extend_reference(EmptyReference(), FieldReferenceStep("people"), ElementReferenceStep(2))
    @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 2
    # Onto the button: the row of the person goes off, and the button, a part
    # through the introduced reference, lights.
    _mtt_move!(driver, 5, 160, 2.1)
    @test is_introduced_reference(get_mouse_target(driver.document))
    @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 0 &&
          get_mouse_target(button) !== nothing
    _mtt_leave!(driver, 2.2)
    @test get_mouse_target(button) === nothing
end

@testset "a row of a list lights, the light follows the pointer, and goes off" begin
    list = WidgetList(["one", "two", "three"]; width = 200)
    other = WidgetButton("Other"; size = Point2D(80, 30), position = Point2D(0, 200))
    driver = MttDriver(projection, WidgetComposite(Any[list, other]))
    # Down the list: each row lights in turn, and only below the last row does
    # the light go off.
    ys = collect(2:2:150)
    rows = Int[]
    for (k, y) in enumerate(ys)
        _mtt_move!(driver, 20, y, 1.0 + k / 100)
        push!(rows, WidgetModule._widget_element_selected(get_mouse_target(list), "items"))
    end
    @test unique(filter(>(0), rows)) == [1, 2, 3]
    @test issorted(rows[1:findlast(>(0), rows)])
    # Onto another widget: the row goes off, and the widget lights.
    first_row = ys[findfirst(==(1), rows)]
    _mtt_move!(driver, 20, first_row, 2.0)
    @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 1
    _mtt_move!(driver, 10, 210, 2.1)
    @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 0 &&
          get_mouse_target(other) !== nothing
    # The leave of the window turns every light off.
    _mtt_move!(driver, 20, first_row, 2.2)
    @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 1 &&
          get_mouse_target(other) === nothing
    _mtt_leave!(driver, 2.3)
    @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 0
end

@testset "a document that a view holds whole, and a later view draws, holds the part under the pointer" begin
    shadow = reflect_document(MtmHeldOuter("root", MtmHeldInner(1, "x")),
                              DepthPolicy(depth = 1, elements = 32))
    driver = MttDriver(ChainingProjection(MtmHeldObjectView(), _mtm_reflection_stage()), shadow)
    card = driver.iomap.step_iomaps[1][].output
    pane = card.content.children[1]
    # The path to the object in the output, and a path of the object there and back.
    @test find_output_node_path(card, shadow) !== nothing
    field = extend_reference(EmptyReference(), FieldReferenceStep("children"), ElementReferenceStep(1))
    @test strip_reference_types(map_held_node_backward(card, shadow,
              map_held_node_forward(card, shadow, field))) == field
    # Down the pane: a row is a part of the later view, the object holds it, and
    # the pane on the way holds the rest of the path.
    row(t) = find_introduced_path(ReflectionToWidget(), t)
    lit = nothing
    for (k, y) in enumerate(0:2:200)
        _mtt_move!(driver, 20, y, 1.0 + k / 1000)
        row(get_mouse_target(shadow)) === nothing || (lit = y; break)
    end
    @test lit !== nothing
    @test get_mouse_target(pane) !== nothing
    # The later view reads the part from the object and lights its row.
    @test get_mouse_target(print_document(ReflectionToWidget(), shadow).output) !== nothing
    _mtt_leave!(driver, 3.0)
    @test row(get_mouse_target(shadow)) === nothing
end

@testset "a light changes the layout of no widget" begin
    list = WidgetList(["one", "two", "three"]; width = 200)
    button = WidgetButton("Go"; size = Point2D(80, 30), position = Point2D(0, 200))
    driver = MttDriver(projection, WidgetComposite(Any[list, button]))
    boxes() = _mtm_collect_canvas_boxes(unwrap_cell(get_iomap_output(driver.iomap)))
    before = boxes()
    lit_row() = WidgetModule._widget_element_selected(get_mouse_target(list), "items")
    for (k, y) in enumerate(2:2:60)
        lit_row() > 0 && break
        _mtt_move!(driver, 20, y, 1.0 + k / 100)
    end
    @test lit_row() > 0
    @test boxes() == before
    _mtt_move!(driver, 10, 210, 1.1)
    @test get_mouse_target(button) !== nothing
    @test boxes() == before
end

end # @testset
end # test_mouse_target_move
