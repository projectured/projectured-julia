# The YAML syntax follows the scales of the appearance: the natural renderer
# gives the YAML projections the scaled `YamlTheme` of its appearance, so at a
# font scale of 1.5 every text of a YAML document is 1.5 times as large, and a
# YAML projection that a builder gives no style has the default styles.

function test_yaml_theme()
@testset "the YAML syntax follows the scales of the appearance" begin
    document = parse_yaml("name: x\ncount: 1\n")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test YamlNumberToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), YamlTheme)
    leaf = YamlNumberToSyntaxLeaf(; style = get_yaml_style(theme, :number_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(YamlTheme(), :number_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    # Each kind of value takes the role of its kind.
    role(name) = resolve_theme_color(ColorRole(name), Appearance())
    @test is_color_equal(YamlNumberToSyntaxLeaf().style.color, role(:number_literal))
    @test is_color_equal(YamlBoolToSyntaxLeaf().style.color, role(:boolean_literal))
    @test is_color_equal(YamlNullToSyntaxLeaf().style.color, role(:null_literal))
    @test is_color_equal(YamlStringToSyntaxLeaf().style.color, role(:string_literal))
    @test !hasfield(YamlNumberToSyntaxLeaf, :theme)
    built = YamlToSyntax(; theme = YamlTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === YamlNumber)[2].style).font.size == 14
end
end
