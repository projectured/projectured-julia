"""
The gesture layer: the recognizer makes a `MousePress` from a `MouseDown` and a
`MouseUp`, counts double and triple clicks, makes a `KeyChord` from a sequence of
the chord table, and `pop_gesture!` delivers in order. A scripted source and a
clock of the test make every case exact, with no backend.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.GestureRecognizerModule: GestureRecognizer, recognize_gesture!, pop_gesture!
using ProjecturedKernel.EventModule: WindowInput
using ProjecturedKernel.EventModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
using ProjecturedKernel.EventModule: MouseButtons
using ProjecturedKernel.EventModule: KeyDown, KeyPress, KeyChord
using ProjecturedKernel.EventModule: ModifierKeys

# A clock of the test: it answers what `t[]` holds.
_mk_clock(t::Ref{Float64}) = () -> t[]

# A scripted source: it answers the inputs of `inputs` in order, then `nothing`.
_mk_source(inputs::Vector) = () -> isempty(inputs) ? nothing : popfirst!(inputs)

# One click through `rec`: a `MouseDown` 0.02 s before `t_up` and a `MouseUp` at
# `t_up`, both at `(x, y)`. Answers the count of the `MousePress` that follows, or
# 0 when the release makes no click.
function _drive_click!(rec, t::Ref{Float64}, x, y, t_up; button = :left)
    empty!(rec.pending)
    t[] = t_up - 0.02
    recognize_gesture!(rec, WindowInput(:win, MouseDown(button, x, y, ModifierKeys())))
    t[] = t_up
    recognize_gesture!(rec, WindowInput(:win, MouseUp(button, x, y, ModifierKeys())))
    isempty(rec.pending) ? 0 : rec.pending[end].event.count
end

const _GR_CTRL = ModifierKeys(ctrl = true)

function test_gesture_recognizer()
@testset "GestureRecognizer" begin

    @testset "a quick press and release in place is a click" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        down = WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys()))
        @test recognize_gesture!(rec, down) === down
        @test isempty(rec.pending)
        t[] = 0.1
        up = WindowInput(:win, MouseUp(:left, 11, 21, ModifierKeys()))
        @test recognize_gesture!(rec, up) === up
        @test length(rec.pending) == 1
        press = rec.pending[1]
        @test press.window_id === :win
        @test press.event isa MousePress
        @test (press.event.button, press.event.x, press.event.y) == (:left, 11, 21)
        @test press.event.count == 1
    end

    @testset "a release too far, too late or of another button is no click" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.1
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 100, 20, ModifierKeys())))
        @test isempty(rec.pending)

        t[] = 1.0
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 1.5   # later than click_max_duration, 0.3 s
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())))
        @test isempty(rec.pending)

        t[] = 2.0
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 2.1
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:right, 10, 20, ModifierKeys())))
        @test isempty(rec.pending)
    end

    @testset "a press and a release in two windows are no click" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:main, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.1
        recognize_gesture!(rec, WindowInput(:popup, MouseUp(:left, 10, 20, ModifierKeys())))
        @test isempty(rec.pending)
    end

    @testset "each button keeps its own press" begin
        # Left down, right down, right up, left up: two clicks, each of its button.
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.05
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:right, 10, 20, ModifierKeys())))
        t[] = 0.1
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:right, 10, 20, ModifierKeys())))
        t[] = 0.15
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())))
        @test [input.event.button for input in rec.pending] == [:right, :left]
    end

    @testset "a release consumes its press" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.05
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())))
        t[] = 0.1
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())))
        @test length(rec.pending) == 1
    end

    @testset "other events pass through" begin
        rec = GestureRecognizer()
        for event in (KeyDown(:home, ModifierKeys()), KeyPress('a'),
                      MouseScroll(0, -1, 5, 6, ModifierKeys()),
                      MouseMove(1, 2, MouseButtons(), ModifierKeys()))
            window_input = WindowInput(:win, event)
            @test recognize_gesture!(rec, window_input) === window_input
        end
        @test isempty(rec.pending)
    end

    @testset "pop_gesture! delivers the waiting gestures first, in order" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        source = _mk_source(Any[
            WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())),
            WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())),
        ])
        @test pop_gesture!(rec, source).event isa MouseDown
        @test pop_gesture!(rec, source).event isa MouseUp
        @test length(rec.pending) == 1
        @test pop_gesture!(rec, source).event isa MousePress
        @test pop_gesture!(rec, source) === nothing
    end

    @testset "pop_gesture! passes a value that is not a WindowInput" begin
        rec = GestureRecognizer()
        @test pop_gesture!(rec, _mk_source(Any[:frame_marker])) === :frame_marker
    end

    @testset "clicks in quick succession count up" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        @test _drive_click!(rec, t, 10, 20, 0.05) == 1
        @test _drive_click!(rec, t, 10, 20, 0.15) == 2
        @test _drive_click!(rec, t, 10, 20, 0.25) == 3
    end

    @testset "the count starts again after a gap, a move or another button" begin
        t = Ref(0.0)
        rec = GestureRecognizer(; clock = _mk_clock(t))
        @test _drive_click!(rec, t, 10, 20, 0.05) == 1
        @test _drive_click!(rec, t, 10, 20, 0.50) == 1     # 0.45 s later
        @test _drive_click!(rec, t, 100, 20, 0.60) == 1    # 90 px away
        @test _drive_click!(rec, t, 100, 20, 0.70; button = :right) == 1
    end

    @testset "a sequence of the chord table is one KeyChord" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL), KeyDown(:k, _GR_CTRL)]])
        @test recognize_gesture!(rec, WindowInput(:win, KeyDown(:c, _GR_CTRL))) === nothing
        @test length(rec.chord_buffer) == 1
        chord = recognize_gesture!(rec, WindowInput(:win, KeyDown(:k, _GR_CTRL)))
        @test chord.window_id === :win
        @test chord.event isa KeyChord
        @test [key.key for key in chord.event.keys] == [:c, :k]
        @test isempty(rec.chord_buffer)
    end

    @testset "a key that breaks a chord flushes the kept keys in order" begin
        rec = GestureRecognizer(;
            chords = [[KeyDown(:c, _GR_CTRL), KeyDown(:k, _GR_CTRL), KeyDown(:x, _GR_CTRL)]])
        recognize_gesture!(rec, WindowInput(:win, KeyDown(:c, _GR_CTRL)))
        recognize_gesture!(rec, WindowInput(:win, KeyDown(:k, _GR_CTRL)))
        first_key = recognize_gesture!(rec, WindowInput(:win, KeyDown(:z, _GR_CTRL)))
        @test first_key.event.key === :c
        @test [input.event.key for input in rec.pending] == [:k, :z]
        @test isempty(rec.chord_buffer)
    end

    @testset "a repeated key neither starts nor continues a chord" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL), KeyDown(:k, _GR_CTRL)]])
        repeated = WindowInput(:win, KeyDown(:c, _GR_CTRL, true))
        @test recognize_gesture!(rec, repeated) === repeated
        recognize_gesture!(rec, WindowInput(:win, KeyDown(:c, _GR_CTRL)))
        @test recognize_gesture!(rec, WindowInput(:win, KeyDown(:c, _GR_CTRL, true))) === nothing
        @test length(rec.chord_buffer) == 1
        @test recognize_gesture!(rec, WindowInput(:win, KeyDown(:k, _GR_CTRL))).event isa KeyChord
    end

    @testset "with no chord table every key passes through" begin
        rec = GestureRecognizer()
        input = WindowInput(:win, KeyDown(:c, _GR_CTRL))
        @test recognize_gesture!(rec, input) === input
        @test isempty(rec.chord_buffer)
    end

    @testset "pop_gesture! keeps the first key and answers the chord in one pull" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL), KeyDown(:k, _GR_CTRL)]])
        source = _mk_source(Any[WindowInput(:win, KeyDown(:c, _GR_CTRL)),
                                WindowInput(:win, KeyDown(:k, _GR_CTRL))])
        @test pop_gesture!(rec, source).event isa KeyChord
        @test pop_gesture!(rec, source) === nothing
    end

    @testset "a chord in progress waits over the end of the input" begin
        rec = GestureRecognizer(; chords = [[KeyDown(:c, _GR_CTRL), KeyDown(:k, _GR_CTRL)]])
        source = _mk_source(Any[WindowInput(:win, KeyDown(:c, _GR_CTRL))])
        @test pop_gesture!(rec, source) === nothing
        @test length(rec.chord_buffer) == 1
    end

end
end # test_gesture_recognizer
