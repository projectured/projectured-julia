# Graph domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [projection-system.md](../../kernel/projection-system.md), [graphics.md](../../platform/graphics/graphics.md)

`ProjecturedGraph` holds node-and-edge diagrams in which each vertex holds a document of any domain. This document says how a graph becomes a picture in two stages, where a layout engine plugs in and when the engine is chosen, and how the highlight that `fsm` and `process` reuse repaints without a new layout. [graph-layout.md](graph-layout.md) describes the engines themselves.

<img width="396" alt="Graph example" src="../../../asset/image/example/graph.png">

## How it works

### The documents

| Document | What it holds |
| --- | --- |
| `GraphGraph` | `vertices`, `edges`, the presentation fields `highlight_vertex` and `highlight_edge`, and `constraints`, the places that a drag gave its vertices |
| `GraphVertex` | `content`, a document of any domain: a table, a JSON object, another graph |
| `GraphEdge` | `source` and `target` vertices, `directed`, an optional `label` document, and `visible`, whether it draws a line |
| `GraphLayout` | `vertex_layouts`, `edge_layouts`, the two highlights, `engine`, the name of the engine that placed it, `graph`, the graph it places, `drag`, the drag of a vertex as view state, `zoom`, the zoom of the layout as view state, and `edge_shape`, the shape of the edges that the menu of the graph chose, as view state |
| `VertexLayout`, `EdgeLayout` | the box `(x, y, w, h)` of one vertex; the route of one edge as a list of points |
| `GraphConstraint` | a `kind` and a `payload` for one vertex, such as a pin or a start |

An edge holds its two vertices by identity, not by index. So a reorder of `vertices` keeps every edge, and a layout engine keys each vertex by its `objectid`. `GraphGraph` is the content. `GraphLayout` is the output of the first stage and holds the computed geometry, as `ChartPlot` does against `Chart`. The graph holds coordinates only as `constraints`: the pin of each vertex that the person dropped, and the start of each other vertex, which a drop writes.

The domain has no `@domain` call and no `@gestures` table. `GraphDocument` is declared by hand. No gesture adds or removes a vertex or an edge, and a drag moves a vertex.

### The chain

```
GraphGraph ──GraphGraphToGraphLayout──▶ GraphLayout ──GraphLayoutToGraphicsCanvas──▶ GraphicsCanvas
```

1. **Size, then place.** `GraphGraphToGraphLayout(engine; extent, border, constraints)` prints the `content` of each vertex through the recursion into a canvas and reads its width and height. The content gets no room on either axis, so it takes the size that it needs: a content that fills the room it gets, such as a table, would otherwise take all the room of the graph. The label of an edge gets no room either. One computed cell then calls `layout_graph` with those sizes. The cell reads the vertex list, the edge list, the sizes and the constraints, so the engine runs again only when one of them changes. `constraints` is a function of the graph, because a constraint names a vertex, and the vertices exist only when there is a document. The engine gets these constraints first and `graph.constraints` after them, so a pin that the person dropped wins over a pin of the projection. The stage keeps the corner of each vertex that the engine placed by itself in the last run, and gives it to the next run as a `:start` before all other constraints, when the engine takes a start. So an edit that changes the size of a box moves only the boxes that overlap after it, and a new vertex is placed among the others. A vertex that a pin or a start placed keeps no corner, so the undo of a drop puts the vertex back where the engine places it. The corners live in the print, so a new print lays out the graph from the start.
2. **Draw.** `GraphLayoutToGraphicsCanvas(; theme, edge_shape)` draws the edges first, with an arrowhead when `directed` is true; see "The edges". It prints each edge `label` and centres it on the middle of the line of the edge by arc length. It then draws each box as a rounded `GraphicsRect`, larger than the vertex by the padding of the theme on each side, with the content canvas on top.

The size of the output canvas is a computed cell over the drawing: the right and bottom edges of the boxes, of the highlight ring and of the line of each edge. So a vertical layout above a graph reserves the right height, and the height grows when the vertices arrive after the first print or when a zoom spreads them.

**The content prints twice.** The first stage prints each content to measure it, and the second stage prints it again to draw it. Nothing caches the first print for the second. A large content in a vertex costs two prints.

