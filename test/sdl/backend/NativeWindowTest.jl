function test_native_window()
@testset "native windows opened before the first projection" begin

    backend = SdlBackend()
    initialize_backend!(backend)
    devices = Device[Display(), Keyboard(), Mouse()]

    # The whole work area is what `run_example` asks for when it is given no
    # size, and it is the size a window manager is most likely to refuse: a
    # decorated window needs room for its title bar inside the same area.
    width, height = get_display_size(backend)
    window = WindowDocument(; id = :native_window_test, title = "native_window_test",
                              x = 100, y = 100, width = width, height = height,
                              content = "content")
    screen = ScreenDocument([window])

    @test open_native_windows!(backend, screen) === nothing

    # The window is open and registered under its own id, so the reconciler
    # updates it instead of opening a second one.
    resource = backend.windows[:native_window_test]
    @test backend.window_ids[resource.sdl_id] === :native_window_test

    # The document carries the size the window really has, whether the manager
    # granted what it was asked for or less.
    granted = ProjecturedSdl._native_window_size(resource)
    @test (window.width, window.height) == granted
    @test (resource.width, resource.height) == granted

    # A resize the document already knows about must not reach the editor: that
    # event is what made the whole document compute a second time.
    resizes = 0
    deadline = time() + 0.5
    while time() < deadline
        input = read_from_devices(backend, devices)
        input isa Tuple && (input = input[1])
        input isa WindowInput && input.event isa WindowResize && (resizes += 1)
        sleep(0.005)
    end
    @test resizes == 0

    # A second call opens nothing: the window is already there.
    open_native_windows!(backend, screen)
    @test length(backend.windows) == 1

    quit_backend!(backend)

end
end # test_native_window
