# The SDL backend fills the `Display` of an editor and draws at its device pixel
# ratio. Each backend has its own `Display`, so two editors in one process each
# keep their own scale and zoom.
function test_device_config()
@testset "device configuration" begin

    SDL = ProjecturedSdl

    @testset "configure_devices! fills the Display and draws with it" begin
        backend = SdlBackend()

        # get_display_size reports the real display as a positive Int tuple.
        w, h = get_display_size(backend)
        @test w isa Integer && h isa Integer
        @test w > 0 && h > 0

        # configure_devices! fills a Display from the display query and the probed
        # scale, and leaves Mouse/Keyboard at their defaults (SDL2 cannot discover
        # those). The zoom of the Display stays as it is.
        display  = Display(zoom = 1.5)
        mouse    = Mouse()
        keyboard = Keyboard()
        @test configure_devices!(backend, Device[display, mouse, keyboard]) === nothing
        @test (display.width, display.height) == (w, h)
        @test display.scale === SDL._PROBED_DISPLAY_SCALE[]
        @test display.scale > 0
        @test display.zoom === 1.5
        @test backend.display === display
        @test (mouse.button_count, mouse.has_scroll_wheel) == (3, true)   # unchanged
        @test keyboard.layout === :qwerty                                 # unchanged

        # The Display of a second editor gets the scale of the hardware, not the
        # zoom of the first.
        other = Display()
        configure_devices!(SdlBackend(), Device[other])
        @test (other.scale, other.zoom) === (display.scale, 1.0)

        # Without a Display in the list, the backend keeps its own.
        lone = SdlBackend()
        own = lone.display
        configure_devices!(lone, Device[Keyboard()])
        @test lone.display === own
    end

    @testset "each backend measures at the ratio of its Display" begin
        font = font_ubuntu_regular_20
        text = "iiiiiiiiii WWWWW"
        single = SdlBackend()
        single.display = Display(scale = 1.0)
        double = SdlBackend()
        double.display = Display(scale = 2.0)
        @test measure_text(single, text, font) == SDL._measure_sdl_text(text, font, 1.0)
        @test measure_text(double, text, font) == SDL._measure_sdl_text(text, font, 2.0)
        # The standalone measure does not depend on the display of the machine.
        @test measure_sdl_text(text, font) == SDL._measure_sdl_text(text, font, 1.0)
        @test SDL._to_logical(88, get_device_pixel_ratio(double.display)) == 44
        @test SDL._to_device(44, get_device_pixel_ratio(double.display)) == 88
    end

    @testset "the zoom of one editor leaves the other" begin
        first_backend = SdlBackend()
        second_backend = SdlBackend()
        first_editor = (backend = first_backend, iomap = nothing)
        SDL.evaluate_operation(first_editor, AdjustZoomOperation(1))
        @test first_backend.display.zoom === step_zoom(1.0, 1)
        @test second_backend.display.zoom === 1.0
        @test get_device_pixel_ratio(first_backend.display) ===
              first_backend.display.scale * step_zoom(1.0, 1)
        SDL.evaluate_operation(first_editor, AdjustZoomOperation(0))
        @test first_backend.display.zoom === 1.0
    end

    @testset "step_zoom walks the table of zoom factors" begin
        @test step_zoom(1.0, 1) === 1.1
        @test step_zoom(1.0, -1) === 0.9
        @test step_zoom(1.2, 1) === 1.5      # 1.2 counts as 1.25
        @test step_zoom(3.0, 1) === 3.0      # the table ends at 3.0
        @test step_zoom(0.5, -1) === 0.5
        @test step_zoom(2.0, 0) === 1.0
    end

    @testset "an export at scale 2 leaves the ratio of a backend" begin
        backend = SdlBackend()
        before = get_device_pixel_ratio(backend.display)
        filename = tempname() * ".bmp"
        write_image(GraphicsCanvas(), filename; width = 40, height = 30, scale = 2)
        rm(filename)
        @test get_device_pixel_ratio(backend.display) === before
    end

end
end # test_device_config
