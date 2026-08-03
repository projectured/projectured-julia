# The chart pipeline: Chart → ChartPlot → GraphicsCanvas, two stages chained.
#
# A chart renders straight to graphics, so unlike the syntax-backed domains it
# needs no recursion — nothing inside a chart is a foreign document. What it does
# need is a size: the fallback below applies when no parent layout has allocated
# one, which is why the standalone examples ask for a bigger canvas than the ones
# sharing a two-by-two grid.

make_chart_pipeline_example(; measure=truetype_measure_text,
                            width::Integer=760, height::Integer=460) =
    ChainingProjection(
        ChartToChartPlot(),
        ChartPlotToGraphicsCanvas(measure=measure, width=width, height=height))

make_chart_line_projection_example(; measure=truetype_measure_text) =
    make_chart_pipeline_example(; measure=measure)
make_chart_bar_projection_example(; measure=truetype_measure_text) =
    make_chart_pipeline_example(; measure=measure)
make_chart_histogram_projection_example(; measure=truetype_measure_text) =
    make_chart_pipeline_example(; measure=measure)
make_chart_scatter_projection_example(; measure=truetype_measure_text) =
    make_chart_pipeline_example(; measure=measure)

# The composite is a WidgetTable whose cells happen to be charts, so it renders
# through the natural projection with one extra dispatch entry. That entry is
# also all it takes to open a chart as a workbench tab or drop one into any other
# document that recurses its children.
function make_chart_projection_example(; measure=truetype_measure_text)
    NaturalToGraphics(measure=measure, font=font_ubuntu_regular_20,
        extra=Pair{Type,Any}[
            Chart => make_chart_pipeline_example(; measure=measure,
                                                 width=430, height=300)])
end
