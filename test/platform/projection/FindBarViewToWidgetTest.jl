# A find bar view through an editor: the bar draws above the text or over it, the
# keys of the view show and hide the bar and move the caret, a key in the field of
# the pattern highlights again, and undo takes a key back and keeps no step for
# the states of the bar.

function test_find_bar_view_to_widget()

_fb_font = StyleFont("Ubuntu Mono", 20)

# Three lines; the first has "Dolor", which matches only when case does not matter.
_fb_block() = TextBlock(TextString("alpha Dolor", _fb_font, color_default), TextNewline(font = _fb_font),
                        TextString("beta gamma", _fb_font, color_default), TextNewline(font = _fb_font),
                        TextString("delta dolor", _fb_font, color_default))

# The view of the gallery: a highlighted text under a collapsible card with a form
# of its pattern.
function _fb_view(; visible = true, case_insensitive = false)
    text = HighlightedText(; text = _fb_block(), pattern = "dolor", case_insensitive)
    bar = WidgetCard(; title = WidgetLabel("Find"), collapsible = true, visible,
                     content = FormLayout([(WidgetLabel("Find"), ObjectField(text, "pattern")),
                                           (WidgetLabel("Regular expression"), ObjectField(text, "regex")),
                                           (WidgetLabel("Ignore case"), ObjectField(text, "case_insensitive"))]))
    FindBarView(; bar, content = text)
end

function _fb_projection()
    measure = FontFileMeasure()
    w2g = WidgetToGraphics(_fb_font; measure)
    stage = RecursiveProjection(TypeDispatchingProjection(HighlightedText => HighlightedTextToText(),
                                                          TextBlock => IdentityProjection()))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection(),
                       FindBarView => ChainingProjection(FindBarViewToWidget(), VerticalLayoutToGraphicsCanvas()),
                       HighlightedText => ChainingProjection(stage, TextToGraphics(measure = measure))],
        LayoutToGraphics().dispatch,
        make_object_field_widget_dispatch(w2g.dispatch))))
end

function _fb_editor(document)
    backend = HeadlessBackend()
    editor = build_editor(document, _fb_projection();
        backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
        window = false, appearance = false, settings = false, tabs = false, focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

# The texts that the last frame draws, each with the point where it is drawn, in
# the order of drawing.
function _fb_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _fb_drawn(element, x, y, found)
        elseif element isa GraphicsViewport
            _fb_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                      y + Int(element.y) + round(Int, element.transform.f), found)
        end
    end
    found
end

_fb_frame(backend) = _fb_drawn(last(rendered_output(backend)))
_fb_texts(backend) = first.(_fb_frame(backend))
_fb_place(backend, text) = first((x, y) for (t, x, y) in _fb_frame(backend) if t == text)

function _fb_click!(editor, backend, text; dx = 2, dy = 2)
    (x, y) = _fb_place(backend, text)
    push_event!(backend, MouseClick(:left, x + dx, y + dy, 1, ModifierKeys(); time = 0.0))
    run_frame!(editor)
end

function _fb_key!(editor, backend, key; ctrl = false)
    push_event!(backend, KeyDown(key, ModifierKeys(ctrl = ctrl); time = 0.0))
    run_frame!(editor)
end

function _fb_type!(editor, backend, character::Char)
    push_event!(backend, KeyPress(character, string(character), ModifierKeys(); time = 0.0))
    run_frame!(editor)
end

_fb_selection(view) = strip_reference_types(get_selection(view))

_fb_path(steps...) = extend_reference(EmptyReference(), steps...)

# The caret at `k` in the field of the pattern, the second child of the form.
_fb_pattern_caret(k) = _fb_path(FieldReferenceStep("bar"), FieldReferenceStep("content"),
                                FieldReferenceStep("children"), RangeReferenceStep(1, 2),
                                FieldReferenceStep("object"), FieldReferenceStep("pattern"),
                                RangeReferenceStep(k, k))

_fb_tick = string(Char(0xe06c))
# The chevron of an expanded card. A glyph is drawn from its origin, and its box
# starts a few pixels inside it.
_fb_chevron = string(Char(0xe06d))
_fb_fold!(editor, backend) = _fb_click!(editor, backend, _fb_chevron; dx = 4, dy = 4)

@testset "the bar draws above the text, and over it at its top left corner" begin

    view = _fb_view()
    editor, backend = _fb_editor(view)
    (_, title_y) = _fb_place(backend, "Find")
    (_, text_y) = _fb_place(backend, "alpha Dolor")
    @test text_y > title_y
    @test "Over" in _fb_texts(backend)

    _fb_click!(editor, backend, "Over")
    @test view.overlaid
    @test "Above" in _fb_texts(backend)
    # The text is laid out as with no bar, and the bar draws after it, on top.
    texts = _fb_texts(backend)
    @test _fb_place(backend, "alpha Dolor")[2] == 0
    @test findfirst(==("Find"), texts) > findfirst(==("alpha Dolor"), texts)

    _fb_click!(editor, backend, "Above")
    @test !view.overlaid
    @test _fb_place(backend, "alpha Dolor")[2] == text_y

