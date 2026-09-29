"""
The device layer: the defaults and the keyword constructors of the three
devices, the properties that a backend writes, and the ratio of device pixels to
logical pixels of a display.
"""

using Test
using ProjecturedKernel.DeviceModule

function test_device_module()
@testset "DeviceModule" begin

    @testset "each device is a Device" begin
        @test Display() isa Device
        @test Keyboard() isa Device
        @test Mouse() isa Device
    end

    @testset "the defaults describe common hardware" begin
        display = Display()
        @test (display.width, display.height) == (1280, 800)
        @test (display.scale, display.zoom) === (1.0, 1.0)
        mouse = Mouse()
        @test (mouse.button_count, mouse.has_scroll_wheel) == (3, true)
        @test Keyboard().layout === :qwerty
    end

    @testset "the keyword constructors set each property" begin
        display = Display(width = 1920, height = 1080, scale = 2, zoom = 1.25)
        @test (display.width, display.height) == (1920, 1080)
        @test (display.scale, display.zoom) === (2.0, 1.25)
        @test Display(width = Int32(640)).width === 640
        mouse = Mouse(button_count = 5, has_scroll_wheel = false)
        @test (mouse.button_count, mouse.has_scroll_wheel) == (5, false)
        @test Keyboard(layout = :azerty).layout === :azerty
    end

    @testset "a scale or a zoom of 0 or less is no display" begin
        @test_throws ArgumentError Display(scale = 0)
        @test_throws ArgumentError Display(zoom = -1.0)
        @test_throws ArgumentError Display(scale = NaN)
    end

    @testset "a backend writes the properties in place" begin
        display = Display()
        display.scale = 2.0
        display.width = 2560
        @test (display.width, display.scale) == (2560, 2.0)
    end

    @testset "the ratio is the scale times the zoom" begin
        display = Display(scale = 2.0)
        @test (@inferred get_device_pixel_ratio(display)) === 2.0
        display.zoom = 1.5
        @test get_device_pixel_ratio(display) === 3.0
        display.scale = 1.0
        @test get_device_pixel_ratio(display) === 1.5
    end

end
end # test_device_module
