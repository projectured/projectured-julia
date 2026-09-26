"""
The gesture layer: the recognizer makes a `MouseClick` from a `MouseDown` and a
`MouseUp`, counts double and triple clicks, makes a `KeyChord` from a sequence of
the chord table, and `pop_gesture!` delivers in order. A scripted source and the
times of the events make every case exact, with no backend.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.GestureRecognizerModule: GestureRecognizer, recognize_gesture!,
                                                pop_gesture!
using ProjecturedKernel.EventModule: WindowInput
using ProjecturedKernel.EventModule: MouseDown, MouseUp, MouseClick, MouseMove, MouseScroll
using ProjecturedKernel.EventModule: MouseButtons
using ProjecturedKernel.EventModule: KeyDown, KeyPress, KeyChord
using ProjecturedKernel.EventModule: ModifierKeys, get_event_time

# A scripted source: it answers the inputs of `inputs` in order, then `nothing`.
_mk_source(inputs::Vector) = () -> isempty(inputs) ? nothing : popfirst!(inputs)

# A press and a release of `button` at `(x, y)` and the time `t`, in `window`.
_gr_down(button, x, y, t; window = :win) =
    WindowInput(window, MouseDown(button, x, y, ModifierKeys(); time = t))
_gr_up(button, x, y, t; window = :win) =
    WindowInput(window, MouseUp(button, x, y, ModifierKeys(); time = t))

# A key of a chord at the time `t`, with Ctrl held unless `modifiers` says else.
_gr_key(name, t; modifiers = _GR_CTRL, repeat = false) =
    WindowInput(:win, KeyDown(name, modifiers, repeat; time = t))

# One click through `rec`: a press 0.02 s before `t_up` and a release at `t_up`,
# both at `(x, y)`. Answers the count of the `MouseClick` that follows, or 0 when
# the release makes no click.
function _drive_click!(rec, x, y, t_up; button = :left)
    empty!(rec.pending)
    recognize_gesture!(rec, _gr_down(button, x, y, t_up - 0.02))
    recognize_gesture!(rec, _gr_up(button, x, y, t_up))
    isempty(rec.pending) ? 0 : rec.pending[end].event.count
end

const _GR_CTRL = ModifierKeys(ctrl = true)

function test_gesture_recognizer()
@testset "GestureRecognizer" begin

    @testset "a quick press and release in place is a click" begin
        rec = GestureRecognizer()
        down = _gr_down(:left, 10, 20, 0.0)
        @test recognize_gesture!(rec, down) === down
        @test isempty(rec.pending)
        up = _gr_up(:left, 11, 21, 0.1)
        @test recognize_gesture!(rec, up) === up
        @test length(rec.pending) == 1
        press = rec.pending[1]
        @test press.window_id === :win
        @test press.event isa MouseClick
        @test (press.event.button, press.event.x, press.event.y) == (:left, 11, 21)
        @test press.event.count == 1
        @test get_event_time(press.event) === 0.1     # the time of the release
    end

    @testset "the times of the events decide, not the time of processing" begin
        # The release is processed a second after the press, as after a slow frame,
        # but the two events are 0.1 s apart: a click.
        rec = GestureRecognizer()
        recognize_gesture!(rec, _gr_down(:left, 10, 20, 100.0))
        sleep(0.35)
        recognize_gesture!(rec, _gr_up(:left, 10, 20, 100.1))
        @test length(rec.pending) == 1
    end

    @testset "a release too far, too late or of another button is no click" begin
        rec = GestureRecognizer()
        recognize_gesture!(rec, _gr_down(:left, 10, 20, 0.0))
        recognize_gesture!(rec, _gr_up(:left, 100, 20, 0.1))
        @test isempty(rec.pending)

        recognize_gesture!(rec, _gr_down(:left, 10, 20, 1.0))
        recognize_gesture!(rec, _gr_up(:left, 10, 20, 1.5))   # after click_max_duration
        @test isempty(rec.pending)

        recognize_gesture!(rec, _gr_down(:left, 10, 20, 2.0))
        recognize_gesture!(rec, _gr_up(:right, 10, 20, 2.1))
        @test isempty(rec.pending)
    end

    @testset "a press and a release in two windows are no click" begin
        rec = GestureRecognizer()
        recognize_gesture!(rec, _gr_down(:left, 10, 20, 0.0; window = :main))
        recognize_gesture!(rec, _gr_up(:left, 10, 20, 0.1; window = :popup))
        @test isempty(rec.pending)
    end

    @testset "each button keeps its own press" begin
        # Left down, right down, right up, left up: two clicks, each of its button.
        rec = GestureRecognizer()
        recognize_gesture!(rec, _gr_down(:left, 10, 20, 0.0))
        recognize_gesture!(rec, _gr_down(:right, 10, 20, 0.05))
        recognize_gesture!(rec, _gr_up(:right, 10, 20, 0.1))
        recognize_gesture!(rec, _gr_up(:left, 10, 20, 0.15))
        @test [input.event.button for input in rec.pending] == [:right, :left]
    end

    @testset "a release consumes its press" begin
        rec = GestureRecognizer()
        recognize_gesture!(rec, _gr_down(:left, 10, 20, 0.0))
        recognize_gesture!(rec, _gr_up(:left, 10, 20, 0.05))
        recognize_gesture!(rec, _gr_up(:left, 10, 20, 0.1))
        @test length(rec.pending) == 1
    end

    @testset "other events pass through" begin
        rec = GestureRecognizer()
        for event in (KeyDown(:home, ModifierKeys(); time = 0.0), KeyPress('a'; time = 0.0),
                      MouseScroll(0, -1, 5, 6, ModifierKeys(); time = 0.0),
                      MouseMove(1, 2, MouseButtons(), ModifierKeys(); time = 0.0))
            window_input = WindowInput(:win, event)
            @test recognize_gesture!(rec, window_input) === window_input
        end
        @test isempty(rec.pending)
    end

    @testset "pop_gesture! delivers the waiting gestures first, in order" begin
        rec = GestureRecognizer()
        source = _mk_source(Any[_gr_down(:left, 10, 20, 0.0), _gr_up(:left, 10, 20, 0.05)])
        @test pop_gesture!(rec, source).event isa MouseDown
        @test pop_gesture!(rec, source).event isa MouseUp
        @test length(rec.pending) == 1
        @test pop_gesture!(rec, source).event isa MouseClick
        @test pop_gesture!(rec, source) === nothing
    end

    @testset "pop_gesture! passes a value that is not a WindowInput" begin
        rec = GestureRecognizer()
        @test pop_gesture!(rec, _mk_source(Any[:frame_marker])) === :frame_marker
    end

    @testset "clicks in quick succession count up" begin
        rec = GestureRecognizer()
        @test _drive_click!(rec, 10, 20, 0.05) == 1
        @test _drive_click!(rec, 10, 20, 0.15) == 2
        @test _drive_click!(rec, 10, 20, 0.25) == 3
    end

    @testset "the count starts again after a gap, a move or another button" begin
        rec = GestureRecognizer()
        @test _drive_click!(rec, 10, 20, 0.05) == 1
        @test _drive_click!(rec, 10, 20, 0.50) == 1     # 0.45 s later
        @test _drive_click!(rec, 100, 20, 0.60) == 1    # 90 px away
        @test _drive_click!(rec, 100, 20, 0.70; button = :right) == 1
    end

    @testset "a sequence of the chord table is one KeyChord" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL; time = 0.0),
                                             KeyDown(:k, _GR_CTRL; time = 0.0)]])
        @test recognize_gesture!(rec, _gr_key(:c, 1.0)) === nothing
        @test length(rec.chord_buffer) == 1
        chord = recognize_gesture!(rec, _gr_key(:k, 1.2))
        @test chord.window_id === :win
        @test chord.event isa KeyChord
        @test [key.key for key in chord.event.keys] == [:c, :k]
        @test get_event_time(chord.event) === 1.2     # the time of the last key
        @test isempty(rec.chord_buffer)
    end

    @testset "a key that breaks a chord flushes the kept keys in order" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL; time = 0.0),
                                             KeyDown(:k, _GR_CTRL; time = 0.0),
                                             KeyDown(:x, _GR_CTRL; time = 0.0)]])
        recognize_gesture!(rec, _gr_key(:c, 0.0))
        recognize_gesture!(rec, _gr_key(:k, 0.1))
        first_key = recognize_gesture!(rec, _gr_key(:z, 0.2))
        @test first_key.event.key === :c
        @test [input.event.key for input in rec.pending] == [:k, :z]
        @test isempty(rec.chord_buffer)
    end

    @testset "a repeated key neither starts nor continues a chord" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL; time = 0.0),
                                             KeyDown(:k, _GR_CTRL; time = 0.0)]])
        repeated = _gr_key(:c, 0.0; repeat = true)
        @test recognize_gesture!(rec, repeated) === repeated
        recognize_gesture!(rec, _gr_key(:c, 0.1))
        @test recognize_gesture!(rec, _gr_key(:c, 0.2; repeat = true)) === nothing
        @test length(rec.chord_buffer) == 1
        @test recognize_gesture!(rec, _gr_key(:k, 0.3)).event isa KeyChord
    end

    @testset "with no chord table every key passes through" begin
        rec = GestureRecognizer()
        input = _gr_key(:c, 0.0)
        @test recognize_gesture!(rec, input) === input
        @test isempty(rec.chord_buffer)
    end

    @testset "pop_gesture! keeps the first key and answers the chord in one pull" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL; time = 0.0),
                                             KeyDown(:k, _GR_CTRL; time = 0.0)]])
        source = _mk_source(Any[_gr_key(:c, 0.0), _gr_key(:k, 0.1)])
        @test pop_gesture!(rec, source).event isa KeyChord
        @test pop_gesture!(rec, source) === nothing
    end

    @testset "a chord in progress waits over the end of the input" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL; time = 0.0),
                                             KeyDown(:k, _GR_CTRL; time = 0.0)]])
        @test pop_gesture!(rec, _mk_source(Any[_gr_key(:c, 0.0)])) === nothing
        @test length(rec.chord_buffer) == 1
    end

end
end # test_gesture_recognizer
