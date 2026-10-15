# The mouse drags a vertex of a graph

> **Kind:** plan · **Status:** in progress on the branch `graph-vertex-drag`; written 2026-10-15; step 1 is done · **Stands on:** [graph.md](../../documentation/package/domain/graph/graph.md), [graph-layout.md](../../documentation/package/domain/graph/graph-layout.md), [graph-domain.md](../done/graph-domain.md), [graph-layout-engines.md](../done/graph-layout-engines.md)

## 1. The request

The owner, 2026-10-15: "I would like to be able to drag graph vertices with the
mouse". Today no gesture moves a vertex ([graph.md](../../documentation/package/domain/graph/graph.md),
"Limits"). The future work of [graph-domain.md](../done/graph-domain.md) names
the drag and a layout that starts from the last positions.

## 2. The decisions

| # | Question | Answer | Who |
| --- | --- | --- | --- |
| D1 | Where does a dropped position live? | In the graph: a `constraints` field of `GraphGraph` holds a `:pin` `GraphConstraint` for each dropped vertex. A drop is an edit, so undo removes it, and every view of the graph shows it. | The owner, 2026-10-15 ("Q1: agreed") |
| D2 | What do the other vertices do at a drop? | The engine starts the layout from the current positions of all vertices and refines it. The drop writes a `:start` position for every vertex that has no pin, at the place where it is drawn. The layout run never writes them. | The owner, 2026-10-15, after the question "why can't we start the layout from the current pinned and unpinned positions?" ("agreed") |
| D3 | How does the drag work? | With the drag mechanism that exists, as the drag of a tab and the rubber band of a chart do. Section 4.3 gives the details. | My design, given in the first answer; the owner did not object |
| D4 | Which engine is the default? | `DeferredLayout`, made by `make_deferred_layout_engine()`, in `GraphGraphToGraphLayout()`, `GraphToGraphLayout()`, `GraphToGraphics()` and `make_graph_projection_example`. With nothing registered it is `FruchtermanReingoldLayout`. A graph in a tab and `graph_example` then refine after a drop. The cost: about 0.13 s for each layout run at 300 vertices, where the grid takes 0.0002 s. | The owner, 2026-10-15 ("I agree with recommendation"), after the question "why not use FruchtermanReingoldLayout by default" |

D1 changes a design decision of [graph.md](../../documentation/package/domain/graph/graph.md):
"`GraphLayout` holds the positions outside `GraphGraph`, so a saved graph holds
no coordinates". From this plan on, the graph holds the places that the person
gave, and the layout holds the computed geometry.

D2 keeps the determinism rule of [graph-layout.md](../../documentation/package/domain/graph/graph-layout.md):
the same graph gives the same positions. The start positions are part of the
document, and an edit is the only way to write them. If the engine used its last
output, the picture would depend on the edits of the session, and a graph that
is opened again would show a different picture.

## 3. Which engines support it

| Engine | Where | What it does with `:start` | What the person sees after a drop |
| --- | --- | --- | --- |
| `FruchtermanReingoldLayout` | projectured | It starts each body at its start position, with a low first temperature, and refines. | The neighbours of the dropped vertex move toward it a little. A new vertex finds a free place. |
| `GridEmbedding` | projectured | It places the vertex at its start position, as a pin. A grid has no refinement. | Nothing else moves. A new vertex takes a grid cell, and it can overlap a placed vertex. |
| `AdaptagramsLayout` | `ProjecturedAdaptagrams` | It places the vertex at its start position on the way out, as it places a pin now (`_fit_and_pin!`). The shim takes no constraint. | Nothing else moves. |
| `SpringEmbedderLayout`, `ForceDirectedLayout` | omnet-julia, by `ModuleLayout` | They place the vertex at its start position, as a pin. The C++ originals have no start positions, so a graph with no `:start` keeps the C++ picture. | Nothing else moves. |
| `DeferredLayout` | projectured | It becomes one of the engines above when the layout runs. | As that engine. |

