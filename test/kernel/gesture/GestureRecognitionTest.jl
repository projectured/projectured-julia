"""
The standard recognitions of the gesture layer, each alone: inputs in, the next
state, the gestures, the deadline and the hold out. A recognition is pure, so a
test reads it with no projection and no editor, and the times of the inputs make
every case exact.
"""

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.GestureModule
using ProjecturedKernel.CellModule: Cell

# Read the inputs of `inputs`, each a `(input, window)`, in order, from the first
# state: the last step, and every input that the steps gave.
function _gr_read(recognition, inputs)
    state = make_recognition_state(recognition)
    given = WindowInput[]
    step = nothing
    for (input, window) in inputs
        step = recognize(recognition, state, input, window)
        state = step.state
        append!(given, step.inputs)
    end
    (step, given)
end

_gr_down(button, x, y, t; window = :win) =
    (MouseDown(button, x, y, ModifierKeys(); time = t), window)
_gr_up(button, x, y, t; window = :win) =
    (MouseUp(button, x, y, ModifierKeys(); time = t), window)
const _GR_CTRL = ModifierKeys(ctrl = true)
_gr_key(name, t; repeat = false) = (KeyDown(name, _GR_CTRL; repeat, time = t), :win)
_gr_chords(names...) =
    ChordRecognition([[KeyDown(name, _GR_CTRL; time = 0.0) for name in names]])

# The clicks of a press 0.02 s before each time of `times` and a release at it,
# all at `(10, 20)`, each in the window of the same index of `windows`: the count
# of each click.
function _gr_click_counts(times; windows = fill(:win, length(times)),
                          recognition = ClickRecognition())
    inputs = vcat([[_gr_down(:left, 10, 20, t - 0.02; window),
                    _gr_up(:left, 10, 20, t; window)]
                   for (t, window) in zip(times, windows)]...)
    [input.event.count for input in last(_gr_read(recognition, inputs))]
end

