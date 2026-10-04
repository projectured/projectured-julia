# The XML syntax follows the scales of the appearance: the natural renderer gives
# the XML projections the scaled `XmlTheme` of its appearance, so at a font scale
# of 1.5 every text of an XML document is 1.5 times as large, and an XML
# projection that a builder gives no style has the default styles.

function test_xml_theme()
@testset "the XML syntax follows the scales of the appearance" begin
    document = parse_xml("""<note id="1"><to>Ann</to></note>""")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test XmlTextToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), XmlTheme)
    leaf = XmlTextToSyntaxLeaf(; style = get_xml_style(theme, :content_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, XmlTheme().content_text.color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(XmlTextToSyntaxLeaf, :theme)
    built = XmlToSyntax(; theme = XmlTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === XmlText)[2].style).font.size == 14
end
end
