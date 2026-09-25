# The fold that stacks a window's wrappers, and the popup a widget in a window
# opens.
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

# The recorder is always outermost, so what a keyword added is one step in. A
# gesture log a person opens in a tab shows the session's own log, which must
# already hold what happened before the tab existed.
_under_recorder(projection) = begin
    @test projection isa GestureLogRecordingProjection
    projection.inner
end

@testset "every wrapper is off, so only the recorder and the hover tracker are added" begin
    document, base = _document(), IdentityProjection()
    answer_document, answer_projection =
        make_window_wrap(; gesture_help = false, command_palette = false,
                           selection = false)(document, base)
    @test answer_document === document
    # A window that shows a button must light it, so the tracker takes no keyword.
    tracker = _under_recorder(answer_projection)
    @test tracker isa WidgetHoverTrackingProjection
    @test tracker.inner === base
end

@testset "a keyword adds the wrapper it names" begin
    document, base = _document(), IdentityProjection()
    wrap(; keywords...) = make_window_wrap(; gesture_help = false, command_palette = false,
                                             selection = false,
                                             keywords...)(document, base)

    @test _under_recorder(wrap(; gesture_help = true)[2]) isa GestureHelpDecoratorProjection
    @test _under_recorder(wrap(; command_palette = true)[2]) isa CommandPaletteDecoratorProjection
    # The history is a wrapper the host gives, and the default changes nothing.
    marked = wrap(; history = projection -> GestureHelpDecoratorProjection(
                      inner = projection, state = GestureHelpState()))[2]
    @test _under_recorder(marked).inner isa GestureHelpDecoratorProjection
    # The clipboard is the one wrapper that wraps the document as well.
    @test wrap(; selection = true)[1] isa ClipboardSlice
end

@testset "the palette sits outside the help" begin
    document, base = _document(), IdentityProjection()
    _, projection = make_window_wrap(; gesture_help = true, command_palette = true,
                                       selection = false)(document, base)
    palette = _under_recorder(projection)
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
    output = print_document(projection, scene).output
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
end

@testset "a select drops down as a window below the select" begin
    # The window manager is what consumes an `OpenWindowOperation`, so the proof
    # is the window that appears, not the operation that comes back. A reader
    # that answers `nothing` here has done the work.
    select = WidgetSelect("Apple"; options = ["Apple", "Banana"], width = 180)
    scene = make_window_scene(select, "shell"; width = 400, height = 300)
    content = make_layout_projection_example()
    projection = make_window_scene_projection(content)
    iomap = print_document(projection, scene)
    press = Intent(WindowInput(:shell, MousePress(:left, 5, 5, ModifierKeys(); time = 0.0)))
    change = read_intent(projection, nothing, press, iomap)
    @test (change isa Intent ? change.operation : change) === nothing
    @test length(scene.windows) == 2
    window, popup = scene.windows[1], scene.windows[2]
    @test popup.content isa VerticalLayout
    @test popup.style === :popup
    # Just below the select, which sits at the origin of the window's content, in
    # screen coordinates. The window offers the select its height, so the
    # select's height is the one the scene printed.
    height = _wrap_iomap_of(iomap, select).control_height
    @test (popup.x, popup.y) == (window.x, window.y + height + 4)
end

end # @testset
end # function
