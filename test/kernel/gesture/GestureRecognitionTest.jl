"""
The standard recognitions of the gesture layer, each alone: inputs in, the next
state, the gestures, the deadline and the hold out. A recognition is pure, so a
test reads it with no projection and no editor, and the times of the inputs make
every case exact.
"""

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.GestureModule

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

_gr_down(button, x, y, t) = (MouseDown(button, x, y, ModifierKeys(); time = t), :win)
_gr_up(button, x, y, t; window = :win) = (MouseUp(button, x, y, ModifierKeys(); time = t), window)
const _GR_CTRL = ModifierKeys(ctrl = true)
_gr_key(name, t; repeat = false) = (KeyDown(name, _GR_CTRL, repeat; time = t), :win)
_gr_chords(names...) = ChordRecognition([[KeyDown(name, _GR_CTRL; time = 0.0) for name in names]])

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

    @testset "a release too far, too late, in another window or of another button is no click" begin
        for up in (_gr_up(:left, 100, 20, 0.1), _gr_up(:left, 10, 20, 0.5),
                   _gr_up(:left, 10, 20, 0.1; window = :popup), _gr_up(:right, 10, 20, 0.1))
            _, given = _gr_read(ClickRecognition(), [_gr_down(:left, 10, 20, 0.0), up])
            @test isempty(given)
        end
    end

    @testset "clicks in quick succession count up, and a gap starts again" begin
        clicks(times) = [e.event.count for e in last(_gr_read(ClickRecognition(),
            vcat([[_gr_down(:left, 10, 20, t - 0.02), _gr_up(:left, 10, 20, t)] for t in times]...)))]
        @test clicks([0.05, 0.15, 0.25]) == [1, 2, 3]
        @test clicks([0.05, 0.50]) == [1, 1]
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

    @testset "the standard list: the chord, the click, the dwell" begin
        @test [typeof(r) for r in make_standard_recognitions()] ==
              [ChordRecognition, ClickRecognition, DwellRecognition]
    end
end
end # test_gesture_recognition
