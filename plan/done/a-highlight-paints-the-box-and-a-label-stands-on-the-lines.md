# A highlight paints the box, and a label stands on the lines

Status: DONE, 2026-10-27, on the branch `graph-highlight`; not landed on `main`. The owner agreed on 2026-10-27, and asked for the plan and its
work.

## The ask

The owner, 2026-10-27: "the highlight still causes the curved edges to shrink, why
don't we simply highlight the box and not change the size of the vertex? then the
edges can just go where they go when not highlighted?" To the proposal and the
question "Shall I write the plan and do it?": "yes / and if we are at it, can we do
something simple to avoid the labels and the edges overlap?"

## The problem

The facts at `main` `b48b06fc8`. Find each function by its name.

1. **A ring makes the edges shorter.** The highlight and the light paint a ring
   6 px outside the box (`highlight_gap` 3 px, then `highlight_width` 3 px),
   behind the box and after the edges. So the drawing cuts each edge of a vertex
   with a ring where it enters the ring (`_cut_edge_at_rings`). The curve keeps its
   shape, but it ends 6 px earlier, and the owner sees the edges shrink.
2. **The drawing keeps a margin for the ring.** `_get_drawing_margin` is the
   padding and the ring, 14 px, and the extent counts the ring too.
3. **A label lies on lines.** The drawing paints each edge and then its label, one
   edge after the other. The line of an edge runs through the text of its own
   label, and a later edge can cross the label of an earlier one. A label has no
   background.

## The decision

- **A highlight paints the border of the box.** The box of the highlighted vertex
  takes the border `highlight`, `highlight_width` wide. The boxes of the vertex
  under the pointer and of the vertices that an edge joins to it take the border
  `light_edge`, the color of their lit edges, `highlight_width` wide; the box under
  the pointer is also filled with `light`. A highlighted vertex keeps the
  highlight when the light also reaches it. A backend draws a border inside its
  rectangle, so the box keeps its size and the content keeps its place.
- **No ring, and no cut at a ring.** Every edge ends at the box with its padding,
  with a highlight or not. `_cut_edge_at_rings`, `_cut_curve_at_rings`,
  `_split_bezier`, `_find_rim_crossing` and `_NO_RIM` go, and `_get_drawn_rim`
  takes no flag. `GraphTheme` loses `highlight_gap`. The margin of the drawing and
  of its extent is the padding, so the whole drawing moves 6 px up and to the
  left.
- **A label stands on the lines.** The drawing paints all lines first, then all
  labels. Behind each label it paints a rectangle in `label_fill`, the color of the
  page (`ColorRole(:background)`), `label_padding` (2 px) larger than the label on
  each side. So no line crosses the text of a label, and the line of an edge
  stops at its own label and goes on after it, as draw.io and yEd draw labels. The
  label is still found by identity, so its selection and its click do not change.

## The steps

1. ✅ **A highlight paints the box.** `GraphLayoutToGraphics.jl`: the border of the
   box, no ring, no cut, the margin and the extent; `GraphTheme.jl`: no
   `highlight_gap`, and the docstrings of `highlight`, `highlight_width`, `light`
   and `light_edge`. Tests: with the highlight and with the light, each edge keeps
   its points and the box keeps its place and size; the border takes the color and
   the width; the margins in the graph tests are the padding; the theme test, the
   state machine test and the process test count and measure no ring. Run
   `test_graph()`, `test_fsm()` and `test_process()`.
2. ✅ **A label stands on the lines.** The order of the drawing, the rectangle behind
   each label, and `label_fill` and `label_padding` in `GraphTheme`. Tests: each
   label comes after every line, on a rectangle of `label_fill` that is larger by
   `label_padding`; a click on a label still puts the caret in it. Run
   `test_graph()`.

   Done, steps 1 and 2 in one commit, because both change the one paint loop. The
   drawn edges no longer hold the index of their boxes, which only the ring cut
   read. The existing test "a click on the label of an edge puts the caret in the
   label" covers the click. Found in the work: the zoom test chose a box whose
   corner is at least 10 px inside the window; with the margin of 8 px the box at
   the top-left is drawn at 8 px, so the test now takes a corner at 0 px or more.
   Results: `test_graph()` 634 pass, `test_fsm()` 179 pass, `test_process()` 316
   pass.
3. ✅ **Pictures, suites and guides.** Pictures of `graph_services_example` with and
   without the light, and of the study map. Run `test_research()` and
   `test_example` for `graph_example` and `graph_services_example`. The guides:
   `graph.md`, `fsm.md`, `process.md`. Then the plan moves to `plan/done/`.

   Done. Found in the work: the research test of the light counted the rings in
   the color of the light; the cards of the items have a border in the color of
   `light_edge` of their own, so the test now counts the boxes that the light adds
   (5 for the decision and the items it joins) and the one filled box. Results:
   `test_research()` 382 pass; `test_example(graph_services_example)` 14 559
   pass; `test_example(graph_example)` 13 206 pass and the 4 REPL failures of
   `main` (`SelectionMismatchException` at the XML child). The pictures of
   `graph_services_example` show each label breaking its line, and with the light
   on `api` the borders of 6 boxes in the light, the fill of `api`, and the edges
   as they are without the light; the study map shows its label on the color of
   the page; no fault.

## Notes

The work happens in the worktree `projectured-julia-graph-highlight` on the branch
`graph-highlight`. The landing on `main` waits for the owner.
