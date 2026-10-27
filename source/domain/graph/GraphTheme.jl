# Fragment of `GraphModule` — the theme of the graph drawing: the box of a node,
# the line of an edge, the border of a highlight, the light of the node under the
# pointer, and the rectangle behind the label of an edge.

"""
    GraphTheme

The colors and the sizes of a graph drawing: the box of a node, the line of an
edge, the border of a highlighted box, the light of the node under the pointer,
and the rectangle behind the label of an edge.

The theme of `GraphLayoutToGraphicsCanvas`. `@theme` declares it, so
`ScaledGraphTheme` holds each value times its scale, and `GraphTheme()` is the
default theme.

The drawing holds the values of the theme, and no theme, in the `style` field of
the projection: one `NamedTuple` that its builder reads from a theme, scaled or
not; with no theme it holds the plain values of the default theme.
"""
@theme struct GraphTheme
    "The fill of the box of a node, under its content."
    node_fill::ThemeColor = ColorRole(:surface)
    "The border of the box of a node."
    node_border::ThemeColor = ColorRole(:border_strong)
    "The width of the border of the box of a node."
    node_border_width::LineWidth = LineWidth(2)
    "The radius of the corners of the box of a node."
    node_radius::Radius = Radius(6)
    "The space between the content of a node and its box."
    node_padding::Spacing = Spacing(8)
    "The line of an edge and its arrowhead."
    edge::ThemeColor = ColorRole(:text_muted)
    "The width of the line of an edge."
    edge_width::LineWidth = LineWidth(2)
    "The length of the arrowhead of a directed edge."
    arrow_size::ControlSize = ControlSize(10)
    "The border of the box of a highlighted node, and the line over a highlighted edge."
    highlight::ThemeColor = ColorRole(:accent)
    "The width of the border of a highlighted or lit box, and of the line over a highlighted or lit edge."
    highlight_width::LineWidth = LineWidth(3)
    "The fill of the box of the node under the pointer."
    light::ThemeColor = ColorRole(:accent_tint)
    "The border of the boxes of the node under the pointer and of the nodes it joins, and the line over its edges."
    light_edge::ThemeColor = ColorRole(:focus_ring)
    "The rectangle behind the label of an edge, in the color of the page, which covers the lines under the label."
    label_fill::ThemeColor = ColorRole(:background)
    "The space between the label of an edge and the edge of its rectangle."
    label_padding::Spacing = Spacing(2)
end
