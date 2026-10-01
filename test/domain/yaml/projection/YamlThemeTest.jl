# The YAML syntax follows the scales of the appearance: the natural renderer
# gives the YAML projections the scaled `YamlTheme` of its appearance, so at a
# font scale of 1.5 every text of a YAML document is 1.5 times as large, and a
# YAML projection with no theme has the default styles.

function test_yaml_theme()
@testset "the YAML syntax follows the scales of the appearance" begin
    document = parse_yaml("name: x\ncount: 1\n")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test YamlNumberToSyntaxLeaf().style.font.size == 20
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), YamlTheme)
    leaf = YamlNumberToSyntaxLeaf(; theme)
    @test leaf.style.font.size == 30
    @test is_color_equal(leaf.style.color, YamlTheme().number_text.color)
end
end
