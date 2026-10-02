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
# baseline is nearest to that of the name. The rows of the scales are at the top
# of the tab, so the topmost text is the name of a row when a card has the same
# title.
function _at_find_row_button(texts, row, button)
    _, _, row_y = argmin(t -> t[3], [t for t in texts if t[1] == row])
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
                     unwrap(op).document === theme &&
                     unwrap(op).reference.head == FieldReferenceStep("font"))
    next_font = unwrap(font_step).value
    @test next_font.size == theme.font.size && next_font.filename != theme.font.filename
end

@testset "the sections are in three groups, the editor themes first, and each folds" begin
    appearance = Appearance()
    get_scaled_theme!(appearance, SyntaxTheme)
    get_scaled_theme!(appearance, FaultTheme)
    projection = NaturalToGraphics(; measure, appearance)
    iomap = print_document(projection, nothing, appearance, offer)
    texts = first.(_at_collect_texts(iomap.output))
    order = [findfirst(==(t), texts) for t in ("Editor", "Widget", "Syntax", "Tools", "Fault")]
    @test all(!isnothing, order) && issorted(order)
    # Every section is closed: a card draws its title and no field.
    @test !("primary" in texts) && !("item gap" in texts)
    tab = _at_find_iomap(iomap, AppearanceToWidgetIoMap)
    card = only(c for (c, name) in tab.folds if name == "WidgetTheme")
    @test card.collapsed
    translate(operation) = ProjecturedPlatform.AppearanceModule._translate_tab_operation(tab, operation)
    fold = translate(ToggleCollapseOperation(card))
    @test fold isa ReplaceViewStateOperation
    # The fold is the state of the tab: the card follows it, and no view prints again.
    @test !is_appearance_change(appearance, fold)
    evaluate_operation(nothing, fold)
    @test appearance.open_sections == ["WidgetTheme"]
    @test !card.collapsed
    evaluate_operation(nothing, translate(ToggleCollapseOperation(card)))
    @test isempty(appearance.open_sections) && card.collapsed
    # An open section shows its fields, and the name of a field has its docstring
    # as its tooltip.
    appearance.open_sections = ["WidgetTheme"]
    iomap = print_document(projection, nothing, appearance, offer)
    @test "item gap" in first.(_at_collect_texts(iomap.output))
    tab = _at_find_iomap(iomap, AppearanceToWidgetIoMap)
    pane = tab.child_iomap.input
    labels = WidgetLabel[]
    function walk(node, depth = 0)
        depth > 30 && return
        node isa WidgetLabel && push!(labels, node)
        node isa Document || return
        for name in fieldnames(typeof(node))
            value = getfield(node, name)
            value isa Cell && (value = value[])
            for child in (value isa AbstractVector ? value : (value,))
                child isa Cell && (child = child[])
                child isa Document && walk(child, depth + 1)
            end
        end
    end
    walk(pane)
    label = only(l for l in labels if l.content == "item gap")
    @test label.tooltip == find_theme_field_text(WidgetTheme, :item_gap)
    @test label.tooltip isa String && !isempty(label.tooltip)
end

@testset "a text style has the controls of its colour and of its font" begin
    appearance = Appearance()
    get_scaled_theme!(appearance, SyntaxTheme)
    syntax = get_theme(appearance, SyntaxTheme)
    appearance.open_sections = ["SyntaxTheme"]
    projection = NaturalToGraphics(; measure, appearance)
    iomap = print_document(projection, nothing, appearance, offer)
    texts = first.(_at_collect_texts(iomap.output))
    @test "bool text" in texts
    @test !any(t -> startswith(t, "StyleText"), texts)
    @test format_style_color(syntax.bool_text.color) in texts
    tab = _at_find_iomap(iomap, AppearanceToWidgetIoMap)
    before = syntax.bool_text
    # The colour text of `bool_text`: a typed digit writes a style with the new
    # colour and the same font.
    writes = [first(edit(1, 1, "f")) for edit in values(tab.edits) if edit(1, 1, "f") !== nothing]
    write = only(w for w in writes
                 if w.document === syntax && w.reference.head == FieldReferenceStep("bool_text"))
    @test write.value isa StyleText
    @test (write.value.font.filename, write.value.font.size) == (before.font.filename, before.font.size)
    @test format_style_color(write.value.color)[2] == 'f'
    # The next font keeps the colour.
    step = only(op for (action, op) in tab.commands if action.label == "›" &&
                op.document === syntax && op.reference.head == FieldReferenceStep("bool_text"))
    @test step.value.font.filename != before.font.filename
    @test step.value.font.size == before.font.size
    @test is_color_equal(step.value.color, before.color)
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

