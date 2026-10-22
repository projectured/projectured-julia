# A graph scrolls in its own pane and draws dark edges

Status: PENDING, 2026-10-22. Not started. The owner approved the decisions
below on 2026-10-22. The owner did not yet ask for the implementation.

This plan continues
[the-edges-of-a-graph-reach-their-boxes-curve-and-zoom.md](../done/the-edges-of-a-graph-reach-their-boxes-curve-and-zoom.md),
on the same branch, `graph-edges`.

## The ask

The owner, 2026-10-22:

- "why is the vertex and edge color gray instead of black? is that a theme
  thing?"
- "generally graphs are large, so when they are open as a tab or embedded into
  something else, they need a scroll pane widget, but not always. small graphs
  should go without them, so I don't know how to handle this."
- "I would say that a graph should be able to be transparent."

## The problem

The facts at the branch `graph-edges`, `b055c2826`. Find each function by its
name.

1. **The gray is the theme.** `GraphTheme` gives `edge` and `node_border` the
   color role `border_strong`, step 8 of the 12 neutral steps, with a contrast
   of at least 3:1. Text is the role `text`, step 12. The role `text_muted` is
   step 11, with a contrast of at least 4.5:1.
2. **No graph scrolls.** The graph chain gives a `GraphicsCanvas` as large as
   its layout. In the window scene of the tests, a graph zoomed to 4 is
   4620 × 2486 px in a window of 900 × 700 px, and nothing scrolls it.
3. **A scroll pane already scrolls only when it must.** `WidgetScrollPane` takes
   its size from, in this order, a size set in code, the room that its parent
   offers, and the size of its content. Its bars are `:auto`: a bar shows only
   while the content is larger than the view. So a small graph in a pane looks
   as it does without one.
4. **A tab does not scroll.** The owner decided on 2026-09-25 that the content
   scrolls where it is made, and a tab page gets no scroll pane.
5. **The natural row of a graph can not hold the graph in a pane as it is.** The
   pane prints its content through its recursion. In the natural renderer that
   recursion sends a `GraphGraph` back to the row of the graph, and the row
   would make a pane again. A `NestingProjection(A, B)` prints the children of A
   through B, and only the children of B through the outer recursion
   (`print_document` of `NestingProjection`). So a pane stage nested over the
   graph stages makes no loop.
6. **A pane paints a fill.** `WidgetScrollPaneToGraphicsCanvas` fills the
   content part with the theme color `background`. One pane can turn the fill
   off: `_get_part_color` reads `content_color` from the `style` of the pane.
7. **A graph is transparent now.** The drawing paints only lines, labels and
   boxes, and `GraphicsCanvas` has no background.

## The decision

The owner approved these on 2026-10-22.

- **The edges are dark.** `GraphTheme.edge`, the line and the arrowhead of an
  edge, takes the role `text_muted`. `node_border` keeps `border_strong`, so a
  box of a graph matches a card of the rest of the editor.
- **A graph view holds itself in a scroll pane.** The pane is made where the
  graph view is made, not by the tab. There is no rule for small and large
  graphs: the pane shows no bar while the graph fits (fact 3).
  - A new stage, `GraphGraphToWidgetScrollPane`, makes
    `WidgetScrollPane(graph; style = (content_color = color_transparent,))`. It
    holds the graph by identity, as `AssistantToWidget` holds its conversation.
  - `make_scrolling_graph_projection(stages; measure, widget_theme = nothing)`
    returns `NestingProjection(ChainingProjection(GraphGraphToWidgetScrollPane(),
    WidgetScrollPaneToGraphicsCanvas(widget_theme; measure)), stages)`. `stages`
    is a graph chain, such as `GraphToGraphics()`.
  - The natural row of `GraphGraph` and `make_graph_projection_example` use it.
    `GraphToGraphics` stays the plain chain, so a host that embeds a graph in a
    widget of its own decides for itself.
  - A pane gives Ctrl and the wheel to its content first and never scrolls on
    Ctrl, so the zoom of the layout still works. A plain turn that the graph
    does not take scrolls the pane.
- **A graph stays transparent.** The pane paints no fill. The host paints the
  background: a tab page, a card or a window. No `background` is added to
  `GraphTheme` now.

## Steps

Do the work in the worktree `projectured-julia-graph-edges`, on the branch
`graph-edges`. Commit each step. Do not land on `main` before the owner
approves. Test with the narrowest test functions of each package.

1. **Dark edges.** Change the default of `GraphTheme.edge` to
   `ColorRole(:text_muted)`. A test in `GraphThemeTest.jl` asserts that the line
   and the arrowhead of an edge take the color of the role `text_muted`, and
   that the box border keeps `border_strong`. Draw a picture of the graph of
   seven cards to check.
2. **The stage and the function.** Add `GraphToWidgetScrollPane.jl` with
   `GraphGraphToWidgetScrollPane` and `make_scrolling_graph_projection`. The
   stage maps `rest...` of the graph to `content.rest...` of the pane, and back.
   Tests in a new `GraphScrollPaneTest.jl` assert these facts:
   - a small graph in an offer of 900 × 700 px shows no scroll bar, and each
     box is drawn where the plain chain draws it;
   - the pane paints no fill;
   - a graph zoomed to 4 in the same offer scrolls by a plain turn of the
     wheel, and the drawing moves up by the distance of the scroll;
   - Ctrl and the wheel zoom the layout through the pane;
   - a click on the content of a vertex selects in that content, and a vertex
     maps forward to its box.
3. **The hosts.** The natural row of `GraphGraph` and
   `make_graph_projection_example` use `make_scrolling_graph_projection`. The
   drag tests and the zoom tests then run through the pane. Update the test
   "the natural renderer draws a graph as a diagram", whose walker does not go
   into a viewport. Run `test_graph()`, the FSM and process diagram tests, and
   the tests of the natural renderer of the platform. Check omnet-julia for a
   test that opens a graph through the natural renderer.
4. **The guides.** Write the dark edges, the pane and the transparent
   background in [graph.md](../../documentation/package/domain/graph/graph.md).
   Move this plan to `plan/done/`.

## Open items

- The map of a study (branch `research`) builds its own chain. It can use
  `make_scrolling_graph_projection` after both branches land.
- The hosts in omnet-julia build their own chains and stay as they are.
- The pane does not keep its scroll position when the graph view is printed
  again, as the zoom does not.
