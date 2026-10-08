# The SQL syntax follows the scales of the appearance: the natural renderer gives
# the SQL projections the scaled `SqlTheme` of its appearance, so at a font scale
# of 1.5 every text of a SQL document is 1.5 times as large, and a SQL projection
# that a builder gives no style has the default styles.

function test_sql_theme()
@testset "the SQL syntax follows the scales of the appearance" begin
    document = parse_sql_text("SELECT a FROM t WHERE a = 1")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test SqlColumnReferenceToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), SqlTheme)
    leaf = SqlColumnReferenceToSyntaxLeaf(; style = get_sql_style(theme, :plain_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(SqlTheme(), :plain_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(SqlColumnReferenceToSyntaxLeaf, :theme)
    built = SqlToSyntax(; theme = SqlTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === SqlColumnReference)[2].style).font.size == 14
end

@testset "a SQL value takes the role of its kind, and follows a change of its kind" begin
    role(name) = resolve_theme_color(ColorRole(name), Appearance())
    color_of(value) = print_document(SqlScalarValueToSyntaxLeaf(), nothing, value, nothing).output.value.font_color
    @test color_of(SqlScalarValue(42)) == role(:number_literal)
    @test color_of(SqlScalarValue("x")) == role(:string_literal)
    @test color_of(SqlScalarValue(true)) == role(:boolean_literal)
    value = SqlScalarValue(42)
    leaf = print_document(SqlScalarValueToSyntaxLeaf(), nothing, value, nothing).output.value
    value.value = "x"
    @test leaf.content == "'x'"
    @test leaf.font_color == role(:string_literal)
end
end
