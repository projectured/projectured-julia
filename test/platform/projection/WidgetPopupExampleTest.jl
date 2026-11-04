# widget_popup example end-to-end (Stage 3, Step 6). The window-route projection
# (WindowManager + ScreenToScreen) turns a trigger's `OpenPopupOperation` into a
# real popup window: each reader moves the popup's position into its own frame,
# ScreenToScreen adds the window's origin and emits an `OpenWindowOperation`, and
# WindowManager opens the window. Driven by routing a `WindowInput` through
# `read_intent`, which grows the screen's window list.

using ProjecturedKernel.EventModule: WindowInput
using ProjecturedKernel.IntentModule: Intent

function test_widget_popup_example()
@testset "widget_popup example (window route)" begin

# ── Static render: the example projects without error, keeping both windows ──
@testset "the screen example renders with its pre-opened popup" begin
    doc   = make_widget_popup_document_example()
    proj  = make_widget_popup_projection_example()
    iomap = print_document(proj, doc)
    @test iomap.output !== nothing
    ids = Symbol[w.id for w in doc.windows]
    @test :widget_popup_main in ids
    @test :widget_popup in ids        # the pre-opened floating popup
end

# ── End-to-end: clicking the select opens a real popup window at its position ──
@testset "clicking the select opens a popup window at the trigger's screen position" begin
    select = WidgetSelect("Apple";
                          options=["Apple", "Banana", "Cherry"], width=200)
    main   = WindowDocument(; id=:default, title="main", x=50, y=40,
                            width=320, height=220,
                            content=VerticalLayout(Any[select]; horizontal_align=:left))
    screen = ScreenDocument([main])
    proj   = make_widget_popup_projection_example()
    iomap  = print_document(proj, screen)

    nbefore = length(screen.windows)
    # A left press at (15, 12) lands on the select (top-left of the window content).
    window_input = WindowInput(:default, MouseClick(:left, 15, 12, ModifierKeys(); time = 0.0))
    read_intent(proj, nothing, Intent(window_input, nothing), iomap)

    @test length(screen.windows) == nbefore + 1
    popup = nothing
    for w in screen.windows
        w isa WindowDocument && w.id === :widget_popup && (popup = w)
    end
    @test popup !== nothing
    if popup !== nothing
        # The select sits at content (0, 0); the default window is at (50, 40), so the
        # popup opens directly below the select in screen space.
        @test popup.x == 50
        @test popup.y > 40
        @test popup.content isa WidgetMenu          # the option list
    end
end

# ── The list follows its window, and goes above the select with no room below ──
@testset "the list of a select stands below the select, follows its window, and goes above it with no room below" begin
    select = WidgetSelect("Apple"; options=["Apple", "Banana", "Cherry"], width=200,
                          position=Point2D(0, 150))
    main   = WindowDocument(; id=:default, title="main", x=50, y=40, width=320, height=220,
                            content=WidgetComposite(Any[select]))
    screen = ScreenDocument([main])
    proj   = make_widget_popup_projection_example()
    iomap  = print_document(proj, screen)
    read_intent(proj, nothing, Intent(WindowInput(:default, MouseClick(:left, 15, 160, ModifierKeys(); time = 0.0)),
                                      nothing), iomap)
    index = findfirst(w -> w isa WindowDocument && w.id === :widget_popup, collect(screen.windows))
    @test index !== nothing
    if index !== nothing
        popup = iomap.output.windows[index]
        @test is_window_placed(popup)
        below = (popup.x, popup.y)
        @test below[1] == 50
        @test below[2] > 40 + 150
        # The window moves, and the list moves with it.
        main.x = 80
        @test (popup.x, popup.y) == (80, below[2])
        # The backend fits the size, and the display has no room below the select:
        # the list goes above it.
        screen.windows[index].height = 60
        screen.display_areas = [(0, 0, 1000, below[2] + 30)]
        @test popup.y < below[2] - 60
    end
end

# ── The dialog of a button stands at the center of the window of the button ──
@testset "the dialog of a button stands at the center of its window" begin
    button = WidgetButton("Open"; size = Point2D(80, 0), dialog = WidgetMessageBox("Confirm", "Proceed?"))
    main   = WindowDocument(; id=:default, title="main", x=50, y=40, width=800, height=600,
                            content=WidgetComposite(Any[button]))
    screen = ScreenDocument([main])
    proj   = make_widget_popup_projection_example()
    iomap  = print_document(proj, screen)
    read_intent(proj, nothing, Intent(WindowInput(:default, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)),
                                      nothing), iomap)
    index = findfirst(w -> w isa WindowDocument && w.id === :widget_dialog, collect(screen.windows))
    @test index !== nothing
    if index !== nothing
        dialog = iomap.output.windows[index]
        @test is_window_placed(dialog)
        @test dialog.modal
        @test (dialog.x, dialog.y) == (50 + (800 - 480) ÷ 2, 40 + (600 - 320) ÷ 2)
    end
end

# ── A right click on a part with a menu answers the menu at its screen point ──
@testset "a right click on the target answers its menu at the screen point" begin
    menu   = WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy")])
    target = WidgetContextMenu(WidgetLabel("right-click for a context menu"), menu)
    main   = WindowDocument(; id=:default, title="main", x=50, y=40,
                            width=320, height=220,
                            content=VerticalLayout(Any[target]; horizontal_align=:left))
    screen = ScreenDocument([main])
    proj   = make_widget_popup_projection_example()
    iomap  = print_document(proj, screen)

    press = MouseClick(:right, 10, 8, ModifierKeys(); time = 0.0)
    window_input = WindowInput(:default, press)
    answer = read_intent(proj, nothing, Intent(window_input, nothing), iomap).operation
    # The window adds its origin to the point, as it does for a popup. The window
    # itself opens in the wrapper that keeps the context menu window, which this
    # screen does not have, so the screen holds one window.
    @test answer isa ReplaceViewStateOperation
    opened = get_wrapped_operation(answer)
    @test opened isa OpenContextMenuOperation
    @test only(opened.layers)[2] === menu
    @test opened.point == (50 + 10, 40 + 8)
    @test length(screen.windows) == 1
end

end # @testset
end # function