`GraphToGraphics(engine = make_deferred_layout_engine(); extent, border, constraints, theme, edge_shape)` returns the chain of the two stages, a `ChainingProjection`. The two stages have no recursion of their own. `make_graph_projection_example` wraps them in a `NestingProjection` with a dispatcher for the content types. The natural renderer gives itself as the recursion, so a vertex content draws as it draws anywhere else.

### The scroll pane

A graph view holds itself in a `WidgetScrollPane`, so a large graph scrolls where it is made, not in the tab or the card that shows it. `make_scrolling_graph_projection(stages; measure, widget_theme)` makes this view from a chain such as `GraphToGraphics()`:

```julia
make_scrolling_graph_projection(GraphToGraphics(); measure)
```

- The stage `GraphGraphToWidgetScrollPane` puts the graph, by identity, in a pane. The pane takes the room that its host offers and shows a bar only while the graph is larger than its view, so a small graph looks as it does without a pane.
- The pane prints the graph and its scroll bars through its recursion. In the natural renderer that recursion would send the graph back to the row of the graph, which would make a pane again. So the projection nests a dispatch under the pane: the graph goes to the graph stages, a scroll bar to its printer, and only the content of a vertex goes on to the outer recursion.
- The pane gives Ctrl and the wheel to the graph first and never scrolls on Ctrl, so the zoom of the layout works in the pane. A plain turn that the graph does not take scrolls the pane.
- The natural row of `GraphGraph` and `make_graph_projection_example` use it. `GraphToGraphics` stays the plain chain, so a host that embeds a graph in a widget of its own decides for itself.

**A graph is transparent.** The drawing paints only lines, labels and boxes, and the pane of a graph paints no fill (`WidgetStyle(; content_color = color_transparent)`). The host paints the background: a tab page, a card or a window.

### The edges

The drawing paints a box larger than the box that the engine places: the padding of the theme, and the ring of a highlighted vertex. So the drawing moves the whole layout right and down by this margin, and a box at the corner (0, 0) of the layout has its frame inside the canvas, where a host that clips does not cut it. And the drawing, not the engine, decides where an edge ends:

1. The line starts at the centre of the drawn box of the source, passes through the bends of the route, and ends at the centre of the drawn box of the target. The two end points of the route are not drawn. So a route that ends on the border of a box (`GridEmbedding`, `FruchtermanReingoldLayout`) and a route that ends at its centre (`AdaptagramsLayout`) draw the same way.
2. The drawing cuts the line where it leaves the painted rectangle of the source and where it enters the painted rectangle of the target. The rectangle is the box with its padding, never with a ring. So the arrowhead touches the box. The cut ignores the rounded corner, so the gap at a corner is at most 2 px.
3. When no part of the line is outside both rectangles, the two boxes overlap, and the drawing draws no line for that edge.
4. A vertex with a ring, of the highlight or of the light, does not change its edges. The drawing paints the ring over the end of each line, so as it paints a line, it cuts the line where it enters the ring: a straight line along its last segment, and a curve in its first or last span, split there. The rest of the line, and the label that sits on it, stay where they are. The cell of the edges reads no highlight and no light, so a move of the light calculates no edge again.

`edge_shape` selects the shape of the line:

- `:straight`, the default, draws a `GraphicsPolyline` through the points.
- `:curved` draws a `GraphicsSpline` of kind `:bezier` through the bends of the route, from a side port of the source to a side port of the target. Each end takes the side that the line from the centre to the next point crosses. The ends on one side of one box are sorted by their next points, from left to right on a top or a bottom side and from top to bottom on a left or a right side, and the `k` ends of a side stand at `1/(k+1)`, …, `k/(k+1)` of it. So one end stands at the middle of its side, and two ends of one side do not cross near the box. This is how draw.io and yEd place the ends; Graphviz, Cytoscape and Mermaid aim a straight line at the centre, as `:straight` does. At each end, the curve leaves the box at a right angle to its side, and its control point is half of the span along that direction. At a bend, the curve keeps the direction from the point before to the point after, as a Catmull-Rom spline does, and its control point is a third of the span. A curve takes one sample for about each 6 px of a span, from 12 to 64 samples, and the label sits on the samples.

```julia
GraphToGraphics(; edge_shape = :curved)
make_graph_projection_example(edge_shape = :curved)
```

