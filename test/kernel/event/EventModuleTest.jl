"""
The event layer — the `WindowInput`, the `@event_case` dispatch table, and the
reified event patterns.
"""

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventModule

function test_event_module()
@testset "EventModule" begin

    @testset "WindowInput carries the window an event came from" begin
        window_input = WindowInput(:default, KeyDown(:period, ModifierKeys(), false))
        @test window_input isa WindowInput
        @test window_input.window_id === :default
        @test window_input.event isa KeyDown
    end

    @testset "@event_case dispatches on event type" begin
        # A minimal event_case usage — dispatches to a matching branch and falls
        # through to the wildcard.
        event = KeyDown(:period, ModifierKeys(ctrl=true), false)
        r = @event_case event begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r === :dot_ctrl

        # A non-matching event returns the wildcard result.
        move = MouseDown(:left, 10, 20, ModifierKeys())
        r2 = @event_case move begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r2 === :fallback
    end

    @testset "EventPattern matches and describes" begin
        p = KeyDownPattern(:period; modifiers = [:ctrl])
        event = KeyDown(:period, ModifierKeys(ctrl=true), false)
        @test matches_event_pattern(p, event)
        @test occursin("Ctrl", describe_event_pattern(p))
    end

end
end # test_event_module
