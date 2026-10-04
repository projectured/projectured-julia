# Fragment of `GraphModule` — the theme of the graph drawing: the box of a node,
# the line of an edge, and the ring of a highlight.

"""
    GraphTheme

The colors and the sizes of a graph drawing: the box of a node, the line of an
edge and the ring around a highlight.

The theme of `GraphLayoutToGraphicsCanvas`. `@theme` declares it, so
`ScaledGraphTheme` holds each value times its scale, and `GraphTheme()` is the
default theme.

The drawing holds the values of the theme, and no theme, in the `style` field of
the projection: one `NamedTuple` that its builder reads from a theme, scaled or
not; with no theme it holds the plain values of the default theme.
"""
@theme struct GraphTheme
    "The fill of the box of a node, under its content."
    node_fill::StyleColor = color_white
    "The border of the box of a node."
    node_border::StyleColor = color_solarized_content_darker
    "The width of the border of the box of a node."
    node_border_width::LineWidth = LineWidth(2)
    "The radius of the corners of the box of a node."
    node_radius::Radius = Radius(6)
    "The space between the content of a node and its box."
    node_padding::Spacing = Spacing(8)
    "The line of an edge and its arrowhead."
    edge::StyleColor = color_solarized_content_darker
    "The width of the line of an edge."
    edge_width::LineWidth = LineWidth(2)
    "The length of the arrowhead of a directed edge."
    arrow_size::ControlSize = ControlSize(10)
    "The ring around a highlighted node, and the line over a highlighted edge."
    highlight::StyleColor = color_solarized_yellow
    "The width of the ring of a highlighted node and of the line of a highlighted edge."
    highlight_width::LineWidth = LineWidth(3)
    "The space between the box of a highlighted node and its ring."
    highlight_gap::Spacing = Spacing(3)
end
