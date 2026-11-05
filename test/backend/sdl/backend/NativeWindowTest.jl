function test_native_window()
@testset "native windows opened before the first projection" begin

    # Xlib finds its locale data, so SDL can give a window its title. SDL keeps
    # its own copy of the title, so asking SDL for it proves nothing; the folder
    # that the package set is what X11 needs.
    @test isfile(joinpath(ENV["XLOCALEDIR"], "locale.dir"))

    backend = SdlBackend()
    initialize_backend!(backend)
    devices = Device[Display(), Keyboard(), Mouse()]

    # The whole work area is what `run_example` asks for when it is given no
    # size, and it is the size a window manager is most likely to refuse: a
    # decorated window needs room for its title bar inside the same area.
    width, height = get_display_size(backend)
    window = WindowDocument(; id = :native_window_test, title = "native_window_test",
                              x = 100, y = 100, width = width, height = height,
                              content = PrimitiveString("content"))
    screen = ScreenDocument([window])

    @test open_native_windows!(backend, screen) === nothing

    # The window is open and registered under its own id, so the reconciler
    # updates it instead of opening a second one.
    resource = backend.windows[:native_window_test]
    @test backend.window_ids[resource.sdl_id] === :native_window_test

    # The document carries the size the window really has, whether the manager
    # granted what it was asked for or less.
    granted = ProjecturedSDL.SdlModule._native_window_size(resource)
    @test (window.width, window.height) == granted
    @test (resource.width, resource.height) == granted

    # A resize the document already knows about must not reach the editor: that
    # event is what made the whole document compute a second time.
    resizes = 0
    deadline = time() + 0.5
    while time() < deadline
        input = take_from_devices!(backend, devices)
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
    SDL = ProjecturedSDL.SdlModule

    backend = SdlBackend()
    initialize_backend!(backend)

    # A window the reconciler opens is made hidden. A window shown before it is
    # painted holds an undefined back buffer, and the compositor draws that
    # black.
    for style in (:default, :tooltip, :floating, :popup)
        held = WindowDocument(; id = :held_window_test, title = "held_window_test",
                                x = 100, y = 100, width = 200, height = 100,
                                style = style, content = PrimitiveString("content"))
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
    write_to_devices!(backend, Device[Display()], screen)
    resource = backend.windows[:painted_window_test]
    @test SDL._is_native_window_shown(resource)

    quit_backend!(backend)

end

@testset "an unchanged window repaints after exposure or focus returns" begin
    SDL = ProjecturedSDL.SdlModule
    backend = SdlBackend()
    initialize_backend!(backend)
    canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    resources = Any[]
    try
        for id in (:exposed_window_test, :other_window_test)
            window = WindowDocument(; id, title = string(id), width = 200, height = 100, content = canvas)
            resource = SDL._open_native_window!(backend, window; hidden = true)
            push!(resources, resource)
            backend.windows[id] = resource
            backend.window_ids[resource.sdl_id] = id
            @test SDL._render_window!(backend, resource, canvas)
            @test !SDL._render_window!(backend, resource, canvas)
        end
        resource, other = resources
        for kind in (SDL.SDL_WINDOWEVENT_EXPOSED, SDL.SDL_WINDOWEVENT_FOCUS_GAINED,
                     SDL.SDL_WINDOWEVENT_SHOWN, SDL.SDL_WINDOWEVENT_RESTORED,
                     SDL.SDL_WINDOWEVENT_MAXIMIZED)
            _push_sdl_event!(_SDL.SDL_WindowEvent(UInt32(_SDL.SDL_WINDOWEVENT), UInt32(0), resource.sdl_id,
                UInt8(kind), UInt8(0), UInt8(0), UInt8(0), Int32(0), Int32(0)))
            while SDL._poll_window_input(backend) != (nothing, nothing)
            end
            @test resource.first_paint
            @test !other.first_paint
            @test SDL._render_window!(backend, resource, canvas)
            @test !SDL._render_window!(backend, resource, canvas)
        end
        # A late event for a closed window changes no live window.
        SDL._request_window_repaint!(backend, :closed_window_test)
        @test !resource.first_paint && !other.first_paint
    finally
        quit_backend!(backend)
    end
