# The appearance wrapper of `build_editor`. Its document holds the `Appearance`
# of the editor around the content. The keys of the zoom and of the scales answer
# when the content declines them, a change of the appearance prints the view once
# in its frame, and an answer that changes no appearance prints nothing again.

import ProjecturedKernelExample: HeadlessBackend, rendered_output, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display

_aw_measure = FixedMeasure(8, 12, 4, 0)

# A projection that answers one key under Ctrl with its own operation, as a view
# that binds the key does, and passes every other input to `inner`.
struct AwKeyProjection <: Projection
    inner::Projection
    key::Symbol
end
ProjecturedKernel.ProjectionModule.print_document(p::AwKeyProjection, recursion, input, ctx) =
    print_document(p.inner, recursion, input, ctx)
function ProjecturedKernel.ProjectionModule.read_intent(p::AwKeyProjection, recursion,
                                                         change::Intent, iomap)
    event = change.gesture
    event isa KeyDown && event.key === p.key && event.modifiers.ctrl &&
        return Intent(event, DoNothingOperation())
    read_intent(p.inner, recursion, change, iomap)
end

_aw_natural(appearance) = NaturalToGraphics(; measure = _aw_measure, appearance)
_aw_key(key; alt = false) = KeyDown(key, ModifierKeys(ctrl = true, alt = alt); time = 0.0)

# An editor on `document` with the appearance wrapper and no window and no tabs,
# after its first frame. With no `projection`, the editor makes the projection
# itself, through the seam of the build. The cycle of the focus is off, so the
# content is right inside the appearance: it reads a key through the projection
# of an IO map, and `AwKeyProjection` makes none of its own.
function _aw_editor(document; projection = nothing, appearance = true, tabs = false)
    backend = HeadlessBackend()
    keywords = (; backend, devices = Device[Keyboard(), Mouse(), Display()],
                window = false, tabs, appearance, settings = false, focus_cycling = false)
    editor = projection === nothing ? build_editor(document; keywords...) :
                                      build_editor(document, projection; keywords...)
    run_frame!(editor)
    (editor, backend)
end

_aw_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

# The canvas of the last frame that the backend drew.
_aw_last_output(backend) = last(rendered_output(backend))

_aw_font_size(backend, text) = first(_collect_text_styles(_aw_last_output(backend))[text])

_aw_display(editor) = only(d for d in editor.devices if d isa Display)

function test_appearance_wrapper()
@testset "the appearance wrapper" begin

@testset "the root holds the appearance around the content" begin
    appearance = Appearance()
    label = WidgetLabel("Name")
    editor, _ = _aw_editor(label; projection = _aw_natural(appearance), appearance)
    @test editor.document isa AppearanceDocument
    @test editor.document.appearance === appearance
    @test editor.document.content === label
    @test get_wrapped_document(editor.document) === label
end

@testset "each key steps its factor when the content declines it" begin
    appearance = Appearance()
    editor, backend = _aw_editor(WidgetLabel("Name"); projection = _aw_natural(appearance), appearance)
    _aw_press!(editor, backend, _aw_key(:equals))
    @test appearance.zoom == 1.1
    @test _aw_display(editor).zoom == 1.1            # the backends read it there
    _aw_press!(editor, backend, _aw_key(:zero))
    @test appearance.zoom == 1.0 && _aw_display(editor).zoom == 1.0
    _aw_press!(editor, backend, _aw_key(:minus))
    @test appearance.zoom == 0.9
    for (key, scale, factor) in ((:equals, :font_scale, 1.1), (:period, :icon_scale, 1.1),
                                 (:right_bracket, :spacing_scale, 1.1), (:minus, :font_scale, 1.0),
                                 (:comma, :icon_scale, 1.0), (:left_bracket, :spacing_scale, 1.0))
        _aw_press!(editor, backend, _aw_key(key; alt = true))
        @test getproperty(appearance, scale) == factor
    end
    _aw_press!(editor, backend, _aw_key(:equals; alt = true), )
    _aw_press!(editor, backend, _aw_key(:zero; alt = true))
    @test appearance.font_scale == 1.0
    @test appearance.zoom == 0.9                     # a scale leaves the zoom
end

@testset "a key that the content binds stays with the content" begin
    appearance = Appearance()
    projection = AwKeyProjection(_aw_natural(appearance), :equals)
    editor, backend = _aw_editor(WidgetLabel("Name"); projection, appearance)
    printed = editor.iomap
    _aw_press!(editor, backend, _aw_key(:equals))
    @test appearance.zoom == 1.0
    @test editor.iomap === printed                   # an answer of the content prints nothing again
end

@testset "a change of a scale prints the view once, and the next input waits" begin
    appearance = Appearance()
    editor, backend = _aw_editor(WidgetLabel("Name"); projection = _aw_natural(appearance), appearance)
    printed = editor.iomap
    @test _aw_font_size(backend, "Name") == 13
    _aw_press!(editor, backend, _aw_key(:equals; alt = true), _aw_key(:equals; alt = true))
    @test appearance.font_scale == 1.1               # the second key waits for the new view
    @test editor.iomap !== printed
    @test _aw_font_size(backend, "Name") == 14
    run_frame!(editor)
    @test appearance.font_scale == 1.25
    @test _aw_font_size(backend, "Name") == 16
