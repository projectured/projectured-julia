# The wrappers of `build_editor` that a window stacks, and the popup a widget in
# a window opens.
#
# A popup is a native window, so the operation that opens one reaches the window
# manager in screen coordinates. The widget answers a position in its own frame,
# each reader on the way up moves it, and the window adds its screen origin: a
# window needs no wrapper for it.

function test_window_wrap()
@testset "window wrap" begin

_document() = PrimitiveString("x")

# The IO map of `document` in the IO map tree of a print: the example projection
# is a chain, so the widget's own IO map sits inside the IO map of the print. The
# chain has the same input, so the deepest IO map of `document` is the one.
function _wrap_iomap_of(iomap, document, depth = 0)
    depth > 12 && return nothing
    for field in fieldnames(typeof(iomap))
        value = getfield(iomap, field)
        value = value isa CellModule.Cell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate = candidate isa CellModule.Cell ? candidate[] : candidate
            candidate isa Tuple && (candidate = last(candidate))
            candidate isa IoMap || continue
            found = _wrap_iomap_of(candidate, document, depth + 1)
            found === nothing || return found
        end
    end
    iomap.input === document ? iomap : nothing
end

# The document and the projection of a window with the wrappers of `keywords`,
# as `build_editor` stacks them, and no editor: the tabs and the appearance are
# off, and a test builds the window scene itself.
_wrap_window(document, projection; keywords...) =
    (parts = make_editor_parts(document, projection; tabs = false, appearance = false, keywords...);
     (parts.document, parts.projection))

# The wrappers that a window has in the application, but its chrome and its undo.
_WRAP_ALL = (; gesture_help = true, command_palette = true, clipboard = true, gesture_log = true)

@testset "with no keyword, only the start over of Tab is added" begin
    document, base = _document(), IdentityProjection()
    answer_document, answer_projection = _wrap_window(document, base)
    @test answer_document === document
    # Tab starts over at the ends of the window, on by default.
    @test answer_projection isa FocusCyclingProjection
    @test answer_projection.inner === base
    @test _wrap_window(document, base; focus_cycling = false)[2] === base
end

@testset "a keyword adds the wrapper it names, around the cycle of the focus" begin
    document, base = _document(), IdentityProjection()
    wrap(; keywords...) = _wrap_window(document, base; keywords...)
    for (keyword, type) in ((:gesture_help, GestureHelpDecoratorProjection),
                            (:command_palette, CommandPaletteDecoratorProjection),
                            (:gesture_log, GestureLogRecordingProjection))
        projection = wrap(; keyword => true)[2]
        @test projection isa type
        @test projection.inner isa FocusCyclingProjection
    end
    # The undo and the clipboard wrap the document as well.
    @test wrap(; undo = true)[1] isa UndoBuffer
    @test wrap(; clipboard = true)[1] isa ClipboardSlice
    # The gesture log is outermost, so it sees every operation of the window.
    @test wrap(; _WRAP_ALL...)[2] isa GestureLogRecordingProjection
end

@testset "a timer and a display update that no reader takes answer nothing" begin
    # The loop reads a timer as a bare event, because it belongs to no window, and
    # a display update in the input of its window. Every reader that does not take
    # them must let them pass.
    shell = WidgetShell(WidgetLabel("content"); size = Point2D(400, 300))
    document, projection = _wrap_window(shell, make_layout_projection_example(); _WRAP_ALL...)
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections())
    iomap = print_document(composed, scene)
    for input in (TimerExpire(:nobody, 0.0), WindowInput(:shell, DisplayUpdate(; time = 0.0)))
        change = read_intent(composed, nothing, Intent(input), iomap)
        @test (change isa Intent ? change.operation : change) === nothing
    end
end

