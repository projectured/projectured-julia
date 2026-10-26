# The study map curves and scrolls, and a larger graph example

Status: IN PROGRESS, 2026-10-26, on the branch `graph-examples`, in the worktree
`projectured-julia-graph-examples`. The owner asked for both parts on 2026-10-26.

## The ask

The owner, 2026-10-26, on the open items of the graph work: "2: let's have the
curved edges and the scrolling" (the map of a study), and "3: yes" (a larger graph
example that shows labels, curved edges, the zoom and the scroll).

## The problem

The facts at `main` `31b19cda3`. Find each function by its name.

1. `make_research_map_projection` builds its own chain: `ResearchMapToGraph`, then
   `GraphGraphToGraphLayout(engine; border)` and `GraphLayoutToGraphicsCanvas()`,
   with the widgets of a part as the recursion. It does not use
   `make_scrolling_graph_projection`, and its edges are straight.
2. It passes a `border` of 14 px, the padding and the ring, so that the frames of
   the boxes have room. The force-directed engine starts a layout with no extent
   at that border. The drawing now keeps that margin itself
   (`_compute_drawing_map`), so the map has 28 px of empty room at the top-left.
   The border came in `fa1d02432` on a `main` that did not have the margin yet.
3. In the map view, `_build_study_view` puts the map as the last row of a
   `VerticalLayout`. A row of a `VerticalLayout` gets no height, so a pane around
   the map would take the height of the map, and nothing would scroll it up and
   down. A `GridLayout` gives a row a `Fill` height and keeps its children in
   `children`, so the path of the map, `.children[k]`, stays the same.
4. `graph_example` has three vertices. It is the only example that opens as a
   diagram; `fsm_example` and `process_example` open as text.

## The decision

- **The study map.** Its edges are curves, it is in its own scroll pane, and in
  the map view it takes the rest of the height of the view, so it scrolls both
  ways while the title and the switch of the views stay. The `border` goes,
  because the drawing keeps the margin.
- **A larger example, `graph_services_example`.** The services of a small shop
  and how they call each other: 15 vertices, each a `WidgetLabel` with the name
  of a service, and directed edges with a label each, such as "calls", "reads"
  and "publishes". Its edges are curves. It is larger than a window when zoomed
  in, so it shows the scroll too.

## Steps

Do the work in the worktree. Commit each step. Do not land on `main` before the
owner approves. Render each changed example in a window of 900 × 700 px with real
fonts and look at it before a step is done.

1. **The study map.** Change `make_research_map_projection` and the map view of
   `_build_study_view`. Run the tests of the research domain. Render a study in
   the map view.

   **Done.** The facts of the implementation:
   - The map view prints its rows as a `GridLayout` whose last row is `Fill`.
     The natural row of a study ended with a fixed `VerticalLayoutToGraphicsCanvas`,
     so it now dispatches on the type of the view: a vertical layout or a grid.
   - The test of the light of the map counts the rings inside the viewport of the
     pane too.
   - The research suite passes (377). A render of the concluded study in the map
     view, 900 × 700 px with real fonts, shows curved edges; a plain turn of the
     wheel scrolls the map while the title and the switch stay; no fault.
2. **The larger example.** Add `make_graph_services_document_example`,
   `make_graph_services_projection_example` and `graph_services_example`, and
   register them as `fsm_toggle_example` is. Run `test_example` for it and the
   graph suite. Render it at zoom 1, zoomed in and scrolled.
3. **The guides.** Write the map in the guide of the research domain and the new
   example in [graph.md](../../documentation/package/domain/graph/graph.md).
   Move this plan to `plan/done/`.
