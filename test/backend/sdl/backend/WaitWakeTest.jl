# The SDL wait and wake — the editor blocks on the real SDL queue between
# frames, and `wake_backend!` ends the block by pushing the registered wake
# event. The wait only looks at the queue: everything stays for `run_read_stage!`.

# Every name this file calls — the seam functions, the event types — arrives
# through the `using` lines of the test package.

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

    @testset "a short wait gives the tasks of this thread the whole wait" begin
        # A wait between the frames of an animation waits in Julia, so a task of
        # this thread runs again and again. A wait that blocked in SDL would give
        # it one turn for each slice of 10 ms.
        _drain_sdl_queue!()
        turns = Ref(0)
        is_counting = Ref(true)
        counter = @async while is_counting[]
            turns[] += 1
            yield()
        end
        wait_for_input(backend, Device[], 0.05)
        is_counting[] = false
        wait(counter)
        @test turns[] > 100
    end

    @testset "a queued event ends a short wait at once" begin
        _drain_sdl_queue!()
        backend.last_hover_motion = 0.0
        _push_motion!(5, 6)
        elapsed = @elapsed wait_for_input(backend, Device[], 0.09)
        @test elapsed < 0.05
        _drain_sdl_queue!()
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
        backend.last_hover_motion = 0.0
        _push_motion!(12, 34)
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        @test elapsed < _FAR_LESS
        answered = take_from_devices!(backend, Device[])
        @test answered isa WindowInput
        @test answered.event isa MouseMove   # the motion survived the wait
    end

    @testset "an owed event skips the wait" begin
        _drain_sdl_queue!()
        push!(backend.pending_inputs, WindowInput(:none, KeyDown(:a, ModifierKeys(); time = 0.0)))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        @test elapsed < _FAR_LESS
        empty!(backend.pending_inputs)
    end
end
end
