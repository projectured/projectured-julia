# The SQL syntax follows the scales of the appearance: the natural renderer gives
# the SQL projections the scaled `SqlTheme` of its appearance, so at a font scale
# of 1.5 every text of a SQL document is 1.5 times as large, and a SQL projection
# with no theme has the default styles.

function test_sql_theme()
@testset "the SQL syntax follows the scales of the appearance" begin
    document = parse_sql_text("SELECT a FROM t WHERE a = 1")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test SqlColumnReferenceToSyntaxLeaf().style.font.size == 20
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), SqlTheme)
    leaf = SqlColumnReferenceToSyntaxLeaf(; theme)
    @test leaf.style.font.size == 30
    @test is_color_equal(leaf.style.color, SqlTheme().plain_text.color)
end
end
