# `read_from_devices` collapses a run of pointer motion into its newest sample.
# The events are pushed onto the real SDL queue, so what is tested is the path
# the editor actually runs, not a stand-in for it.

# The SDL bindings, reached through the backend package: this test package
# depends on `ProjecturedSdl`, not on SDL itself.
const _SDL = ProjecturedSdl.SdlModule.SimpleDirectMediaLayer.LibSDL2

const _SDL_KEYDOWN         = 0x00000300
const _SDL_KEYUP           = 0x00000301
const _SDL_MOUSEMOTION     = 0x00000400
const _SDL_MOUSEBUTTONDOWN = 0x00000401
const _SDL_MOUSEBUTTONUP   = 0x00000402
const _SDL_MOUSEWHEEL      = 0x00000403
const _SDL_BUTTON_LEFT     = 0x01
const _SDL_BUTTON_X1       = 0x04         # a side button: the event layer has no name
const _SDL_BUTTON_LMASK    = 0x00000001   # the left button in the `state` of a motion
const _SDLK_LCTRL          = Int32(1073742048)
const _KMOD_LCTRL          = 0x0040

# Write one event of type `T` into an `SDL_Event` blob and push it on the queue.
function _push_sdl_event!(payload::T) where {T}
    event = Ref{_SDL.SDL_Event}()
    GC.@preserve event begin
        base = Base.unsafe_convert(Ptr{_SDL.SDL_Event}, event)
        unsafe_store!(convert(Ptr{T}, base), payload)
        _SDL.SDL_PushEvent(event)
    end
end

_push_motion!(x, y; buttons::UInt32 = UInt32(0)) =
    _push_sdl_event!(_SDL.SDL_MouseMotionEvent(_SDL_MOUSEMOTION, UInt32(0), UInt32(0),
                                               UInt32(0), buttons,
                                               Int32(x), Int32(y), Int32(0), Int32(0)))

_push_button_down!(x, y; button::UInt8 = _SDL_BUTTON_LEFT) =
    _push_sdl_event!(_SDL.SDL_MouseButtonEvent(_SDL_MOUSEBUTTONDOWN, UInt32(0), UInt32(0),
                                               UInt32(0), button, UInt8(1),
                                               UInt8(1), UInt8(0), Int32(x), Int32(y)))

_push_button_up!(x, y; button::UInt8 = _SDL_BUTTON_LEFT) =
    _push_sdl_event!(_SDL.SDL_MouseButtonEvent(_SDL_MOUSEBUTTONUP, UInt32(0), UInt32(0),
                                               UInt32(0), button, UInt8(0),
                                               UInt8(1), UInt8(0), Int32(x), Int32(y)))

_push_window_event!(kind) =
    _push_sdl_event!(_SDL.SDL_WindowEvent(UInt32(_SDL.SDL_WINDOWEVENT), UInt32(0), UInt32(0),
                                          UInt8(kind), UInt8(0), UInt8(0), UInt8(0),
                                          Int32(0), Int32(0)))

# A wheel turn of `dy` steps, as SDL reports it: a positive `dy` is a turn away from
# the user. The fields of the event differ between the versions of the SDL bindings,
# so each field that the turn does not name is 0.
function _push_wheel!(dy)
    T = _SDL.SDL_MouseWheelEvent
    values = Dict(:type => _SDL_MOUSEWHEEL, :y => dy)
    fields = (fieldtype(T, name)(get(values, name, 0)) for name in fieldnames(T))
    _push_sdl_event!(T(fields...))
end

# A key event of the left Ctrl key, with the modifier mask `mod` that SDL gives it.
_push_ctrl_key!(type, mod) =
    _push_sdl_event!(_SDL.SDL_KeyboardEvent(type, UInt32(0), UInt32(0),
                                            type == _SDL_KEYDOWN ? UInt8(1) : UInt8(0),
                                            UInt8(0), UInt8(0), UInt8(0),
                                            _SDL.SDL_Keysym(_SDL.SDL_SCANCODE_LCTRL,
                                                            _SDLK_LCTRL, UInt16(mod),
                                                            UInt32(0))))