end # @testset

@testset "a press in the text puts a caret in the text" begin

    view = _fb_view()
    editor, backend = _fb_editor(view)
    _fb_click!(editor, backend, "beta gamma"; dx = 22)
    steps = get_reference_steps(_fb_selection(view))
    @test steps[1:2] == [FieldReferenceStep("content"), FieldReferenceStep("text")]
    @test steps[end] isa TextRangeReferenceStep

end # @testset

@testset "Ctrl+F shows the bar and puts the caret at the end of the pattern; Escape puts it back" begin

    view = _fb_view(; visible = false)
    editor, backend = _fb_editor(view)
    @test !("Find" in _fb_texts(backend))
    _fb_click!(editor, backend, "beta gamma"; dx = 22)
    in_text = _fb_selection(view)

    _fb_key!(editor, backend, :f; ctrl = true)
    @test view.bar.visible
    @test "Find" in _fb_texts(backend)
    @test _fb_selection(view) == _fb_pattern_caret(5)

    _fb_key!(editor, backend, :escape)
    @test !view.bar.visible
    @test !("Find" in _fb_texts(backend))
    @test _fb_selection(view) == in_text

    # The bar keeps its caret while it is hidden, and Ctrl+F puts it back.
    _fb_key!(editor, backend, :f; ctrl = true)
    @test _fb_selection(view) == _fb_pattern_caret(5)

end # @testset

@testset "typing in the pattern highlights again, and the caret stays in the field" begin

    view = _fb_view()
    editor, backend = _fb_editor(view)
    @test "dolor" in _fb_texts(backend)                  # the match of the third line
    @test "alpha Dolor" in _fb_texts(backend)            # case matters

    _fb_key!(editor, backend, :f; ctrl = true)
    _fb_type!(editor, backend, 'X')
    @test view.content.pattern == "dolorX"
    @test _fb_selection(view) == _fb_pattern_caret(6)
    @test "delta dolor" in _fb_texts(backend)            # no match: one span

    _fb_key!(editor, backend, :backspace)
    _fb_key!(editor, backend, :backspace)
    @test view.content.pattern == "dolo"
    @test _fb_selection(view) == _fb_pattern_caret(4)
    @test "dolo" in _fb_texts(backend)

end # @testset

@testset "a press on a checkbox of the bar changes the matches" begin

    view = _fb_view(; case_insensitive = true)
    editor, backend = _fb_editor(view)
    @test "Dolor" in _fb_texts(backend)                  # case does not matter

    _fb_click!(editor, backend, _fb_tick)
    @test !view.content.case_insensitive
    @test "alpha Dolor" in _fb_texts(backend)

end # @testset

@testset "a hide keeps the collapse and the placement, and Ctrl+F expands the bar" begin

    view = _fb_view()
    editor, backend = _fb_editor(view)
    _fb_click!(editor, backend, "beta gamma"; dx = 22)
    in_text = _fb_selection(view)
    _fb_key!(editor, backend, :f; ctrl = true)
    _fb_click!(editor, backend, "Over")
    _fb_fold!(editor, backend)
    @test view.bar.collapsed
    @test !("Regular expression" in _fb_texts(backend))

    _fb_key!(editor, backend, :escape)
    @test !view.bar.visible
    @test view.bar.collapsed
    @test view.overlaid
    @test _fb_selection(view) == in_text
    @test _fb_place(backend, "alpha Dolor")[2] == 0

    _fb_key!(editor, backend, :f; ctrl = true)
    @test view.bar.visible
    @test !view.bar.collapsed
    @test view.overlaid
    @test "Regular expression" in _fb_texts(backend)
    @test _fb_place(backend, "alpha Dolor")[2] == 0      # the text keeps its place
    @test _fb_selection(view) == _fb_pattern_caret(5)

end # @testset

@testset "Ctrl+Z takes a key in the pattern back, and the states of the bar make no step" begin

    view = _fb_view()
    editor, backend = _fb_editor(UndoBuffer(view))
    _fb_click!(editor, backend, "beta gamma"; dx = 22)
    _fb_key!(editor, backend, :f; ctrl = true)
    _fb_type!(editor, backend, 'X')
    _fb_click!(editor, backend, "Over")
    _fb_fold!(editor, backend)
    _fb_key!(editor, backend, :escape)
    @test view.content.pattern == "dolorX"
    @test view.bar.collapsed

    _fb_key!(editor, backend, :z; ctrl = true)
    @test view.content.pattern == "dolor"
    @test !view.bar.visible
    @test view.bar.collapsed
    @test view.overlaid

end # @testset

end # test_find_bar_view_to_widget
