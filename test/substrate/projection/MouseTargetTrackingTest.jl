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
    push!(p.log, (change.gesture, change.route === nothing ? nothing :
                                  strip_reference_types(change.route)))
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

_mtt_apply!(driver, operation::CompoundOperation) =
    foreach(o -> _mtt_apply!(driver, o), operation.operations)
_mtt_apply!(driver, operation::SetTimerOperation) =
    (driver.timers[operation.name] = operation.time; nothing)
_mtt_apply!(driver, ::Nothing) = nothing
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

_mtt_move!(driver, x, y, t) = _mtt_play!(driver, WindowInput(:win, MouseMove(x, y; time = t)))
_mtt_path(names...) = extend_reference(EmptyReference(), (FieldReferenceStep(n) for n in names)...)

# The crossings the content read, as `(kind, route)`, from `start` on.
_mtt_crossings(driver, start = 1) =
    [(nameof(typeof(g)), r) for (g, r) in driver.log[start:end]
     if g isa Union{MouseEnter,MouseLeave,MouseHover}]

function test_mouse_target_tracking()
@testset "MouseTargetTrackingProjection" begin

    @testset "a move onto a leaf enters its parts, the outer first, after the move" begin
        driver = MttDriver()
        _mtt_move!(driver, 10, 10, 1.0)
        @test driver.log[1][1] isa WindowInput && driver.log[1][1].event isa MouseMove
        @test _mtt_crossings(driver) == [(:MouseEnter, _mtt_path("a")),
                                         (:MouseEnter, _mtt_path("a", "leaf"))]
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
        @test driver.log[end][2] == _mtt_path("b", "leaf")
    end

    @testset "a move leaves the parts it is no longer on, the inner first" begin
        driver = MttDriver()
        _mtt_move!(driver, 10, 10, 1.0)
        start = length(driver.log) + 1
        _mtt_move!(driver, 10, 60, 1.1)        # the box, below its leaf
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("a", "leaf"))]
        start = length(driver.log) + 1
        _mtt_move!(driver, 150, 10, 1.2)       # the leaf of the other box
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("a")),
                                                (:MouseEnter, _mtt_path("b")),
                                                (:MouseEnter, _mtt_path("b", "leaf"))]
    end

    @testset "the leave of the window leaves every part and clears the target" begin
        driver = MttDriver()
        _mtt_move!(driver, 150, 10, 1.0)
        start = length(driver.log) + 1
        _mtt_play!(driver, WindowInput(:win, WindowLeave(; time = 1.1)))
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
        @test _mtt_crossings(driver, start) == [(:MouseLeave, _mtt_path("a", "leaf")),
                                                (:MouseLeave, _mtt_path("a")),
                                                (:MouseEnter, _mtt_path("b")),
                                                (:MouseEnter, _mtt_path("b", "leaf"))]
        # A new frame with the same target gives no hover: the pointer did not move.
        start = length(driver.log) + 1
        _mtt_play!(driver, WindowInput(:win, DisplayUpdate(1.2)))
        @test isempty(_mtt_crossings(driver, start))
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
        @test one.hovered == true && two.hovered == false
        _mtt_move!(driver, 5, 45, 1.1)
        @test one.hovered == false && two.hovered == true
        _mtt_play!(driver, WindowInput(:win, WindowLeave(; time = 1.2)))
        @test one.hovered == false && two.hovered == false
    end
end
end # test_mouse_target_tracking