end

@testset "a tooltip or a popup window never takes the key focus" begin
    SDL = ProjecturedSDL.SdlModule

    # A tooltip and a popup refuse the key focus: their keys come through the
    # window under them.
    @test !SDL._can_take_key_focus(:tooltip)
    @test !SDL._can_take_key_focus(:popup)
    @test all(SDL._can_take_key_focus, (:default, :floating))

    backend = SdlBackend()
    initialize_backend!(backend)
    tooltip = WindowDocument(; id = :key_focus_test, title = "key_focus_test",
                               x = 100, y = 100, width = 200, height = 100,
                               style = :tooltip, content = PrimitiveString("content"))
    resource = SDL._open_native_window!(backend, tooltip; hidden = true)

    # The backend reads the window struct of SDL by offset. On X11 the subsystem
    # is X11, and the first handle, the `Display`, is set.
    found = SDL._find_native_window_handle(resource.win)
    if unsafe_string(SDL.SDL_GetCurrentVideoDriver()) == "x11"
        @test found !== nothing
        @test found.subsystem == SDL._SDL_SYSWM_X11
        @test found.handle != C_NULL
    end

    # Only a window of Cocoa gets the mark, and only there does the backend answer
    # the questions of AppKit. The tooltip shows as before.
    @test SDL._refuse_key_focus!(resource.win) === nothing
    @test isempty(SDL._REPLACED_KEY_WINDOW_METHODS) == !Sys.isapple()
    SDL._show_painted_window!(backend, resource, tooltip)
    @test SDL._is_native_window_shown(resource)
    SDL._close_native_window!(resource)

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
        write_to_devices!(backend, Device[Display()], screen)   # opens, paints, shows
        write_to_devices!(backend, Device[Display()], screen)   # the paint after the show
        resource = backend.windows[id]
        before = length(resource.damage_history)
        write_to_devices!(backend, Device[Display()], screen)   # nothing changed
        @test length(resource.damage_history) == before + grows
    end
    quit_backend!(partial)
    quit_backend!(full)
end

@testset "the render settings switch the repaint of a backend that runs" begin
    # A backend that starts with the full repaint gets the partial repaint from
    # its settings, and then repaints as a backend that starts with it: a frame
    # in which nothing changed adds no damage record. A change of the mode or of
    # the outline repaints the whole window at the next frame.
    backend = SdlBackend(partial_render = false, debug_dirty = false)
    @test is_settings_target(backend, RenderSettings())
    initialize_backend!(backend)
    canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    window = WindowDocument(; id = :render_settings_test, title = "render_settings_test",
                              x = 100, y = 100, width = 200, height = 100,
                              style = :tooltip, content = canvas)
    screen = ScreenDocument([window])
    write_to_devices!(backend, Device[Display()], screen)   # opens, paints, shows
    write_to_devices!(backend, Device[Display()], screen)   # the paint after the show
    resource = backend.windows[:render_settings_test]
    apply_settings!(backend, RenderSettings(partial_render = true))
    @test backend.partial_render && !backend.debug_dirty
    @test resource.first_paint
    write_to_devices!(backend, Device[Display()], screen)   # the whole window once
    @test first(resource.damage_history) == [(0, 0, 200, 100)]
    before = length(resource.damage_history)
    write_to_devices!(backend, Device[Display()], screen)   # nothing changed
    @test length(resource.damage_history) == before
    # The outline goes off: the next frame paints over the last outline.
    apply_settings!(backend, RenderSettings(partial_render = true, debug_dirty = true))
    write_to_devices!(backend, Device[Display()], screen)
    apply_settings!(backend, RenderSettings(partial_render = true, debug_dirty = false))
    @test resource.first_paint
    # The same values again ask for no repaint.
    write_to_devices!(backend, Device[Display()], screen)
    apply_settings!(backend, RenderSettings(partial_render = true))
    @test !resource.first_paint
    # A new supersample factor makes the target of the window again.
    width = resource.target_w
    apply_settings!(backend, RenderSettings(partial_render = true, supersample = 1))
    @test backend.supersample == 1 && resource.ss == 1
    write_to_devices!(backend, Device[Display()], screen)
    @test resource.target_w * 2 == width
    @test first(resource.damage_history) == [(0, 0, 200, 100)]
    quit_backend!(backend)
