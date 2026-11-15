# The edges of a graph end at side ports, and the light moves no edge

Status: DONE, 2026-10-27, on the branch `graph-ports`. The owner agreed to the three fixes on 2026-10-27, and asked to implement the plan. Not landed on `main`.

## The ask

The owner, 2026-10-27, with a picture of `graph_services_example`:

- "why do the edges move when they get blue colored when I dwell above a vertex
  and its tooltip is shown?"
- "the tooltip has a black rectangle which is smaller than the tooltip window,
  there's extra spacing at the right edge of the window"
- "how could we make the edges connect to vertices more nicely? … connect at the
  center on the side if there's only one and align nicely if there are more than
  one, or something like that."

After the report of the causes and of what other tools do, the owner answered
"yes, looks good" to one plan for the three fixes.

## The problem

The facts at `main` `728307d08`. Find each function by its name.

1. **The light changes the shape of the edges.** `_compute_drawn_edges` in
   `GraphLayoutToGraphics.jl` cuts each edge at `_get_drawn_rim`. That rim holds
   the ring (`highlight_gap + highlight_width`, 6 px) when the vertex has the
   highlight or the light. The light covers the vertex under the pointer and the
   vertices that an edge joins to it. A curved edge leaves its box at a right
   angle to the side that it crosses (`_get_rim_normal`). Near a corner, 6 px more
   can change that side from the top to the left. The curve then leaves in
   another direction, so it takes another shape, and its label moves with it.
   The cell `drawn_edges` reads `lit`, so each move of the light onto another
   vertex calculates all the edges and labels again.
2. **The tooltip window is wider than its frame.** The window takes the extent
   of what it printed, but at least `TooltipTheme.minimum_size` (120 × 32 px).
   The frame (`_make_tooltip_frame` in `TooltipContentToLayout.jl`) fits what it
   holds. A vertex of `graph_services_example` holds a text block, so its note
   has only "Edges out" and "Edges in", and its frame is 105 px wide (a print with
   `FontFileMeasure`). The window shows 15 px of its own surface right of the
   frame.
3. **The ends of the edges are where the line between the centres crosses the
   rim.** An edge aims at the centre of each box. Two edges that leave one side
   can start at points close together, and an edge that crosses near a corner
   starts at the corner.

## The decision

- **The light and the highlight move no edge.** The drawing calculates each edge
  from the box with its padding only, never with a ring. A vertex with a ring
  only cuts the line shorter where it enters the ring: a straight line along its
  last segment, and a curve where its last span enters the ring, split there
  (de Casteljau), so the rest of the curve is the same. The label stays on the
  line as calculated before the cut. So `drawn_edges` and `drawn_labels` read no
  light and no highlight, and a move of the light calculates no edge again.
- **A curved edge ends at a side port.** For each end of a curved edge:
  1. The side is the side of the box that the line from its centre to the next
     point crosses. The next point is the first bend of the route, or the centre
     of the other box.
  2. The ends on one side of one box are sorted by the next point: from left to
     right on a top or bottom side, from top to bottom on a left or right side.
  3. With `k` ends on a side, end `i` is at `i/(k+1)` of that side. One end is at
     the middle.
  4. The curve leaves the port at a right angle to its side, as it does now.

  This is what draw.io and yEd do, and what ELK does with sorted ports. A straight
  edge still aims at the centres and is cut at the rims, as Graphviz, Cytoscape
  and Mermaid draw it. The layout engine, the routes and the document do not
  change.
- **The tooltip frame fills its window.** The column around the frame gives the
  frame the least width of `TooltipTheme.minimum_size` as the least of its range
  (`child_width = SizePolicy(min, nothing, nothing, 0.0)`). A `WidgetComposite`
  already grows to the least width of its context. So the frame and the window
  have the same width. A frame of one line is 34 px high, more than the least
  height of 32 px, so the height needs nothing.

## The steps

