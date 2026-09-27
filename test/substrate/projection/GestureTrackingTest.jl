# The gesture tracking projection gives the content each event and the gestures
# that the events make: the click with its count, the key chord and the mouse
# dwell. A small driver plays the part of the editor: it evaluates each answer,
# keeps the timers that the answer sets, and reads the timer that brings in a
# waiting gesture before the next input, as `read!` does. The times of the
# events make every case exact.

# The content: it logs what it reads, with the state it sees then, and it answers
# a `MouseUp` with a write, so a test can see whether the click came after it.
@document struct GtProbeDocument
    released::Bool = false
end

struct GtProbeProjection <: Projection
    log::Vector{Any}
end
ProjectionModule.print_document(p::GtProbeProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
function ProjectionModule.read_intent(p::GtProbeProjection, recursion, change::Intent,
                                      iomap::SimpleIoMap)
    input = change.gesture
    push!(p.log, (input, iomap.input.released))
    input isa WindowInput && input.event isa MouseUp &&
        return Intent(input, ReplaceReferencedValueOperation(iomap.input, "released", true))
    Intent(input, nothing)
end

# The driver: the state, the projection, the IoMap, and the timers of an editor.
mutable struct GtDriver
    projection::GestureTrackingProjection
    state::GestureTrackingState
    iomap::Any
    log::Vector{Any}
    timers::Dict{Symbol,Float64}
end

function GtDriver(; keywords...)
    log = Any[]
    projection = make_gesture_tracking_projection(GtProbeProjection(log); keywords...)
    state = make_gesture_tracking_document(GtProbeDocument())
    GtDriver(projection, state, print_document(projection, state), log, Dict{Symbol,Float64}())
end

# Evaluate an answer: a timer goes to the timers, and every other operation is
# evaluated.
_gt_apply!(driver::GtDriver, operation::CompoundOperation) =
    foreach(o -> _gt_apply!(driver, o), operation.operations)
_gt_apply!(driver::GtDriver, operation::SetTimerOperation) =
    (driver.timers[operation.name] = operation.time; nothing)
_gt_apply!(driver::GtDriver, ::Nothing) = nothing
_gt_apply!(driver::GtDriver, operation) = (evaluate_operation(nothing, operation); nothing)

_gt_read!(driver::GtDriver, input) =
    _gt_apply!(driver, read_intent(driver.projection, driver.iomap, input))

# Read one input, then every waiting gesture, as the editor reads a due timer
# before the next input. The dwell timer stays, for a test to fire.
function _gt_play!(driver::GtDriver, input)
    _gt_read!(driver, input)
    while haskey(driver.timers, :gesture_tracking_waiting)
        time = pop!(driver.timers, :gesture_tracking_waiting)
        _gt_read!(driver, TimerExpire(:gesture_tracking_waiting, time))
    end
end

# What the content read, as the events and the gestures in order.
_gt_read_events(driver::GtDriver) =
    Any[input isa WindowInput ? input.event : input for (input, _) in driver.log]

_gt_down(button, x, y, t; window = :win) =
    WindowInput(window, MouseDown(button, x, y, ModifierKeys(); time = t))
_gt_up(button, x, y, t; window = :win) =
    WindowInput(window, MouseUp(button, x, y, ModifierKeys(); time = t))
_gt_move(x, y, t; buttons = MouseButtons(), window = :win) =
    WindowInput(window, MouseMove(x, y, buttons, ModifierKeys(); time = t))
const _GT_CTRL = ModifierKeys(ctrl = true)
_gt_key(name, t; modifiers = _GT_CTRL, repeat = false) =
    WindowInput(:win, KeyDown(name, modifiers, repeat; time = t))
_gt_chord(names...) = [[KeyDown(name, _GT_CTRL; time = 0.0) for name in names]]

# The clicks that the content read.
_gt_clicks(driver::GtDriver) = [event for event in _gt_read_events(driver) if event isa MouseClick]

# One click: a press 0.02 s before `t_up` and a release at `t_up`, both at (x, y).
function _gt_click!(driver::GtDriver, x, y, t_up; button = :left)
    _gt_play!(driver, _gt_down(button, x, y, t_up - 0.02))
    _gt_play!(driver, _gt_up(button, x, y, t_up))
end

function test_gesture_tracking()
@testset "GestureTrackingProjection" begin

    @testset "a quick press and release in place is a click, after the release" begin
        driver = GtDriver()
        _gt_play!(driver, _gt_down(:left, 10, 20, 0.0))
        _gt_play!(driver, _gt_up(:left, 11, 21, 0.1))
        events = _gt_read_events(driver)
        @test [typeof(event) for event in events] == [MouseDown, MouseUp, MouseClick]
        click = events[3]
        @test (click.button, click.x, click.y, click.count) == (:left, 11, 21, 1)
        @test get_event_time(click) === 0.1              # the time of the release
        @test driver.log[3][1].window_id === :win
    end

    @testset "the content reads the click after the operation of the release" begin
        driver = GtDriver()
        _gt_play!(driver, _gt_down(:left, 10, 20, 0.0))
        _gt_play!(driver, _gt_up(:left, 10, 20, 0.1))
        # The release wrote `released`; the click saw the write.
        @test driver.log[2][2] == false
        @test driver.log[3][1].event isa MouseClick && driver.log[3][2] == true
    end

    @testset "a release too far, too late or of another button is no click" begin
        driver = GtDriver()
        _gt_play!(driver, _gt_down(:left, 10, 20, 0.0))
        _gt_play!(driver, _gt_up(:left, 100, 20, 0.1))
        _gt_play!(driver, _gt_down(:left, 10, 20, 1.0))
        _gt_play!(driver, _gt_up(:left, 10, 20, 1.5))    # after click_max_duration
        _gt_play!(driver, _gt_down(:left, 10, 20, 2.0))
        _gt_play!(driver, _gt_up(:right, 10, 20, 2.1))
        @test isempty(_gt_clicks(driver))
    end

    @testset "a press and a release in two windows are no click" begin
        driver = GtDriver()
        _gt_play!(driver, _gt_down(:left, 10, 20, 0.0; window = :main))
        _gt_play!(driver, _gt_up(:left, 10, 20, 0.1; window = :popup))
        @test isempty(_gt_clicks(driver))
    end

    @testset "each button keeps its own press" begin
        driver = GtDriver()
        _gt_play!(driver, _gt_down(:left, 10, 20, 0.0))
        _gt_play!(driver, _gt_down(:right, 10, 20, 0.05))
        _gt_play!(driver, _gt_up(:right, 10, 20, 0.1))
        _gt_play!(driver, _gt_up(:left, 10, 20, 0.15))
        @test [click.button for click in _gt_clicks(driver)] == [:right, :left]
    end

    @testset "a release consumes its press" begin
        driver = GtDriver()
        _gt_play!(driver, _gt_down(:left, 10, 20, 0.0))
        _gt_play!(driver, _gt_up(:left, 10, 20, 0.05))
        _gt_play!(driver, _gt_up(:left, 10, 20, 0.1))
        @test length(_gt_clicks(driver)) == 1
    end

    @testset "other events reach the content unchanged, and nothing follows them" begin
        driver = GtDriver()
        events = Any[KeyDown(:home, ModifierKeys(); time = 0.0), KeyPress('a'; time = 0.0),
                     MouseScroll(0, -1, 5, 6, ModifierKeys(); time = 0.0)]
        foreach(event -> _gt_play!(driver, WindowInput(:win, event)), events)
        @test _gt_read_events(driver) == events
        # A key that no chord waits for writes no state, so the content's answer
        # is the whole answer, as the editor needs for its own keys.
        @test read_intent(driver.projection, driver.iomap,
                          WindowInput(:win, KeyDown(:escape, ModifierKeys(); time = 1.0))) ===
              nothing
    end

    @testset "clicks in quick succession count up" begin
        driver = GtDriver()
        _gt_click!(driver, 10, 20, 0.05)
        _gt_click!(driver, 10, 20, 0.15)
        _gt_click!(driver, 10, 20, 0.25)
        @test [click.count for click in _gt_clicks(driver)] == [1, 2, 3]
    end

    @testset "the count starts again after a gap, a move away or another button" begin
        driver = GtDriver()
        _gt_click!(driver, 10, 20, 0.05)
        _gt_click!(driver, 10, 20, 0.50)                 # 0.45 s later
        _gt_click!(driver, 100, 20, 0.60)                # 90 px away
        _gt_click!(driver, 100, 20, 0.70; button = :right)
        @test [click.count for click in _gt_clicks(driver)] == [1, 1, 1, 1]
    end

    @testset "a sequence of the chord table is one KeyChord in place of its keys" begin
        driver = GtDriver(; chords = _gt_chord(:c, :k))
        _gt_play!(driver, _gt_key(:c, 1.0))
        @test isempty(driver.log)                        # the first key is kept
        _gt_play!(driver, _gt_key(:k, 1.2))
        events = _gt_read_events(driver)
        @test length(events) == 1 && events[1] isa KeyChord
        @test [key.key for key in events[1].keys] == [:c, :k]
        @test get_event_time(events[1]) === 1.2          # the time of the last key
        @test driver.state.chord_keys == ()
    end

    @testset "a key that breaks a chord gives out the kept keys and itself, in order" begin
        driver = GtDriver(; chords = _gt_chord(:c, :k, :x))
        _gt_play!(driver, _gt_key(:c, 0.0))
        _gt_play!(driver, _gt_key(:k, 0.1))
        _gt_play!(driver, _gt_key(:z, 0.2))
        @test [event.key for event in _gt_read_events(driver)] == [:c, :k, :z]
        @test driver.state.chord_keys == () && driver.state.waiting == ()
    end

    @testset "a repeated key neither starts nor continues a chord" begin
        driver = GtDriver(; chords = _gt_chord(:c, :k))
        _gt_play!(driver, _gt_key(:c, 0.0; repeat = true))
        @test length(driver.log) == 1                    # it reached the content
        _gt_play!(driver, _gt_key(:c, 0.1))
        _gt_play!(driver, _gt_key(:c, 0.2; repeat = true))   # dropped while a chord waits
        @test length(driver.log) == 1
        _gt_play!(driver, _gt_key(:k, 0.3))
        @test _gt_read_events(driver)[end] isa KeyChord
    end

    @testset "a pointer that rests after a move dwells once, where it rests" begin
        driver = GtDriver(; dwell_delay = 0.5)
        _gt_play!(driver, _gt_move(30, 40, 1.0))
        @test driver.timers[:gesture_tracking_dwell] == 1.5
        _gt_play!(driver, TimerExpire(:gesture_tracking_dwell, 1.5))
        dwell = _gt_read_events(driver)[end]
        @test dwell isa MouseDwell && (dwell.x, dwell.y) == (30, 40)
        @test get_event_time(dwell) === 1.5
        @test driver.log[end][1].window_id === :win
        # One motion gives one dwell.
        _gt_play!(driver, TimerExpire(:gesture_tracking_dwell, 2.0))
        @test count(event -> event isa MouseDwell, _gt_read_events(driver)) == 1
    end

    @testset "a newer move, a held button or a press stops the dwell" begin
        # A timer of an older move matches nothing after a newer move.
        driver = GtDriver(; dwell_delay = 0.5)
        _gt_play!(driver, _gt_move(30, 40, 1.0))
        _gt_play!(driver, _gt_move(31, 40, 1.3))
        _gt_play!(driver, TimerExpire(:gesture_tracking_dwell, 1.5))
        @test !any(event -> event isa MouseDwell, _gt_read_events(driver))
        # A move with a button held is a drag, and no dwell follows it.
        driver = GtDriver(; dwell_delay = 0.5)
        _gt_play!(driver, _gt_move(30, 40, 1.0; buttons = MouseButtons(; left = true)))
        _gt_play!(driver, TimerExpire(:gesture_tracking_dwell, 1.5))
        @test !any(event -> event isa MouseDwell, _gt_read_events(driver))
        # A press after the move stops the wait.
        driver = GtDriver(; dwell_delay = 0.5)
        _gt_play!(driver, _gt_move(30, 40, 1.0))
        _gt_play!(driver, _gt_down(:left, 30, 40, 1.1))
        _gt_play!(driver, TimerExpire(:gesture_tracking_dwell, 1.5))
        @test !any(event -> event isa MouseDwell, _gt_read_events(driver))
    end

    @testset "a timer of another reader reaches the content" begin
        driver = GtDriver()
        _gt_play!(driver, TimerExpire(:someone_else, 1.0))
        @test _gt_read_events(driver) == Any[TimerExpire(:someone_else, 1.0)]
    end

    @testset "the wrapper is transparent to the printer and to the references" begin
        driver = GtDriver()
        @test get_iomap_output(driver.iomap) === driver.state.content
        @test get_wrapped_document(driver.state) === driver.state.content
        inner = extend_reference(EmptyReference(), FieldReferenceStep("released"))
        outer = extend_reference(EmptyReference(), FieldReferenceStep("content"),
                                 FieldReferenceStep("released"))
        # Forward, the wrapper takes off its step and asks the content; a reference
        # that does not go into the content maps to nothing.
        child = driver.iomap.child_iomap
        @test map_reference_forward(driver.projection, driver.iomap, outer) ==
              map_reference_forward(child.projection, child, inner)
        @test map_reference_forward(driver.projection, driver.iomap,
                                    extend_reference(EmptyReference(),
                                                     FieldReferenceStep("presses"))) === nothing
        # Backward, the content's answer gets the step of the wrapper, and the
        # forward mapping takes it off again.
        back = map_reference_backward(driver.projection, driver.iomap, inner)
        @test get_reference_head(back) == FieldReferenceStep("content")
        @test strip_reference_types(map_reference_forward(driver.projection, driver.iomap,
                                                          back)) == inner
    end
end
end # test_gesture_tracking
