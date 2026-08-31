function test_device_config()
@testset "device configuration" begin

    backend = SdlBackend()

    # get_display_size reports the real display as a positive Int tuple.
    w, h = get_display_size(backend)
    @test w isa Integer && h isa Integer
    @test w > 0 && h > 0

    # configure_devices! populates a Display from the display query + HiDPI scale,
    # and leaves Mouse/Keyboard at their defaults (SDL2 cannot discover those).
    display  = Display()
    mouse    = Mouse()
    keyboard = Keyboard()
    @test configure_devices!(backend, Device[display, mouse, keyboard]) === nothing
    @test (display.width, display.height) == (w, h)
    @test display.scale isa Float64 && display.scale > 0
    @test (mouse.button_count, mouse.has_scroll_wheel) == (3, true)   # unchanged
    @test keyboard.layout === :qwerty                                 # unchanged

end
end # test_device_config
