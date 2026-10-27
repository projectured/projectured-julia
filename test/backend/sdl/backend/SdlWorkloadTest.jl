# The inputs of a workload go through the event queue of SDL: each comes out of
# `take_from_devices!` as the event that went in, the focus events stay out of the
# queue while a workload runs, and the gestures of the window run on SDL.

# An event with its time left out, to compare an event that went in with the one
# that came out.
_get_workload_event_fields(event) =
    (typeof(event), Tuple(getfield(event, name) for name in fieldnames(typeof(event)) if name !== :time))

# The inputs that the backend gives until it has none.
function _take_workload_inputs!(backend)
    taken = WindowInput[]
    while (input = take_from_devices!(backend, Device[])) !== nothing
        push!(taken, input)
    end
    taken
end

"""
    test_sdl_workload()

The inputs of a workload come out of SDL as the events that went in, the focus
events of SDL stay out of the queue while a workload runs, and the gestures of
the window of the platform each find their target on SDL.
"""
function test_sdl_workload()
    sdl = ProjecturedSDL.SdlModule.SimpleDirectMediaLayer.LibSDL2
    @testset "the workload on SDL" begin
        @testset "an input comes out of SDL as the event that went in" begin
            backend = SdlBackend()
            backend.window_ids[UInt32(7)] = :W
            _take_workload_inputs!(backend)
            none, ctrl = ModifierKeys(), ModifierKeys(ctrl = true)
            events = Any[MouseMove(30, 40; time = 0.0), MouseDown(:right, 30, 40; time = 0.0),
                         MouseUp(:right, 30, 40; time = 0.0),
                         KeyDown(:s, ctrl; time = 0.0), KeyUp(:s, ctrl; time = 0.0),
                         KeyDown(:a, none; time = 0.0), KeyPress('a', "a", none; time = 0.0),
                         KeyUp(:a, none; time = 0.0),
                         KeyDown(:f1, none; time = 0.0), KeyUp(:f1, none; time = 0.0),
                         KeyDown(:return, none; time = 0.0), KeyPress('\n', "\n", none; time = 0.0),
                         KeyUp(:return, none; time = 0.0)]
            try
                send_workload_inputs!(backend, WindowInput[WindowInput(:W, event) for event in events])
                @test has_workload_inputs(backend)
                taken = _take_workload_inputs!(backend)
                @test all(input -> input.window_id === :W, taken)
                @test map(input -> _get_workload_event_fields(input.event), taken) ==
                      map(_get_workload_event_fields, events)
                @test !has_workload_inputs(backend)
            finally
                sdl.SDL_SetEventFilter(C_NULL, C_NULL)
            end
        end

        @testset "a workload keeps the focus events out of the queue" begin
            backend = SdlBackend()
            backend.window_ids[UInt32(7)] = :W
            focus = Ref{sdl.SDL_Event}()
            GC.@preserve focus begin
                pointer = Base.unsafe_convert(Ptr{sdl.SDL_Event}, focus)
                Libc.memset(pointer, 0, sizeof(sdl.SDL_Event))
                unsafe_store!(Ptr{sdl.SDL_WindowEvent}(pointer),
                              sdl.SDL_WindowEvent(UInt32(sdl.SDL_WINDOWEVENT), UInt32(0), UInt32(7),
                                                  UInt8(sdl.SDL_WINDOWEVENT_FOCUS_LOST), 0x00, 0x00,
                                                  0x00, Int32(0), Int32(0)))
                try
                    send_workload_inputs!(backend, WindowInput[])
                    @test sdl.SDL_PushEvent(pointer) == 0
                finally
                    sdl.SDL_SetEventFilter(C_NULL, C_NULL)
                end
                @test sdl.SDL_PushEvent(pointer) == 1
            end
            _take_workload_inputs!(backend)
        end

        @testset "the gestures of the window each find their target" begin
            @test ProjecturedSDL.SdlModule.run_sdl_window_workload() === nothing
        end
    end
end
