# Graph domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [projection-system.md](../../kernel/projection-system.md), [graphics.md](../../platform/graphics/graphics.md)

`ProjecturedGraph` holds node-and-edge diagrams in which each vertex holds a document of any domain. This document says how a graph becomes a picture in two stages, where a layout engine plugs in and when the engine is chosen, and how the highlight that `fsm` and `process` reuse repaints without a new layout. [graph-layout.md](graph-layout.md) describes the engines themselves.

<img width="396" alt="Graph example" src="../../../asset/image/example/graph.png">

## How it works

### The documents

| Document | What it holds |
| --- | --- |
| `GraphGraph` | `vertices`, `edges`, and the presentation fields `highlight_vertex` and `highlight_edge` |
| `GraphVertex` | `content`, a document of any domain: a table, a JSON object, another graph |
| `GraphEdge` | `source` and `target` vertices, `directed`, and an optional `label` document |
| `GraphLayout` | `vertex_layouts`, `edge_layouts`, the two highlights, and `engine`, the name of the engine that placed it |
| `VertexLayout`, `EdgeLayout` | the box `(x, y, w, h)` of one vertex; the route of one edge as a list of points |
| `GraphConstraint` | a `kind` and a `payload` for one vertex, such as a pin |

An edge holds its two vertices by identity, not by index. So a reorder of `vertices` keeps every edge, and a layout engine keys each vertex by its `objectid`. `GraphGraph` is the content. `GraphLayout` is the output of the first stage and holds the geometry, so a saved graph has no coordinates. `ChartPlot` makes the same split against `Chart`.

The domain has no `@domain` call and no `@gestures` table. `GraphDocument` is declared by hand, and no gesture adds or removes a vertex or an edge.

### The chain

```
GraphGraph ──GraphGraphToGraphLayout──▶ GraphLayout ──GraphLayoutToGraphicsCanvas──▶ GraphicsCanvas
```

1. **Size, then place.** `GraphGraphToGraphLayout(engine; extent, border, constraints)` prints the `content` of each vertex through the recursion into a canvas and reads its width and height. One computed cell then calls `layout_graph` with those sizes. The cell reads the vertex list, the edge list, the sizes and the constraints, so the engine runs again only when one of them changes. `constraints` is a function of the graph, because a constraint names a vertex, and the vertices exist only when there is a document.
2. **Draw.** `GraphLayoutToGraphicsCanvas` draws the edges first, as `GraphicsPolyline`s with an arrowhead when `directed` is true. It prints each edge `label` and centres it on the midpoint of the route by arc length. It then draws each box as a rounded `GraphicsRect`, larger than the vertex by the padding of the theme on each side, with the content canvas on top.

The size of the output canvas is a computed cell over the layout: the right and bottom edges of the boxes, of the highlight ring and of the route points. So a vertical layout above a graph reserves the right height, and the height grows when the vertices arrive after the first print.

**The content prints twice.** The first stage prints each content to measure it, and the second stage prints it again to draw it. Nothing caches the first print for the second. A large content in a vertex costs two prints.

`GraphToGraphics(engine = GridEmbedding(); extent, border, constraints)` returns the chain of the two stages, a `ChainingProjection`. The two stages have no recursion of their own. `make_graph_projection_example` wraps them in a `NestingProjection` with a dispatcher for the content types. The natural renderer gives itself as the recursion, so a vertex content draws as it draws anywhere else.

### Selection and clicks

The first stage maps `vertices[i].rest` to `vertex_layouts[i].vertex.rest` and back. The second stage maps `vertex_layouts[i].vertex.content.rest` forward through the IO map of that content. A reference to a whole vertex, `vertex_layouts[i].vertex`, maps forward to the box element in the drawing. An annotation that anchors beside a node uses this.

The second stage maps no reference backward. Its reader re-roots instead:

- A left press inside a box goes to the reader of that content, with the point moved into the frame of the content. A `ReplaceSelectionOperation` that comes back is rooted under `vertex_layouts[i].vertex.content`. An operation for which `is_self_contained_operation` is true passes unchanged. The reader drops every other operation.
- A key goes to the reader of each content in turn, and the first answer wins.

Edges and edge labels are decorations: a click on them selects nothing.

```julia
@reference vertices[2].content.entries[1].value   # a value inside the JSON of vertex 2
```

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

A producer sets the two fields as computed cells over the state it follows. Two domains do this, and each builds a `GraphGraph` in a stage of its own:

- `FsmDiagramToGraph` makes one vertex for each state and one edge for each transition with a target. The highlights follow `FsmDiagram.live_state` and `live_transition`; see [fsm.md](../fsm/fsm.md).
- `ProcessDiagramToGraph` makes one vertex for each step, decision, loop and jump, and synthesizes the edges from the nesting. The highlights follow the current and the previous node of a debug session; see [process.md](../process/process.md).

