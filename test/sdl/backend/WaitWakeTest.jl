# The SDL wait and wake — the editor blocks on the real SDL queue between
# frames, and `wake_backend!` ends the block by pushing the registered wake
# event. The wait only looks at the queue: everything stays for `read!`.

# Every name this file calls — the seam functions, the event types — arrives
# flat through `using Projectured` in the test package.

# Every timing assertion here is one-sided and generous: the machine may be
# loaded, so a bound says "far less than the full timeout", never "exactly
# this fast".
const _FAR_LESS = 5.0

function _drain_sdl_queue!()
    _SDL.SDL_PumpEvents()
    _SDL.SDL_FlushEvents(UInt32(0), typemax(UInt32))
end

function test_sdl_wait_wake()
@testset "the SDL wait and wake" begin
    backend = SdlBackend()
    initialize_backend!(backend)

    @testset "initialize registers the wake event" begin
        @test backend.wake_event_type != UInt32(0)
    end

    @testset "a wake on an uninitialized backend is a no-op" begin
        @test wake_backend!(SdlBackend()) === nothing
    end

    @testset "the wait times out when nothing happens" begin
        _drain_sdl_queue!()
        elapsed = @elapsed wait_for_input(backend, Device[], 0.05)
        @test elapsed >= 0.04
        @test elapsed < _FAR_LESS
    end

    @testset "a wake from another task ends a long wait" begin
        _drain_sdl_queue!()
        waker = @async (sleep(0.05); wake_backend!(backend))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        wait(waker)
        @test elapsed < _FAR_LESS
        _drain_sdl_queue!()               # the wake event stays queued; drop it
    end

    @testset "the wait looks at the queue and consumes nothing" begin
        _drain_sdl_queue!()
        ProjecturedSdl._LAST_HOVER_MOTION[] = 0.0
        _push_motion!(12, 34)
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        @test elapsed < _FAR_LESS
        answered = read_from_devices(backend, Device[])
        @test answered isa WindowInput
        @test answered.event isa MouseMove   # the motion survived the wait
    end

    @testset "an owed event skips the wait" begin
        _drain_sdl_queue!()
        backend.pending_input = WindowInput(:none, KeyDown(:a, ModifierKeys()))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        @test elapsed < _FAR_LESS
        backend.pending_input = nothing
    end
end
end
