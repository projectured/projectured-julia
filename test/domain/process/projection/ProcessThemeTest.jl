# The Process syntax follows the scales of the appearance: the chain to text
# gives the Process projections, and the Julia nodes an action, a condition, a
# variable or an iterable is built from, the scaled themes of its appearance, so
# at a font scale of 1.5 every text of a process is 1.5 times as large, and a
# Process projection that a builder gives no style has the default styles.

function test_process_theme()
@testset "the Process syntax follows the scales of the appearance" begin
    document = make_process_transmit_document_example()
    _projection(appearance) = ChainingProjection(
        RecursiveProjection(ProcessToSyntax(;
            theme = get_scaled_theme!(appearance, ProcessTheme),
            julia_theme = get_scaled_theme!(appearance, JuliaTheme),
            syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))),
        RecursiveProjection(SyntaxToText(; theme = get_scaled_theme!(appearance, SyntaxTheme))),
        TextToGraphics(; measure = FixedMeasure(8, 12, 4, 0),
                       theme = get_scaled_theme!(appearance, TextTheme)))
    offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
    draw(appearance) = collect_font_sizes(print_document(_projection(appearance), nothing, document, offer).output)

    plain = draw(Appearance())
    @test !isempty(plain)
    @test draw(Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test ProcessModelToSyntaxNode().keyword.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), ProcessTheme)
    node = ProcessModelToSyntaxNode(; keyword = get_process_style(theme, :keyword_text))
    @test node.keyword.font.size == 21
    @test is_color_equal(node.keyword.color, ProcessTheme().keyword_text.color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(ProcessModelToSyntaxNode, :theme)
    @test !hasfield(ProcessStepToSyntaxLabel, :theme)
    built = ProcessToSyntax(; theme = ProcessTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === ProcessModel)[2].keyword).font.size == 14
end
end