# Start from an empty queue and an expired rate limit, so each case sees only
# what it pushed.
function _reset_input!(backend)
    _SDL.SDL_PumpEvents()
    _SDL.SDL_FlushEvents(UInt32(0), typemax(UInt32))
    backend.last_hover_motion = 0.0
end

# The `Display` of the backend below has the scale 2, so an event holds the half of
# the device coordinates that SDL reports.
_logical(v) = ProjecturedSdl.SdlModule._to_logical(Int(v), 2.0)

function test_input_coalescing()
@testset "pointer motion is coalesced" begin

    backend = SdlBackend()
    backend.display.scale = 2.0

    @testset "a run of motion answers with the newest sample" begin
        _reset_input!(backend)
        for (x, y) in ((10, 10), (20, 20), (30, 30), (44, 55))
            _push_motion!(x, y)
        end
        input = read_from_devices(backend, Device[])
        @test input isa WindowInput
        @test input.event isa MouseMove
        # The newest sample, not the oldest. Answering with (10, 10) here is what
        # left the highlight a frame behind the pointer.
        @test (input.event.x, input.event.y) == (_logical(44), _logical(55))
        # The whole run was consumed, so nothing stale is owed.
        @test read_from_devices(backend, Device[]) === nothing
    end

    @testset "an event behind a run does not overtake it" begin
        _reset_input!(backend)
        _push_motion!(1, 1)
        _push_motion!(7, 9)
        _push_button_down!(7, 9)
        first_input = read_from_devices(backend, Device[])
        @test first_input.event isa MouseMove
        @test (first_input.event.x, first_input.event.y) == (_logical(7), _logical(9))
        second_input = read_from_devices(backend, Device[])
        @test second_input.event isa MouseDown          # the press, after the motion
        @test read_from_devices(backend, Device[]) === nothing
    end

    @testset "a sample the rate limit blocks is held, not dropped" begin
        _reset_input!(backend)
        _push_motion!(12, 34)
        probe = read_from_devices(backend, Device[])
        @test probe.event isa MouseMove
        # The rate limit applies to idle motion only. A button held during the
        # run makes it a drag, which is never rate-limited; skip the case then.
        if probe.event.buttons == MouseButtons()
            backend.last_hover_motion = time()   # the limit is now active
            _push_motion!(60, 70)
            @test read_from_devices(backend, Device[]) === nothing   # held, not answered
            backend.last_hover_motion = 0.0     # the interval has passed
            held = read_from_devices(backend, Device[])   # the queue is empty by now
            @test held isa WindowInput
            @test held.event isa MouseMove
            # A pointer that stops sends nothing more. Dropping this sample would
            # leave the highlight one step behind for as long as it rests there.
            @test (held.event.x, held.event.y) == (_logical(60), _logical(70))
        end
        _reset_input!(backend)
    end

    @testset "a motion holds the buttons of its own place in the queue" begin
        # The release waits behind the motion, so the motion is the last sample of
        # a drag and holds the left button, not the buttons at the time of the poll.
        _reset_input!(backend)
        _push_motion!(20, 30; buttons = _SDL_BUTTON_LMASK)
        _push_button_up!(20, 30)
        motion = read_from_devices(backend, Device[])
        @test motion.event isa MouseMove
        @test motion.event.buttons == MouseButtons(:left)
        @test read_from_devices(backend, Device[]).event isa MouseUp
        @test read_from_devices(backend, Device[]) === nothing
    end

    @testset "a side button makes no mouse event" begin
        # The event layer names the left, the middle and the right button. A side
        # button is none of them, so SDL reports no press and no release for it.
        _reset_input!(backend)
        _push_button_down!(10, 10; button = _SDL_BUTTON_X1)
        _push_button_up!(10, 10; button = _SDL_BUTTON_X1)
        @test read_from_devices(backend, Device[]) === nothing
    end

    @testset "the buttons and the wheel have the names of the event layer" begin
        # SDL numbers the left button 1, the middle 2 and the right 3. A side button,
        # 4 or 5, has no name in the event layer and makes no event.
        for (button, name) in ((0x01, :left), (0x02, :middle), (0x03, :right),
                               (0x05, nothing))
            _reset_input!(backend)
            _push_button_down!(10, 10; button)
            _push_button_up!(10, 10; button)
            if name === nothing
                @test read_from_devices(backend, Device[]) === nothing
            else
                down = read_from_devices(backend, Device[]).event
                up = read_from_devices(backend, Device[]).event
                @test down isa MouseDown && down.button === name
                @test up isa MouseUp && up.button === name
            end
        end
        # A turn of the wheel away from the user scrolls up: a positive `dy`.
        _reset_input!(backend)
        _push_wheel!(1)
        scroll = read_from_devices(backend, Device[]).event
        @test scroll isa MouseScroll && scroll.dy > 0
        _reset_input!(backend)
    end

    @testset "a press holds the modifiers of its own place in the queue" begin
        # Ctrl goes down, the button goes down, and Ctrl goes up, all before the
        # poll. The press holds Ctrl, because Ctrl was down when it happened.
        _reset_input!(backend)
        _push_ctrl_key!(_SDL_KEYDOWN, _KMOD_LCTRL)
        _push_button_down!(10, 10)
        _push_ctrl_key!(_SDL_KEYUP, 0x0000)
        @test read_from_devices(backend, Device[]).event isa KeyDown
        down = read_from_devices(backend, Device[]).event
        @test down isa MouseDown
        @test down.modifiers.ctrl
        up = read_from_devices(backend, Device[]).event
        @test up isa KeyUp
        @test !up.modifiers.ctrl
        @test read_from_devices(backend, Device[]) === nothing
    end

    @testset "a press and a release keep the times that SDL stamps on them" begin
        # SDL stamps an event when it is pushed. The press is read at once, the
        # release is pushed 0.1 s later and read after a slow frame of 0.5 s: the
        # stamps are 0.1 s apart, inside the click window of a gesture tracker
        # (0.3 s), although the release was read 0.6 s after the press.
        _reset_input!(backend)
        _push_button_down!(10, 10)
        down = read_from_devices(backend, Device[])
        @test down.event isa MouseDown
        sleep(0.1)
        _push_button_up!(10, 10)
        sleep(0.5)
        # Read what waits, for a bounded number of reads: an idle motion that the
        # rate limit holds back can make a read answer nothing.
        release = nothing
        for _ in 1:20
            input = read_from_devices(backend, Device[])
            input === nothing && (sleep(0.01); continue)
            input.event isa MouseUp && (release = input.event; break)
        end
        @test release !== nothing
        @test release !== nothing &&
              0.05 < get_event_time(release) - get_event_time(down.event) < 0.3
        _reset_input!(backend)
    end

    @testset "the rate limit of one backend leaves another" begin
        # Each backend keeps the time of its own last idle motion, so a hover in
        # the windows of one editor does not hold the motion of another.
        other = SdlBackend()
        other.display.scale = 2.0
        _reset_input!(other)
        _push_motion!(12, 34)
        probe = read_from_devices(other, Device[])
        @test probe.event isa MouseMove
        # The rate limit applies to idle motion only; skip the case when a
        # button is held.
        if probe.event.buttons == MouseButtons()
            backend.last_hover_motion = time()   # the limit of `backend` is active
            other.last_hover_motion = 0.0        # the limit of `other` is not
            _push_motion!(60, 70)
            answered = read_from_devices(other, Device[])
            @test answered isa WindowInput
            @test (answered.event.x, answered.event.y) == (_logical(60), _logical(70))
        end
        _reset_input!(other)
        _reset_input!(backend)
    end

    @testset "a window that loses the focus says so, and one that gains it says nothing" begin
        _reset_input!(backend)
        _push_window_event!(_SDL.SDL_WINDOWEVENT_FOCUS_LOST)
        input = read_from_devices(backend, Device[])
        @test input isa WindowInput
        @test input.event isa WindowDefocus
        _reset_input!(backend)
        _push_window_event!(_SDL.SDL_WINDOWEVENT_FOCUS_GAINED)
        @test read_from_devices(backend, Device[]) === nothing
        _reset_input!(backend)
    end

    @testset "the pointer that leaves a window is a window event" begin
        _reset_input!(backend)
        _push_window_event!(_SDL.SDL_WINDOWEVENT_LEAVE)
        input = read_from_devices(backend, Device[])
        @test input isa WindowInput
        @test input.event isa WindowLeave
        _reset_input!(backend)
    end

end
end # test_input_coalescing