1. ✅ **The light and the highlight move no edge.** `GraphLayoutToGraphics.jl`:
   `_compute_drawn_edges` takes no `joined` and reads no highlight; the drawing
   cuts each line of a vertex with a ring at the ring as it paints it, and draws
   the lit and the highlighted line over the same cut line. Tests in the graph
   suite: with the light on a vertex and with the highlight on a vertex, each
   curve and each label keeps its points, except the ends at the ring; the
   arrowhead stops at the ring; the value of `drawn_edges` is the same object
   after a move of the light. The test "an edge ends at the rim of the box that
   the drawing paints" keeps its check of the ring. Run `test_graph()`.

   Done. Each drawn edge holds the index of the box at each end (0 for an edge
   whose ends have no box, so no ring cuts it). `_cut_edge_at_rings` cuts a
   straight line with `_clip_route` at the ring rims, and a curve by
   `_cut_curve_at_rings`: a bisection on the first and the last span
   (`_find_rim_crossing`), then a split of the span there (`_split_bezier`). The
   cut line keeps the `path` of the uncut line, so the label stays. The value of
   `drawn_edges` is not visible from the IO map, so the test checks that
   `label_boxes`, which reads it, keeps its value. Graph projection tests: 336 pass.
   Found later: a field of the IO map reads the value of its cell, so the test
   reads the cell with `getfield`; `v[]` of a vector with one element answers that
   element, and the first form of the check compared two equal tuples.
2. ✅ **A curved edge ends at a side port.** `_compute_drawn_edges`: the sides, the
   sort and the ports for a curved edge; the start and the finish of the curve
   from the normal of the side of the port. Tests: one end on a side is at its
   middle; two ends on one side are at 1/3 and 2/3, in the order of their next
   points; an edge with a bend takes its side from the first bend; a straight edge
   keeps its ends. The test "a curved edge leaves each box at a right angle to its
   side" now expects the middles of the sides. Pictures of
   `graph_services_example` and of the study map, before and after. Run
   `test_graph()`, `test_research()`, and `test_example` for `graph_example` and
   `graph_services_example`.

   Done. `_compute_side_ports` groups the ends by box and side, sorts them by
   the next point of the route, and places them; `_compute_drawn_edges` first
   collects the clipped routes, then a straight edge keeps them and a curved edge
   takes its ports. An edge with a bend takes its side from the first bend: the
   test "a curved edge passes through the bends of its route" keeps its points,
   because its bend is at the height of the centre. Graph projection tests: 347
   pass. The suites, the examples and the pictures run once after step 3.
3. ✅ **The tooltip frame fills its window.** `TooltipContentToVerticalLayout` reads
   `minimum_size` from its theme and gives it to the column around the frame.
   Tests in the tooltip tests of the platform: the frame of a short note is as
   wide as the least width of the window; the frame of a long note keeps the width
   of what it holds. Run the tooltip tests (`TooltipNoteTest.jl`,
   `TooltipProjectionTest.jl`, `WidgetTooltipTest.jl`) and the tooltip window
   test of the Julia domain.

   Done. The column around the frame takes `child_width = SizePolicy(least,
   nothing, nothing, 0.0)`; the cross axis of a vertical layout gives the frame a
   range with that least, and `WidgetComposite` grows to it. Tooltip tests: 132
   pass (`test_tooltip_note`, `test_tooltip`, `test_widget_tooltip`), and
   `test_tooltip_window()` 55 pass. The note of a vertex of the services example,
   printed with the real fonts, is 120 px wide, the width of its window.
4. ✅ **The guides.** `graph.md`: the ports, and the ring that only cuts a line.
   `tooltip.md`: the frame and the least size. Then the plan
   moves to `plan/done/`.

   Done. `graph.md`: the rule of the ring, the side ports, and two decisions;
   `tooltip.md`: the least width of the frame; the head comment of
   `GraphLayoutToGraphics.jl`.

   Results after all steps: `test_graph()` 625 pass; `test_research()` 381 pass;
   `test_example(graph_services_example)` 14 335 pass;
   `test_example(graph_example)` 13 192 pass and the 4 REPL failures of `main`
   (`SelectionMismatchException` at the XML child). The pictures of
   `graph_services_example` show each end at the middle of a side, or spread on a
   side with more ends; with the light on `api` (5 edges), the curves keep their
   shape, the labels keep their places, and no fault occurs. The study map shows
   its edges at the middles of the sides and no fault.

## Notes

The work happens in the worktree `projectured-julia-graph-ports` on the branch
`graph-ports`. The landing on `main` waits for the owner.
