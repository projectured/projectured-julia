# `read_from_devices` collapses a run of pointer motion into its newest sample.
# The events are pushed onto the real SDL queue, so what is tested is the path
# the editor actually runs, not a stand-in for it.

# The SDL bindings, reached through the backend package: this test package
# depends on `ProjecturedSdl`, not on SDL itself.
const _SDL = ProjecturedSdl.SimpleDirectMediaLayer.LibSDL2

const _SDL_MOUSEMOTION     = 0x00000400
const _SDL_MOUSEBUTTONDOWN = 0x00000401
const _SDL_MOUSEBUTTONUP   = 0x00000402
const _SDL_BUTTON_LEFT     = 0x01

# Write one event of type `T` into an `SDL_Event` blob and push it on the queue.
function _push_sdl_event!(payload::T) where {T}
    event = Ref{_SDL.SDL_Event}()
    GC.@preserve event begin
        base = Base.unsafe_convert(Ptr{_SDL.SDL_Event}, event)
        unsafe_store!(convert(Ptr{T}, base), payload)
        _SDL.SDL_PushEvent(event)
    end
end

_push_motion!(x, y) =
    _push_sdl_event!(_SDL.SDL_MouseMotionEvent(_SDL_MOUSEMOTION, UInt32(0), UInt32(0),
                                               UInt32(0), UInt32(0),
                                               Int32(x), Int32(y), Int32(0), Int32(0)))

_push_button_down!(x, y) =
    _push_sdl_event!(_SDL.SDL_MouseButtonEvent(_SDL_MOUSEBUTTONDOWN, UInt32(0), UInt32(0),
                                               UInt32(0), _SDL_BUTTON_LEFT, UInt8(1),
                                               UInt8(1), UInt8(0), Int32(x), Int32(y)))

_push_button_up!(x, y) =
    _push_sdl_event!(_SDL.SDL_MouseButtonEvent(_SDL_MOUSEBUTTONUP, UInt32(0), UInt32(0),
                                               UInt32(0), _SDL_BUTTON_LEFT, UInt8(0),
                                               UInt8(1), UInt8(0), Int32(x), Int32(y)))

# Start from an empty queue and an expired rate limit, so each case sees only
# what it pushed.
function _reset_input!(backend)
    _SDL.SDL_PumpEvents()
    _SDL.SDL_FlushEvents(UInt32(0), typemax(UInt32))
    backend.last_hover_motion = 0.0
end

# The `Display` of the backend below has the scale 2, so an event holds the half of
# the device coordinates that SDL reports.
_logical(v) = ProjecturedSdl._to_logical(Int(v), 2.0)

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

    @testset "a click keeps the times that SDL stamps on its events" begin
        # SDL stamps an event when it is pushed. The press is read at once, the
        # release is pushed 0.1 s later and read after a slow frame of 0.5 s:
        # the stamps are 0.1 s apart, so the recognizer makes a click.
        _reset_input!(backend)
        recognizer = GestureRecognizer()
        source = () -> read_from_devices(backend, Device[])
        _push_button_down!(10, 10)
        down = pop_gesture!(recognizer, source)
        @test down.event isa MouseDown
        sleep(0.1)
        _push_button_up!(10, 10)
        sleep(0.5)
        # Read what waits, for a bounded number of reads: an idle motion that the
        # rate limit holds back can make a read answer nothing.
        gestures = Any[]
        for _ in 1:20
            gesture = pop_gesture!(recognizer, source)
            gesture === nothing ? sleep(0.01) : push!(gestures, gesture.event)
            any(event -> event isa MousePress, gestures) && break
        end
        release = findfirst(event -> event isa MouseUp, gestures)
        press = findfirst(event -> event isa MousePress, gestures)
        @test release !== nothing
        @test press !== nothing && gestures[press].count == 1
        # The events are 0.1 s apart, although the release was read 0.6 s later.
        @test release !== nothing &&
              0.05 < get_event_time(gestures[release]) - get_event_time(down.event) < 0.3
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

end
end # test_input_coalescing
