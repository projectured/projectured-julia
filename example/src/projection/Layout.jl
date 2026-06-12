"""
    make_layout_projection_example(; measure)

Project a tree of `HorizontalLayout` / `VerticalLayout` / `GridLayout` /
`FlowLayout` whose leaves are widgets. The dispatcher routes layout
nodes to their `…ToGraphicsCanvas` projections and any other document
(widgets in this example) to `WidgetToGraphics`.
"""
function make_layout_projection_example(; measure=sdl_measure_text)
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
