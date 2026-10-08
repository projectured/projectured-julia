# The chart pipeline: Chart → ChartPlot → GraphicsCanvas, two stages chained.
#
# A chart renders straight to graphics, so unlike the syntax-backed domains it
# needs no recursion — nothing inside a chart is a foreign document. What it does
# need is a size: the fallback below applies when no parent layout has allocated
# one, which is why the standalone examples ask for a bigger canvas than the ones
# sharing a two-by-two grid.

make_chart_pipeline_example(; measure=FontFileMeasure(),
                            width::Integer=760, height::Integer=460) =
    ChainingProjection(
        ChartToChartPlot(),
        ChartPlotToGraphicsCanvas(measure=measure, width=width, height=height))

make_chart_line_projection_example(; measure=FontFileMeasure()) =
    make_chart_pipeline_example(; measure=measure)
make_chart_bar_projection_example(; measure=FontFileMeasure()) =
    make_chart_pipeline_example(; measure=measure)
make_chart_histogram_projection_example(; measure=FontFileMeasure()) =
    make_chart_pipeline_example(; measure=measure)
make_chart_scatter_projection_example(; measure=FontFileMeasure()) =
    make_chart_pipeline_example(; measure=measure)
make_chart_strip_projection_example(; measure=FontFileMeasure()) =
    make_chart_pipeline_example(; measure=measure)

# The composite is a WidgetTable whose cells happen to be charts, so it renders
# through the natural projection with one extra dispatch entry. That entry is
# also all it takes to open a chart as a pane tab or drop one into any other
# document that recurses its children.
function make_chart_projection_example(; measure=FontFileMeasure())
    NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20),
        extra=Pair{Type,Any}[
            Chart => make_chart_pipeline_example(; measure=measure,
                                                 width=430, height=300)])
end

# The inspector pane: the chart renders through the chart pipeline, and the
# series through ObjectToWidget's reflection-driven form, whose controls write
# back to the series' own cells. Two projections over one document — which is
# what makes a chart property editable without a bespoke property editor.
function make_chart_inspector_projection_example(; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    w2g = WidgetToGraphics(font; measure=measure)
    # Named fields, not reflection over everything: the data columns are not
    # properties, and a form with one row per sample would be both useless and,
    # at a million samples, unusable.
    form = ChainingProjection(
        ObjectToWidget(fields=[:label, :draw_style, :line_style, :line_width,
                               :symbol, :symbol_size, :visible]),
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            make_object_field_widget_dispatch(w2g.dispatch),
            Pair{Type,Any}[TextBlock => TextToGraphics(measure=measure)]))))
    NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20),
        extra=Pair{Type,Any}[
            Chart => make_chart_pipeline_example(; measure=measure, width=520, height=340),
            ChartSeries => form])
end