**The menu of the graph switches the shape.** A right click on a graph opens the menu "Show the menu of the graph" of its `GraphLayout`, with the items "Straight edges" and "Curved edges". A right click on the content of a vertex shows it too, as an outer layer of the menu of that content. An item writes `GraphLayout.edge_shape`, which overrides the keyword. It is view state, as the zoom is: no undo records it, and a new print of the graph starts from the keyword again. The menu offers both items, because a gesture table gets the document and not the projection, so the menu does not know the shape that the keyword gave.

The geometry of each edge is one computed cell, `drawn_edges`. The element list and the size of the canvas read it.

### Selection and clicks

The first stage maps `vertices[i].rest` to `vertex_layouts[i].vertex.rest` and back, and `edges[j].rest` to `edge_layouts[j].edge.rest`. The second stage maps `vertex_layouts[i].vertex.content.rest` forward through the IO map of that content. A reference to a whole vertex, `vertex_layouts[i].vertex`, maps forward to the box element in the drawing. An annotation that anchors beside a node uses this.

The second stage maps no reference backward. Its reader re-roots instead:

- A left click inside a box goes to the reader of that content, with the point moved into the frame of the content. A left press goes there first too, and starts the drag of the vertex when the content does not take it; see "The drag of a vertex". A `ReplaceSelectionOperation` that comes back is rooted under `vertex_layouts[i].vertex.content`, and so is any other operation that names its part by a path of its own (`operation_reference`), such as the open of the menu of a part, with the types of the nodes of that path. An operation for which `is_self_contained_operation` is true passes unchanged. The reader drops every other operation. A key goes the same way to the content that holds the caret.
- A key goes to the reader of each content in turn, and the first answer wins.

An edge is a decoration: a click on its line selects nothing. Its label is a part, as the content of a vertex is: the second stage maps `edge_layouts[j].edge.label.rest` forward through the IO map of the label, a click and a point on the label go to the label in the frame of its canvas, and a key goes to the labels after the contents of the vertices. So a person edits the text of a label as the text of a vertex.

```julia
@reference vertices[2].content.entries[1].value   # a value inside the JSON of vertex 2
```

### The drag of a vertex

A plain left press on the box of a vertex, its content or the padding around it, that the content does not take, writes `GraphLayout.drag` with the vertex and the point. No drag is on yet, so a release before the pointer moves is a click. A move of 5 pixels with the button held starts the drag: the graph answers `StartDragOperation` and the closed hand pointer, and the drag wrapper then sends it `DragMove`, `DragEnd` and `DragCancel` by its path.

- **A move** writes the offset of the drag. Only the drawing reads it, through one cell of the started drag that the element list and the size of the canvas read, so the drawing moves the box, its content and its edges, which lose the bends of their routes, and the engine does not run. A press that has not become a drag leaves that cell at `nothing`, so it draws nothing again. The dragged box is drawn over the others.
- **The release** writes one edit, `ReplaceReferencedValueOperation(graph, "constraints", …)`: the constraints of other kinds and the pins of the other vertices stay, the dragged vertex gets a `:pin` at its new corner, and each other vertex without a pin gets a `:start` at its corner in the layout. A constraint holds a corner of the layout, so the pin is the corner of the release through the inverse of the zoom. The engine runs one time. Undo takes the edit back.
- **Escape**, a loss of focus, or a move with no button held cancels the drag, and the vertex goes back.

The hit tests, the drag and the routed changes read the boxes where the drawing draws them, with the zoom and the drag, from the cell `drawn_boxes` of the IO map.

A part of a content that takes a press keeps it, such as the edge of a column of a table. The drag wrapper then sends the parts of that drag by the path of the part, and the drawing gives a change whose route leads into a vertex to its content, in the frame of its canvas (`get_child_iomaps`, `read_child_by_route`). The drag of a vertex and the drag of its content do not mix. Where two boxes overlap, the box on top takes the press, the click and the point.

### The zoom of the layout

Ctrl and the wheel over a graph zoom its layout, not its pixels. The zoom moves the centre of each box and each bend of a route. A box keeps its size, and its content and its fonts do not change.