end

@testset "a read copies the render values of a backend into its settings" begin
    backend = SdlBackend(partial_render = true, debug_dirty = true, debug_dirty_hold = 1.5,
                         supersample = 3)
    settings = RenderSettings()
    read_settings!(settings, backend)
    @test (settings.partial_render, settings.debug_dirty, settings.debug_dirty_hold,
           settings.supersample) == (true, true, 1.5, 3)
    @test (SdlBackend().partial_render, SdlBackend().supersample) == (true, 2)
end

@testset "an outline stays for its hold on the frames after it" begin
    backend = SdlBackend(partial_render = true, debug_dirty = true)
    initialize_backend!(backend)
    x = Cell(10)
    canvas = GraphicsCanvas(CellVector(@computation [GraphicsRect(x[], 10, 20, 20)]),
                            layout_none)
    window = WindowDocument(; id = :outline_hold_test, title = "outline_hold_test",
                              x = 100, y = 100, width = 200, height = 100,
                              style = :tooltip, content = canvas)
    screen = ScreenDocument([window])
    write_to_devices!(backend, Device[Display()], screen)
    write_to_devices!(backend, Device[Display()], screen)
    resource = backend.windows[:outline_hold_test]
    # With no hold, the outline is the rects of the frame.
    @test ProjecturedSDL.SdlModule._get_held_outline!(backend, resource, [(1, 2, 3, 4)]) ==
          [(1, 2, 3, 4)]
    apply_settings!(backend, RenderSettings(partial_render = true, debug_dirty = true,
                                            debug_dirty_hold = 5.0))
    @test backend.debug_dirty_hold == 5.0
    for position in (40, 120)
        x[] = position
        write_to_devices!(backend, Device[Display()], screen)
    end
    held = ProjecturedSDL.SdlModule._get_held_outline!(backend, resource, NTuple{4,Int}[])
    # The rects of both moves are still held.
    @test !isempty(resource.damage_history[1]) && !isempty(resource.damage_history[2])
    @test all(rect -> rect in held, resource.damage_history[1])
    @test all(rect -> rect in held, resource.damage_history[2])
    quit_backend!(backend)
end

@testset "a backend reports each frame that changed, and no other" begin
    # A `DisplayUpdate` runs the loop again after a frame that changed. So a
    # frame that shows something new is reported, and one that shows nothing new
    # is not, or the loop would never sleep. Both modes report the same, because
    # the walk runs in both.
    backends = [SdlBackend(partial_render = partial, debug_dirty = false)
                for partial in (false, true)]
    for backend in backends
        initialize_backend!(backend)
        devices = Device[Display()]
        id = Symbol("display_update_test_", backend.partial_render)
        x = Cell(10)
        canvas = GraphicsCanvas(CellVector(@computation [GraphicsRect(x[], 10, 60, 20)]),
                                layout_none)
        window = WindowDocument(; id = id, title = String(id), x = 100, y = 100,
                                  width = 200, height = 100, style = :tooltip,
                                  content = canvas)
        screen = ScreenDocument([window])
        write_to_devices!(backend, devices, screen)   # opens, paints, shows
        write_to_devices!(backend, devices, screen)   # the paint after the show
        # One update for the window, however many changed frames it showed.
        @test length(backend.display_updates) == 1
        # An update that waits ends a wait at once.
        started = time()
        wait_for_input(backend, devices, 5.0)
        @test time() - started < 1.0
        input = take_from_devices!(backend, devices)
        @test input isa WindowInput && input.window_id === id &&
              input.event isa DisplayUpdate
        @test isempty(backend.display_updates)
        write_to_devices!(backend, devices, screen)   # nothing changed
        @test isempty(backend.display_updates)
        x[] = 50
        backend.pending_motion = nothing
        write_to_devices!(backend, devices, screen)   # the rectangle moved
        @test length(backend.display_updates) == 1
        # A move at the point of the pointer follows the frame, in the window
        # under the pointer, and none when the pointer is on no window of the
        # backend. The pointer of the display is where the person left it.
        pointed = ProjecturedSDL.SdlModule._find_pointer_window(backend)
        motion = backend.pending_motion
        @test pointed === nothing ? motion === nothing :
              motion.window_id === pointed && motion.event isa MouseMove
    end
    foreach(quit_backend!, reverse(backends))
