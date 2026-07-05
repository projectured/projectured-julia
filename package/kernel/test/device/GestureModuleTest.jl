"""
`GestureModule` — the merged @event_case + gesture-binding module and the
rehomed EventEnvelope. Kernel plan P5 (R4 + R5).
"""

using Test
using ProjecturedKernel.GestureModule
using ProjecturedKernel.KeyboardModule: KeyDown, KeyPress
using ProjecturedKernel.MouseModule: MouseDown
using ProjecturedKernel.ModifiersModule: Modifiers

@testset "GestureModule" begin

    @testset "EventEnvelope lives on the device layer (R5)" begin
        env = EventEnvelope(:main, KeyDown(:period, Modifiers(), false))
        @test env isa EventEnvelope
        @test env.window_id === :main
        @test env.event isa KeyDown
    end

    @testset "@event_case dispatches on event type" begin
        # A minimal event_case usage — dispatches to a matching branch and falls
        # through to the wildcard.
        evt = KeyDown(:period, Modifiers(ctrl=true), false)
        r = @event_case evt begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r === :dot_ctrl

        # A non-matching event returns the wildcard result.
        move = MouseDown(:left, 10, 20, Modifiers())
        r2 = @event_case move begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r2 === :fallback
    end

    @testset "GesturePattern matches and describes" begin
        p = KeyDownPattern(:period, [:ctrl], nothing)
        evt = KeyDown(:period, Modifiers(ctrl=true), false)
        @test matches(p, evt)
        s = describe(p)
        @test occursin("Ctrl", s)
    end

end