In both, the content of a vertex is the domain node itself, held by identity. So a click on a box selects the real state or step through the path above, and the domain adds no code for drawing or for clicks.

### The theme

`GraphTheme` holds the look of the drawing: the fill, the border, the border width, the radius and the padding of the box of a node; the color and the width of an edge and the size of its arrowhead; and the color, the width and the gap of the ring of a highlight. Each value has the default that the domain draws with no appearance, and each field has a docstring, which the appearance tab shows under the name of the field. `GraphLayoutToGraphicsCanvas(; theme)` takes a `GraphTheme`, scaled or not, and holds all values as one `NamedTuple` and no theme, which a print reads once; with no theme it holds the default values. `GraphToGraphics` passes its `theme` on. The natural registration gives the scaled theme of the `Appearance` of the editor, so the drawing follows its scales, and the appearance tab shows a section for `GraphTheme`. The content of a node follows the themes of its own domain.

## How it fits

`ProjecturedGraph` depends on the kernel and the platform. `ProjecturedFSM` and `ProjecturedProcess` depend on it, and `ProjecturedAdaptagrams` adds an engine to it.

The `__init__` in `GraphLayoutToGraphics.jl` calls `register_natural_graphics!(:graph, …)`. It maps `GraphGraph` to the two stages with the default engine, `GridEmbedding`, so a tab draws a graph as a diagram. The package registers no natural domain row: a graph has no text form, no parser and no file type.

## Design decisions

- **The geometry is a separate document.** `GraphLayout` holds the positions outside `GraphGraph`, so a saved graph holds no coordinates and two views can place one graph in two ways. See [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md).
- **A vertex holds any document.** The content prints through the recursion of the caller, so a table, a card or another graph can be a node with no code in this package. See [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md).
- **An engine throws on a constraint that it does not implement.** A picture does not show whether a pin was kept or dropped, so a silent drop is the worst answer. See [plan/done/graph-layout-engines.md](../../../../plan/done/graph-layout-engines.md).
- **The pure-Julia engines are ports.** They must draw the picture that the C++ original draws, so each C++ file has one Julia file with the same name and order. See [plan/done/graph-layout-engines.md](../../../../plan/done/graph-layout-engines.md).
- **The engine is chosen when the layout runs.** A projection that chose at construction would keep the fallback engine for the whole session. See [plan/done/graph-layout-engines.md](../../../../plan/done/graph-layout-engines.md).
- **A highlight goes around the layout cell.** A running state machine moves its marker many times a second, and a force-directed layout for each move costs too much. See [plan/done/state-machine-domain.md](../../../../plan/done/state-machine-domain.md).
- **The native engine is a separate package.** Its native dependency stays out of every other package. See [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md).

## Usage

```julia
a = GraphVertex(JsonString("client"))
b = GraphVertex(JsonObject("id" => JsonNumber(42)))
graph = GraphGraph([a, b], [GraphEdge(a, b; label = JsonString("uses"))])
projection = make_graph_projection_example(engine = make_deferred_layout_engine())
run_example(graph, projection; name = "graph")
```

- Examples: `graph_example`, a table, a JSON object and an XML element joined by edges, in `example/domain/graph/`. The atomic catalog has the entries `graph/graph` and `graph/layout`. `graph_adaptagrams_example` is in `ProjecturedAdaptagramsExample`.
- Test: `test_graph()` runs the layering guard, `test_graph_projection()`, `test_fruchterman_reingold_layout()` and `test_graph_theme()`.

## Limits

- Edges and labels are not selectable. No gesture adds or removes a vertex or an edge, and a vertex can not be dragged. [plan/done/graph-domain.md](../../../../plan/done/graph-domain.md) lists these as future work.
- `GraphLayout.direction`, `node_sep`, `rank_sep`, `VertexLayout.pinned` and the ports of `EdgeLayout` are fields that no stage reads. The first stage writes constants into them.
- With a pure-Julia engine, a self-loop edge gets a route of two equal points at the centre of its box, so it does not show.
- The registered factory is not a cell, so the layout cell does not depend on it. A graph that is drawn before `ProjecturedAdaptagrams` loads keeps its layout until its vertices, edges, sizes or constraints change.
- The constraint kinds `:align`, `:same_rank` and `:min_separation` have a name and no engine that implements them.
- The atom `graph/layout` is in the broken sets of `test/projectured/projection/CatalogTest.jl`. A `GraphLayout` printed alone has no recursion for the content of its vertices.