end

@testset "a window with a maximum fits what it printed" begin
    SDL = ProjecturedSDL.SdlModule
    fit(canvas_width, canvas_height; minimum_size, maximum_size) = begin
        window = WindowDocument(; id = :fit_test, title = "fit_test", x = 0, y = 0,
                                  width = maximum_size[1], height = maximum_size[2],
                                  minimum_size = minimum_size, maximum_size = maximum_size,
                                  content = PrimitiveString("content"))
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
                             width = 420, height = 120, content = PrimitiveString("content"))
    canvas = GraphicsCanvas(CellVector(Any[]), layout_none)
    canvas.w = Int32(150)
    canvas.h = Int32(40)
    SDL._fit_window_size!(fixed, canvas)
    @test (fixed.width, fixed.height) == (420, 120)
end

@testset "a window on a monitor above, left of or right of the main one keeps its place" begin
    SDL = ProjecturedSDL.SdlModule
    # Only the place (-1, -1) lets the backend choose; SDL centers that window and
    # gets every other place as it is, negative too.
    window(x, y) = WindowDocument(; id = :place_test, title = "place_test", x = x, y = y,
                                    width = 200, height = 100, content = PrimitiveString("content"))
    @test is_automatic_window_place(window(-1, -1))
    @test !is_automatic_window_place(window(885, -950))
    @test !is_automatic_window_place(window(-1, 100))
    @test SDL._get_native_window_place(window(-1, -1), 1.0) ==
          (SDL.SDL_WINDOWPOS_CENTERED, SDL.SDL_WINDOWPOS_CENTERED)
    @test SDL._get_native_window_place(window(885, -950), 1.0) == (Int32(885), Int32(-950))
    @test SDL._get_native_window_place(window(-1, 100), 2.0) == (Int32(-2), Int32(200))
end

@testset "a window takes the place that the window manager gives it" begin
    # A window manager can put a window elsewhere than asked, and a person can move
    # it. The document takes that place, so a popup opens at the window; a place
    # the document asks for itself still moves the window. The place of the document
    # is in logical pixels and the place of SDL in window units, which are device
    # pixels on X11, at each zoom.
    LibSDL2 = ProjecturedSDL.SdlModule.SimpleDirectMediaLayer.LibSDL2
    for zoom in (1.0, 2.0)
        backend = SdlBackend()
        initialize_backend!(backend)
        backend.display.zoom = zoom
        ratio = get_device_pixel_ratio(backend.display)
        canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
        window = WindowDocument(; id = :moved_window_test, title = "moved_window_test",
                                  x = 100, y = 100, width = 200, height = 100, content = canvas)
        screen = ScreenDocument([window])
        write_to_devices!(backend, Device[Display()], screen)
        resource = backend.windows[:moved_window_test]
        placed() = (x = Ref{Cint}(0); y = Ref{Cint}(0);
                    LibSDL2.SDL_GetWindowPosition(resource.win, x, y); (Int(x[]), Int(y[])))
        # The window manager moves it.
        LibSDL2.SDL_SetWindowPosition(resource.win, Int32(600), Int32(400))
        moved = placed()
        write_to_devices!(backend, Device[Display()], screen)
        @test (window.x, window.y) == (round(Int, moved[1] / ratio), round(Int, moved[2] / ratio))
        # The document asks for a place of its own, and the window goes there.
        window.x = window.x + 50
        write_to_devices!(backend, Device[Display()], screen)
        @test placed()[1] == round(Int, window.x * ratio)
        quit_backend!(backend)
    end
end

