# widget_popup example end-to-end (Stage 3, Step 6). The window-route projection
# (WindowManager + WidgetPopupResolver + ScreenToScreen) turns a trigger's
# `OpenPopupOperation` into a real popup window: ScreenToScreen forward-maps the
# trigger's screen-rooted anchor to absolute screen coordinates (shifting by each
# window's origin), the resolver adds the trigger-baked offset and emits an
# `OpenWindowOperation`, and WindowManager opens the window. Driven exactly like the
# HoverProbe pipeline test (an `EventEnvelope` routed in grows the screen's window
# list).

using ProjecturedKernel.EventModule: EventEnvelope
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
    select = WidgetSelect(Point2D(0, 0), "Apple";
                          options=["Apple", "Banana", "Cherry"], width=200)
    main   = WindowDocument(; id=:default, title="main", x=50, y=40,
                            width=320, height=220,
                            content=VerticalLayout(Any[select]; horizontal_align=:left))
    screen = ScreenDocument([main])
    proj   = make_widget_popup_projection_example()
    iomap  = print_document(proj, screen)

    nbefore = length(screen.windows)
    # A left press at (15, 12) lands on the select (top-left of the window content).
    env = EventEnvelope(:default, MousePress(:left, 15, 12, ModifierKeys()))
    read_intent(proj, nothing, Intent(env, nothing), iomap)

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
        @test popup.content isa VerticalLayout      # the option list
    end
end

end # @testset
end # function
