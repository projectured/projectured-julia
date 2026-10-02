# The DbCatalog syntax follows the scales of the appearance: the chain to text
# gives the DbCatalog projections the scaled `DbCatalogTheme` of its appearance,
# so at a font scale of 1.5 every text of a catalog is 1.5 times as large, and a
# DbCatalog projection with no theme has the default styles.

function test_dbcatalog_theme()
@testset "the DbCatalog syntax follows the scales of the appearance" begin
    document = make_db_catalog_rdbms_document_example()
    _projection(appearance) = ChainingProjection(
        RecursiveProjection(DbCatalogToSyntax(; theme = get_scaled_theme!(appearance, DbCatalogTheme))),
        RecursiveProjection(SyntaxToText(; theme = get_scaled_theme!(appearance, SyntaxTheme))),
        TextToGraphics(; measure = FixedMeasure(8, 12, 4, 0),
                       theme = get_scaled_theme!(appearance, TextTheme)))
    offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
    draw(appearance) = collect_font_sizes(print_document(_projection(appearance), nothing, document, offer).output)

    plain = draw(Appearance())
    @test !isempty(plain)
    @test draw(Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test DbCatalogColumnToSyntaxLeaf().style.font.size == 20
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), DbCatalogTheme)
    leaf = DbCatalogColumnToSyntaxLeaf(; theme)
    @test leaf.style.font.size == 30
    @test is_color_equal(leaf.style.color, DbCatalogTheme().column_text.color)
end
end
