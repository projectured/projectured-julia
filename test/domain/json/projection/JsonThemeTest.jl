# The JSON syntax follows the scales of the appearance: the natural renderer gives
# the JSON projections the scaled `JsonTheme` of its appearance, so at a font scale
# of 1.5 every text of a JSON document is 1.5 times as large, and a JSON
# projection that a builder gives no style has the default styles.

function test_json_theme()
@testset "the JSON syntax follows the scales of the appearance" begin
    document = parse_json("""{"name": "x", "list": [1, true, null], "empty": {}}""")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test JsonNumberToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), JsonTheme)
    leaf = JsonNumberToSyntaxLeaf(; style = get_json_style(theme, :number_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(JsonTheme(), :number_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(JsonNumberToSyntaxLeaf, :theme)
    built = JsonToSyntax(; theme = JsonTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === JsonNumber)[2].style).font.size == 14
end
end
