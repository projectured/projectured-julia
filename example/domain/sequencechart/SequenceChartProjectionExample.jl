# The sequence chart pipeline: SequenceChart → SequenceChartPlot → GraphicsCanvas,
# two stages chained.
#
# A sequence chart renders straight to graphics, so like the chart domain and
# unlike the syntax-backed ones it needs no recursion — nothing inside it is a
# foreign document. What it does need is a size: the fallback below applies when
# no parent layout has allocated one.

make_sequencechart_pipeline_example(; measure=FontFileMeasure(),
                                    width::Integer=900, height::Integer=520) =
    ChainingProjection(
        SequenceChartToSequenceChartPlot(),
        SequenceChartPlotToGraphicsCanvas(measure=measure, width=width, height=height))

make_sequencechart_projection_example(; measure=FontFileMeasure()) =
    make_sequencechart_pipeline_example(; measure=measure)

# Time running downward wants a taller canvas than one running across.
make_sequencechart_vertical_projection_example(; measure=FontFileMeasure()) =
    make_sequencechart_pipeline_example(; measure=measure, width=620, height=700)

make_sequencechart_linear_projection_example(; measure=FontFileMeasure()) =
    make_sequencechart_pipeline_example(; measure=measure)

make_sequencechart_large_projection_example(; measure=FontFileMeasure()) =
    make_sequencechart_pipeline_example(; measure=measure)

# Embedding a sequence chart in anything that recurses its children takes one
# dispatch entry — which is also all it takes to open one as a pane tab.
function make_sequencechart_composite_projection_example(; measure=FontFileMeasure(),
                                                         width::Integer=880,
                                                         height::Integer=330)
    NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20),
        extra=Pair{Type,Any}[
            SequenceChart => make_sequencechart_pipeline_example(; measure=measure,
                                                                width=width, height=height)])
end

make_sequencechart_pair_projection_example(; measure=FontFileMeasure()) =
    make_sequencechart_composite_projection_example(; measure=measure)

# The inspector: the chart renders through its own pipeline, and the lane through
# ObjectToWidget's reflection-driven form, whose controls write back to the
# lane's own cells. Two projections over one document, which is what makes a
# chart's properties editable without a bespoke property editor.
function make_sequencechart_inspector_projection_example(; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    w2g = WidgetToGraphics(font; measure=measure)
    form = ChainingProjection(
        ObjectToWidget(fields=[:label, :visible]),
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            make_object_field_widget_dispatch(w2g.dispatch),
            Pair{Type,Any}[TextBlock => TextToGraphics(measure=measure)]))))
    NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20),
        extra=Pair{Type,Any}[
            SequenceChart => make_sequencechart_pipeline_example(; measure=measure,
                                                                width=600, height=420),
            SequenceChartAxis => form])
end
