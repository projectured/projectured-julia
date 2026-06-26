"""
    make_layout_projection_example(; measure)

Project a tree of `HorizontalLayout` / `VerticalLayout` / `GridLayout` /
`FlowLayout` whose leaves are widgets. The dispatcher routes layout
nodes to their `…ToGraphicsCanvas` projections and any other document
(widgets in this example) to `WidgetToGraphics`.
"""
function make_layout_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_regular_24
    # Dark foreground — this example renders directly onto the backend's
    # default (light) background, without a `WidgetShell` to provide a
    # dark fill behind it.
    fg   = (0x22, 0x22, 0x2a, 0xff)
    SequentialProjection(
        RecursiveProjection(TypeDispatchingProjection(
            HorizontalLayout => HorizontalLayoutToGraphicsCanvas(),
            VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
            GridLayout       => GridLayoutToGraphicsCanvas(),
            FlowLayout       => FlowLayoutToGraphicsCanvas(),
            Any              => WidgetToGraphics(font; measure=measure),
        )),
    )
end

"""
    make_constraint_layout_projection_example(; measure)

Project a `ConstraintLayout` whose children are widgets. The dispatcher routes
the constraint layout to `ConstraintLayoutToGraphicsCanvas` and any other
document (the widgets) to `WidgetToGraphics`.
"""
function make_constraint_layout_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_regular_24
    SequentialProjection(
        RecursiveProjection(TypeDispatchingProjection(
            ConstraintLayout => ConstraintLayoutToGraphicsCanvas(),
            Any              => WidgetToGraphics(font; measure=measure),
        )),
    )
end