Every engine must list `:start` in `get_supported_constraint_kinds`. If an
engine did not list it, `check_constraints` would throw at the first drop. This
matters for omnet-julia, because `ModuleLayout` registers itself as the engine
of `DeferredLayout` ([ModuleLayout.jl:133](../../../omnet-julia/source/presentation/module/layout/ModuleLayout.jl#L133)).

A start position that the engine keeps without a move is a correct answer: the
contract of `:start` is "begin here, and you can move it". So no engine drops
the constraint.

Before this plan, `graph_example` and a graph in a tab used `GridEmbedding`
([GraphProjectionExample.jl:11](../../example/domain/graph/GraphProjectionExample.jl#L11),
the `__init__` in [GraphLayoutToGraphics.jl](../../source/domain/graph/GraphLayoutToGraphics.jl)).
D4 makes `DeferredLayout` their engine, so they refine after a drop. The state
machine example names `GridEmbedding` itself and keeps it. The process example
already uses the deferred engine, and omnet-julia and inet-julia name their own
engines.

## 4. The design

### 4.1 The documents

- `GraphGraph.constraints`: a cell that holds a `Vector` of `GraphConstraint`,
  empty by default. Each write replaces the whole vector. This gives one cell for
  the layout cell to read and one undo step for each drop. The field comes after
  `highlight_edge`.
- `GraphLayout.graph`: the `GraphGraph` that the layout places, held by identity,
  as `ChartPlot.chart` holds its chart. The reader of the drawing writes the drop
  on it.
- `GraphLayout.drag`: the drag of a vertex as view state, as `PaneTree.drag` and
  `ChartPlot.drag_anchor` are. It holds the vertex, the point of the press, the
  offset, and whether the drag started. Only the drawing reads it, so a move does
  not run the engine.
- The two `GraphLayout` fields come after `engine`. These positional callers
  change:
  - [GraphDocument.jl:65](../../source/domain/graph/GraphDocument.jl#L65);
  - [FsmDiagramToGraph.jl:176](../../source/domain/fsm/FsmDiagramToGraph.jl#L176);
  - [ProcessDiagramToGraph.jl:282](../../source/domain/process/ProcessDiagramToGraph.jl#L282);
  - [GraphToGraphLayout.jl:137](../../source/domain/graph/GraphToGraphLayout.jl#L137).

### 4.2 The constraints and the engines

- `:start` joins `GRAPH_CONSTRAINT_KINDS`. Its payload is `(x, y)`, the top-left
  corner, as for `:pin`. `get_constraint_starts(constraints)` reads them, as
  `get_constraint_pins` reads the pins. A pin wins over a start on one vertex.
- The first stage gives the engine the constraints of the projection
  (`p.constraints(graph)`) first and `graph.constraints` after them. The last pin
  of a vertex wins, so a pin that the person dropped wins over a pin of the
  producer.
- `FruchtermanReingoldLayout`:
  - `_place_on_spiral!` puts a body with a start position at that position. The
    other bodies go on the spiral, as now.
  - The temperature is per body. A body with a start begins at a fraction of
    `k`, and a body without one begins at `start_temperature`, as now. Step 2
    sets the fraction from a measurement and writes it here.
  - A start counts as a pin for the extent rule. The drawing keeps its scale and
    is not moved to the border, because a start is a place in the extent.
  - A family of a cluster starts at the mean of the start positions of its
    members, less their offsets.
  - `_remove_overlaps!` stays as it is. A vertex dropped on another vertex
    pushes that vertex away.

### 4.3 The drag

The reader is `read_intent` of `GraphLayoutToGraphicsCanvas`
([GraphLayoutToGraphics.jl:283](../../source/domain/graph/GraphLayoutToGraphics.jl#L283)).
The pattern is the drag of a tab ([PaneToWidget.jl:700](../../source/platform/pane/PaneToWidget.jl#L700)).

1. **Press.** A left `MouseDown` goes by position to the content of the vertex
   under the point, in the frame of its canvas, as `_route_click` sends a click.
   Today a `MouseDown` goes to the content with the caret (`_forward_to_selected`).
   If the content gives an answer, such as the drag of a column edge of a table,
   that answer wins. If the content gives no answer, the graph writes
   `GraphLayout.drag` with the vertex and the point, and `started = false`. The
   hit test for the press uses the box that the graph draws, with
   `node_padding`. `_find_vertex_at` uses the box of the content.
2. **Start.** A `MouseMove` with the button held, 5 pixels from the press,
   writes `started = true` and answers `StartDragOperation(EmptyReference(),
   nothing)` and the pointer shape `:closed_hand`. A `MouseUp` before the start
   clears the drag, so a click still goes to the content.
3. **Move.** Each `DragMove` writes the offset. The drawing moves the box and
   the content of the vertex. It draws each edge of that vertex as a straight
   route from the moved box, with `_border_point`. The other edges keep their
   routes.
4. **Drop.** `DragEnd` answers one edit and clears the drag:
   `ReplaceReferencedValueOperation(layout.graph, "constraints", new)`. In the
   new vector:
   - each constraint that is not a `:pin` or a `:start` stays;
   - the pins of the other vertices stay;
   - the dragged vertex gets a `:pin` at its new corner, with `x >= 0` and
     `y >= 0`;
   - every other vertex without a pin gets a `:start` at its drawn corner.

   The engine runs one time.
5. **Cancel.** `DragCancel` and Escape clear the drag, and the vertex goes back.

The drag needs no new event, operation or channel. The drag wrapper sends
`DragMove`, `DragEnd` and `DragCancel` to the graph by its path. The path ends at
the input of the view as a whole, so the chain reads them at the deepest stage.

## 5. Steps

- [x] **1. The documents, the `:start` kind and the default engine.** Section
  4.1, the constraint part of section 4.2, and D4. A test that uses a default
  and tests the grid names `GridEmbedding()`. Tests in `GraphProjectionTest.jl`:
  - a pin in `graph.constraints` places the vertex at the pin;
  - the pin of the graph wins over a pin of the projection.

  Done 2026-10-15. `get_constraint_starts` leaves out a vertex that has a pin,
  so every engine gets the rule "a pin wins over a start" from one place; it and
  `get_constraint_pins` share `_collect_constraint_corners`. Only one test
  depended on the grid default: it asserted the engine type of `GraphToGraphics()`.
  `test_graph()`, `test_fsm()` and `test_process()` pass together: 898 passes.
- [ ] **2. The engines.** `FruchtermanReingoldLayout` as in section 4.2.
  `GridEmbedding` and `AdaptagramsLayout` place a start as a pin. Tests in
  `FruchtermanReingoldLayoutTest.jl`:
  - with start positions, the same input gives the same positions;
  - when the start positions are an earlier result of the engine, each vertex
    moves less than a bound that the test names;
  - a new vertex with no start overlaps no box.

  A grid test asserts that a start is placed at its corner.
  `ProjecturedAdaptagrams` has no test, so the step loads the package and checks
  `get_supported_constraint_kinds` of `AdaptagramsLayout`.
- [ ] **3. The drag.** Section 4.3. A new test file in
  `test/domain/graph/projection/` prints `graph_example` one time. It reads the
  gestures through that one IO map with the drag wrapper, as
  `PaneDragTest.jl` does. It asserts:
  - the corner of the pin of the dragged vertex;
  - the start corner of each other vertex, which is its drawn corner;
  - that the other vertices do not move during the moves;
  - that Escape puts the vertex back;
  - that a click with no move selects in the content;
  - that undo removes the pin.
- [ ] **4. omnet-julia.** `SpringEmbedderLayout` and `ForceDirectedLayout` take
  `:start` as a pin. A test in the layout tests of omnet-julia covers it. Run
  `Pkg.precompile` of omnet-julia. This step lands after step 3 is on `main` of
  projectured.
- [ ] **5. The documents and the live check.**
  - In [graph.md](../../documentation/package/domain/graph/graph.md), write the
    design decision again, change the limits and the usage, and link this plan.
  - In [graph-layout.md](../../documentation/package/domain/graph/graph-layout.md),
    add the `:start` row and the table of section 3.
  - Do the live check: drag a vertex of `graph_example` in the SDL editor with
    pushed SDL events, then press Escape, then undo.
- [ ] **6. Review and the suites.** A code review of the diff. Then run
  `test_graph()`, `test_fsm()`, `test_process()`, and the layout tests of
  omnet-julia.

## 6. Limits

- A graph that a view makes keeps its pins only while the view lives. Examples
  are the diagram of a state machine, a process diagram, the topology of an
  omnet simulation and the graph of a database catalog. The pins go on that
  graph, and a reprint makes a new graph. After a reprint, undo of such a drop
  has no visible result. A domain that wants to keep the places must map them to
  its own document.
- During a drag, the edges of the dragged vertex are straight. An engine that
  routes around boxes routes them again at the drop.

## 7. Not in this plan

Not in this plan: a command that removes the pins and the start positions (lay
out again); a drag of an edge, of a bend, or of the empty canvas; feeding start
positions to libcola through a wider C interface.
