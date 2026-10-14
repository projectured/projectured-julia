# The held frames of the SDL backend, `SdlHeldFrames.jl`: what a window takes and
# what it keeps while a code unit runs. The events are pushed onto the real SDL
# queue with the id of a real window, so what is tested is the path that the
# editor runs. SDL gives a pushed event the time of its push.

const _SDL_WINDOW_CLOSE_EVENT = 0x0e
const _SDLK_ESCAPE = Int32(27)

_push_held_key!(window_id, type, keysym, scancode) =
    _push_sdl_event!(_SDL.SDL_KeyboardEvent(type, UInt32(0), UInt32(window_id),
                                            type == _SDL_KEYDOWN ? UInt8(1) : UInt8(0),
                                            UInt8(0), UInt8(0), UInt8(0),
                                            _SDL.SDL_Keysym(scancode, Int32(keysym), UInt16(0),
                                                            UInt32(0))))

_push_held_letter!(window_id, type, letter::Char) =
    _push_held_key!(window_id, type, Int(letter),
                    _SDL.SDL_Scancode(Int(_SDL.SDL_SCANCODE_A) + (letter - 'a')))

_push_held_escape!(window_id, type) =
    _push_held_key!(window_id, type, _SDLK_ESCAPE, _SDL.SDL_SCANCODE_ESCAPE)

_push_held_button!(window_id, type, x, y) =
    _push_sdl_event!(_SDL.SDL_MouseButtonEvent(type, UInt32(0), UInt32(window_id), UInt32(0),
                                               _SDL_BUTTON_LEFT,
                                               type == _SDL_MOUSEBUTTONDOWN ? UInt8(1) : UInt8(0),
                                               UInt8(1), UInt8(0), Int32(x), Int32(y)))

_push_held_window_close!(window_id) =
    _push_sdl_event!(_SDL.SDL_WindowEvent(UInt32(_SDL.SDL_WINDOWEVENT), UInt32(0), UInt32(window_id),
                                          _SDL_WINDOW_CLOSE_EVENT, UInt8(0), UInt8(0), UInt8(0),
                                          Int32(0), Int32(0)))

# Every input that the backend has for the frames after a hold.
function _take_held_inputs!(backend)
    events = Any[]
    while (input = take_from_devices!(backend, Device[])) !== nothing
        input isa WindowInput && push!(events, input.event)
    end
    events
end

_get_held_center(box) = ((box[1] + box[3]) ÷ 2, (box[2] + box[4]) ÷ 2)

function test_sdl_held_frames()
@testset "the held frames of the SDL backend" begin
    SDL = ProjecturedSDL.SdlModule
    backend = SdlBackend()
    initialize_backend!(backend)
    canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    window = WindowDocument(; id = :held_frames_test, title = "held_frames_test",
                              x = 100, y = 100, width = 480, height = 240, content = canvas)
    screen = ScreenDocument([window])
    write_to_devices!(backend, Device[Display()], screen)
    write_to_devices!(backend, Device[Display()], screen)
    id = backend.windows[:held_frames_test].sdl_id
    run(seconds; is_quit_asked = false) =
        run_held_frame!(backend, Device[], HeldFrameState(seconds, 1, false, is_quit_asked))
    controls() = SDL._HELD_FRAMES[backend].controls[id]

    @testset "the keys stay for after the hold, and its pointer input goes" begin
        _drain_sdl_queue!()
        prepare_held_frames!(backend, Device[], ["a probe of the hold"])
        _push_held_letter!(id, _SDL_KEYDOWN, 'a')
        _push_held_letter!(id, _SDL_KEYUP, 'a')
        _push_held_button!(id, _SDL_MOUSEBUTTONDOWN, 30, 30)
        _push_held_button!(id, _SDL_MOUSEBUTTONUP, 30, 30)
        _push_held_letter!(id, _SDL_KEYDOWN, 'b')
        _push_held_letter!(id, _SDL_KEYUP, 'b')
        @test run(0.2) === :none
        @test run(0.3) === :none                   # a kept event goes through again
        end_held_frames!(backend, Device[])
        inputs = _take_held_inputs!(backend)
        @test [event.key for event in inputs if event isa KeyDown] == [:a, :b]
        @test count(event -> event isa KeyUp, inputs) == 2
        @test !any(event -> event isa Union{MouseDown,MouseUp}, inputs)
    end

    @testset "Escape is a key before the bar shows, and the stop after" begin
        _drain_sdl_queue!()
        prepare_held_frames!(backend, Device[], ["a probe of the hold"])
        _push_held_escape!(id, _SDL_KEYDOWN)
        _push_held_escape!(id, _SDL_KEYUP)
        @test run(0.2) === :none
        @test run(0.6) === :none                   # the bar shows from this frame on
        _push_held_escape!(id, _SDL_KEYDOWN)
        _push_held_escape!(id, _SDL_KEYUP)
        @test run(0.7) === :stop
        @test run(0.8) === :none                   # its release goes with it
        end_held_frames!(backend, Device[])
        inputs = _take_held_inputs!(backend)
        @test [event.key for event in inputs if event isa KeyDown] == [:escape]
        @test count(event -> event isa KeyUp, inputs) == 1
    end

    @testset "the Stop control stops, a close closes, and the Quit control quits when asked" begin
        _drain_sdl_queue!()
        prepare_held_frames!(backend, Device[], ["a probe of the hold"])
        @test run(1.0) === :none                   # the bar shows, with its Stop control
        stop, quit = controls()
        @test stop !== nothing && quit === nothing
        x, y = _get_held_center(stop)
        _push_held_button!(id, _SDL_MOUSEBUTTONDOWN, x, y)
        _push_held_button!(id, _SDL_MOUSEBUTTONUP, x, y)
        @test run(1.1) === :stop
        _push_held_window_close!(id)
        @test run(1.2) === :close
        @test run(3.5; is_quit_asked = true) === :none
        quit = last(controls())
        @test quit !== nothing
        x, y = _get_held_center(quit)
        _push_held_button!(id, _SDL_MOUSEBUTTONDOWN, x, y)
        @test run(3.6; is_quit_asked = true) === :quit
        end_held_frames!(backend, Device[])
        @test !haskey(SDL._HELD_FRAMES, backend)
        @test isempty(_take_held_inputs!(backend))
    end

    quit_backend!(backend)
end
end
