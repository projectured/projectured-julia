# The SDL backend fills the `Display` of an editor and draws at its device pixel
# ratio. Each backend has its own `Display`, so two editors in one process each
# keep their own density and zoom.
function test_device_config()
@testset "device configuration" begin

    SDL = ProjecturedSDL.SdlModule

    @testset "configure_devices! fills the Display and draws with it" begin
        backend = SdlBackend()

        # get_display_size reports the real display as a positive Int tuple.
        w, h = get_display_size(backend)
        @test w isa Integer && h isa Integer
        @test w > 0 && h > 0

        # configure_devices! fills a Display from the display query and the probed
        # density, and leaves Mouse/Keyboard at their defaults (SDL2 cannot discover
        # those). The zoom of the Display stays as it is.
        display  = Display(zoom = 1.5)
        mouse    = Mouse()
        keyboard = Keyboard()
        @test configure_devices!(backend, Device[display, mouse, keyboard]) === nothing
        @test (display.width, display.height) == (w, h)
        @test display.density === SDL._PROBED_DISPLAY_DENSITY[]
        @test display.density > 0
        @test display.zoom === 1.5
        @test backend.display === display
        @test (mouse.button_count, mouse.has_scroll_wheel) == (3, true)   # unchanged
        @test keyboard.layout === :qwerty                                 # unchanged

        # The Display of a second editor gets the density of the hardware, not the
        # zoom of the first.
        other = Display()
        configure_devices!(SdlBackend(), Device[other])
        @test (other.density, other.zoom) === (display.density, 1.0)

        # Without a Display in the list, the backend keeps its own.
        lone = SdlBackend()
        own = lone.display
        configure_devices!(lone, Device[Keyboard()])
        @test lone.display === own
    end

    @testset "the ratio of a Display converts logical and device pixels" begin
        double = SdlBackend()
        double.display = Display(density = 2.0)
        @test SDL._to_logical(88, get_device_pixel_ratio(double.display)) == 44
        @test SDL._to_device(44, get_device_pixel_ratio(double.display)) == 88
    end

    @testset "the zoom of one editor leaves the other" begin
        first_backend = SdlBackend()
        second_backend = SdlBackend()
        first_backend.display.zoom = step_factor(1.0, 1)
        @test second_backend.display.zoom === 1.0
        @test get_device_pixel_ratio(first_backend.display) ===
              first_backend.display.density * step_factor(1.0, 1)
        @test get_device_pixel_ratio(second_backend.display) === second_backend.display.density
    end

    @testset "a new zoom keeps the device size and place of each window" begin
        backend = SdlBackend()
        window = WindowDocument(; id = :zoom_window_test, title = "zoom_window_test",
                                x = 100, y = 60, width = 400, height = 300,
                                content = GraphicsCanvas())
        chosen = WindowDocument(; id = :zoom_chosen_test, title = "zoom_chosen_test",
                                width = 400, height = 300, content = GraphicsCanvas())
        screen = ScreenDocument([window, chosen])
        geometry(w) = (Int(w.x), Int(w.y), Int(w.width), Int(w.height))
        # The first frame keeps the size and the place that the window has.
        SDL._keep_device_geometry_at_new_zoom!(backend, screen)
        @test geometry(window) == (100, 60, 400, 300)
        # A frame at twice the zoom: the logical size and place halve, so the
        # device size and place, the logical ones times the ratio, stay. A place
        # that the backend chooses stays below zero.
        backend.display.zoom = 2.0
        SDL._keep_device_geometry_at_new_zoom!(backend, screen)
        @test geometry(window) == (50, 30, 200, 150)
        @test (Int(chosen.x), Int(chosen.y)) == (-1, -1)
        # A new density, as the probe of the first window finds, moves no size.
        backend.display.density = 2.0
        SDL._keep_device_geometry_at_new_zoom!(backend, screen)
        @test geometry(window) == (50, 30, 200, 150)
        backend.display.zoom = 1.0
        SDL._keep_device_geometry_at_new_zoom!(backend, screen)
        @test geometry(window) == (100, 60, 400, 300)
    end

    @testset "step_factor walks the table of zoom factors" begin
        @test step_factor(1.0, 1) === 1.1
        @test step_factor(1.0, -1) === 0.9
        @test step_factor(1.2, 1) === 1.5      # 1.2 counts as 1.25
        @test step_factor(3.0, 1) === 3.0      # the table ends at 3.0
        @test step_factor(0.5, -1) === 0.5
        @test step_factor(2.0, 0) === 1.0
    end

    @testset "an export at density 2 leaves the ratio of a backend" begin
        backend = SdlBackend()
        before = get_device_pixel_ratio(backend.display)
        filename = tempname() * ".bmp"
        write_image(GraphicsCanvas(), filename; width = 40, height = 30, density = 2)
        rm(filename)
        @test get_device_pixel_ratio(backend.display) === before
    end

end
end # test_device_config
