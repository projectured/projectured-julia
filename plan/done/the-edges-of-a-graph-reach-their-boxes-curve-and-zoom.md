# The edges of a graph reach their boxes, can curve, and the layout zooms

Status: DONE, 2026-10-22, on the branch `graph-edges`, in the worktree
`projectured-julia-graph-edges`. Not landed on `main`. The owner approved the plan on 2026-10-22, with
the keyword only for curves: no switch in the window.

## The ask

The owner, 2026-10-22, with a screenshot of the map of a study:

- "the arrowheads are covered by the vertex boxes"
- "connections would look much better with splines, no? I think it should be an
  option"
- "we need some kind of layout zoom in/out mechanism which only affects the graph
  layout, not a pixel zoom in/out"

## The problem

The facts at `main` `06af45419`. Find each function by its name.

1. **The drawing paints a larger box than the engine places.**
   `GraphGraphToGraphLayout` gives the engine the size of the content of each
   vertex (`_canvas_wh`). The engines of `ProjecturedGraph` route each edge from
   the border of one content box to the border of the other
   (`_make_straight_route`). `print_document` of `GraphLayoutToGraphicsCanvas`
   then paints each box `node_padding` (8 px) larger on each side, after the
   edges, with an opaque fill. The last 8 px of each edge are under the box, and
   2 px of the arrowhead (`arrow_size` 10) show. The ring of a highlighted vertex
   is 6 px further out and hides all of the arrowhead.
2. **An Adaptagrams route ends at the centre of the box.** The shim connects the
   centres (`ConnEnd` in `adaptagrams_shim.cpp`), so its arrowhead is under the
   target box and does not show.
3. **The drawing makes only `GraphicsPolyline`.** `GraphicsSpline` exists, with
   `kind = :bezier` or `:catmullrom` and with arrowheads. The SDL, PDF and web
   backends draw it through `tessellate_spline`. The arrowhead follows the last
   segment of the tessellated curve (`build_polyline_arrowhead`).
4. **A route of the engines in `ProjecturedGraph` has two points.** A curve
   through two points is a straight line. A curve needs a direction at each end.
5. **No part of a graph reads the wheel.** A chart reads Ctrl and the wheel as a
   zoom of its data, and keeps the zoom as view state on its `ChartPlot`
   (`_scroll_intent`, `ReplaceViewStateOperation`). A graph keeps the drag of a
   vertex the same way, on `GraphLayout.drag`.
6. **Eight places read the corner of a vertex from `VertexLayout.x` and `.y`:**
   the cell `drawn`, the cell `extent`, `_find_vertex_at`, `_find_node_at`,
   `_read_graph_move`, `_get_dragged_corner`, `_collect_dragged_boxes` and
   `_make_vertex_drop_operation`.

## The decision

These were my recommendations. The owner approved them on 2026-10-22.

- **An edge ends at the rim of what the drawing paints for its vertex.** The
  drawing cuts each end of a route, not the engine. First it sets the first
  point to the centre of the source box and the last point to the centre of the
  target box. Then it cuts the route where it leaves the painted source box and
  where it enters the painted target box. The painted box is the box with its
  padding and its border, and the ring when the vertex has the highlight.
  - One rule serves a border-to-border route (the engines of `ProjecturedGraph`),
    a centre-to-centre route (Adaptagrams), a dragged box and a zoomed layout.
  - Only the drawing knows the padding and the ring, so the cut belongs to the
    drawing. The engines and their tests do not change.
  - The cut uses the rectangle and ignores the rounded corner. The gap at a
    corner is at most 2 px.
  - If no part of the route is outside both boxes, the boxes overlap, and the
    drawing draws no line for that edge.
- **A curve is an option of the drawing.** The keyword is `edge_shape` on
  `GraphLayoutToGraphicsCanvas` and on `GraphToGraphics`.
  - `:straight` is the default and the drawing of today. No picture changes
    until a caller asks for a curve.
  - `:curved` draws a `GraphicsSpline(kind = :bezier)` through the cut route. At
    each end, the curve leaves the box at a right angle to the side that it
    crosses. At a bend of a routed edge, the curve passes through the bend in
    the direction from the point before to the point after (Catmull-Rom). The
    control point of an end is half of its span along the direction of that
    end, as in the vertical link of d3, and the control point of a bend is a
    third of its span. (Changed in step 3, see there.)
  - The label of an edge sits at the middle of the curve by arc length. The
    highlight strokes the same curve again. A dragged edge curves too.
- **The layout zoom is view state of the drawing.** `GraphLayout.zoom` holds it,
  beside `drag`: `nothing` at the start, then a scale and a shift (changed in
  step 3, see there). `ChartPlot.view` is the same for a chart.
  - Ctrl and the wheel over the graph multiply the zoom by 1.15 for each notch,
    the step of a chart. The zoom stays inside 0.25 … 4. A notch at a limit
    answers `nothing`. A turn without Ctrl answers `nothing`, so the page
    scrolls.
  - The zoom moves the centre of each box and each bend of a route. A box keeps
    its size, and its content and its fonts do not change.
  - The top-left corner of the drawing stays where it is, and the drawing grows
    to the right and down. The graph can not scroll the pane around it, and no
    operation asks a pane to scroll to a point. A zoom that keeps the point
    under the pointer needs that new mechanism, so it is not part of this plan.
  - The engine does not run again. A zoom changes only the cells `drawn` and
    `extent`.
  - The IO map gets one cell, `drawn_boxes`: the drawn corner of each vertex at
    the zoom and the drag of now. Each place of fact 6 reads this cell.
  - A drop writes the pin back in the frame of the layout, with the inverse of
    the zoom. So a pin stays where the person dropped it, at each zoom.
  - A zoom under 1 can make boxes overlap, and can move a bend of an Adaptagrams
    route into a box. A zoom of positions does that.

