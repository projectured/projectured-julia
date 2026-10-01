# The appearance tab: the natural renderer draws an `Appearance` as a row for the
# zoom and for each scale, a press of a button of a row answers the step of its
# factor, and in an editor the step prints the view again with the new value.

# Each text that a canvas tree draws, with its place in the frame of the root.
function _at_collect_texts(canvas)
    found = Tuple{String,Int,Int}[]
    function walk(c, ox, oy)
        x0 = ox + Int(c.x); y0 = oy + Int(c.y)
        for element in c.elements
            element = element isa Cell ? element[] : element
            if element isa GraphicsCanvas
                walk(element, x0, y0)
            elseif element isa GraphicsViewport
                walk(element.content, x0 + Int(element.x) + round(Int, element.transform.e),
                     y0 + Int(element.y) + round(Int, element.transform.f))
            elseif element isa GraphicsText
                push!(found, (String(element.text), x0 + Int(element.x), y0 + Int(element.y)))
            end
        end
    end
    walk(canvas, 0, 0)
    found
end

# The place of the text `button` in the row whose name is `row`: the button whose
# baseline is nearest to that of the name.
function _at_find_row_button(texts, row, button)
    _, _, row_y = only(t for t in texts if t[1] == row)
    _, x, y = argmin(t -> abs(t[3] - row_y), [t for t in texts if t[1] == button])
    (x + 2, y + 2)
end

# The first IO map of type `T` in the IO map tree under `iomap`, by its fields.
function _at_find_iomap(iomap, ::Type{T}; depth = 12) where {T}
    iomap isa T && return iomap
    depth == 0 && return nothing
    for name in fieldnames(typeof(iomap))
        value = getfield(iomap, name)
        value isa Cell && (value = value[])
        candidates = value isa AbstractVector ? value : (value,)
        for candidate in candidates
            candidate isa Cell && (candidate = candidate[])
            (candidate isa Document || candidate isa Projection || candidate === nothing ||
             candidate isa Number || candidate isa AbstractString) && continue
            found = _at_find_iomap(candidate, T; depth = depth - 1)
            found === nothing || return found
        end
    end
    nothing
end

_at_click(x, y, time) = (MouseDown(:left, x, y, ModifierKeys(); time),
                         MouseUp(:left, x, y, ModifierKeys(); time = time + 0.05))

function test_appearance_tab()
@testset "the appearance tab" begin

measure = FixedMeasure(8, 12, 4, 0)
offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())

@testset "an Appearance draws as a row for the zoom and for each scale" begin
    appearance = Appearance(font_scale = 1.25)
    output = print_document(NaturalToGraphics(; measure, appearance), nothing, appearance, offer).output
    texts = first.(_at_collect_texts(output))
    for name in ("Zoom", "Text", "Icons", "Spacing", "Controls", "Corners", "Lines", "Reset all")
        @test name in texts
    end
    @test "125%" in texts
    @test count(==("100%"), texts) == 6
end

@testset "a press of a button of a row answers the step of its factor" begin
    appearance = Appearance()
    projection = NaturalToGraphics(; measure, appearance)
    iomap = print_document(projection, nothing, appearance, offer)
    texts = _at_collect_texts(iomap.output)
    press(row, button) = begin
        x, y = _at_find_row_button(texts, row, button)
        answer = read_intent(projection, nothing,
                             Intent(MouseClick(:left, x, y, ModifierKeys(); time = 0.0), nothing), iomap)
        answer isa Intent ? answer.operation : answer
    end
    plus = press("Text", "+")
    @test plus isa AdjustScaleOperation && plus.scale === :font_scale && plus.delta == 1
    @test plus.appearance === appearance
    minus = press("Zoom", "−")
    @test minus isa AdjustZoomOperation && minus.delta == -1
    reset = press("Spacing", "Reset")
    @test reset isa AdjustScaleOperation && reset.scale === :spacing_scale && reset.delta == 0
end

@testset "a step of a size, a font or a preset answers a write of the theme" begin
    appearance = Appearance()
    projection = NaturalToGraphics(; measure, appearance)
    theme = get_theme(appearance, WidgetTheme)
    iomap = print_document(projection, nothing, appearance, offer)
    tab = _at_find_iomap(iomap, AppearanceToWidgetIoMap)
    @test tab !== nothing
    translate(operation) = ProjecturedPlatform.AppearanceModule._translate_tab_operation(tab, operation)
    unwrap(operation) = operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
    # The spin box of the gap between items: a step to 5 writes `Spacing(5)`.
    box = only(w for (w, _) in tab.writes if w isa WidgetSpinBox && w.value == 4 &&
               translate(ReplaceReferencedValueOperation(w, "value", 5)) |> unwrap |>
               (op -> op.reference.head == FieldReferenceStep("item_gap")))
    write = unwrap(translate(ReplaceReferencedValueOperation(box, "value", 5)))
    @test write.document === theme && write.value == Spacing(5)
    evaluate_operation(nothing, translate(ReplaceReferencedValueOperation(box, "value", 5)))
    @test get_scaled_theme!(appearance, WidgetTheme).item_gap == 5
    # The choice of the dark preset writes every field of the preset.
    choice = only(w for (w, _) in tab.writes if w isa WidgetRadioGroup)
    preset = translate(ReplaceReferencedValueOperation(choice, "selected", 2))
    @test preset isa CompoundOperation
    @test length(preset.operations) == length(get_theme_field_names(WidgetTheme))
    evaluate_operation(nothing, preset)
    @test is_color_equal(theme.background, make_slate_dark_theme().background)
    # The step of a font goes to the next font file, at the same size.
    font_step = only(op for (action, op) in tab.commands if action.label == "›" &&
                     unwrap(op).reference.head == FieldReferenceStep("font"))
    next_font = unwrap(font_step).value
    @test next_font.size == theme.font.size && next_font.filename != theme.font.filename
end

@testset "in an editor, Ctrl+, opens the tab, and a press prints the new value" begin
    backend = HeadlessBackend()
    editor = build_editor(WidgetLabel("Name"); backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "T", width = 900, height = 700), tabs = (; title = "Doc"))
    run_frame!(editor)
    appearance = find_editor_appearance(editor)
    push_event!(backend, WindowInput(:T, KeyDown(:comma, ModifierKeys(ctrl = true); time = 1.0)))
    run_frame!(editor)
    window = only(last(rendered_output(backend)).windows)
    texts = _at_collect_texts(window.content)
    @test "Text" in first.(texts) && "Appearance" in first.(texts)
    x, y = _at_find_row_button(texts, "Text", "+")
    for event in _at_click(x, y, 2.0)
        push_event!(backend, WindowInput(:T, event))
    end
    run_frame!(editor)
    run_frame!(editor)
    @test appearance.font_scale == 1.1
    texts = _at_collect_texts(only(last(rendered_output(backend)).windows).content)
    # The new print shows the same tab: the appearance, not the first document.
    @test "110%" in first.(texts)
    @test !("Name" in first.(texts))
end

end
end
