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
  and how they call each other: 15 vertices, each the name of a service as a
  line of text (changed in step 3), and directed edges with a label each, such as "calls", "reads"
  and "publishes". Its edges are curves. It is larger than a window when zoomed
  in, so it shows the scroll too.

- **The texts of the example are editable.** `test_example` types into every
  text of an example. Two gaps made the texts of a graph not editable, and the
  owner chose on 2026-10-26 to fix them ("it's B, we need to be able to edit
  these, they should be fairly trivial"):
  - A text block that is the value of a field gets its caret from a parent as a
    flat `PositionReferenceStep`, which the text printer and reader do not read.
    `_text_flat_selection` reads it as the same flat caret.
  - The graph gives a key to the contents of the vertices only, and the stages do
    not map the path of an edge. The drawing gives a key and a click to the label
    of an edge as to the content of a vertex, and both stages map
    `edges[j]` ↔ `edge_layouts[j].edge`.

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
2. **Editable texts.** Read a flat `PositionReferenceStep` in
   `_text_flat_selection`. Route a key and a click to the label of an edge, map the
   path of an edge in both stages, and map a point on a label to the label. Tests:
   the type-in sweep of a graph whose vertex and edge label are text blocks, and
   of `graph_example`, has no failure; a click on a label puts the caret there.

   **Done.** The facts of the implementation:
   - `_text_flat_selection` reads a range step right on a text block as a place
     of its flat text.
   - The drawing keeps the IO map and the box of each label
     (`label_iomaps`, `label_boxes`). A key goes to the labels after the contents
     of the vertices (`_forward_to_selected`), a click and a point go to the label
     at their place when no vertex is there (`_find_label_at`), and a path into a
     label maps forward. `_reroot_part_answer` reroots the answer of a vertex
     content and of a label by one set of rules, with the path builder of each.
   - A span edit leaves the caret of a text block in its structural spelling,
     `.elements[i].elements[j].content{k}`, which names the same place as the
     flat `{k}`. The type-in sweep compared the spelling, so for a text-block
     target (`:texttext`) it now compares the flat place (`_get_text_block_caret`).
   - `test_example(graph_example)` has no type-in failure left; 4 failures of its
     REPL test stay, which were on `main` before: a key at the child of the XML
     vertex selects `children[2]`, which does not exist
     (`SelectionMismatchException`). The services example passes all its
     example tests.
   - The graph suite, the FSM and process diagram tests and the text tests pass
     (751).
3. **The larger example.** Add `make_graph_services_document_example`,
   `make_graph_services_projection_example` and `graph_services_example`, and
   register them as `fsm_toggle_example` is. Run `test_example` for it and the
   graph suite. Render it at zoom 1, zoomed in and scrolled.

   **Done.** The facts of the implementation:
   - A vertex and a label hold a line of text, a `TextBlock` in the font of the
     widgets (`_make_graph_text`), which a person can edit. A `WidgetLabel`, which
     the plan named, is display text with no caret, so the type-in sweep failed on
     it.
   - `test_example(graph_services_example)` passes with no failure. A render at
     900 × 700 px shows all 15 services at zoom 1; Ctrl and the wheel spread
     them, a plain turn scrolls, and no fault occurs.
4. **The guides.** Write the map in the guide of the research domain and the new
   example in [graph.md](../../documentation/package/domain/graph/graph.md).
   Move this plan to `plan/done/`.
