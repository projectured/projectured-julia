# The sequence chart pipeline: SequenceChart → SequenceChartPlot → GraphicsCanvas,
# two stages chained.
#
# A sequence chart renders straight to graphics, so like the chart domain and
# unlike the syntax-backed ones it needs no recursion — nothing inside it is a
# foreign document. What it does need is a size: the fallback below applies when
# no parent layout has allocated one.

make_sequencechart_pipeline_example(; measure=truetype_measure_text,
                                    width::Integer=900, height::Integer=520) =
    ChainingProjection(
        SequenceChartToSequenceChartPlot(),
        SequenceChartPlotToGraphicsCanvas(measure=measure, width=width, height=height))

make_sequencechart_projection_example(; measure=truetype_measure_text) =
    make_sequencechart_pipeline_example(; measure=measure)

# Time running downward wants a taller canvas than one running across.
make_sequencechart_vertical_projection_example(; measure=truetype_measure_text) =
    make_sequencechart_pipeline_example(; measure=measure, width=620, height=700)

make_sequencechart_linear_projection_example(; measure=truetype_measure_text) =
    make_sequencechart_pipeline_example(; measure=measure)

make_sequencechart_large_projection_example(; measure=truetype_measure_text) =
    make_sequencechart_pipeline_example(; measure=measure)
