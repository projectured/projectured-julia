# The JSON syntax follows the scales of the appearance: the natural renderer gives
# the JSON projections the scaled `JsonTheme` of its appearance, so at a font scale
# of 1.5 every text of a JSON document is 1.5 times as large, and a JSON
# projection with no theme has the default styles.

function test_json_theme()
@testset "the JSON syntax follows the scales of the appearance" begin
    document = parse_json("""{"name": "x", "list": [1, true, null], "empty": {}}""")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test JsonNumberToSyntaxLeaf().style.font.size == 20
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), JsonTheme)
    leaf = JsonNumberToSyntaxLeaf(; theme)
    @test leaf.style.font.size == 30
    @test is_color_equal(leaf.style.color, JsonTheme().number_text.color)
end
end
