# The SDL backend sets the cursor of the system to the shape of the region under
# the pointer. A test can not read the cursor of the system, so it reads the shape
# that the backend chose for a motion pushed onto the real SDL queue.

# Push a motion to the point `(x, y)` of the window `resource`, in logical pixels.
function _push_window_motion!(resource, x, y, ratio)
    _push_sdl_event!(_SDL.SDL_MouseMotionEvent(_SDL_MOUSEMOTION, UInt32(0), resource.sdl_id,
                                               UInt32(0), UInt32(0),
                                               Int32(round(Int, x * ratio)),
                                               Int32(round(Int, y * ratio)), Int32(0), Int32(0)))
end

# Read every input that waits, at most 50.
function _read_waiting_input!(backend)
    for _ in 1:50
        take_from_devices!(backend, Device[]) === nothing && break
    end
end

function test_sdl_pointer_shape()
@testset "the pointer takes the shape of the region under it" begin

    backend = SdlBackend()
    initialize_backend!(backend)
    try
        shape = Cell(:ibeam)
        canvas = GraphicsCanvas([GraphicsRect(0, 0, 200, 100; color = color_white),
                                 GraphicsPointerShape(0, 0, 100, 100, () -> shape[]),
                                 GraphicsPointerShape(100, 0, 20, 100, :open_hand)];
                                w = 200, h = 100)
        window = WindowDocument(; id = :pointer_shape_test, title = "pointer_shape_test",
                                  x = 100, y = 100, width = 200, height = 100, content = canvas)
        screen = ScreenDocument([window])
        write_to_devices!(backend, Device[], screen)
        resource = backend.windows[:pointer_shape_test]
        ratio = get_device_pixel_ratio(backend.display)
        _reset_input!(backend)

        @testset "a motion sets the shape of the region at its point" begin
            _push_window_motion!(resource, 10, 10, ratio)
            _read_waiting_input!(backend)
            @test backend.pointer_shape === :ibeam
            _push_window_motion!(resource, 105, 10, ratio)
            _read_waiting_input!(backend)
            @test backend.pointer_shape === :open_hand
            _push_window_motion!(resource, 150, 10, ratio)
            _read_waiting_input!(backend)
            @test backend.pointer_shape === :default
        end

        @testset "each shape has a cursor, made once" begin
            # The offscreen driver, which SDL uses where no display is, makes no
            # system cursor, and whether it makes a cursor of a glyph depends on
            # the machine. So a cursor is asserted only with a display; that each
            # shape asks SDL once is asserted everywhere.
            has_display = unsafe_string(_SDL.SDL_GetCurrentVideoDriver()) != "offscreen"
            made = backend.cursors[:open_hand]
            has_display && @test made != C_NULL
            _push_window_motion!(resource, 105, 10, ratio)
            _read_waiting_input!(backend)
            @test backend.cursors[:open_hand] === made
            for name in POINTER_SHAPES
                cursor = ProjecturedSDL.SdlModule._get_shape_cursor!(backend, name)
                has_display && @test cursor != C_NULL
                @test ProjecturedSDL.SdlModule._get_shape_cursor!(backend, name) === cursor
            end
        end

        @testset "a hand cursor is white at its hot spot, in the middle of the hand" begin
            for glyph in values(ProjecturedSDL.SdlModule._GLYPH_OF_SHAPE)
                image = ProjecturedSDL.SdlModule._make_glyph_cursor_image(glyph, 2.0)
                @test image !== nothing
                image === nothing && continue
                info = unsafe_load(image)
                middle_row = Ptr{UInt32}(info.pixels) + (Int(info.h) ÷ 2) * Int(info.pitch)
                @test unsafe_load(middle_row, Int(info.w) ÷ 2 + 1) == 0xffffffff
                _SDL.SDL_FreeSurface(image)
            end
        end

        @testset "a motion off every region and a shape that changes in place" begin
            _push_window_motion!(resource, 10, 10, ratio)
            _read_waiting_input!(backend)
            @test backend.pointer_shape === :ibeam
            # The region under the pointer takes another shape: the next motion
            # at the same point shows it.
            shape[] = :double_arrow_horizontal
            _push_window_motion!(resource, 10, 10, ratio)
            _read_waiting_input!(backend)
            @test backend.pointer_shape === :double_arrow_horizontal
        end
    finally
        quit_backend!(backend)
    end
    @test isempty(backend.cursors)
    @test backend.pointer_shape === :default

    @testset "a glyph cursor is white where its outline closes in" begin
        fill_enclosed! = ProjecturedSDL.SdlModule._fill_enclosed_pixels!
        clear, line, white = 0x00000000, 0xff000000, 0xffffffff
        # A square ring with a half transparent pixel inside.
        ring = fill(clear, 5, 5)
        ring[2:4, [2, 4]] .= line
        ring[[2, 4], 3] .= line
        ring[3, 3] = 0x80ffffff
        expected = copy(ring)
        expected[3, 3] = white
        @test fill_enclosed!(copy(ring)) == expected
        # A ring with a gap closes in nothing.
        open_ring = copy(ring)
        open_ring[2, 3] = clear
        @test fill_enclosed!(copy(open_ring)) == open_ring
        # A diamond of diagonal steps closes in the five pixels in its middle.
        diamond = fill(clear, 7, 7)
        for index in ((2, 4), (3, 3), (3, 5), (4, 2), (4, 6), (5, 3), (5, 5), (6, 4))
            diamond[index...] = line
        end
        expected = copy(diamond)
        for index in ((3, 4), (4, 3), (4, 4), (4, 5), (5, 4))
            expected[index...] = white
        end
        @test fill_enclosed!(copy(diamond)) == expected
    end

    @testset "the cursor library searches the icon folders of the system" begin
        set_cursor_path! = ProjecturedSDL.SdlModule._set_x11_cursor_path!
        if ProjecturedSDL.SdlModule.Xorg_libX11_jll.is_available()
            home = homedir()
            withenv("XCURSOR_PATH" => nothing, "XDG_DATA_HOME" => "/data/home",
                    "XDG_DATA_DIRS" => "/data/one::/data/two") do
                set_cursor_path!()
                @test ENV["XCURSOR_PATH"] ==
                      "/data/home/icons:$home/.icons:/data/one/icons:/data/two/icons:/usr/share/pixmaps"
            end
            # A variable that is not set or is empty takes the default of the XDG
            # base directory specification.
            withenv("XCURSOR_PATH" => nothing, "XDG_DATA_HOME" => nothing,
                    "XDG_DATA_DIRS" => "") do
                set_cursor_path!()
                @test ENV["XCURSOR_PATH"] ==
                      "$home/.local/share/icons:$home/.icons:/usr/local/share/icons:" *
                      "/usr/share/icons:/usr/share/pixmaps"
            end
            withenv("XCURSOR_PATH" => "/the/folder/of/the/user") do
                set_cursor_path!()
                @test ENV["XCURSOR_PATH"] == "/the/folder/of/the/user"
            end
            # The package sets the path before the first search of the library, so
            # the library searches the path of the process.
            library = Base.Libc.Libdl.dlopen("libXcursor.so.1"; throw_error = false)
            if library !== nothing
                search_path = ccall(Base.Libc.Libdl.dlsym(library, :XcursorLibraryPath), Cstring, ())
                @test unsafe_string(search_path) == ENV["XCURSOR_PATH"]
            end
        end
    end

end
end
