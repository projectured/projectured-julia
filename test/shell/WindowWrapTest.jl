# The fold that stacks a window's wrappers, and the wrap that puts the popup
# resolver on the window route.
#
# The second half is the one that matters: a popup is a native window, so the
# operation that opens one carries screen coordinates. A window built without
# `make_popup_screen_wrap` draws every popup-offering widget and opens none of
# them, and nothing says so — the click is simply swallowed.

function test_window_wrap()
@testset "window wrap" begin

_document() = PrimitiveString("x")

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

@testset "the help window is drawn only when the help is on" begin
    @test length(make_opened_window_projections(; gesture_help = true)) == 1
    @test first(make_opened_window_projections(; gesture_help = true)).first === GestureMap
    @test isempty(make_opened_window_projections(; gesture_help = false))
end

@testset "a select drops down only when the screen wrap is there" begin
    # The window manager is what consumes an `OpenWindowOperation`, so the proof
    # is the window that appears, not the operation that comes back. A reader
    # that answers `nothing` here has done the work.
    make_scene() = make_window_scene(
        WidgetSelect(Point2D(0, 0), "Apple"; options = ["Apple", "Banana"], width = 180),
        "shell"; width = 400, height = 300)
    content = make_layout_projection_example()
    press = Intent(WindowInput(:shell, MousePress(:left, 5, 5, ModifierKeys())))
    answer(projection, scene) = begin
        iomap = print_document(projection, scene)
        change = read_intent(projection, nothing, press, iomap)
        change isa Intent ? change.operation : change
    end

    # What every window does today. The select answers an anchor-relative
    # `OpenPopupOperation`, it reaches the top of the window route with nothing
    # to resolve it, and no window opens. The dropdown never appears.
    bare = make_scene()
    operation = answer(make_window_scene_projection(content), bare)
    @test operation isa OpenPopupOperation
    @test length(bare.windows) == 1

    # With the wrap, the resolver turns the anchor into screen coordinates and
    # the manager opens the window, so the reader has nothing left to answer.
    wrapped = make_scene()
    @test answer(make_window_scene_projection(content;
                                              screen_wrap = make_popup_screen_wrap()),
                 wrapped) === nothing
    @test length(wrapped.windows) == 2
    @test last(wrapped.windows).content isa VerticalLayout
end

end # @testset
end # function
