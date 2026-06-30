# Table examples render a `WidgetTable` (the single table abstraction). The
# renderer delegates positioning to a GridLayout and recurses each cell document
# through the projection, so the recursion must dispatch widgets, layouts, and
# each cell's own domain to graphics. That is exactly what `NaturalToGraphics`
# is — so the examples are just `NaturalToGraphics` with the sans font the
# workbench/table chrome uses. JSON/Primitive/Math cells render through the
# shared syntax fabric (no word-wrap), as before.
make_table_projection_example(; measure=truetype_measure_text) =
    NaturalToGraphics(measure=measure, font=font_ubuntu_regular_20)

make_math_table_projection_example(; measure=truetype_measure_text) =
    NaturalToGraphics(measure=measure, font=font_ubuntu_regular_20)
