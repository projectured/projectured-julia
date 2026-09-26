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

@testset "a window the reconciler opens is painted before it is shown" begin
    SDL = ProjecturedSdl

    backend = SdlBackend()
    initialize_backend!(backend)

    # A window the reconciler opens is made hidden. A window shown before it is
    # painted holds an undefined back buffer, and the compositor draws that
    # black.
    for style in (:default, :tooltip, :floating, :popup)
        held = WindowDocument(; id = :held_window_test, title = "held_window_test",
                                x = 100, y = 100, width = 200, height = 100,
                                style = style, content = "content")
        resource = SDL._open_native_window!(backend, held; hidden = true)
        @test !SDL._is_native_window_shown(resource)
        # Painted, then shown. The paint that follows asks for the whole window,
        # because a driver is free to drop a present made while it is hidden.
        SDL._show_painted_window!(backend, resource, held)
        @test SDL._is_native_window_shown(resource)
        @test resource.first_paint
        SDL._close_native_window!(resource)
    end

    canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    window = WindowDocument(; id = :painted_window_test, title = "painted_window_test",
                              x = 100, y = 100, width = 200, height = 100,
                              style = :tooltip, content = canvas)
    screen = ScreenDocument([window])

    # One pass of the reconciler opens the window, paints it and shows it.
    write_to_devices(backend, Device[Display()], screen)
    resource = backend.windows[:painted_window_test]
    @test SDL._is_native_window_shown(resource)

    quit_backend!(backend)

end

@testset "each backend repaints with its own switches" begin
    # Two backends in one process: one repaints the whole window at each frame,
    # the other only what changed. A frame in which nothing changed adds a damage
    # record to the first and none to the second.
    full = SdlBackend(partial_render = false, debug_dirty = false)
    partial = SdlBackend(partial_render = true, debug_dirty = false)
    initialize_backend!(full)
    initialize_backend!(partial)
    for (backend, grows) in ((full, 1), (partial, 0))
        id = Symbol("repaint_test_", backend.partial_render)
        canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
        window = WindowDocument(; id = id, title = String(id), x = 100, y = 100,
                                  width = 200, height = 100, style = :tooltip,
                                  content = canvas)
        screen = ScreenDocument([window])
        write_to_devices(backend, Device[Display()], screen)   # opens, paints, shows
        write_to_devices(backend, Device[Display()], screen)   # the paint after the show
        resource = backend.windows[id]
        before = length(resource.damage_history)
        write_to_devices(backend, Device[Display()], screen)   # nothing changed
        @test length(resource.damage_history) == before + grows
    end
    quit_backend!(partial)
    quit_backend!(full)
end

@testset "a window with a maximum fits what it printed" begin
    SDL = ProjecturedSdl
    fit(canvas_width, canvas_height; minimum_size, maximum_size) = begin
        window = WindowDocument(; id = :fit_test, title = "fit_test", x = 0, y = 0,
                                  width = maximum_size[1], height = maximum_size[2],
                                  minimum_size = minimum_size, maximum_size = maximum_size,
                                  content = "content")
        canvas = GraphicsCanvas(CellVector(Any[]), layout_none)
        canvas.w = Int32(canvas_width)
        canvas.h = Int32(canvas_height)
        SDL._fit_window_size!(window, canvas)
        (window.width, window.height)
    end

    # What the content needed, between the two bounds.
    @test fit(150, 40; minimum_size = (120, 32), maximum_size = (560, 400)) == (150, 40)
    # A content larger than the maximum is cut to it; a smaller one takes the minimum.
    @test fit(900, 900; minimum_size = (120, 32), maximum_size = (560, 400)) == (560, 400)
    @test fit(10, 5; minimum_size = (120, 32), maximum_size = (560, 400)) == (120, 32)
    # A window with no maximum keeps the size it was asked for.
    fixed = WindowDocument(; id = :fixed_test, title = "fixed_test", x = 0, y = 0,
                             width = 420, height = 120, content = "content")
    canvas = GraphicsCanvas(CellVector(Any[]), layout_none)
    canvas.w = Int32(150)
    canvas.h = Int32(40)
    SDL._fit_window_size!(fixed, canvas)
    @test (fixed.width, fixed.height) == (420, 120)
end

@testset "such a window stays on the screen, and beside the pointer" begin
    place = ProjecturedSdl.compute_window_place
    area = (area_width = 1000, area_height = 800)

    # Inside the work area, wherever it was asked for.
    @test place(100, 100, 200, 80; area..., pointer = nothing) == (100, 100)
    # Over the right or the bottom edge: moved in.
    @test place(900, 100, 200, 80; area..., pointer = nothing) == (800, 100)
    @test place(100, 780, 200, 80; area..., pointer = nothing) == (100, 720)
    # A window that would hold the pointer goes to the left of it, and to the
    # right when there is no room on the left.
    @test place(900, 100, 200, 80; area..., pointer = (850, 120)) == (642, 100)
    @test place(0, 100, 200, 80; area..., pointer = (40, 120)) == (48, 100)
end

@testset "a tooltip goes beside the pointer, and a popup stays under it" begin
    # The pointer goes into a popup to choose, so only a tooltip moves away from
    # it. The test reads the real pointer and never moves it.
    SDL = ProjecturedSdl
    backend = SdlBackend()
    initialize_backend!(backend)
    (px, py) = get_pointer_position(backend)
    (area_width, area_height) = get_display_size(backend)
    x, y = clamp(px - 20, 0, area_width - 200), clamp(py - 20, 0, area_height - 100)
    held(style) = WindowDocument(; id = :place_test, title = "place_test", x = x, y = y,
                                   width = 200, height = 100, maximum_size = (200, 100),
                                   style = style, content = "content")
    if x <= px < x + 200 && y <= py < y + 100
        popup = SDL._place_fitted_window!(backend, held(:popup))
        @test (popup.x, popup.y) == (x, y)
        tooltip = SDL._place_fitted_window!(backend, held(:tooltip))
        @test !(tooltip.x <= px < tooltip.x + 200)
    end
    quit_backend!(backend)
end

@testset "a window takes the place that the window manager gives it" begin
    # A window manager can put a window elsewhere than asked, and a person can move
    # it. The document takes that place, so a popup opens at the window; a place
    # the document asks for itself still moves the window.
    LibSDL2 = ProjecturedSdl.SimpleDirectMediaLayer.LibSDL2
    backend = SdlBackend()
    initialize_backend!(backend)
    canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    window = WindowDocument(; id = :moved_window_test, title = "moved_window_test",
                              x = 100, y = 100, width = 200, height = 100, content = canvas)
    screen = ScreenDocument([window])
    write_to_devices(backend, Device[Display()], screen)
    resource = backend.windows[:moved_window_test]
    placed() = (x = Ref{Cint}(0); y = Ref{Cint}(0);
                LibSDL2.SDL_GetWindowPosition(resource.win, x, y); (Int(x[]), Int(y[])))
    # The window manager moves it.
    LibSDL2.SDL_SetWindowPosition(resource.win, Int32(300), Int32(200))
    moved = placed()
    write_to_devices(backend, Device[Display()], screen)
    @test (window.x, window.y) == moved
    # The document asks for a place of its own, and the window goes there.
    window.x = moved[1] + 50
    write_to_devices(backend, Device[Display()], screen)
    @test placed()[1] == window.x
    quit_backend!(backend)
end
end # test_native_window