- A notch multiplies the scale by 1.15, inside 0.25 … 4. A turn away from the person zooms in. A notch at a limit answers `nothing`.
- The content of the vertex under the pointer reads the turn first, in the frame of its canvas, so a content that zooms keeps it. A turn without Ctrl does not zoom.
- `GraphLayout.zoom` holds the zoom as view state: `nothing`, or `(scale, shift)`. The drawing draws the centre `c` of a box at `scale .* c .+ shift`. Each notch writes the scale and the shift together, so that the top-left corner of the drawing stays where it is. A drop changes neither, so a dropped vertex stays where the person put it.
- A notch answers the write of the zoom wrapped in `KeepPointOperation`, with the move of the point under the pointer: the move of the box under it, or else of the point of the layout under it. The scroll pane around the graph scrolls by that move, so the part under the pointer stays where it is while the drawing is larger than the view. A graph that fits in its view grows from its top-left corner until it fills the view.
- If a box would be drawn left of or above the drawing, for example after the engine placed a new vertex there, the drawing moves as a whole, at every zoom.
- The engine does not run again. A zoom changes only the drawing and the size of the canvas, so a graph in a scroll pane gets more room to scroll.

### The layout engine seam

`layout_graph(engine, graph, sizes, constraints; extent, border)` returns the positions and the routes, keyed by `objectid`. The call reads no cell, so the first stage can hold it in one computed cell. `GridEmbedding` and `FruchtermanReingoldLayout` are in this package; `AdaptagramsLayout` is in `ProjecturedAdaptagrams`, see [adaptagrams.md](../../adapter/adaptagrams/adaptagrams.md). Each engine lists the constraint kinds it implements, and `check_constraints` throws an `ArgumentError` for any other kind. [graph-layout.md](graph-layout.md) has the table of engines and constraints.

`extent` and `border` are fields of the projection, not of the engine. Two panes that show one graph have two projections, and so two extents.

### The deferred choice of an engine

`make_deferred_layout_engine(; orthogonal)` returns a `DeferredLayout`. It becomes a real engine in each call of `layout_graph`, through `resolve_layout_engine`:

1. If a package registered a factory with `register_layout_engine!`, the factory makes the engine.
2. If not, `make_pure_julia_layout_engine(vertex_count)` returns `FruchtermanReingoldLayout`, for every size.

The choice is made when the layout runs, not when the projection is built, because an `Example` builds its projection at module load. At that time an optional engine package is not loaded yet. The first stage writes the name of the engine that ran into `GraphLayout.engine`, so a view can show it and a test can assert it.

`register_layout_engine!` writes the factory into a `Ref`. It does not add a method, because a method added during precompilation is a fatal overwrite.

`orthogonal = true` selects right-angled routes in an engine that can route them. The pure-Julia engines ignore the flag and route every edge as a straight line.

### The highlight

`highlight_vertex` and `highlight_edge` of `GraphGraph` name one vertex and one edge by identity. The first stage passes them to `GraphLayout` as computed cells, and the cell that runs the engine does not read them. The second stage reads them only in the cell that builds the element list. It draws a ring behind the highlighted box and draws the highlighted edge again with a thicker stroke. So a change of a highlight builds the element list again, but it prints no content and runs no engine.

The vertex under the pointer lights the same way. The first stage maps the mouse target of the graph forward into the layout, and the second stage keeps the index of the vertex that the mouse target of the layout names in a cell of its own, so a move inside one vertex draws nothing again. It draws a ring of `light` behind the vertex and behind each vertex that an edge joins to it, and draws each of its edges again in `light_edge`. An edge that is not `visible` draws no line and no label, and still joins its vertices in the layout and in the light: the map of a study gives a decision such edges to the items that it settled, so the pointer on the decision lights them and no line crosses the map.

A producer sets the two fields as computed cells over the state it follows. Two domains do this, and each builds a `GraphGraph` in a stage of its own:

- `FsmDiagramToGraph` makes one vertex for each state and one edge for each transition with a target. The highlights follow `FsmDiagram.live_state` and `live_transition`; see [fsm.md](../fsm/fsm.md).
- `ProcessDiagramToGraph` makes one vertex for each step, decision, loop and jump, and synthesizes the edges from the nesting. The highlights follow the current and the previous node of a debug session; see [process.md](../process/process.md).

In both, the content of a vertex is the domain node itself, held by identity. So a click on a box selects the real state or step through the path above, and the domain adds no code for drawing or for clicks.

### The theme

