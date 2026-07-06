"""
    make_layout_projection_example(; measure)

Project a tree of `HorizontalLayout` / `VerticalLayout` / `GridLayout` /
`FlowLayout` whose leaves are widgets. The dispatcher routes layout
nodes to their `…ToGraphicsCanvas` projections and any other document
(widgets in this example) to `WidgetToGraphics`.
"""
function make_layout_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_regular_20
    # Dark foreground — this example renders directly onto the backend's
    # default (light) background, without a `WidgetShell` to provide a
    # dark fill behind it.
    fg   = (0x22, 0x22, 0x2a, 0xff)
    ChainingProjection(
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
    make_constraint_layout_projection_example(; measure, solver)

Project a `ConstraintLayout` whose children are widgets. The dispatcher routes
the constraint layout to `ConstraintLayoutToGraphicsCanvas` and any other
document (the widgets) to `WidgetToGraphics`.

`solver` defaults to the dependency-free `FallbackConstraintSolver` (children
stack at the origin — a valid but unsolved layout). Pass a `TulipConstraintSolver`
from the opt-in `ProjecturedTulip` package for real constraint solving; the
`constraint_layout_tulip` example in `ProjecturedTulipExample` does exactly that.
"""
function make_constraint_layout_projection_example(; measure=truetype_measure_text,
                                                   solver=FallbackConstraintSolver())
    font = font_ubuntu_regular_20
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            ConstraintLayout => ConstraintLayoutToGraphicsCanvas(solver=solver),
            Any              => WidgetToGraphics(font; measure=measure),
        )),
    )
end
