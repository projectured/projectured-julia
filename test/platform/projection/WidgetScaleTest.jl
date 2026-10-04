# The scales of an appearance on the widgets. Each scale at 1.5 changes the
# lengths of its own kind and leaves every other length as it is, and a press at
# the drawn place of a control hits the control when every scale is at 1.5.

using ProjecturedKernel.CellModule: Cell

_scale_test_measure = FixedMeasure(8, 12, 4, 0)

# The widget projection that draws with the default widget theme, scaled by
# `appearance`.
_make_scaled_widget_projection(appearance::Appearance) =
    RecursiveProjection(TypeDispatchingProjection(vcat(LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = _scale_test_measure,
                         theme = make_scaled_theme(WidgetTheme(), appearance),
                         graphics_theme = make_scaled_theme(GraphicsTheme(), appearance)).dispatch)))

# The lengths that a canvas tree draws: the size of the canvas, the corner radii
# and the border widths of its rects, the sizes of its fonts, the place and the
# size of each rect, the centre and the radius of each circle, and the place of
# each text, in the frame of the canvas. A viewport adds its translation.
function _compute_drawn_lengths(canvas)
    radii = Set{Int}(); borders = Set{Int}(); fonts = Set{Int}()
    rects = NTuple{4,Int}[]; circles = NTuple{3,Int}[]; texts = Dict{String,Tuple{Int,Int}}()
    function walk(c, ox, oy)
        x0 = ox + Int(c.x); y0 = oy + Int(c.y)
        for element in c.elements
            element = element isa Cell ? element[] : element
            if element isa GraphicsCanvas
                walk(element, x0, y0)
            elseif element isa GraphicsViewport
                # A viewport that clips a strip moves its content by a translation.
                walk(element.content, x0 + Int(element.x) + round(Int, element.transform.e),
                     y0 + Int(element.y) + round(Int, element.transform.f))
            elseif element isa GraphicsRect
                (Int(element.w) > 0 && Int(element.h) > 0) || continue
                push!(radii, Int(element.radius_tl))
                Int(element.border_width) > 0 && push!(borders, Int(element.border_width))
                push!(rects, (x0 + Int(element.x), y0 + Int(element.y), Int(element.w), Int(element.h)))
            elseif element isa GraphicsCircle
                Int(element.border_width) > 0 && push!(borders, Int(element.border_width))
                push!(circles, (x0 + Int(element.cx), y0 + Int(element.cy), Int(element.radius)))
            elseif element isa GraphicsText
                push!(fonts, Int(element.font.size))
                texts[String(element.text)] = (x0 + Int(element.x), y0 + Int(element.y))
            end
        end
    end
    walk(canvas, -Int(canvas.x), -Int(canvas.y))
    (w = Int(canvas.w[]), h = Int(canvas.h[]), radii = sort!(collect(radii)),
     borders = sort!(collect(borders)), fonts = sort!(collect(fonts)),
     rects, circles, texts)
end

function test_widget_scales()
@testset "Widget scales" begin

draw(appearance, make) =
    _compute_drawn_lengths(print_document(_make_scaled_widget_projection(appearance), make()).output)
button() = WidgetButton("Save")
icon_button() = WidgetButton("Run"; icon = :play)
checkbox() = WidgetCheckbox(true)
radio_group() = WidgetRadioGroup(["One", "Two"]; selected = 1)
widgets = (button, icon_button, checkbox, radio_group)
default = Dict(make => draw(Appearance(), make) for make in widgets)

# The lengths of `make` under `appearance`, with the lengths that `kinds` names
# left out, equal those of the default appearance.
function is_equal_except(appearance, make, kinds...)
    scaled = draw(appearance, make)
    all(name -> name in kinds || getfield(scaled, name) == getfield(default[make], name),
        (:w, :h, :radii, :borders, :fonts, :rects, :circles))
end

@testset "the font scale changes the fonts" begin
    appearance = Appearance(font_scale = 1.5)
    @test default[button].fonts == [13]
    @test draw(appearance, button).fonts == [20]
    # The fixed measure gives a line the same height at each size, so no extent moves.
    @test all(make -> is_equal_except(appearance, make, :fonts), widgets)
