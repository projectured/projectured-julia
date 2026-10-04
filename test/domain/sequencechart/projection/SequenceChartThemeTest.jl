# The sequence chart renderer follows the scales of the appearance: it gives its
# title, its ticks, its lane names and its labels the scaled `SequenceChartTheme`
# of its appearance, so at a font scale of 1.5 every text of a chart is 1.5 times
# as large, and a renderer with no theme holds the plain values of the default
# theme — a length scaling with the spacing scale among them.

function test_sequencechart_theme()
@testset "the sequence chart renderer follows the scales of the appearance" begin
    chart = _sc_chart()
    _projection(theme) = ChainingProjection(
        SequenceChartToSequenceChartPlot(),
        SequenceChartPlotToGraphicsCanvas(; measure = FixedMeasure(8, 12, 4, 0),
                                          width = 600, height = 400, theme))
    draw(theme) = collect_font_sizes(print_document(_projection(theme), nothing, chart,
                                                     PrinterContext()).output)

    plain = draw(nothing)
    @test !isempty(plain)
    @test sort(unique(plain)) == [12, 14]

    theme = get_scaled_theme!(Appearance(font_scale = 1.5), SequenceChartTheme)
    large = draw(theme)
    @test large == round.(Int, plain .* 1.5)
    @test sort(unique(large)) == [18, 21]
end

@testset "a renderer with no theme holds the default values, and a theme scales a length" begin
    p = SequenceChartPlotToGraphicsCanvas(measure = FixedMeasure(8, 12, 4, 0))
    @test unwrap_cell(p.style).padding == 8

    scaled = SequenceChartPlotToGraphicsCanvas(measure = FixedMeasure(8, 12, 4, 0),
                                               theme = get_scaled_theme!(Appearance(spacing_scale = 2.0),
                                                                        SequenceChartTheme))
    @test unwrap_cell(scaled.style).padding == 16
end
end
