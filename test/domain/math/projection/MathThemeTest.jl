# The Math syntax follows the scales of the appearance: the natural renderer gives
# the Math projections the scaled `MathTheme` of its appearance, so at a font scale
# of 1.5 every text of a formula is 1.5 times as large, a Math projection that a
# builder gives no style has the default styles, and the typeset form draws at
# the scaled font size.

function test_math_theme()
@testset "the Math syntax follows the scales of the appearance" begin
    document = parse_math("x = a + 1")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test MathVariableToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), MathTheme)
    leaf = MathVariableToSyntaxLeaf(; style = get_math_style(theme, :variable_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, MathTheme().variable_text.color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(MathVariableToSyntaxLeaf, :theme)
    built = MathToSyntax(; theme = MathTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === MathVariable)[2].style).font.size == 14
end

@testset "the typeset form of a formula follows the scale of the appearance" begin
    document = parse_math("x = a + 1")
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), MathTheme)
    projection = RecursiveProjection(MathToGraphics(; measure = FixedMeasure(8, 12, 4, 0), theme))
    offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
    sizes = collect_font_sizes(print_document(projection, nothing, document, offer).output)
    @test !isempty(sizes)
    @test all(==(21), sizes)
end
end
