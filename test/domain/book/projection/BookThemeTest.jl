# The book syntax follows the scales of the appearance: the natural renderer
# gives the book projections the scaled `BookTheme` of its appearance, so at a
# font scale of 1.5 every text of a book document is 1.5 times as large, and a
# book projection that a builder gives no style has the default styles.

# The size of the font of each text `BookToSyntax` draws for `document` with
# `appearance`, in a fixed measure. A book has no document-type natural
# registration of its own (only the `:book` named notation an embed selects),
# so the chain is built by hand rather than through `draw_font_sizes`.
function draw_book_font_sizes(document, appearance::Appearance)
    theme = get_scaled_theme!(appearance, BookTheme)
    syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)
    measure = FixedMeasure(8, 12, 4, 0)
    syntax = print_document(RecursiveProjection(BookToSyntax(; theme)), document).output
    text = print_document(RecursiveProjection(SyntaxToText(; theme = syntax_theme)), syntax).output
    graphics = print_document(TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme)), text).output
    collect_font_sizes(graphics)
end

function test_book_theme()
@testset "the book syntax follows the scales of the appearance" begin
    document = BookBook("The Title", "An Author",
                        [BookChapter("One", "1", [BookParagraph(TextBlock(TextString("Some prose.")))])])

    plain = draw_book_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test maximum(plain) > minimum(plain)
    @test draw_book_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test BookParagraphToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), BookTheme)
    leaf = BookParagraphToSyntaxLeaf(; style = get_book_style(theme, :paragraph_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, BookTheme().paragraph_text.color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(BookParagraphToSyntaxLeaf, :theme)
    built = BookToSyntax(; theme = BookTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === BookParagraph)[2].style).font.size == 14
end
end
