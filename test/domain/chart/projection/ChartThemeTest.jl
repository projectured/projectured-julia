# The chart renderer follows the scales of the appearance: it gives its title,
# its axis titles, its tick labels and its legend the scaled `ChartTheme` of its
# appearance, so at a font scale of 1.5 every text of a chart is 1.5 times as
# large, and a renderer with no theme holds the plain values of the default
# theme — a length scaling with the spacing scale among them. A chart's own
# `ChartStyle` keeps its priority over the theme.

function test_chart_theme()
@testset "the chart renderer follows the scales of the appearance" begin
    chart = _line_chart()
    _projection(theme) = ChainingProjection(
        ChartToChartPlot(),
        ChartPlotToGraphicsCanvas(; measure = FixedMeasure(8, 12, 4, 0),
                                  width = 600, height = 400, theme))
    draw(theme) = collect_font_sizes(print_document(_projection(theme), nothing, chart,
                                                     PrinterContext()).output)

    plain = draw(nothing)
    @test !isempty(plain)
    @test sort(unique(plain)) == [14, 16]

    theme = get_scaled_theme!(Appearance(font_scale = 1.5), ChartTheme)
    large = draw(theme)
    @test large == round.(Int, plain .* 1.5)
    @test sort(unique(large)) == [21, 24]
end

@testset "a renderer with no theme holds the default values, and a theme scales a length" begin
    p = ChartPlotToGraphicsCanvas(measure = FixedMeasure(8, 12, 4, 0))
    @test unwrap_cell(p.style).padding == 8

    scaled = ChartPlotToGraphicsCanvas(measure = FixedMeasure(8, 12, 4, 0),
                                       theme = get_scaled_theme!(Appearance(spacing_scale = 2.0),
                                                                 ChartTheme))
    @test unwrap_cell(scaled.style).padding == 16
end

@testset "a chart's own legend font reaches the legend text" begin
    styled = Chart("Signal",
        [ChartLineSeries("sin", collect(0.0:0.05:10.0), sin.(0.0:0.05:10.0))];
        style = ChartStyle(; legend_font = StyleFont(font_ubuntu_bold_16.filename, 30)))
    projection = ChainingProjection(ChartToChartPlot(),
        ChartPlotToGraphicsCanvas(; measure = FixedMeasure(8, 12, 4, 0)))
    canvas = print_document(projection, projection, styled, PrinterContext()).output
    @test 30 in collect_font_sizes(canvas)
end
end