@testset "a frame writes the areas of the displays into the screen" begin
    # A placement reads the areas in the coordinates of the place of a window, the
    # logical pixels of the zoom.
    SDL = ProjecturedSDL.SdlModule
    backend = SdlBackend()
    initialize_backend!(backend)
    canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    screen = ScreenDocument([WindowDocument(; id = :areas_test, title = "areas_test", x = 100, y = 100,
                                              width = 200, height = 100, content = canvas)])
    write_to_devices!(backend, Device[Display()], screen)
    areas = screen.display_areas
    @test !isempty(areas)
    @test areas == SDL._get_zoomed_display_areas(backend)
    backend.display.zoom = 2.0
    write_to_devices!(backend, Device[Display()], screen)
    @test screen.display_areas == [Tuple(round(Int, value / 2) for value in area) for area in areas]
    quit_backend!(backend)
end

@testset "a person moves a placed window with a frame, and it stays there" begin
    # The place of a placed window is a computation of the screen, so the backend
    # gives a window with a frame a fixed placement at the place that the window
    # manager reports. A popup has no frame and keeps its placement.
    LibSDL2 = ProjecturedSDL.SdlModule.SimpleDirectMediaLayer.LibSDL2
    projection = RecursiveProjection(TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        Any            => IdentityProjection()))
    backend = SdlBackend()
    initialize_backend!(backend)
    ratio = get_device_pixel_ratio(backend.display)
    canvas() = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    screen = ScreenDocument([
        WindowDocument(; id = :placed_dialog_test, title = "placed_dialog_test", style = :dialog,
                         width = 200, height = 100, placement = context -> WindowPlace(100, 100),
                         content = canvas()),
        WindowDocument(; id = :placed_popup_test, title = "placed_popup_test", style = :popup,
                         width = 200, height = 100, placement = context -> WindowPlace(400, 100),
                         content = canvas())])
    output = print_document(projection, screen).output
    write_to_devices!(backend, Device[Display()], output)
    placed(id) = (x = Ref{Cint}(0); y = Ref{Cint}(0);
                  LibSDL2.SDL_GetWindowPosition(backend.windows[id].win, x, y); (Int(x[]), Int(y[])))
    LibSDL2.SDL_SetWindowPosition(backend.windows[:placed_dialog_test].win, Int32(600), Int32(400))
    moved = placed(:placed_dialog_test)
    write_to_devices!(backend, Device[Display()], output)
    dialog = output.windows[1]
    @test is_window_placed(dialog)
    @test (dialog.x, dialog.y) == (round(Int, moved[1] / ratio), round(Int, moved[2] / ratio))
    write_to_devices!(backend, Device[Display()], output)
    @test placed(:placed_dialog_test) == moved
    # A new zoom keeps the window where it is on the device, as it keeps a window
    # with no placement: the fixed placement takes the coordinates of the new zoom.
    before = (dialog.x, dialog.y)
    backend.display.zoom = 2.0
    write_to_devices!(backend, Device[Display()], output)
    @test dialog.placement isa FixedPlacement
    @test (dialog.x, dialog.y) == (round(Int, before[1] / 2), round(Int, before[2] / 2))
    @test placed(:placed_dialog_test) == moved
    backend.display.zoom = 1.0
    write_to_devices!(backend, Device[Display()], output)
    LibSDL2.SDL_SetWindowPosition(backend.windows[:placed_popup_test].win, Int32(700), Int32(500))
    write_to_devices!(backend, Device[Display()], output)
    popup = output.windows[2]
    @test (popup.x, popup.y) == (400, 100)
    @test placed(:placed_popup_test) == (round(Int, 400 * ratio), round(Int, 100 * ratio))
    quit_backend!(backend)
end

@testset "a place that SDL gives back rounded is no move of a person" begin
    # Below the zoom 1 a window unit is larger than a logical pixel, so the place
    # that the backend sends comes back rounded. It is the place of the backend: a
    # placed dialog keeps its placement, and a popup is not moved again.
    projection = RecursiveProjection(TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        Any            => IdentityProjection()))
    backend = SdlBackend()
    initialize_backend!(backend)
    backend.display.zoom = 0.8
    canvas() = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
    screen = ScreenDocument([
        WindowDocument(; id = :rounded_dialog_test, title = "rounded_dialog_test", style = :dialog,
                         width = 200, height = 100, placement = context -> WindowPlace(103, 101),
                         content = canvas()),
        WindowDocument(; id = :rounded_popup_test, title = "rounded_popup_test", style = :popup,
                         width = 200, height = 100, placement = context -> WindowPlace(203, 101),
                         content = canvas())])
    output = print_document(projection, screen).output
    for _ in 1:3
        write_to_devices!(backend, Device[Display()], output)
    end
    dialog = output.windows[1]
    @test !(dialog.placement isa FixedPlacement)
    @test (dialog.x, dialog.y) == (103, 101)
    popup = backend.windows[:rounded_popup_test]
    @test (popup.x, popup.y) == (203, 101)
    quit_backend!(backend)