`GraphTheme` holds the look of the drawing: the fill, the border, the border width, the radius and the padding of the box of a node; the color and the width of an edge and the size of its arrowhead; the color, the width and the gap of the ring of a highlight; and the colors of the light of the vertex under the pointer. The line and the arrowhead of an edge take the role `text_muted`, almost black, and the border of a box takes `border_strong`, the line of a card. Each value has the default that the domain draws with no appearance, and each field has a docstring, which the appearance tab shows under the name of the field. `GraphLayoutToGraphicsCanvas(; theme)` takes a `GraphTheme`, scaled or not, and holds all values as one `NamedTuple` and no theme, which a print reads once; with no theme it holds the default values. `GraphToGraphics` passes its `theme` on. The natural registration gives the scaled theme of the `Appearance` of the editor, so the drawing follows its scales, and the appearance tab shows a section for `GraphTheme`. The content of a node follows the themes of its own domain.

### The tooltip of a part

A graph says, for a vertex under the pointer, its edges out and in, and its label when its content is a string ([tooltip.md](../../platform/tooltip/tooltip.md)).

## How it fits

`ProjecturedGraph` depends on the kernel and the platform. `ProjecturedFSM` and `ProjecturedProcess` depend on it, and `ProjecturedAdaptagrams` adds an engine to it.

The `__init__` in `GraphLayoutToGraphics.jl` calls `register_natural_graphics!(:graph, …)`. It maps `GraphGraph` to the two stages with the default engine, `DeferredLayout`, in a scroll pane of their own, so a tab draws a graph as a diagram that scrolls when it is large. The package registers no natural domain row: a graph has no text form, no parser and no file type.

## Design decisions

- **The computed geometry is a separate document, and the places that the person gave are in the graph.** `GraphLayout` holds the positions that an engine computed. A drop is an edit that the person keeps and takes back, so its pins and starts are `constraints` of `GraphGraph`, and every view of the graph shows them. See [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md) and [the-mouse-drags-a-vertex-of-a-graph.md](../../../../plan/done/the-mouse-drags-a-vertex-of-a-graph.md).
- **The default engine defers its choice.** `GraphGraphToGraphLayout()`, `GraphToGraphics()` and `make_graph_projection_example` use `DeferredLayout`: a force-directed placement shows the structure of a graph, and a grid shows only its order. A layout run costs about 0.13 s at 300 vertices. See [the-mouse-drags-a-vertex-of-a-graph.md](../../../../plan/done/the-mouse-drags-a-vertex-of-a-graph.md).
- **A vertex holds any document.** The content prints through the recursion of the caller, so a table, a card or another graph can be a node with no code in this package. See [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md).
- **An engine throws on a constraint that it does not implement.** A picture does not show whether a pin was kept or dropped, so a silent drop is the worst answer. See [plan/done/graph-layout-engines.md](../../../../plan/done/graph-layout-engines.md).
- **The pure-Julia engines are ports.** They must draw the picture that the C++ original draws, so each C++ file has one Julia file with the same name and order. See [plan/done/graph-layout-engines.md](../../../../plan/done/graph-layout-engines.md).
- **The engine is chosen when the layout runs.** A projection that chose at construction would keep the fallback engine for the whole session. See [plan/done/graph-layout-engines.md](../../../../plan/done/graph-layout-engines.md).
- **A highlight goes around the layout cell.** A running state machine moves its marker many times a second, and a force-directed layout for each move costs too much. See [plan/done/state-machine-domain.md](../../../../plan/done/state-machine-domain.md).
- **The native engine is a separate package.** Its native dependency stays out of every other package. See [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md).
- **The drawing cuts an edge, not the engine.** Only the drawing knows the padding and the ring that it paints around a box. One rule then serves each engine, a dragged box and a zoom. See [the-edges-of-a-graph-reach-their-boxes-curve-and-zoom.md](../../../../plan/done/the-edges-of-a-graph-reach-their-boxes-curve-and-zoom.md).
- **A graph scrolls where it is made.** A tab page gets no scroll pane, so the graph view holds its own. The pane shows a bar only while the graph is larger than its view, so no rule for small and large graphs is needed. See [a-graph-scrolls-in-its-own-pane-and-draws-dark-edges.md](../../../../plan/done/a-graph-scrolls-in-its-own-pane-and-draws-dark-edges.md).
- **A graph is transparent, and its host paints the background.** A background on the graph would also hide a fault of a pane that does not clip. See [a-graph-scrolls-in-its-own-pane-and-draws-dark-edges.md](../../../../plan/done/a-graph-scrolls-in-its-own-pane-and-draws-dark-edges.md).
- **The zoom keeps a scale and a shift.** A shift that the drawing computed from the positions at each print moved the whole drawing at a drop of the vertex at the top-left corner. See [the-edges-of-a-graph-reach-their-boxes-curve-and-zoom.md](../../../../plan/done/the-edges-of-a-graph-reach-their-boxes-curve-and-zoom.md).
- **A ring cuts a line, and does not change it.** A curve that took its ends from the rim of a ring could leave from another side near a corner, so the light under the pointer changed the shape of the edges and moved their labels. See [the-edges-of-a-graph-end-at-side-ports.md](../../../../plan/done/the-edges-of-a-graph-end-at-side-ports.md).
- **A curved edge ends at a side port, and a straight edge aims at the centres.** The ends of curves that aimed at the centres stood close together on one side, or at a corner. A straight line that aims at the centre is easy to read, and a port would turn it away from the centre. See [the-edges-of-a-graph-end-at-side-ports.md](../../../../plan/done/the-edges-of-a-graph-end-at-side-ports.md).

