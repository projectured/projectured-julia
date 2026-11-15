# The sequence chart pipeline: SequenceChart → SequenceChartPlot → GraphicsCanvas,
# the view that `make_sequence_chart_projection` builds.
#
# A sequence chart renders straight to graphics, and the view prints its buttons
# and bars through a recursion of its own, so it needs none from its host. What it
# does need is a size: the fallback below applies when no parent layout has
# allocated one.

make_sequencechart_pipeline_example(; measure=FontFileMeasure(),
                                    width::Integer=900, height::Integer=520) =
    make_sequence_chart_projection(; measure, width, height)

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
    w2g = WidgetToGraphics(; measure=measure)
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
