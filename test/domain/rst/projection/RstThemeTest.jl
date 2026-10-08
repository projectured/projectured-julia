# The RST syntax follows the scales of the appearance: the natural renderer
# gives the RST projections the scaled `RstTheme` of its appearance, so at a
# font scale of 1.5 every text of an RST document is 1.5 times as large in the
# source form and in the rendered form, and an RST projection that a builder
# gives no style has the default styles.

# The size of the font of each text the rendered RST form draws for `document`
# with `appearance`, in a fixed measure: the source form goes through the
# natural renderer (`draw_font_sizes`), and the rendered form — which the
# natural renderer reaches only through the `:rst` named notation, not a
# document type — goes through its own chain by hand.
function draw_rendered_rst_font_sizes(document, appearance::Appearance)
    theme = get_scaled_theme!(appearance, RstTheme)
    syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)
    measure = FixedMeasure(8, 12, 4, 0)
    syntax = print_document(RecursiveProjection(RstToSyntax(; style = :rendered, theme)), document).output
    text = print_document(RecursiveProjection(SyntaxToText(; theme = syntax_theme)), syntax).output
    graphics = print_document(TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme)), text).output
    collect_font_sizes(graphics)
end

function test_rst_theme()
@testset "the RST syntax follows the scales of the appearance" begin
    document = parse_rst("""
Title
=====

Some *em* text.
""")

    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test RstTextToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), RstTheme)
    leaf = RstTextToSyntaxLeaf(; style = get_rst_style(theme, :source_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(RstTheme(), :source_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    # The name of a field and of an option take the roles of their kinds.
    role(name) = resolve_theme_color(ColorRole(name), Appearance())
    @test is_color_equal(RstFieldToSyntaxNode().name_style.color, role(:field))
    @test is_color_equal(RstDirectiveOptionToSyntaxNode().name_style.color, role(:parameter))
    @test !hasfield(RstTextToSyntaxLeaf, :theme)
    @test !hasfield(RstSectionToStyledNode, :theme)
    @test !hasfield(RstSectionToVerticalLayout, :theme)
    built = RstToSyntax(; theme = RstTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === RstText)[2].style).font.size == 14

    # The rendered form: a section title takes a bigger font than the body, and
    # both scale with the appearance — headings scale too.
    rendered_plain = draw_rendered_rst_font_sizes(document, Appearance())
    @test !isempty(rendered_plain)
    @test maximum(rendered_plain) > minimum(rendered_plain)
    @test draw_rendered_rst_font_sizes(document, Appearance(font_scale = 1.5)) ==
          round.(Int, rendered_plain .* 1.5)
end
end
