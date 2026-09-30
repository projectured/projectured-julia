# The mouse target tracking projection keeps the part under the pointer and gives
# the crossings to its parts by route. A probe content maps each point to a part
# and logs every change that reaches it, with its route. A small driver plays the
# part of the editor: it evaluates each answer, keeps the timers, and reads the
# timer that brings in a waiting crossing before the next input, as `read!` does.

# Two boxes side by side, each with a leaf in its upper half. A point maps to the
# leaf of its box and the point in the frame of the box, or to the box below the
# leaf. `shifted` moves the boundary between the boxes, as a view that changes
# under a still pointer.
@document struct MttLeaf
    name::String = ""
end
@document struct MttBox
    leaf::MttLeaf = MttLeaf()
end
@document struct MttProbe
    a::MttBox = MttBox()
    b::MttBox = MttBox()
    shifted::Bool = false
end

struct MttProbeProjection <: Projection
    log::Vector{Any}
end
ProjectionModule.print_document(p::MttProbeProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
function ProjectionModule.read_intent(p::MttProbeProjection, recursion, change::Intent,
                                      iomap::SimpleIoMap)
    push!(p.log, (change.gesture, change.route))
    Intent(change.gesture, nothing)
end
function ProjectionModule.map_reference_backward(p::MttProbeProjection, iomap::SimpleIoMap,
                                                 reference)
    point = find_reference_point(reference)
    point === nothing && return nothing
    boundary = iomap.input.shifted ? 50 : 100
    box, left = point.x < boundary ? ("a", 0) : ("b", boundary)
    steps = Any[FieldReferenceStep(box)]
    point.y < 50 && push!(steps, FieldReferenceStep("leaf"))
    push!(steps, PointReferenceStep(point.x - left, point.y))
    extend_reference(EmptyReference(), steps...)
end

# A view of a domain: the people as the rows of a list, and a button of the view
# under them. A row maps back to its person, and the button, which shows no part
# of the input, to an introduced reference of the view.
@document struct MttPerson
    name::String = ""
end
@document struct MttContacts
    people::Vector{MttPerson} = MttPerson[]
end

struct MttContactsToWidgets <: Projection end

function ProjectionModule.print_document(p::MttContactsToWidgets, recursion, input::MttContacts, ctx)
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
const _MTT_ROW_STEPS = (FieldReferenceStep("elements"), ElementReferenceStep(1),
                        FieldReferenceStep("items"))

function ProjectionModule.map_reference_backward(p::MttContactsToWidgets, iomap::SimpleIoMap,
                                                 reference)
    if reference isa Reference
        steps = collect(get_reference_steps(strip_reference_types(reference)))
        length(steps) == 4 && Tuple(steps[1:3]) == _MTT_ROW_STEPS &&
            return extend_reference(EmptyReference(), FieldReferenceStep("people"), steps[4])
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function ProjectionModule.map_reference_forward(p::MttContactsToWidgets, iomap::SimpleIoMap,
                                                reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    reference isa Reference || return nothing
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    length(steps) == 2 && steps[1] == FieldReferenceStep("people") || return nothing
    extend_reference(EmptyReference(), _MTT_ROW_STEPS..., steps[2])
end

mutable struct MttDriver
    projection::MouseTargetTrackingProjection
    state::MouseTargetTrackingState
    iomap::Any
    log::Vector{Any}
    timers::Dict{Symbol,Float64}
end

function MttDriver()
    log = Any[]
    projection = make_mouse_target_tracking_projection(MttProbeProjection(log))
    state = make_mouse_target_tracking_document(MttProbe())
    MttDriver(projection, state, print_document(projection, state), log, Dict{Symbol,Float64}())
end

# A driver over `document` drawn through `inner`, with the mouse target tracking
# around both, as the screen puts it: how a test of a widget moves the pointer.
function MttDriver(inner::Projection, document)
    projection = make_mouse_target_tracking_projection(inner)
    state = make_mouse_target_tracking_document(document)
    MttDriver(projection, state, print_document(projection, state), Any[], Dict{Symbol,Float64}())
end

_mtt_apply!(driver, operation::CompoundOperation) =
    foreach(o -> _mtt_apply!(driver, o), operation.operations)
_mtt_apply!(driver, operation::SetTimerOperation) =
    (driver.timers[operation.name] = operation.time; nothing)
_mtt_apply!(driver, ::Nothing) = nothing
# A move names the part under the pointer, which the editor writes at its root.
_mtt_apply!(driver, operation::ReplaceMouseTargetOperation) =
    (replace_mouse_target!(driver.state, operation.path); nothing)
_mtt_apply!(driver, operation) = (evaluate_operation(nothing, operation); nothing)

# Read one input, then every crossing that waits.
function _mtt_play!(driver::MttDriver, input)
    _mtt_apply!(driver, read_intent(driver.projection, driver.iomap, input))
    while haskey(driver.timers, :mouse_target_tracking_waiting)
        time = pop!(driver.timers, :mouse_target_tracking_waiting)
        _mtt_apply!(driver, read_intent(driver.projection, driver.iomap,
                                        TimerExpire(:mouse_target_tracking_waiting, time)))
    end
end

# A move and a leave of the window, as the screen reads them. A content that draws
# and has no windows is the view of the window itself, so the driver does what the
# window does: the content reads the move, or the leave when the point is off it,
# and the part under the pointer is written at the root. The tracker then reads
# the input for its crossings. A content that is a screen reads the input itself.
function _mtt_move!(driver, x, y, t)
    move = MouseMove(x, y; time = t)
    if _mtt_is_window_view(driver)
        content = driver.iomap.child_iomap
        in_content(operation) = reroot_operation(operation, (FieldReferenceStep("content"),))
        _mtt_apply!(driver, _mtt_is_on_view(content, x, y) ?
            in_content(read_child_move(content, move)) :
            join_move_answers(in_content(read_child_leave(content, move, 0, 0)),
                              ReplaceMouseTargetOperation(EmptyReference())))
    end
    _mtt_play!(driver, WindowInput(:win, move))
end

function _mtt_leave!(driver, t)
    if _mtt_is_window_view(driver)
        leave = MouseMove(-1, -1; time = t)
        _mtt_apply!(driver, join_move_answers(
            reroot_operation(read_child_leave(driver.iomap.child_iomap, leave, 0, 0),
                             (FieldReferenceStep("content"),)),
            ReplaceMouseTargetOperation(EmptyReference())))
    end
    _mtt_play!(driver, WindowInput(:win, WindowLeave(; time = t)))
end

_mtt_is_window_view(driver) = !hasproperty(driver.state.content, :windows) &&
    unwrap_cell(get_iomap_output(driver.iomap.child_iomap)) isa GraphicsDocument

# Whether `(x, y)` is on the canvas that `iomap` draws; a canvas with no size
# leaves it to the content.
function _mtt_is_on_view(iomap, x, y)
    canvas = unwrap_cell(get_iomap_output(iomap))
    canvas isa GraphicsCanvas || return true
    (Int(canvas.w) <= 0 || Int(canvas.h) <= 0) && return true
    0 <= x < Int(canvas.w) && 0 <= y < Int(canvas.h)
end
_mtt_path(names...) = extend_reference(EmptyReference(), (FieldReferenceStep(n) for n in names)...)

# The crossings the content read, as `(kind, route)`, from `start` on.
_mtt_crossings(driver, start = 1) =
    [(nameof(typeof(g)), strip_reference_types(r)) for (g, r) in driver.log[start:end]
     if g isa Union{MouseEnter,MouseLeave,MouseHover}]

function test_mouse_target_tracking()
@testset "MouseTargetTrackingProjection" begin

    @testset "a move onto a leaf enters its parts, the outer first, after the move" begin
        driver = MttDriver()
        _mtt_move!(driver, 10, 10, 1.0)
        @test driver.log[1][1] isa WindowInput && driver.log[1][1].event isa MouseMove
        # The hover of the move comes after the enters, to the deepest part.
        @test _mtt_crossings(driver) == [(:MouseEnter, _mtt_path("a")),
                                         (:MouseEnter, _mtt_path("a", "leaf")),
                                         (:MouseHover, _mtt_path("a", "leaf"))]
        @test driver.state.target == _mtt_path("a", "leaf")
        @test driver.state.waiting == ()
    end

    @testset "a move over the same target hovers its deepest part, at the point of the part" begin
        driver = MttDriver()
        _mtt_move!(driver, 10, 10, 1.0)
        start = length(driver.log) + 1
        _mtt_move!(driver, 120, 20, 1.1)       # the leaf of the second box
        _mtt_move!(driver, 130, 20, 1.2)
        hover = driver.log[end][1]
        @test hover isa MouseHover && (hover.x, hover.y) == (30, 20)
        @test strip_reference_types(driver.log[end][2]) == _mtt_path("b", "leaf")
    end

    @testset "a move leaves the parts it is no longer on, the inner first" begin
        driver = MttDriver()
        _mtt_move!(driver, 10, 10, 1.0)
        start = length(driver.log) + 1
        _mtt_move!(driver, 10, 60, 1.1)        # the box, below its leaf
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("a", "leaf")),
                                                (:MouseHover, _mtt_path("a"))]
        start = length(driver.log) + 1
        _mtt_move!(driver, 150, 10, 1.2)       # the leaf of the other box
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("a")),
                                                (:MouseEnter, _mtt_path("b")),
                                                (:MouseEnter, _mtt_path("b", "leaf")),
                                                (:MouseHover, _mtt_path("b", "leaf"))]
    end

    @testset "the leave of the window leaves every part and clears the target" begin
        driver = MttDriver()
        _mtt_move!(driver, 150, 10, 1.0)
        start = length(driver.log) + 1
        _mtt_leave!(driver, 1.1)
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("b", "leaf")),
                                                (:MouseLeave, _mtt_path("b"))]
        @test driver.state.target === nothing && driver.state.position === nothing
        # The leave of another window changes nothing.
        _mtt_move!(driver, 150, 10, 1.2)
        start = length(driver.log) + 1
        _mtt_play!(driver, WindowInput(:other, WindowLeave(; time = 1.3)))
        @test isempty(_mtt_crossings(driver, start))
    end

    @testset "a view that changes under a still pointer finds the target again" begin
        driver = MttDriver()
        _mtt_move!(driver, 70, 10, 1.0)        # the leaf of the first box
        driver.state.content.shifted = true    # now the point is in the second box
        start = length(driver.log) + 1
        _mtt_play!(driver, WindowInput(:win, DisplayUpdate(1.1)))
        # The target changed, so the new deepest part gets a hover, at the point
        # in its own frame.
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("a", "leaf")),
                                                (:MouseLeave, _mtt_path("a")),
                                                (:MouseEnter, _mtt_path("b")),
                                                (:MouseEnter, _mtt_path("b", "leaf")),
                                                (:MouseHover, _mtt_path("b", "leaf"))]
        @test (driver.log[end][1].x, driver.log[end][1].y) == (20, 10)
        # A new frame with the same target gives no hover: the pointer did not move.
        start = length(driver.log) + 1
        _mtt_play!(driver, WindowInput(:win, DisplayUpdate(1.2)))
        @test isempty(_mtt_crossings(driver, start))
    end

    @testset "a route holds the types of its nodes, and a part that is gone gets nothing" begin
        driver = MttDriver()
        _mtt_move!(driver, 10, 10, 1.0)
        route = driver.log[end][2]
        # A view that maps a route forward checks the type of each node.
        @test route == annotate_reference_types(driver.state.content, _mtt_path("a", "leaf"))
        @test route.type === MttProbe
        start = length(driver.log) + 1
        gone = MouseTargetTrackingModule._Crossing(_mtt_path("gone"),
                                                  MouseLeave(0, 0; time = 1.1))
        driver.state.waiting = (gone,)
        _mtt_apply!(driver, read_intent(driver.projection, driver.iomap,
                                        TimerExpire(:mouse_target_tracking_waiting, 1.1)))
        @test isempty(_mtt_crossings(driver, start))
        @test driver.state.waiting == ()
    end

    @testset "an enter by route lights a real button, and a leave turns it off" begin
        one = WidgetButton("One"; size = Point2D(80, 30))
        two = WidgetButton("Two"; size = Point2D(80, 30), position = Point2D(0, 40))
        projection = make_mouse_target_tracking_projection(
            make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0)))
        state = make_mouse_target_tracking_document(WidgetComposite(Any[one, two]))
        driver = MttDriver(projection, state, print_document(projection, state), Any[],
                           Dict{Symbol,Float64}())
        _mtt_move!(driver, 5, 5, 1.0)
        @test get_mouse_target(one) !== nothing && get_mouse_target(two) === nothing
        _mtt_move!(driver, 5, 45, 1.1)
        @test get_mouse_target(one) === nothing && get_mouse_target(two) !== nothing
        _mtt_leave!(driver, 1.2)
        @test get_mouse_target(one) === nothing && get_mouse_target(two) === nothing
    end

    @testset "a widget that a view makes lights: a row of a part, and a button of the view" begin
        people = [MttPerson(name = name) for name in ("Ann", "Bob", "Cy")]
        chain = ChainingProjection(MttContactsToWidgets(),
                                   make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0)))
        driver = MttDriver(chain, MttContacts(people = people))
        composite = driver.iomap.child_iomap.step_iomaps[1][].output
        list, button = composite.elements[1], composite.elements[2]
        # Down the rows: the target is the person, and the row that shows it lights.
        ys = collect(2:2:100)
        rows = Int[]
        for (k, y) in enumerate(ys)
            _mtt_move!(driver, 20, y, 1.0 + k / 100)
            push!(rows, WidgetModule._widget_element_selected(get_mouse_target(list), "items"))
        end
        @test unique(filter(>(0), rows)) == [1, 2, 3]
        _mtt_move!(driver, 20, ys[findfirst(==(2), rows)], 2.0)
        @test strip_reference_types(driver.state.target) ==
              extend_reference(EmptyReference(), FieldReferenceStep("people"), ElementReferenceStep(2))
        @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 2
        # Onto the button: the leave of the person turns its row off, and the
        # button, a part through the introduced reference, gets its enter.
        _mtt_move!(driver, 5, 160, 2.1)
        @test is_introduced_reference(driver.state.target)
        @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") == 0 &&
              get_mouse_target(button) !== nothing
        _mtt_leave!(driver, 2.2)
        @test get_mouse_target(button) === nothing
    end

    @testset "a row of a list lights, the light follows the pointer, and goes off" begin
        list = WidgetList(["one", "two", "three"]; width = 200)
        other = WidgetButton("Other"; size = Point2D(80, 30), position = Point2D(0, 200))
        driver = MttDriver(make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0)),
                           WidgetComposite(Any[list, other]))
        # Down the list: each row lights in turn, and only below the last row
        # does the light go off.
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

    @testset "a light changes the layout of no widget" begin
        list = WidgetList(["one", "two", "three"]; width = 200)
        button = WidgetButton("Go"; size = Point2D(80, 30), position = Point2D(0, 200))
        driver = MttDriver(make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0)),
                           WidgetComposite(Any[list, button]))
        before = _mtt_layout(_mtt_value(driver.iomap.output))
        lit_row() = WidgetModule._widget_element_selected(get_mouse_target(list), "items")
        for (k, y) in enumerate(2:2:60)
            lit_row() > 0 && break
            _mtt_move!(driver, 20, y, 1.0 + k / 100)
        end
        @test lit_row() > 0
        @test _mtt_layout(_mtt_value(driver.iomap.output)) == before
        _mtt_move!(driver, 10, 210, 1.1)
        @test get_mouse_target(button) !== nothing
        @test _mtt_layout(_mtt_value(driver.iomap.output)) == before
    end
end
end # test_mouse_target_tracking

_mtt_value(x) = x isa Cell ? x[] : x

# The place and the size of every canvas under `canvas`, in the order of a walk.
function _mtt_layout(canvas)
    found = Any[]
    walk(c) = for element in c.elements
        element = _mtt_value(element)
        element isa GraphicsCanvas || continue
        push!(found, Int.(_mtt_value.((element.x, element.y, element.w, element.h))))
        walk(element)
    end
    walk(canvas)
    found
end
