# A swatch: a square of its color inside a border of the widget theme, as large as
# the swatch size of the theme, or as the size that the swatch asks for.

function test_widget_swatch()
@testset "a swatch draws a square of its color, as large as the theme says or as it asks" begin
    projection = make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0))
    context = PrinterContext(EmptyReference(), nothing, nothing, Dict{Symbol,Any}())
    theme = get_theme_defaults(WidgetTheme)
    border = 2 * theme.border_width
    output = print_document(projection, nothing, WidgetSwatch(color_solarized_blue), context).output
    @test (Int(output.w), Int(output.h)) == (theme.swatch_size + border, theme.swatch_size + border)
    rects = [element for element in output.elements if element isa GraphicsRect]
    # The color fills the square, and the border of the theme frames it.
    @test any(rect -> is_color_equal(rect.color, color_solarized_blue) &&
                      is_color_equal(rect.border_color, theme.border), rects)
    larger = print_document(projection, nothing, WidgetSwatch(color_solarized_blue; size = 24), context).output
    @test (Int(larger.w), Int(larger.h)) == (24 + border, 24 + border)
end
end