end

@testset "a write into the appearance or into one of its themes prints the view again" begin
    appearance = Appearance()
    scaled = get_scaled_theme!(appearance, WidgetTheme)
    document = AppearanceDocument(appearance, WidgetLabel("Name"))
    theme = get_base_theme(scaled)
    write(object) = ReplaceReferencedValueOperation(object, ConcreteReference(FieldReferenceStep("zoom"), EmptyReference()), 1)
    @test is_appearance_change(appearance, write(appearance))
    @test is_appearance_change(appearance, write(theme))
    @test is_appearance_change(appearance, CompoundOperation(Any[DoNothingOperation(), write(theme)]))
    @test !is_appearance_change(appearance, write(document.content))
    @test !is_appearance_change(appearance, DoNothingOperation())
    @test !is_appearance_change(Appearance(), AdjustZoomOperation(appearance, 1))
end

@testset "the keys are listed with the keys of the content" begin
    appearance = Appearance()
    editor, _ = _aw_editor(WidgetLabel("Name"); projection = _aw_natural(appearance), appearance)
    answer = read_intent(editor.projection, nothing, Intent(CollectIntents()), editor.iomap)
    collected = answer isa Intent ? answer.operation : answer
    @test collected isa CollectedIntentsOperation
    labels = Set(intent.description for intent in collected.intents)
    @test "Zoom in" in labels && "Make the text larger" in labels && "Make the spacing smaller" in labels
end

@testset "two editors keep two appearances" begin
    one, two = Appearance(), Appearance()
    first_editor, first_backend = _aw_editor(WidgetLabel("Name"); projection = _aw_natural(one),
                                             appearance = one)
    second_editor, second_backend = _aw_editor(WidgetLabel("Name"); projection = _aw_natural(two),
                                               appearance = two)
    _aw_press!(first_editor, first_backend, _aw_key(:equals; alt = true))
    run_frame!(second_editor)
    @test one.font_scale == 1.1 && two.font_scale == 1.0
    @test _aw_font_size(first_backend, "Name") == 14
    @test _aw_font_size(second_backend, "Name") == 13
end

@testset "with no projection named, the editor's renderer takes the editor's appearance" begin
    editor, backend = _aw_editor(WidgetLabel("Name"))
    appearance = editor.document.appearance
    @test _aw_font_size(backend, "Name") == 13
    _aw_press!(editor, backend, _aw_key(:equals; alt = true))
    @test appearance.font_scale == 1.1
    @test _aw_font_size(backend, "Name") == 14
end

@testset "the tab strip of the tabs wrapper follows the appearance of the editor" begin
    editor, backend = _aw_editor(WidgetLabel("Name"); tabs = (; title = "Tab"))
    @test get_wrapped_document(editor.document) isa PaneTree
    @test _aw_font_size(backend, "Tab") == 13
    _aw_press!(editor, backend, _aw_key(:equals; alt = true))
    @test _aw_font_size(backend, "Tab") == 14
    @test _aw_font_size(backend, "Name") == 14
end

@testset "a change while the editor runs draws as an editor that starts with it" begin
    running, running_backend = _aw_editor(WidgetButton("Save"))
    _aw_press!(running, running_backend, _aw_key(:equals; alt = true))
    _aw_press!(running, running_backend, _aw_key(:right_bracket; alt = true))
    started, started_backend = _aw_editor(WidgetButton("Save");
                                          appearance = Appearance(font_scale = 1.1, spacing_scale = 1.1))
    @test _collect_text_styles(_aw_last_output(running_backend)) ==
          _collect_text_styles(_aw_last_output(started_backend))
    running_output, started_output = _aw_last_output(running_backend), _aw_last_output(started_backend)
    @test (Int(running_output.w[]), Int(running_output.h[])) == (Int(started_output.w[]), Int(started_output.h[]))
end


@testset "each window takes the colour of the role background, and follows the mode" begin
    backend = HeadlessBackend()
    appearance = Appearance()
    editor = build_editor(WidgetLabel("Name"); backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "T", width = 400, height = 300), tabs = false,
                          appearance)
    run_frame!(editor)
    background(a) = (c = resolve_theme_color(ColorRole(:background), a);
                     Tuple(UInt8(round(Int, x * 255)) for x in (c.red, c.green, c.blue, c.alpha)))
    window() = only(last(rendered_output(backend)).windows)
    @test window().bg == background(appearance)
    appearance.color_mode = :dark
    run_frame!(editor)
    @test window().bg == background(appearance)
    @test window().bg != background(Appearance())
    # A window that opens later takes the background of the screen, and follows it.
    evaluate_operation(editor, OpenWindowOperation(; id = :later, title = "Later", width = 200,
                                                     height = 100, content = WidgetLabel("Later")))
    run_frame!(editor)
    later() = only(w for w in last(rendered_output(backend)).windows if w.id === :later)
    @test later().bg == background(appearance)
    appearance.color_mode = :light
    run_frame!(editor)
    @test later().bg == background(appearance)
end

end
end
