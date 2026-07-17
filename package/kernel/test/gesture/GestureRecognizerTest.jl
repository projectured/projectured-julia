# ═══════════════════════════════════════════════════════════════════════════
# test/device/GestureRecognizerTest.jl
#
# Unit tests for the event → gesture recogniser. These exercise the click
# synthesis (MouseDown + MouseUp → MousePress) independently of the SDL
# backend. A scripted `source` and an injectable clock make recognition
# fully deterministic without SDL. GestureRecognizer is a kernel device type
# (no document coupling), so this is its lowest test home.
# ═══════════════════════════════════════════════════════════════════════════

using Test
using ProjecturedKernel
using ProjecturedKernel.GestureRecognizerModule: GestureRecognizer, recognize_gesture!, pop_gesture!
using ProjecturedKernel.EventModule: WindowInput
using ProjecturedKernel.EventModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
using ProjecturedKernel.EventModule: KeyDown, KeyPress, KeyChord
using ProjecturedKernel.EventModule: ModifierKeys

# A controllable clock: returns whatever `t[]` currently holds.
_mk_clock(t::Ref{Float64}) = () -> t[]

# A scripted event source: pops envelopes off a vector, `nothing` when empty.
_mk_source(envs::Vector) = () -> isempty(envs) ? nothing : popfirst!(envs)

# Drive one click (MouseDown then MouseUp at (x, y); the up at time `t_up`, the
# down 0.02 s earlier) through `rec`, and return the synthesised MousePress count
# (or 0 if the up did not complete a click). Clears `pending` first so the count
# returned is the one from *this* click.
function _drive_click!(rec, t::Ref{Float64}, x, y, t_up; button = :left)
    empty!(rec.pending)
    t[] = t_up - 0.02
    recognize_gesture!(rec, WindowInput(:win, MouseDown(button, x, y, ModifierKeys())))
    t[] = t_up
    recognize_gesture!(rec, WindowInput(:win, MouseUp(button, x, y, ModifierKeys())))
    isempty(rec.pending) ? 0 : rec.pending[end].event.count
end

