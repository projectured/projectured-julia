# The DbCatalog syntax follows the scales of the appearance: the chain to text
# gives the DbCatalog projections the scaled `DbCatalogTheme` of its appearance,
# so at a font scale of 1.5 every text of a catalog is 1.5 times as large, and a
# DbCatalog projection that a builder gives no style has the default styles.

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

    @test DbCatalogColumnToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), DbCatalogTheme)
    leaf = DbCatalogColumnToSyntaxLeaf(; style = get_db_catalog_style(theme, :column_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(DbCatalogTheme(), :column_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(DbCatalogColumnToSyntaxLeaf, :theme)
    built = DbCatalogToSyntax(; theme = DbCatalogTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === DbCatalogColumn)[2].style).font.size == 14
end
end
