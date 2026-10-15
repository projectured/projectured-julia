# The natural projection example: just `NaturalToGraphics`, the generic
# render-almost-anything-to-graphics factory, which a tab of the editor draws its
# document with. No per-domain table is assembled here — that is the whole point:
# each document finds the row that its slice registers.
make_natural_projection_example(; measure=FontFileMeasure()) =
    NaturalToGraphics(measure=measure)