@testset "a point of a window maps to the part drawn there, in a popup too" begin
    # The screen peels `windows[i].content`, and the window's own projection maps
    # the point in the window's frame, so every window maps its points alike.
    shell = WidgetShell(WidgetList(Any["a", "b", "c"]); size = Point2D(400, 300))
    document, projection = _wrap_window(shell, make_layout_projection_example(); gesture_log = true)
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    menu = WidgetMenu(Any[WidgetMenuItem("Alpha"), WidgetMenuItem("Beta"), WidgetMenuItem("Gamma")];
                      orientation = :vertical)
    push!(scene.windows, WindowDocument(; id = :widget_popup, title = "popup", x = 50, y = 50,
                                          width = 200, height = 150, style = :popup, content = menu))
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections(; gesture_help = false))
    iomap = print_document(composed, scene)
    window(i) = (FieldReferenceStep("windows"), RangeReferenceStep(i - 1, i), FieldReferenceStep("content"))
    function at(i, x, y)
        answer = map_reference_backward(composed, iomap,
            extend_reference(EmptyReference(), window(i)..., PointReferenceStep(x, y)))
        answer === nothing ? nothing : strip_reference_types(answer)
    end
    @test at(1, 5, 45) == extend_reference(EmptyReference(), window(1)..., FieldReferenceStep("content"),
                                           FieldReferenceStep("items"), RangeReferenceStep(1, 2))
    # Below the rows, the list itself is the part.
    @test at(1, 5, 280) == extend_reference(EmptyReference(), window(1)..., FieldReferenceStep("content"))
    @test at(2, 5, 30) == extend_reference(EmptyReference(), window(2)..., FieldReferenceStep("elements"),
                                           RangeReferenceStep(1, 2))
    @test at(2, 5, 140) === nothing
end