## Usage

```julia
a = GraphVertex(JsonString("client"))
b = GraphVertex(JsonObject("id" => JsonNumber(42)))
graph = GraphGraph([a, b], [GraphEdge(a, b; label = JsonString("uses"))])
projection = make_graph_projection_example(engine = make_deferred_layout_engine())
run_example(graph, projection; name = "graph")
```

- Examples: `graph_example`, a table, a JSON object and an XML element joined by edges, in `example/domain/graph/`. `graph_services_example`, the fifteen services of a small shop, each the name of a service as a line of text, and the calls between them as directed edges with labels, drawn with curves: it is larger than a window when zoomed in, so it shows the zoom and the scroll. The atomic catalog has the entries `graph/graph` and `graph/layout`. `graph_adaptagrams_example` is in `ProjecturedAdaptagramsExample`.
- Test: `test_graph()` runs the layering guard, `test_graph_projection()`, `test_fruchterman_reingold_layout()`, `test_graph_theme()`, `test_graph_vertex_drag()`, `test_graph_layout_zoom()`, `test_graph_scroll_pane()` and `test_graph_context_menu()`.

## Limits

- An edge itself is not selectable; its label is. No gesture adds or removes a vertex or an edge. [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md) lists these as future work.
- A graph that a view makes keeps the places of a drop only while the view lives: the diagram of a state machine, a process diagram, the topology of a network simulation. The pins go on that graph, and a reprint makes a new graph. After a reprint, undo of such a drop has no visible result.
- During a drag, the edges of the dragged vertex lose the bends of their routes. An engine that routes around boxes routes them again at the drop.
- No command removes the pins and the starts; undo is the way back.
- A zoom keeps the point under the pointer only through a scroll pane, and only while the drawing is larger than the view. A graph that a host draws with `GraphToGraphics` alone, outside a scroll pane, grows from its top-left corner, and does not scroll when a zoom makes it larger than its room.
- The zoom maps the centre of a box, so a box that grows by `d` px at the zoom `scale` moves its left edge by `(scale - 1) * d / 2` px: an edit in a zoomed box moves the box a little.
- The pane of a graph does not keep its scroll position when the graph view is printed again, as the zoom does not.
- A zoom under 1 can make boxes overlap, and can move a bend of a routed edge into a box. The zoom lives in `GraphLayout`, so a reprint of the graph starts at no zoom.
- A layout corner is an integer, so at a zoom a dropped vertex is drawn at most `scale / 2` px from the place of the release.
- `GraphLayout.direction`, `node_sep`, `rank_sep`, `VertexLayout.pinned` and the ports of `EdgeLayout` are fields that no stage reads. The first stage writes constants into them.
- A self-loop edge has no part outside its box, so the drawing draws no line for it.
- The registered factory is not a cell, so the layout cell does not depend on it. A graph that is drawn before `ProjecturedAdaptagrams` loads keeps its layout until its vertices, edges, sizes or constraints change.
- The constraint kinds `:align`, `:same_rank` and `:min_separation` have a name and no engine that implements them.
- The atom `graph/layout` is in the broken sets of `test/projectured/projection/CatalogTest.jl`. A `GraphLayout` printed alone has no recursion for the content of its vertices.
