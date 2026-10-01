# The Julia syntax follows the scales of the appearance: the natural renderer gives
# the Julia projections the scaled `JuliaTheme` of its appearance, so at a font scale
# of 1.5 every text of a Julia document is 1.5 times as large, and a Julia
# projection with no theme has the default styles.

function test_julia_theme()
@testset "the Julia syntax follows the scales of the appearance" begin
    document = parse_julia("function f(x)\n    y = g(x, 2.5, \"s\", true, nothing, :sym)\n    y.z\nend")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test JuliaIntegerToSyntaxLeaf().style.font.size == 20
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), JuliaTheme)
    leaf = JuliaIntegerToSyntaxLeaf(; theme)
    @test leaf.style.font.size == 30
    @test is_color_equal(leaf.style.color, JuliaTheme().literal_text.color)
end
end
