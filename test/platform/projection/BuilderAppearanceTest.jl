# Each builder of a view passes the `Appearance` of its editor to the widgets that
# it draws. Two renderers with two appearances draw with their own widget themes,
# and at a font scale of 2 every text that a builder draws is twice as large. A
# text that keeps its size is drawn by a projection that a builder left at its
# default theme.

_builder_test_measure = FixedMeasure(8, 12, 4, 0)

# The size and the color of the font of each text that a canvas tree draws.
function _collect_text_styles(canvas)
    styles = Dict{String,Tuple{Int,StyleColor}}()
    function walk(c)
        for element in c.elements
            element = element isa Cell ? element[] : element
            if element isa GraphicsCanvas
                walk(element)
            elseif element isa GraphicsViewport
                walk(element.content)
            elseif element isa GraphicsText
                styles[String(element.text)] = (Int(element.font.size), element.color)
            end
        end
    end
    walk(canvas)
    styles
end

# Whether `text` is an icon: a glyph of the icon font, in the private use area.
_is_icon_text(text) = !isempty(text) && all(c -> '\ue000' <= c <= '\uf8ff', text)

# The texts of `draw(appearance)` that do not grow when the font scale is 2. An
# icon is left out: its box is a line of its label times the icon scale, and the
# fixed measure gives a line the same height at each size of the font.
function _find_texts_that_keep_their_size(draw)
    plain = _collect_text_styles(draw(Appearance()))
    large = _collect_text_styles(draw(Appearance(font_scale = 2.0)))
    String[text for (text, (size, _)) in plain
           if !_is_icon_text(text) &&
              (!haskey(large, text) || first(large[text]) != scale_length(size, 2.0))]
end

function test_builder_appearance()
@testset "Builder appearance" begin

measure = _builder_test_measure
offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
print_output(projection, document) = print_document(projection, nothing, document, offer).output
widgets() = VerticalLayout(Any[WidgetLabel("Name"), WidgetButton("Save"), WidgetCheckbox(true)]; gap = 8)
natural(appearance) = NaturalToGraphics(; measure, appearance)

@testset "two renderers with two appearances draw with their own widget themes" begin
    light, dark = Appearance(), Appearance(color_mode = :dark)
    color(appearance) = last(_collect_text_styles(print_output(natural(appearance), WidgetLabel("Name")))["Name"])
    @test is_color_equal(color(light), resolve_theme_color(ColorRole(:text), light))
    @test is_color_equal(color(dark), resolve_theme_color(ColorRole(:text), dark))
    @test !is_color_equal(color(light), color(dark))
end

@testset "every text that a builder draws grows with the font scale" begin
    @testset "the natural renderer" begin
        @test isempty(_find_texts_that_keep_their_size(appearance ->
            print_output(natural(appearance), widgets())))
    end
    @testset "the tabs" begin
        tree() = PaneTree(PaneGroup([PaneTab("Tab", widgets())]))
        texts = _find_texts_that_keep_their_size(appearance ->
            print_output(make_tabs_projection(natural(appearance); appearance, measure), tree()))
        @test isempty(texts)
    end
    @testset "the window shell" begin
        shell() = make_window_shell_document(widgets(); status_bar = WidgetStatusBar(Any["Ready"]))
        texts = _find_texts_that_keep_their_size(appearance ->
            print_output(make_window_shell_projection(natural(appearance); measure, appearance), shell()))
        @test isempty(texts)
    end
    @testset "a window that a wrapper opens" begin
        opened(appearance) = RecursiveProjection(TypeDispatchingProjection(
            make_opened_window_projections(; gesture_help = false, measure, appearance)))
        @test isempty(_find_texts_that_keep_their_size(appearance ->
            print_output(opened(appearance), WidgetButton("Save"))))
    end
end

end
end
