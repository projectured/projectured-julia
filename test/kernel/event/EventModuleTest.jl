"""
The event layer: the events and their constructors, `MouseButtons`, and the
`WindowInput`, which is generic over its input.
"""

using Test
using ProjecturedKernel.EventModule

function test_event_module()
@testset "EventModule" begin

    @testset "WindowInput carries the window an event came from" begin
        window_input = WindowInput(:default, KeyDown(:period, ModifierKeys(), false; time = 0.0))
        @test window_input isa WindowInput
        @test window_input.window_id === :default
        @test window_input.event isa KeyDown
        # The type is generic over the input, so this layer names no gesture.
        @test WindowInput(:default, MouseMove(1, 2; time = 0.0)) isa WindowInput{MouseMove}
    end

    @testset "the short forms of the constructors" begin
        @test KeyDown(:a, ModifierKeys(); time = 0.0).repeat === false
        @test KeyPress('a'; time = 0.0).text == "a"
        @test MouseMove(1, 2; time = 0.0).buttons == MouseButtons()
    end

    @testset "MouseButtons holds every held button" begin
        @test MouseButtons() == MouseButtons(false, false, false)
        @test MouseButtons(:left) == MouseButtons(left = true)
        both = MouseButtons(:left, :right)
        @test both.left && both.right && !both.middle
        move = MouseMove(3, 4, both, ModifierKeys(); time = 0.0)
        @test move.buttons.left && move.buttons.right
        @test_throws ArgumentError MouseButtons(:none)
        @test isbitstype(MouseButtons)
    end

end
end # test_event_module