end

@testset "a window whose units are points converts with the window unit ratio" begin
    # On macOS SDL counts a window in points, and a Retina screen has two device
    # pixels in each point. A window on X11 measures one pixel in each unit, so the
    # test gives it two, as a window on a Retina screen measures, at the density 2
    # that such a window finds. A logical pixel is then one window unit. With one
    # pixel in each unit, as on X11 at a density of 2, it is two window units.
    SDL = ProjecturedSDL.SdlModule
    LibSDL2 = SDL.SimpleDirectMediaLayer.LibSDL2
    for (pixels_per_window_unit, unit_ratio) in ((2.0, 1.0), (1.0, 2.0))
        backend = SdlBackend()
        initialize_backend!(backend)
        canvas = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]), layout_none)
        window = WindowDocument(; id = :unit_window_test, title = "unit_window_test",
                                  x = 100, y = 100, width = 160, height = 80, content = canvas)
        screen = ScreenDocument([window])
        write_to_devices!(backend, Device[Display()], screen)
        resource = backend.windows[:unit_window_test]
        resource.pixels_per_window_unit = pixels_per_window_unit
        backend.display.density = 2.0
        @test SDL._get_window_unit_ratio(backend, :unit_window_test) == unit_ratio
        # A new size of the document reaches SDL in window units, and the size of
        # SDL reads back as the size of the document.
        window.width, window.height = 200, 100
        write_to_devices!(backend, Device[Display()], screen)
        width, height = Ref{Cint}(0), Ref{Cint}(0)
        LibSDL2.SDL_GetWindowSize(resource.win, width, height)
        @test (Int(width[]), Int(height[])) ==
              (round(Int, 200 * unit_ratio), round(Int, 100 * unit_ratio))
        @test SDL._native_window_size(resource) == (200, 100)
        # A press at a place in window units arrives at that place over the ratio.
        _push_sdl_event!(_SDL.SDL_MouseButtonEvent(_SDL_MOUSEBUTTONDOWN, UInt32(0),
                                                   resource.sdl_id, UInt32(0),
                                                   _SDL_BUTTON_LEFT, UInt8(1), UInt8(1),
                                                   UInt8(0), Int32(120), Int32(40)))
        pressed = nothing
        for _ in 1:50
            input = take_from_devices!(backend, Device[])
            input === nothing && break
            input isa Tuple && (input = input[1])
            input isa WindowInput && input.event isa MouseDown && (pressed = input.event)
        end
        @test pressed isa MouseDown
        pressed isa MouseDown &&
            @test (pressed.x, pressed.y) == (round(Int, 120 / unit_ratio), round(Int, 40 / unit_ratio))
        quit_backend!(backend)
    end
end

@testset "a window made in the units of another screen takes its size in its own" begin
    # A new window is made in the units of the last window. Here the last window
    # was on a Retina screen, with two pixels in each unit, and the new window on
    # X11 measures one, so at the density 2 it takes its size again: 200 logical
    # pixels are 200 units in the units of the last window and 400 in its own.
    SDL = ProjecturedSDL.SdlModule
    LibSDL2 = SDL.SimpleDirectMediaLayer.LibSDL2
    # The work area that the backend reads first is in the units of that window.
    SDL._LAST_PIXELS_PER_WINDOW_UNIT[] = 2.0
    backend = SdlBackend()
    initialize_backend!(backend)
    backend.display.density = 2.0
    window = WindowDocument(; id = :other_units_test, title = "other_units_test",
                              x = 100, y = 100, width = 200, height = 100,
                              content = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]),
                                                       layout_none))
    write_to_devices!(backend, Device[Display()], ScreenDocument([window]))
    resource = backend.windows[:other_units_test]
    @test SDL._LAST_PIXELS_PER_WINDOW_UNIT[] == resource.pixels_per_window_unit
    unit_ratio = SDL._get_window_unit_ratio(resource, 2.0)
    width, height = Ref{Cint}(0), Ref{Cint}(0)
    LibSDL2.SDL_GetWindowSize(resource.win, width, height)
    @test (Int(width[]), Int(height[])) == (round(Int, 200 * unit_ratio), round(Int, 100 * unit_ratio))
    @test SDL._native_window_size(resource) == (200, 100)
    # The work area follows the units of the new window.
    @test (backend.display.width, backend.display.height) == SDL.get_sdl_display_size()
    quit_backend!(backend)
