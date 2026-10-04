# The Formula syntax follows the scales of the appearance: the chain to text
# gives the Formula projections, and the Julia nodes a formula's code is built
# from, the scaled themes of its appearance, so at a font scale of 1.5 every
# text of a formula is 1.5 times as large, and a Formula projection that a
# builder gives no style has the default styles.

function test_formula_theme()
@testset "the Formula syntax follows the scales of the appearance" begin
    formula = FormulaFormula("A1", parse_julia("2 + 3"); display_mode = :both)
    _projection(appearance) = ChainingProjection(
        RecursiveProjection(FormulaToSyntax(;
            theme = get_scaled_theme!(appearance, FormulaTheme),
            julia_theme = get_scaled_theme!(appearance, JuliaTheme),
            syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))),
        RecursiveProjection(SyntaxToText(; theme = get_scaled_theme!(appearance, SyntaxTheme))),
        TextToGraphics(; measure = FixedMeasure(8, 12, 4, 0),
                       theme = get_scaled_theme!(appearance, TextTheme)))
    offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
    draw(appearance) = collect_font_sizes(print_document(_projection(appearance), nothing, formula, offer).output)

    plain = draw(Appearance())
    @test !isempty(plain)
    @test draw(Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test FormulaReferenceToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), FormulaTheme)
    leaf = FormulaReferenceToSyntaxLeaf(; style = get_formula_style(theme, :reference_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, FormulaTheme().reference_text.color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(FormulaReferenceToSyntaxLeaf, :theme)
    built = FormulaToSyntax(; theme = FormulaTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === FormulaReference)[2].style).font.size == 14
end
end
