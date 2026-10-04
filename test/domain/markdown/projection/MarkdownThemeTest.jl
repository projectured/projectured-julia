# The markdown syntax follows the scales of the appearance: the natural renderer
# gives the markdown projections the scaled `MarkdownTheme` of its appearance, so
# at a font scale of 1.5 every text of a markdown document is 1.5 times as large
# in the source form and in the rendered form, and a markdown projection that a
# builder gives no style has the default styles.

# The size of the font of each text the rendered markdown form draws for
# `document` with `appearance`, in a fixed measure: the source form goes through
# the natural renderer (`draw_font_sizes`), and the rendered form — which the
# natural renderer reaches only through the `:markdown` named notation, not a
# document type — goes through its own chain by hand.
function draw_rendered_markdown_font_sizes(document, appearance::Appearance)
    theme = get_scaled_theme!(appearance, MarkdownTheme)
    syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)
    measure = FixedMeasure(8, 12, 4, 0)
    syntax = print_document(RecursiveProjection(MarkdownToSyntax(; style = :rendered, theme)), document).output
    text = print_document(RecursiveProjection(SyntaxToText(; theme = syntax_theme)), syntax).output
    graphics = print_document(TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme)), text).output
    collect_font_sizes(graphics)
end

function test_markdown_theme()
@testset "the markdown syntax follows the scales of the appearance" begin
    document = parse_markdown("# Heading\n\nSome *em* and **strong** text.\n")

    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test MarkdownTextToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), MarkdownTheme)
    leaf = MarkdownTextToSyntaxLeaf(; style = get_markdown_style(theme, :source_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(MarkdownTheme(), :source_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(MarkdownTextToSyntaxLeaf, :theme)
    @test !hasfield(MarkdownHeadingToStyledNode, :theme)
    built = MarkdownToSyntax(; theme = MarkdownTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === MarkdownText)[2].style).font.size == 14

    # The rendered form: a heading takes a bigger font than the body, and both
    # scale with the appearance — headings scale too.
    rendered_plain = draw_rendered_markdown_font_sizes(document, Appearance())
    @test !isempty(rendered_plain)
    @test maximum(rendered_plain) > minimum(rendered_plain)
    @test draw_rendered_markdown_font_sizes(document, Appearance(font_scale = 1.5)) ==
          round.(Int, rendered_plain .* 1.5)
end
end
