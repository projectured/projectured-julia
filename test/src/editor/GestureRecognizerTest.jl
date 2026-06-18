# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/GestureRecognizerTest.jl
#
# Unit tests for the event → gesture recogniser. These exercise the click
# synthesis (MouseDown + MouseUp → MousePress) that used to live, untested,
# inside the SDL backend. A scripted `source` and an injectable clock make
# recognition fully deterministic without SDL.
# ═══════════════════════════════════════════════════════════════════════════

using Projectured
using Projectured: GestureRecognizer, recognize!, next_gesture!
using Projectured: EventEnvelope, MouseDown, MouseUp, MousePress, MouseMove,
                   MouseScroll, KeyDown, KeyPress, Modifiers

# A controllable clock: returns whatever `t[]` currently holds.
_mk_clock(t::Ref{Float64}) = () -> t[]

# A scripted event source: pops envelopes off a vector, `nothing` when empty.
_mk_source(envs::Vector) = () -> isempty(envs) ? nothing : popfirst!(envs)

function test_gesture_recognizer()
@testset "GestureRecognizer" begin

    # ── a quick, in-place down/up pair synthesises a MousePress ──────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        down = EventEnvelope(:win, MouseDown(:left, 10, 20, Modifiers()))
        @test recognize!(rec, down) === down        # forwarded unchanged
        @test isempty(rec.pending)                  # nothing synthesised yet

        t[] = 0.1
        up = EventEnvelope(:win, MouseUp(:left, 11, 21, Modifiers()))
        @test recognize!(rec, up) === up            # the up is still forwarded
        @test length(rec.pending) == 1              # plus a synthesised click
        press = rec.pending[1]
        @test press isa EventEnvelope
        @test press.window_id == :win               # window id preserved
        @test press.event isa MousePress
        @test (press.event.button, press.event.x, press.event.y) == (:left, 11, 21)
    end

    # ── too far away: no click ───────────────────────────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize!(rec, EventEnvelope(:win, MouseDown(:left, 10, 20, Modifiers())))
        t[] = 0.1
        recognize!(rec, EventEnvelope(:win, MouseUp(:left, 100, 20, Modifiers())))
        @test isempty(rec.pending)
    end

    # ── too slow: no click ───────────────────────────────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize!(rec, EventEnvelope(:win, MouseDown(:left, 10, 20, Modifiers())))
        t[] = 0.5   # > CLICK_MAX_DURATION (0.3)
        recognize!(rec, EventEnvelope(:win, MouseUp(:left, 10, 20, Modifiers())))
        @test isempty(rec.pending)
    end

    # ── different button up does not complete a click ────────────────────────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        recognize!(rec, EventEnvelope(:win, MouseDown(:left, 10, 20, Modifiers())))
        t[] = 0.1
        recognize!(rec, EventEnvelope(:win, MouseUp(:right, 10, 20, Modifiers())))
        @test isempty(rec.pending)
    end

    # ── non-mouse events pass through untouched, nothing synthesised ─────────
    let rec = GestureRecognizer()
        for evt in (KeyDown(:home, Modifiers()), KeyPress('a'),
                    MouseScroll(0, -1, 5, 6, Modifiers()),
                    MouseMove(1, 2, :none, Modifiers()))
            env = EventEnvelope(:win, evt)
            @test recognize!(rec, env) === env
        end
        @test isempty(rec.pending)
    end

    # ── next_gesture! drains pending before pulling new input, in order ──────
    let t = Ref(0.0), rec = GestureRecognizer(; clock = _mk_clock(t))
        script = Any[
            EventEnvelope(:win, MouseDown(:left, 10, 20, Modifiers())),
            EventEnvelope(:win, MouseUp(:left, 10, 20, Modifiers())),
        ]
        source = _mk_source(script)

        g1 = next_gesture!(rec, source)             # MouseDown forwarded
        @test g1.event isa MouseDown

        g2 = next_gesture!(rec, source)             # MouseUp forwarded, click queued
        @test g2.event isa MouseUp
        @test length(rec.pending) == 1

        g3 = next_gesture!(rec, source)             # queued click delivered next
        @test g3.event isa MousePress

        @test next_gesture!(rec, source) === nothing # source exhausted
    end

end
end