end

@testset "a start of SDL video that repeats leaves every window open" begin
    # SDL counts the starts of video in one byte, and the start after 256 of them
    # quits video, which destroys every window and sends no event.
    SDL = ProjecturedSDL.SdlModule
    LibSDL2 = SDL.SimpleDirectMediaLayer.LibSDL2
    backend = SdlBackend()
    initialize_backend!(backend)
    held = WindowDocument(; id = :start_test, title = "start_test", x = 100, y = 100,
                            width = 200, height = 100, content = PrimitiveString("content"))
    resource = SDL._open_native_window!(backend, held; hidden = true)
    @test all(_ -> SDL._start_sdl_video!(), 1:300)
    @test LibSDL2.SDL_GetWindowFlags(resource.win) != 0
    SDL._close_native_window!(resource)
    quit_backend!(backend)
end

@testset "the frames of an open popup leave the window under it open" begin
    # The pointer over an open menu makes a frame at each move, and each frame
    # places the popup in the work area.
    SDL = ProjecturedSDL.SdlModule
    LibSDL2 = SDL.SimpleDirectMediaLayer.LibSDL2
    backend = SdlBackend(partial_render = true, debug_dirty = false)
    initialize_backend!(backend)
    main = WindowDocument(; id = :main_test, title = "main_test", x = 100, y = 100,
                            width = 300, height = 200,
                            content = GraphicsCanvas(CellVector(Any[GraphicsRect(10, 10, 60, 20)]),
                                                     layout_none))
    popup = WindowDocument(; id = :popup_test, title = "popup_test", x = 120, y = 130,
                             width = 200, height = 100, maximum_size = (200, 100),
                             style = :popup, auto_dismiss = true,
                             content = GraphicsCanvas(CellVector(Any[GraphicsRect(5, 5, 40, 10)]),
                                                      layout_none))
    screen = ScreenDocument([main, popup])
    for _ in 1:300
        write_to_devices!(backend, Device[Display()], screen)
    end
    @test LibSDL2.SDL_GetWindowFlags(backend.windows[:main_test].win) != 0
    quit_backend!(backend)
end

@testset "a frame gives the placements the size that the display holds" begin
    # A frame asks SDL and `xrandr` nothing. The backend reads the size when it
    # starts and again at a display event.
    SDL = ProjecturedSDL.SdlModule
    backend = SdlBackend()
    initialize_backend!(backend)
    @test (backend.display.width, backend.display.height) == SDL.get_sdl_display_size()
    backend.display.width, backend.display.height = 400, 300
    @test SDL._get_zoomed_display_areas(backend) == [(0, 0, 400, 300)]
    # The size of the display is at the zoom 1, and a window is placed in the
    # logical pixels of the zoom: at twice the zoom the area is 200 by 150.
    backend.display.zoom = 2.0
    @test SDL._get_zoomed_display_areas(backend) == [(0, 0, 200, 150)]
    backend.display.zoom = 1.0
    _push_sdl_event!(_SDL.SDL_DisplayEvent(UInt32(_SDL.SDL_DISPLAYEVENT), UInt32(0), UInt32(0),
                                           UInt8(_SDL.SDL_DISPLAYEVENT_CONNECTED),
                                           0x00, 0x00, 0x00, Int32(0)))
    for _ in 1:100
        take_from_devices!(backend, Device[Display()]) === nothing && break
    end
    @test (backend.display.width, backend.display.height) == SDL.get_sdl_display_size()
    quit_backend!(backend)
end
end # test_native_window
