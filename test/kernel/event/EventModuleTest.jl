"""
The event layer: the events and their constructors, `MouseButtons`, and the
`WindowInput`, which is generic over its input.
"""

using Test
using ProjecturedKernel.EventModule

# An event type of another module, as a package defines one.
struct EmTestRestEvent <: Event
    x::Int
    y::Int
    time::Float64
end

function test_event_module()
@testset "EventModule" begin

    @testset "WindowInput carries the window an event came from" begin
        window_input = WindowInput(:default, KeyDown(:period, ModifierKeys(); time = 0.0))
        @test window_input isa WindowInput
        @test window_input.window_id === :default
        @test window_input.event isa KeyDown
        # The type is generic over the input, so this layer names no gesture.
        @test WindowInput(:default, MouseMove(1, 2; time = 0.0)) isa WindowInput{MouseMove}
    end

    @testset "the short forms of the constructors" begin
        @test KeyDown(:a, ModifierKeys(); time = 0.0).repeat === false
        @test KeyDown(:a, ModifierKeys(); repeat = true, time = 0.0).repeat === true
        @test KeyPress('a'; time = 0.0).text == "a"
        @test MouseMove(1, 2; time = 0.0).buttons == MouseButtons()
    end

    @testset "each modifier predicate reads get_modifier_keys" begin
        key = KeyDown(:a, ModifierKeys(ctrl = true, alt = true); time = 0.0)
        @test has_ctrl_modifier_key(key) && has_alt_modifier_key(key)
        @test !has_shift_modifier_key(key) && !has_meta_modifier_key(key)
        down = MouseDown(:left, 1, 2, ModifierKeys(shift = true, meta = true); time = 0.0)
        @test has_shift_modifier_key(down) && has_meta_modifier_key(down)
        @test !has_ctrl_modifier_key(down) && !has_alt_modifier_key(down)
    end

    @testset "an event with no modifiers of its own holds none" begin
        @test get_modifier_keys(WindowResize(10, 20; time = 0.0)) == ModifierKeys()
        @test !has_ctrl_modifier_key(WindowResize(10, 20; time = 0.0))
        @test get_modifier_keys(WindowQuit(; time = 0.0)) == ModifierKeys()
    end

    @testset "get_event_time reads the time of an event of another module" begin
        @test get_event_time(EmTestRestEvent(3, 4, 1.5)) === 1.5
        @test get_event_time(KeyPress('a'; time = 2)) === 2.0
    end

    @testset "MouseButtons holds every held button" begin
        @test MouseButtons() == MouseButtons(left = false, middle = false, right = false)
        @test MouseButtons(:left) == MouseButtons(left = true)
        both = MouseButtons(:left, :right)
        @test both.left && both.right && !both.middle
        move = MouseMove(3, 4, both, ModifierKeys(); time = 0.0)
        @test move.buttons.left && move.buttons.right
        @test_throws ArgumentError MouseButtons(:none)
        @test isbitstype(MouseButtons)
    end

    @testset "SystemColors holds a known mode and contrast, and its change the time" begin
        @test SystemColors() == SystemColors(:light, :normal, nothing)
        dark = SystemColors(; mode = :dark, contrast = :high, accent = (0x25, 0x63, 0xeb))
        @test (dark.mode, dark.contrast, dark.accent) === (:dark, :high, (0x25, 0x63, 0xeb))
        @test_throws ArgumentError SystemColors(; mode = :sepia)
        @test_throws ArgumentError SystemColors(; contrast = :low)
        change = SystemColorsChange(dark; time = 2)
        @test change.colors == dark
        @test get_event_time(change) === 2.0
    end

end
end # test_event_module
