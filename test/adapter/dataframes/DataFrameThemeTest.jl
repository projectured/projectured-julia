"""
    test_data_frame_theme()

The data frame view follows the scales of the appearance: the width of a field
of the filter row and of the expression bar, the gap between the parts of each,
and the width of a column in the list form of a wide frame.
"""
function test_data_frame_theme()
@testset "the data frame view follows the scales of the appearance" begin
    defaults = DataFrameTheme()
    plain = DataFrameViewToWidget()
    @test plain.query_field_width == 80
    @test plain.expression_field_width == 480
    @test plain.list_column_width == 160
    @test plain.filter_gap == 4
    @test plain.expression_gap == 8
    @test is_color_equal(plain.invalid_query, get_theme_value(defaults, :invalid_query))
    @test is_color_equal(plain.unsorted_glyph, get_theme_value(defaults, :unsorted_glyph))

    @test !hasfield(DataFrameViewToWidget, :theme)
    appearance = Appearance(control_scale = 1.5, spacing_scale = 1.5)
    chain = make_data_frame_view_projection(; measure = FixedMeasure(8, 12, 4, 0), appearance)
    scaled = first(chain.projections)
    @test scaled.query_field_width == 120
    @test scaled.expression_field_width == 720
    @test scaled.list_column_width == 240
    @test scaled.filter_gap == 6
    @test scaled.expression_gap == 12

    # End to end: the field of the filter row of a header is `query_field_width`
    # wide.
    projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0), appearance)
    view = DataFrameView(DataFrame(id = 1:3))
    context = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
    io = print_document(projection, nothing, view, context)
    table = _data_frame_table_iomap(io).input
    @test table.column_headers[1].children[2].width == 120
end
end