function test_gesture_recognizer()
@testset "GestureRecognizer" begin

    # ── a quick, in-place down/up pair synthesises a MousePress ──────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        down = WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys()))
        @test recognize_gesture!(rec, down) === down        # forwarded unchanged
        @test isempty(rec.pending)                  # nothing synthesised yet

        t[] = 0.1
        up = WindowInput(:win, MouseUp(:left, 11, 21, ModifierKeys()))
        @test recognize_gesture!(rec, up) === up            # the up is still forwarded
        @test length(rec.pending) == 1              # plus a synthesised click
        press = rec.pending[1]
        @test press isa WindowInput
        @test press.window_id == :win               # window id preserved
        @test press.event isa MousePress
        @test (press.event.button, press.event.x, press.event.y) == (:left, 11, 21)
        @test press.event.count == 1                 # a lone click is count 1
    end

    # ── too far away: no click ───────────────────────────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.1
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 100, 20, ModifierKeys())))
        @test isempty(rec.pending)
    end

    # ── too slow: no click ───────────────────────────────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.5   # > CLICK_MAX_DURATION (0.3)
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())))
        @test isempty(rec.pending)
    end

    # ── different button up does not complete a click ────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize_gesture!(rec, WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())))
        t[] = 0.1
        recognize_gesture!(rec, WindowInput(:win, MouseUp(:right, 10, 20, ModifierKeys())))
        @test isempty(rec.pending)
    end

    # ── non-mouse events pass through untouched, nothing synthesised ─────────
    let rec = GestureRecognizer()
        for evt in (KeyDown(:home, ModifierKeys()), KeyPress('a'),
                    MouseScroll(0, -1, 5, 6, ModifierKeys()),
                    MouseMove(1, 2, :none, ModifierKeys()))
            env = WindowInput(:win, evt)
            @test recognize_gesture!(rec, env) === env
        end
        @test isempty(rec.pending)
    end

    # ── pop_gesture! drains pending before pulling new input, in order ──────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        script = Any[
            WindowInput(:win, MouseDown(:left, 10, 20, ModifierKeys())),
            WindowInput(:win, MouseUp(:left, 10, 20, ModifierKeys())),
        ]
        source = _mk_source(script)

        g1 = pop_gesture!(rec, source)             # MouseDown forwarded
        @test g1.event isa MouseDown

        g2 = pop_gesture!(rec, source)             # MouseUp forwarded, click queued
        @test g2.event isa MouseUp
        @test length(rec.pending) == 1

        g3 = pop_gesture!(rec, source)             # queued click delivered next
        @test g3.event isa MousePress

        @test pop_gesture!(rec, source) === nothing # source exhausted
    end

    # ── multi-click: consecutive in-window clicks increment the count ────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        @test _drive_click!(rec, t, 10, 20, 0.05) == 1   # single
        @test _drive_click!(rec, t, 10, 20, 0.15) == 2   # double (Δ 0.10 s)
        @test _drive_click!(rec, t, 10, 20, 0.25) == 3   # triple (Δ 0.10 s)
    end

    # ── multi-click resets when the gap is too long ──────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        @test _drive_click!(rec, t, 10, 20, 0.05) == 1
        @test _drive_click!(rec, t, 10, 20, 0.50) == 1   # Δ 0.45 s > 0.3 → reset
    end

    # ── multi-click resets when the second click is too far away ─────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        @test _drive_click!(rec, t, 10, 20, 0.05) == 1
        @test _drive_click!(rec, t, 100, 20, 0.15) == 1  # 90 px away → reset
    end

    # ── multi-click resets when the button differs ───────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        @test _drive_click!(rec, t, 10, 20, 0.05) == 1
        @test _drive_click!(rec, t, 10, 20, 0.15; button = :right) == 1  # other button
    end

    # ── key chord: a configured sequence collapses to one KeyChord ──────────
    let ctrl   = ModifierKeys(ctrl = true),
        chords = [[KeyDown(:c, ctrl), KeyDown(:k, ctrl)]],
        rec    = GestureRecognizer(; chords = chords)

        pfx = WindowInput(:win, KeyDown(:c, ctrl))
        @test recognize_gesture!(rec, pfx) === nothing       # prefix absorbed, nothing out
        @test length(rec.chord_buffer) == 1

        fin   = WindowInput(:win, KeyDown(:k, ctrl))
        chord = recognize_gesture!(rec, fin)
        @test chord isa WindowInput
        @test chord.window_id == :win                # window id of the first key
        @test chord.event isa KeyChord
        @test [k.key for k in chord.event.keys] == [:c, :k]
        @test isempty(rec.chord_buffer)              # buffer cleared after firing
    end

    # ── key chord: a breaking key flushes the prefix + itself as raw keys ────
    let ctrl   = ModifierKeys(ctrl = true),
        chords = [[KeyDown(:c, ctrl), KeyDown(:k, ctrl)]],
        rec    = GestureRecognizer(; chords = chords)

        recognize_gesture!(rec, WindowInput(:win, KeyDown(:c, ctrl)))   # prefix buffered
        breaker = WindowInput(:win, KeyDown(:x, ctrl))
        flushed = recognize_gesture!(rec, breaker)
        @test flushed isa WindowInput
        @test flushed.event isa KeyDown && flushed.event.key == :c  # prefix emitted first
        @test length(rec.pending) == 1
        @test rec.pending[1].event.key == :x                        # breaker queued next
        @test isempty(rec.chord_buffer)
    end

    # ── chords disabled by default: every key passes straight through ────────
    let rec = GestureRecognizer()
        e = WindowInput(:win, KeyDown(:c, ModifierKeys(ctrl = true)))
        @test recognize_gesture!(rec, e) === e
        @test isempty(rec.chord_buffer)
    end

    # ── pop_gesture! absorbs the prefix and returns the chord in one pull ───
    let ctrl   = ModifierKeys(ctrl = true),
        chords = [[KeyDown(:c, ctrl), KeyDown(:k, ctrl)]],
        rec    = GestureRecognizer(; chords = chords)

        source = _mk_source(Any[
            WindowInput(:win, KeyDown(:c, ctrl)),
            WindowInput(:win, KeyDown(:k, ctrl)),
        ])
        g = pop_gesture!(rec, source)               # Ctrl-C absorbed, chord delivered
        @test g.event isa KeyChord
        @test pop_gesture!(rec, source) === nothing # source exhausted
    end

    # ── a dangling prefix persists across an input-exhausted pull ────────────
    let ctrl   = ModifierKeys(ctrl = true),
        chords = [[KeyDown(:c, ctrl), KeyDown(:k, ctrl)]],
        rec    = GestureRecognizer(; chords = chords)

        source = _mk_source(Any[WindowInput(:win, KeyDown(:c, ctrl))])
        @test pop_gesture!(rec, source) === nothing # prefix buffered, no more input
        @test length(rec.chord_buffer) == 1          # kept for the next frame
    end

end
end
