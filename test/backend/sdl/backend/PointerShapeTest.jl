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
        read_from_devices(backend, Device[]) === nothing && break
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
        write_to_devices(backend, Device[], screen)
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

end
end
