# The projection of the pivot examples: the natural renderer, which draws a
# `PivotTable` through the seam `make_graphics_projection` of the pivot domain,
# and the widgets and the cell documents inside it through its own rows.

"""
    make_pivot_projection_example(; measure = FontFileMeasure())

The natural renderer that draws a pivot: its bar of zones and its table.
"""
make_pivot_projection_example(; measure = FontFileMeasure()) =
    NaturalToGraphics(measure = measure, font = StyleFont("Ubuntu", 20))
