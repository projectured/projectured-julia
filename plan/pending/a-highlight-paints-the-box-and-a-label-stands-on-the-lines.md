# A highlight paints the box, and a label stands on the lines

Status: IN PROGRESS on the branch `graph-highlight`. The owner agreed on 2026-10-27, and asked for the plan and its
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

1. **A highlight paints the box.** `GraphLayoutToGraphics.jl`: the border of the
   box, no ring, no cut, the margin and the extent; `GraphTheme.jl`: no
   `highlight_gap`, and the docstrings of `highlight`, `highlight_width`, `light`
   and `light_edge`. Tests: with the highlight and with the light, each edge keeps
   its points and the box keeps its place and size; the border takes the color and
   the width; the margins in the graph tests are the padding; the theme test, the
   state machine test and the process test count and measure no ring. Run
   `test_graph()`, `test_fsm()` and `test_process()`.
2. **A label stands on the lines.** The order of the drawing, the rectangle behind
   each label, and `label_fill` and `label_padding` in `GraphTheme`. Tests: each
   label comes after every line, on a rectangle of `label_fill` that is larger by
   `label_padding`; a click on a label still puts the caret in it. Run
   `test_graph()`.
3. **Pictures, suites and guides.** Pictures of `graph_services_example` with and
   without the light, and of the study map. Run `test_research()` and
   `test_example` for `graph_example` and `graph_services_example`. The guides:
   `graph.md`, `fsm.md`, `process.md`. Then the plan moves to `plan/done/`.

## Notes

The work happens in the worktree `projectured-julia-graph-highlight` on the branch
`graph-highlight`. The landing on `main` waits for the owner.