function test_gesture_recognition()
@testset "the standard recognitions of gestures" begin

    @testset "a quick press and release in place is a click, at the release" begin
        step, given = _gr_read(ClickRecognition(), [_gr_down(:left, 10, 20, 0.0),
                                                   _gr_up(:left, 11, 21, 0.1)])
        @test !step.held && step.deadline === nothing
        @test length(given) == 1 && given[1].window_id === :win
        click = given[1].event
        @test (click.button, click.x, click.y, click.count) == (:left, 11, 21, 1)
        @test get_event_time(click) === 0.1
    end

    @testset "a release too far, in another window or of another button is no click" begin
        for up in (_gr_up(:left, 100, 20, 0.1),
                   _gr_up(:left, 10, 20, 0.1; window = :popup), _gr_up(:right, 10, 20, 0.1))
            _, given = _gr_read(ClickRecognition(), [_gr_down(:left, 10, 20, 0.0), up])
            @test isempty(given)
        end
    end

    @testset "a click window ends before its limit" begin
        # The tests are strict: a release 5 px away from its press is no click,
        # and 4 px is inside. No check reads `click_max_duration`, so a release
        # 0.5 s after its press is a click; the comment on `_is_click` says why.
        release_at(x, y, t) = length(last(_gr_read(ClickRecognition(),
            [_gr_down(:left, 10, 20, 0.0), _gr_up(:left, x, y, t)])))
        @test release_at(15, 20, 0.1) == 0
        @test release_at(10, 25, 0.1) == 0
        @test release_at(14, 24, 0.29) == 1
        @test release_at(10, 20, 0.5) == 1
    end

    @testset "clicks in quick succession count up, and a gap starts again" begin
        @test _gr_click_counts([0.05, 0.15, 0.25]) == [1, 2, 3]
        @test _gr_click_counts([0.05, 0.50]) == [1, 1]
    end

    @testset "a limit that is a cell follows the cell" begin
        interval = Cell(0.3)
        distance = Cell(5)
        recognition = ClickRecognition(; multi_click_max_interval = interval,
                                         click_max_displacement = distance)
        @test _gr_click_counts([0.05, 0.50]; recognition) == [1, 1]
        interval[] = 0.6
        @test _gr_click_counts([0.05, 0.50]; recognition) == [1, 2]
        release_far = [_gr_down(:left, 10, 20, 0.0), _gr_up(:left, 18, 20, 0.1)]
        @test isempty(last(_gr_read(recognition, release_far)))
        distance[] = 10
        @test length(last(_gr_read(recognition, release_far))) == 1
        delay = Cell(0.5)
        dwell = DwellRecognition(; delay)
        move = (MouseMove(30, 40; time = 1.0), :win)
        @test first(_gr_read(dwell, [move])).deadline == 1.5
        delay[] = 1.0
        @test first(_gr_read(dwell, [move])).deadline == 2.0
    end

    @testset "the next click in another window starts the count again" begin
        @test _gr_click_counts([0.05, 0.15, 0.25]; windows = [:win, :popup, :popup]) ==
              [1, 1, 2]
    end

    @testset "a key of the chord table is held, and the last one gives the chord" begin
        step, given = _gr_read(_gr_chords(:c, :k), [_gr_key(:c, 1.0)])
        @test step.held && isempty(given)
        step, given = _gr_read(_gr_chords(:c, :k), [_gr_key(:c, 1.0), _gr_key(:k, 1.2)])
        @test step.held && step.state == ()
        @test length(given) == 1 && given[1].event isa KeyChord
        @test [key.key for key in given[1].event.keys] == [:c, :k]
        @test get_event_time(given[1].event) === 1.2
    end

    @testset "a key that breaks a chord gives back the kept keys and itself" begin
        step, given = _gr_read(_gr_chords(:c, :k, :x),
                               [_gr_key(:c, 0.0), _gr_key(:k, 0.1), _gr_key(:z, 0.2)])
        @test step.held
        @test [input.event.key for input in given] == [:c, :k, :z]
    end

    @testset "with no chord table, a key is not held and changes no state" begin
        recognition = ChordRecognition()
        step = recognize(recognition, make_recognition_state(recognition),
                         KeyDown(:escape, ModifierKeys(); time = 0.0), :win)
        @test !step.held && step.state === make_recognition_state(recognition)
    end

    @testset "a move asks for a deadline, and its timer gives one dwell" begin
        recognition = DwellRecognition(; delay = 0.5)
        move = (MouseMove(30, 40; time = 1.0), :win)
        step, _ = _gr_read(recognition, [move])
        @test step.deadline == 1.5 && !step.held
        step, given = _gr_read(recognition, [move, (TimerExpire(:dwell, 1.5), nothing)])
        @test step.held && length(given) == 1
        @test given[1].event isa MouseDwell && (given[1].event.x, given[1].event.y) == (30, 40)
        @test given[1].window_id === :win && get_event_time(given[1].event) === 1.5
        step, given = _gr_read(recognition, [move, (TimerExpire(:dwell, 1.5), nothing),
                                             (TimerExpire(:dwell, 2.0), nothing)])
        @test length(given) == 1                     # one motion, one dwell
    end

    @testset "a newer move, a held button or a press stops the dwell; a key does not" begin
        recognition = DwellRecognition(; delay = 0.5)
        timer = (TimerExpire(:dwell, 1.5), nothing)
        dwells(inputs) = count(i -> i.event isa MouseDwell, last(_gr_read(recognition, inputs)))
        @test dwells([(MouseMove(30, 40; time = 1.0), :win), (MouseMove(31, 40; time = 1.3), :win), timer]) == 0
        @test dwells([(MouseMove(30, 40, MouseButtons(:left), ModifierKeys(); time = 1.0), :win), timer]) == 0
        @test dwells([(MouseMove(30, 40; time = 1.0), :win), _gr_down(:left, 30, 40, 1.1), timer]) == 0
        @test dwells([(MouseMove(30, 40; time = 1.0), :win),
                      (KeyDown(:a, ModifierKeys(); time = 1.1), :win), timer]) == 1
    end

    @testset "a move to the same point is no motion" begin
        recognition = DwellRecognition(; delay = 0.5)
        dwells(inputs) = count(i -> i.event isa MouseDwell, last(_gr_read(recognition, inputs)))
        move(x, t; window = :win) = (MouseMove(x, 40; time = t), window)
        timer(t) = (TimerExpire(:dwell, t), nothing)
        # It keeps the wait of the motion before it, with no new deadline.
        step, _ = _gr_read(recognition, [move(30, 1.0), move(30, 1.3)])
        @test step.deadline === nothing && step.state.time == 1.0
        @test dwells([move(30, 1.0), move(30, 1.3), timer(1.5)]) == 1
        # It starts no second dwell after the first, and none after a press.
        @test dwells([move(30, 1.0), timer(1.5), move(30, 1.6), timer(2.1)]) == 1
        @test dwells([move(30, 1.0), _gr_down(:left, 30, 40, 1.1), move(30, 1.2), timer(1.5),
                      timer(1.7)]) == 0
        # A drag that ends where the pointer rests gives no dwell there.
        @test dwells([(MouseMove(30, 40, MouseButtons(:left), ModifierKeys(); time = 1.0), :win),
                      move(30, 1.1), timer(1.6)]) == 0
        # The same point in another window is a motion.
        @test dwells([move(30, 1.0), timer(1.5), move(30, 1.6; window = :other), timer(2.1)]) == 2
    end

    @testset "the standard list: the chord, the click, the dwell" begin
        @test [typeof(r) for r in make_standard_recognitions()] ==
              [ChordRecognition, ClickRecognition, DwellRecognition]
    end
end
end # test_gesture_recognition
