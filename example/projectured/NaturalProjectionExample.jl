# The natural projection example: just `NaturalToGraphics`, the generic
# render-almost-anything-to-graphics factory. No per-domain table is assembled
# here — that is the whole point. Paired with `make_natural_document_example`
# (a mixed-domain CellVector) it shows one projection rendering several domains
# and a collection combinator together.
make_natural_projection_example(; measure=measure_truetype_text) =
    NaturalToGraphics(measure=measure)