@testset "every window lights the part under the pointer, and its leave turns the light off" begin
    # One target for the whole screen: a popup lights its item as the first
    # window lights its row, and the light moves from one window to the other.
    list = WidgetList(Any["a", "b", "c"])
    shell = WidgetShell(list; size = Point2D(400, 300))
    document, projection = _wrap_window(shell, make_layout_projection_example(); gesture_log = true)
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    menu = WidgetMenu(Any[WidgetMenuItem("Alpha"), WidgetMenuItem("Beta"), WidgetMenuItem("Gamma")];
                      orientation = :vertical)
    push!(scene.windows, WindowDocument(; id = :widget_popup, title = "popup", x = 50, y = 50,
                                          width = 200, height = 150, style = :popup, content = menu))
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections(; gesture_help = false))
    tracked, tracking = make_tracking_screen(scene, composed)
    backend = HeadlessBackend()
    editor = Editor(tracked, tracking; backend = backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    move!(window, x, y, time) = (push_event!(backend, WindowInput(window, MouseMove(x, y; time))); run_frame!(editor))
    lit() = [item.action.label for item in menu.elements if get_mouse_target(item) !== nothing]
    lit_row() = WidgetModule._widget_element_selected(get_mouse_target(list), "items")

    move!(:widget_popup, 5, 30, 1.0)
    @test lit() == ["Beta"]
    move!(:widget_popup, 5, 10, 1.1)
    @test lit() == ["Alpha"]
    # Into the first window: the item goes off, and the row lights.
    move!(:shell, 5, 45, 1.2)
    @test isempty(lit()) && lit_row() == 2
    # The leave of the window of the pointer turns every light off (H3).
    push_event!(backend, WindowInput(:shell, WindowLeave(; time = 1.3)))
    run_frame!(editor)
    @test lit_row() == 0
    @test isempty(editor.timers)
end

@testset "the palette sits outside the help" begin
    document, base = _document(), IdentityProjection()
    _, palette = _wrap_window(document, base; gesture_help = true, command_palette = true)
    @test palette isa CommandPaletteDecoratorProjection
    @test palette.inner isa GestureHelpDecoratorProjection
end

@testset "the help window is drawn only when the help is on, and a popup always" begin
    types(rows) = [row.first for row in rows]
    @test first(types(make_opened_window_projections(; gesture_help = true))) === GestureMap
    @test !(GestureMap in types(make_opened_window_projections(; gesture_help = false)))
    # The rows of a host come before the rows of the widgets a popup holds.
    rows = types(make_opened_window_projections(; gesture_help = false,
                                                content = Pair{Type,Any}[PrimitiveString => IdentityProjection()]))
    @test first(rows) === PrimitiveString
    @test WidgetMenu in rows && VerticalLayout in rows
end

@testset "a popup window draws the widgets it holds, and the first window keeps its projection" begin
    # The first window holds a widget, and the rows of a popup name widgets too:
    # the place of the first window's content decides before its type.
    shell = WidgetShell(WidgetLabel("content"); size = Point2D(400, 300))
    scene = make_window_scene(shell, "shell"; width = 400, height = 300)
    marker = Ref(0)
    counting = ReferenceDispatchingProjection(reference -> (marker[] += 1; make_layout_projection_example()))
    projection = make_window_scene_projection(counting;
        opened_window_projections = make_opened_window_projections(; gesture_help = false))
    # The screen prints a window when its output is read.
    first_content = print_document(projection, scene).output.windows[1].content
    @test (first_content isa Cell ? first_content[] : first_content) isa GraphicsCanvas
    @test marker[] == 1
    # A popup window with a menu draws the names of its items.
    menu = WidgetMenu(Any[WidgetMenuItem("New tab"), WidgetMenuItem("Close tab")])
    push!(scene.windows, Cell(WindowDocument(; id = :widget_popup, x = 10, y = 20, width = 120,
                                              height = 60, style = :popup, content = menu)))
    shown = print_document(projection, scene)
    output = shown.output
    canvas = output.windows[2].content
    canvas = canvas isa Cell ? canvas[] : canvas
    @test canvas isa GraphicsCanvas
    value(x) = x isa Cell ? x[] : x
    placed = Tuple{String,Int}[]
    walk(node, oy) = begin
        node = value(node)
        if node isa GraphicsText
            push!(placed, (String(value(node.text)), oy + Int(value(node.y))))
        elseif node isa GraphicsCanvas
            foreach(element -> walk(element, oy + Int(value(node.y))), value(node.elements))
        end
    end
    walk(canvas, 0)
    @test first.(placed) == ["New tab", "Close tab"]
    # The window offers its height, and each item is as tall as its label and not
    # as the window, so both items are drawn inside the window, one below the other.
    @test placed[1][2] < placed[2][2] < 60 - 20
    # Both items are as wide as the wider one, also through the wrapper that the
    # screen puts around each of them, so the highlight of a row spans the menu.
    new_tab, close_tab = (_wrap_iomap_of(shown, item) for item in collect(menu.elements))
    @test Int(close_tab.natural_width) > Int(new_tab.natural_width)
    @test Int(new_tab.control_width) == Int(close_tab.control_width) == Int(close_tab.natural_width)
end

@testset "a select drops down as a window below the select" begin
    # The window manager is what consumes an `OpenWindowOperation`, so the proof
    # is the window that appears, not the operation that comes back. A reader
    # that answers `nothing` here has done the work.
    select = WidgetSelect("Apple"; options = ["Apple", "Banana"], width = 180)
    scene = make_window_scene(select, "shell"; width = 400, height = 300)
    content = make_layout_projection_example()
    projection = make_window_scene_projection(content;
        opened_window_projections = make_opened_window_projections(; gesture_help = false))
    iomap = print_document(projection, scene)
    press = Intent(WindowInput(:shell, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)))
    change = read_intent(projection, nothing, press, iomap)
    @test (change isa Intent ? change.operation : change) === nothing
    @test length(scene.windows) == 2
    window, popup = scene.windows[1], scene.windows[2]
    @test popup.content isa WidgetMenu
    @test popup.style === :popup
    # Just below the select, which sits at the origin of the window's content, in
    # screen coordinates. The window offers the select its height, so the
    # select's height is the one the scene printed.
    height = _wrap_iomap_of(iomap, select).control_height
    @test (popup.x, popup.y) == (window.x, window.y + height + 4)
    # The window takes the extent of what it draws, up to the bound of a popup. It
    # offers the dropdown that bound, and the dropdown draws its two options on
    # its surface, as wide as the select and no wider than the bound. The select
    # fills its window, so its height is the window's and not a row's.
    @test popup.maximum_size == (640, 800)
    drawn = print_document(projection, scene).output.windows[2].content
    drawn = drawn isa Cell ? drawn[] : drawn
    @test 180 <= Int(drawn.w) < 640
    @test 0 < Int(drawn.h) < 200
end

end # @testset
end # function