@testset "the tab keeps its place after the new print that a change starts" begin
    # A change of the appearance prints the whole view again, so the place of the
    # tab is in the appearance, and each new pane scrolls that cell.
    backend = HeadlessBackend()
    editor = build_editor(WidgetLabel("Name"); backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "T", width = 900, height = 700), tabs = (; title = "Doc"))
    run_frame!(editor)
    appearance = find_editor_appearance(editor)
    function send!(events...)
        for event in events
            push_event!(backend, WindowInput(:T, event))
        end
        run_frame!(editor)
        run_frame!(editor)
    end
    drawn() = _at_collect_texts(only(last(rendered_output(backend)).windows).content)
    appearance.open_sections = ["WidgetTheme"]
    send!(KeyDown(:comma, ModifierKeys(ctrl = true); time = 1.0))
    _, x, y = only(t for t in drawn() if t[1] == "Spacing")
    send!(MouseScroll(0, -1, x, y, ModifierKeys(); time = 2.0))
    scrolled = Int(appearance.scroll_position.y[])
    @test scrolled > 0
    texts = drawn()
    place = only(t for t in texts if t[1] == "primary")
    x, y = _at_find_row_button(texts, "Text", "Reset")
    send!(_at_click(x, y, 3.0)...)
    @test Int(appearance.scroll_position.y[]) == scrolled
    @test only(t for t in drawn() if t[1] == "primary") == place
end

@testset "a colour is a text: a typed digit writes the colour, and the caret stays after the new print" begin
    @test format_style_color(StyleColor(1.0, 0.0, 0.0, 0.5)) == "#ff000080"
    @test is_color_equal(convert_text_to_style_color("#00FF00"), StyleColor(0.0, 1.0, 0.0, 1.0))
    @test convert_text_to_style_color("#00ff0") === nothing
    @test convert_text_to_style_color("green") === nothing

    backend = HeadlessBackend()
    editor = build_editor(WidgetLabel("Name"); backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "T", width = 900, height = 900), tabs = (; title = "Doc"))
    run_frame!(editor)
    appearance = find_editor_appearance(editor)
    theme = get_theme(appearance, WidgetTheme)
    before = format_style_color(theme.primary)
    time = Ref(1.0)
    send!(events...) = begin
        for event in events
            push_event!(backend, WindowInput(:T, event))
        end
        run_frame!(editor)
        run_frame!(editor)
        time[] += 1.0
    end
    appearance.open_sections = ["WidgetTheme"]
    send!(KeyDown(:comma, ModifierKeys(ctrl = true); time = time[]))
    # The widget theme is one section of many, one for each loaded domain, so the
    # place of the tab, which the appearance holds, brings its row into the window.
    _, _, row_y = only(t for t in _at_collect_texts(only(last(rendered_output(backend)).windows).content)
                       if t[1] == "primary")
    appearance.scroll_position = Point2D(0, max(0, row_y - 300))
    run_frame!(editor)
    texts = _at_collect_texts(only(last(rendered_output(backend)).windows).content)
    x, y = _at_find_row_button(texts, "primary", before)
    @test 0 < y < 900
    send!(_at_click(x - 1, y, time[])...)
    send!(KeyDown(:home, ModifierKeys(); time = time[]), KeyDown(:right, ModifierKeys(); time = time[] + 0.1))
    send!(KeyPress('f'; time = time[]))
    @test format_style_color(theme.primary) == "#f" * before[3:end]
    # The caret is after the first digit in the text of the new print.
    send!(KeyPress('0'; time = time[]))
    @test format_style_color(theme.primary) == "#f0" * before[4:end]
    texts = first.(_at_collect_texts(only(last(rendered_output(backend)).windows).content))
    @test ("#f0" * before[4:end]) in texts
    # A character that is no hex digit, and a deletion, leave the colour.
    send!(KeyPress('g'; time = time[]))
    send!(KeyDown(:backspace, ModifierKeys(); time = time[]))
    @test format_style_color(theme.primary) == "#f0" * before[4:end]
