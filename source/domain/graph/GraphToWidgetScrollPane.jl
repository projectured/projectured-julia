# Fragment of `GraphModule`.
#
# GraphGraph → WidgetScrollPane: a graph view holds itself in a scroll pane, so the
# graph scrolls where it is made, not in the tab or the card that shows it. The pane
# shows a bar only while the graph is larger than its view, so a small graph looks
# as it does without a pane.
#
# The pane holds the graph by identity, and its printer prints the graph and its
# scroll bars through the recursion that it gets. In the natural renderer that
# recursion sends a graph back to the row of the graph, which would make a pane
# again. So `make_scrolling_graph_projection` nests a dispatch under the pane: the
# graph goes to the graph stages and a scroll bar to its printer, and only the
# content of a vertex goes on to the outer recursion.

"""
    GraphGraphToWidgetScrollPane()

Put a `GraphGraph` in a `WidgetScrollPane` that paints no fill, so the graph stays
transparent and its host paints the background. The selection peels the one step
that this stage owns, `content`, and hands the rest on.
"""
struct GraphGraphToWidgetScrollPane <: Projection end

@iomap struct GraphGraphToWidgetScrollPaneIoMap
    projection::Any
    input::Any
    output::Any
end

function print_document(p::GraphGraphToWidgetScrollPane, recursion, graph::GraphGraph, ctx)
    iomap_cell = Cell(nothing)
    # Positional: content, position, size, scroll_position, follow_end, wheel_run,
    # vertical_scroll_bar, horizontal_scroll_bar, visible, margin, border, padding,
    # style, tooltip, selection, mouse_target.
    pane = WidgetScrollPane(Cell(graph), Cell(nothing), Cell(nothing), Cell(Point2D(0, 0)), Cell(nothing),
                            Cell(nothing), Cell(:auto), Cell(:auto), Cell(true),
                            Cell(nothing), Cell(nothing), Cell(nothing),
                            Cell(WidgetStyle(; content_color = color_transparent)), Cell(nothing),
                            Cell(@computation let im = iomap_cell[]
                                im === nothing ? nothing : map_reference_forward(p, im, graph.selection)
                            end),
                            Cell(@computation map_mouse_target_forward(graph, path -> let im = iomap_cell[]
                                im === nothing ? nothing : map_reference_forward(p, im, path)
                            end)))
    iomap = GraphGraphToWidgetScrollPaneIoMap(p, graph, pane)
    iomap_cell[] = iomap
    iomap
end

# anything... ↔ content.anything...
#
# A reference can come without its node types, for example the path that the pane
# builds back from a point. The graph is the document on each side, so the stage
# gives a reference its types from the graph before it builds a typed one.
function map_reference_forward(::GraphGraphToWidgetScrollPane, iomap, reference)
    reference === nothing && return nothing
    reference = _type_graph_reference(iomap.input, reference)
    # A path that the graph can not type goes on as the pane takes it, untyped.
    is_fully_typed_reference(reference) ||
        return ConcreteReference(FieldReferenceStep("content"), strip_reference_types(reference))
    @reference_case reference begin
        ∅ => @reference ::WidgetScrollPane
        rest... => (@reference ::WidgetScrollPane.content::GraphGraph.^(rest))
    end
end

function map_reference_backward(::GraphGraphToWidgetScrollPane, iomap, reference)
    reference === nothing && return nothing
    path = strip_reference_types(reference)
    path isa EmptyReference && return @reference ::GraphGraph
    path isa ConcreteReference || return nothing
    (path.head isa FieldReferenceStep && path.head.name == "content") || return nothing
    reference isa ConcreteReference && is_fully_typed_reference(reference.tail) && return reference.tail
    _type_graph_reference(iomap.input, path.tail)
end

# `reference`, a path in `graph`, with the node types that `graph` gives it. A step
# that the graph can not type, such as a step into the output of a content, stays
# untyped.
_type_graph_reference(graph, reference) =
    is_fully_typed_reference(reference) ? reference :
    annotate_reference_types(graph, strip_reference_types(reference))

"""
    make_scrolling_graph_projection(stages = GraphToGraphics(); measure,
                                    widget_theme = WidgetTheme()) -> Projection

A graph view that scrolls: `stages`, a chain from a `GraphGraph` to a
`GraphicsCanvas` such as `GraphToGraphics()`, inside a `WidgetScrollPane` that the
projection makes. The pane takes the room that its host offers and shows a bar only
while the graph is larger, so a small graph looks as it does without a pane. Ctrl
and the wheel still zoom the layout, and a plain turn that the graph does not take
scrolls the pane. `measure` and `widget_theme` are those of the pane.

The content of a vertex prints through the recursion that encloses the projection,
for example a `NestingProjection`.
"""
make_scrolling_graph_projection(stages = GraphToGraphics(); measure::TextMeasure,
                                widget_theme = WidgetTheme()) =
    NestingProjection(ChainingProjection(GraphGraphToWidgetScrollPane(),
                                         WidgetScrollPaneToGraphicsCanvas(widget_theme; measure)),
                      TypeDispatchingProjection(GraphGraph => stages,
                                                WidgetScrollBar => WidgetScrollBarToGraphicsCanvas(widget_theme)))