## Steps

Do the work in a worktree, on the branch `graph-edges`. Commit each step. Do not
land on `main` before the owner approves. Test with `test_graph()` and the
narrower test functions in `test/domain/graph/projection/`.

1. **The edge ends at the rim of the painted box.** Add `_clip_route` to
   `GraphLayoutToGraphicsCanvas.jl`, and call it for each edge in the cell
   `drawn`. Tests in `GraphProjectionTest.jl` assert the coordinate of the tip of
   each arrowhead on the rim of the painted target box. Test four cases: the
   grid engine, a highlighted target, a dragged vertex, and a hand-made
   `GraphLayout` with a centre-to-centre route of three points. The last case
   stands for an Adaptagrams route, because the shim is not built here.

   **Done.** The facts of the implementation:
   - `_compute_drawn_boxes` gives the box of each vertex in the drawing, with
     the drag. The cell `drawn` and the cell `extent` read it.
   - Each edge starts at the centre of its drawn box, so the edges of a dragged
     vertex need no route of their own. `_collect_dragged_boxes` and
     `_make_dragged_route` are gone.
   - An edge whose ends have no box in the layout is drawn along its route, as
     before.
   - `test_graph_projection` passes (293), and the drag, theme, FSM diagram and
     process diagram tests pass.
2. **A curve is an option.** Add `edge_shape` and `_make_curve_points`. Tests
   assert that each edge is a `GraphicsSpline` of kind `:bezier`, that its ends
   are the cut points of step 1, and that each end tangent is at a right angle
   to its side. The label sits on the curve. The default draws the same
   `GraphicsPolyline` as before, so the tests that exist do not change.

   **Done.** The facts of the implementation:
   - `_compute_drawn_edges` and the cell `drawn_edges` hold the geometry of
     each edge: the points of its element and the polyline that a backend
     strokes. A curve samples 16 points for each span (changed in step 3).
   - The cell `drawn` and the cell `extent` read `drawn_edges`. So the extent
     counts the line that the drawing draws, not the points of the route. The
     two ends of a route are not drawn any more, so the test of the extent got
     a route with a bend at x 4000 in place of an end at x 4000.
   - `make_graph_projection_example` takes `edge_shape` too.
   - A picture of a graph of seven cards, drawn by the force-directed engine,
     shows each arrowhead, with straight edges and with curved edges.
   - `test_graph_projection` passes (307).
3. **The layout zoom.** Add `GraphLayout.zoom`, the cell `drawn_boxes`,
   `_read_layout_zoom` and `_write_layout_zoom`. Tests assert these facts:
   - one notch writes a zoom of 1.15;
   - the distance between two centres grows by 1.15, and the box sizes stay;
   - the engine runs one time only;
   - a drop at zoom 2 pins the vertex where the release put it;
   - a turn without Ctrl answers `nothing`.

   Check in a live window that a zoomed graph in a tab scrolls. If it does not
   scroll, report it and ask. Do not add a scroll pane in this plan.

   **Done.** The facts of the implementation:
   - **The zoom holds a scale and a shift, not a number.** A shift computed
     from the positions at each print moved the whole drawing at a drop, when
     the dropped vertex was the one at the top-left corner. So each notch writes
     both, as `GraphLayout.zoom = (scale, shift)`, and a drop changes neither.
     `_compute_next_zoom` computes the shift that keeps the top-left corner.
   - `_compute_zoom_map` adds to the shift only when a box would be drawn left
     of or above the drawing, for example after the engine placed a new vertex
     there.
   - Ctrl and the wheel go first to the content of the vertex under the point
     (`_read_ctrl_wheel`), so a content that zooms keeps the turn.
   - The hit tests, the press and the move of a drag, and the routed intents
     (`_collect_drawn_entries`) read the cell `drawn_boxes` of the IO map.
   - A layout corner is an integer. So a dropped vertex is drawn at most
     scale / 2 px from the place of the release.
   - **The curve changed.** The pictures of the zoom showed two faults. An edge
     that left the top of a wide card toward a card far to the side made a
     loop. Zoomed in, a long curve showed corners. Now the control point of an
     end is half of its span along the direction of that end. A curve takes one
     sample for about each 6 px of a span, from 12 to 64 samples
     (`_get_curve_segments`).
   - `GraphLayoutZoomTest.jl` holds four test sets, and one of them sends the
     wheel through the window of an editor. The zoom, drag and projection tests
     pass (379).
   - **The scroll check.** In the window of the test editor
     (`make_window_scene`), no scroll pane holds the graph. Zoomed to 4, the
     graph is 4620 × 2486 px in a window of 900 × 700 px, and a turn of the
     wheel without Ctrl moves nothing. I reported this to the owner.
4. **The guides.** Write the rim rule, `edge_shape` and the zoom in
   [graph.md](../../documentation/package/domain/graph/graph.md) and
   [graph-layout.md](../../documentation/package/domain/graph/graph-layout.md).
   Move this plan to `plan/done/`.

   **Done.** `graph.md` has the sections "The edges" and "The zoom of the
   layout", two design decisions and three limits. `graph-layout.md` says that
   the drawing uses only the bends of a route. The whole graph suite and the
   FSM and process diagram tests pass (577), and the naming guard passes.

## Open items

- The map of a study is on the branch `research`, not on `main`. It can ask for
  `edge_shape = :curved` after both branches land.
- A host with no scroll pane does not scroll a zoomed graph, as the scroll check
  of step 3 found. The owner decides whether a host of a graph gets one.