end

@testset "the wrapper makes a write of a theme a step that prints the view again, and so is its inverse" begin
    appearance = Appearance()
    get_scaled_theme!(appearance, WidgetTheme)
    theme = get_theme(appearance, WidgetTheme)
    wrap(operation) = ProjecturedPlatform.AppearanceModule._wrap_theme_writes(appearance, operation)
    write = ReplaceReferencedValueOperation(theme, "item_gap", Spacing(7))
    wrapped = wrap(CompoundOperation(Any[ReplaceViewStateOperation(write)]))
    step = get_wrapped_operation(only(wrapped.operations))
    @test step isa ReplaceThemeValueOperation && step.operation === write
    @test describe_operation(step) == "set item gap of WidgetTheme"
    # A write into a document that is no theme of the appearance stays as it is.
    other = ReplaceReferencedValueOperation(WidgetTheme(), "item_gap", Spacing(7))
    @test wrap(other) === other
    @test wrap(ReplaceReferencedValueOperation(appearance, "open_sections", String[])) isa
          ReplaceReferencedValueOperation
    inverse = make_inverse_operation(nothing, step)
    @test inverse isa ReplaceThemeValueOperation
    @test inverse.operation.value == Spacing(4)
    @test_throws ArgumentError ReplaceThemeValueOperation(
        ReplaceReferencedValueOperation(appearance, "zoom", 2.0))
end

@testset "Ctrl+Z in the history of the window takes back a change of a theme, and the view shows it" begin
    backend = HeadlessBackend()
    editor = build_editor(WidgetLabel("Name"); backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "T", width = 900, height = 900), tabs = (; title = "Doc"),
                          undo = true)
    run_frame!(editor)
    appearance = find_editor_appearance(editor)
    theme = get_theme(appearance, WidgetTheme)
    before = format_style_color(theme.primary)
    changed = "#f" * before[3:end]
    time = Ref(1.0)
    send!(events...) = begin
        for event in events
            push_event!(backend, WindowInput(:T, event))
        end
        run_frame!(editor)
        run_frame!(editor)
        time[] += 1.0
    end
    drawn() = _at_collect_texts(only(last(rendered_output(backend)).windows).content)
    appearance.open_sections = ["WidgetTheme"]
    send!(KeyDown(:comma, ModifierKeys(ctrl = true); time = time[]))
    _, _, row_y = only(t for t in drawn() if t[1] == "primary")
    appearance.scroll_position = Point2D(0, max(0, row_y - 300))
    run_frame!(editor)
    x, y = _at_find_row_button(drawn(), "primary", before)
    send!(_at_click(x - 1, y, time[])...)
    send!(KeyDown(:home, ModifierKeys(); time = time[]), KeyDown(:right, ModifierKeys(); time = time[] + 0.1))
    send!(KeyPress('f'; time = time[]))
    @test format_style_color(theme.primary) == changed
    @test changed in first.(drawn())
    send!(KeyDown(:z, ModifierKeys(ctrl = true); time = time[]))
    @test format_style_color(theme.primary) == before
    @test !(changed in first.(drawn()))
    send!(KeyDown(:y, ModifierKeys(ctrl = true); time = time[]))
    @test format_style_color(theme.primary) == changed
    @test changed in first.(drawn())
end

end
end