end

@testset "the spacing scale changes the paddings and the gaps" begin
    appearance = Appearance(spacing_scale = 1.5)
    scaled = draw(appearance, button)
    # The padding of a control is 5 above and below and 10 at the sides; at a
    # scale of 1.5 it is 8 and 15, so each side grows by 3 and by 5.
    @test (scaled.w - default[button].w, scaled.h - default[button].h) == (2 * 5, 2 * 3)
    @test is_equal_except(appearance, button, :w, :h, :rects)
    @test is_equal_except(appearance, checkbox)
end

@testset "the radius scale changes the corners" begin
    appearance = Appearance(radius_scale = 1.5)
    @test default[button].radii == [6]
    @test draw(appearance, button).radii == [9]
    @test is_equal_except(appearance, button, :radii)
end

@testset "the line scale changes the borders and the strokes" begin
    appearance = Appearance(line_scale = 1.5)
    scaled = draw(appearance, button)
    @test default[button].borders == [1]
    @test scaled.borders == [2]
    # The border is part of the box, so the button grows by one at each side.
    @test (scaled.w - default[button].w, scaled.h - default[button].h) == (2, 2)
    @test is_equal_except(appearance, button, :w, :h, :borders, :rects)
end

@testset "the control scale changes the parts of a control that are not text" begin
    appearance = Appearance(control_scale = 1.5)
    box(lengths) = filter(r -> r[3] == r[4], lengths.rects)
    @test any(r -> r[3] == 16, box(default[checkbox]))
    @test any(r -> r[3] == 24, box(draw(appearance, checkbox)))
    @test !is_equal_except(appearance, radio_group)
    @test is_equal_except(appearance, button) && is_equal_except(appearance, icon_button)
end

@testset "the icon scale changes the box of an icon" begin
    appearance = Appearance(icon_scale = 1.5)
    scaled = draw(appearance, icon_button)
    # The box of the icon is one line, 16, so 24; the button takes the larger of
    # the icon and the label.
    @test (scaled.w - default[icon_button].w, scaled.h - default[icon_button].h) == (8, 8)
    @test is_equal_except(appearance, button)
    @test is_equal_except(appearance, checkbox) && is_equal_except(appearance, radio_group)
end

@testset "a press at the drawn place of a control hits it, with every scale at 1.5" begin
    appearance = Appearance(font_scale = 1.5, icon_scale = 1.5, spacing_scale = 1.5,
                            control_scale = 1.5, radius_scale = 1.5, line_scale = 1.5)
    projection = _make_scaled_widget_projection(appearance)
    function press(document, x, y)
        iomap = print_document(projection, document)
        answer = read_intent(projection, nothing,
                             Intent(MouseClick(:left, x, y, ModifierKeys(); time = 0.0), nothing), iomap)
        answer isa Intent ? answer.operation : answer
    end
    # The far corner of the box of the checkbox, which a box of the default size
    # does not reach.
    document = checkbox()
    lengths = _compute_drawn_lengths(print_document(projection, document).output)
    x, y, w, h = only(filter(r -> r[3] == r[4] == 24, lengths.rects))
    @test press(document, x + w - 2, y + h - 2) isa ReplaceReferencedValueOperation
    # The circle of the second option: the rows stand apart by the control size
    # and the gap of a section, both scaled.
    document = radio_group()
    lengths = _compute_drawn_lengths(print_document(projection, document).output)
    cx, cy, _ = last(sort(lengths.circles; by = c -> c[2]))
    answer = press(document, cx, cy)
    @test answer isa ReplaceReferencedValueOperation && answer.value == 2
    # The label of the second tab: the tabs stand apart by their padding.
    document = WidgetTabbedPane(Any[("one", WidgetLabel("1")), ("two", WidgetLabel("2"))])
    lengths = _compute_drawn_lengths(print_document(projection, document).output)
    tx, ty = lengths.texts["two"]
    answer = press(document, tx + 2, ty + 2)
    @test answer isa ReplaceSelectionOperation &&
          occursin("selector_element_pairs[2]", string(answer.path))
end

end
end
