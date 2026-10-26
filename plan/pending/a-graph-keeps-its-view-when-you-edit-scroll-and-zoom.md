# A graph keeps its view when you edit, scroll and zoom

Status: IN PROGRESS, 2026-10-26, on the branch `graph-view`. The owner approved the plan on 2026-10-26.

## The ask

The owner, 2026-10-26: "Check the graph example that it works with both scrolling
and graph zooming together including selecting content and editing, because both
zoom and scroll seems to reset and work incorrectly." After the report of three
causes, the owner agreed that a zoom keeps the point under the pointer in place,
through a new wrapping operation that the nearest scroll pane turns into a scroll.

## The problem

The facts at `main` `e2a8bdeec`. Find each function by its name. A headless run of
`graph_example` in a window of 900 × 700 px did these steps: 8 notches of Ctrl and
the wheel over the JSON box, 3 turns of the wheel down, a click into the key
`"active"`, and the text `42`. No fault occurred, and nothing printed again.

1. **An edit moves every vertex.** The text `42` made the JSON box 14 px wider.
   The `placed` cell of `GraphGraphToGraphLayout` runs the engine again on each
   change of a size, and the force-directed engine starts from its spiral. So the
   JSON box went from y 740 to y 339 at the same zoom, and every other box moved
   too. A drop keeps the places, because it writes a `:start` for each vertex into
   `graph.constraints`, but an edit of a content is no drop.
2. **A turn of the wheel to the bottom pins the view to the end.** The third turn
   reached the end of the drawing, and `_scroll_pane_by` wrote
   `follow_end = true`. The rule "back at the end: follow again" applies to every
   `WidgetScrollPane`, also to a pane that was not made to follow its end. After
   that, each growth of the drawing moves the view to the new end, the stored
   `scroll_position` has no effect, and a turn down does nothing. The drag of a
   bar to the end does the same (`follow_end` in the reader of the bar). Only the
   terminal, the assistant, the evaluator, the MCP log and the task group make a
   pane that follows its end.
3. **A zoom keeps the top-left corner of the drawing in place.**
   `_compute_next_zoom` chooses the shift so that the top-left corner of the boxes
   stays. In a pane that is scrolled, the part under the pointer moves away: 8
   notches over the JSON box moved it from y 250 to y 740, out of the view. The
   graph can not scroll its pane, because a projection does not write the state of
   another projection.
4. `_pane_scroll_x` does not clamp a content with an extent as it reads the
   offset; `_pane_scroll_y` does. A zoom out shrinks the drawing, so an offset to
   the side can be larger than the room after it.
5. `_compute_zoom_map` moves the drawing right and down when a box would be drawn
   left of it or above it, but only when `layout.zoom` is set. With places kept
   from the last run, the pass that removes overlaps can push a box to a negative
   corner at the zoom `nothing` too.

## The decision

- **A layout keeps its places.** The layout stage keeps the corners of its last
  run, and gives the engine a `:start` at that corner for each vertex that it
  placed before. A box then stays where it is, and only the pass that removes
  overlaps moves a box that grew into another one. A new vertex has no start, so
  the forces place it among the others. The corners live in a `Ref` of the print,
  as the last lines of `make_text_block` do, so they are view state: a new print
  lays out the graph from the start, and the document does not change. The stage
  gives the starts only to an engine whose `get_supported_constraint_kinds` holds
  `:start`, and before the constraints of the graph, so a drop and a pin of the
  person win.
- **Only a pane that is made to follow its end follows it.** `follow_end` holds
  `true` while a pane shows the end of its content, `false` while a pane that
  follows its end is scrolled away from it, and `nothing` for a pane that never
  follows its end. `nothing` is the default. The wheel and the bar turn the value
  between `true` and `false`, and never from `nothing`. The makers that pass
  `follow_end = true` keep their behaviour; the panes of tables, texts, graphs and
  the explorer stop to follow their end. No new field: the type of the field
  becomes `Union{Bool,Nothing}`.
- **A zoom keeps the point under the pointer.** A new wrapping operation of the
  platform widgets, `KeepPointOperation(operation, move)`, says: `operation` moves
  the point of the content under the pointer by `move` pixels. The nearest scroll
  pane on the way out answers `operation` and a scroll by `move`, so the point
  stays under the pointer, and the panes further out see no wrapper. With no pane,
  applying it applies `operation`. The drawing keeps its rule for the top-left
  corner, so it starts at its margin, and answers the zoom wrapped in
  `KeepPointOperation`: over a box, the move of the box, so the box stays under
  the pointer; elsewhere, the move of the point of the layout under the pointer.
  `_pane_scroll_x` clamps as it reads, as `_pane_scroll_y` does. A transform pane
  applies the inner operation and does not pan; that is outside this plan.
- `_compute_zoom_map` moves the drawing right and down for a negative corner at
  every zoom, also at `nothing`.

## The steps

1. ✅ **A layout keeps its places on a change of a size.** `GraphGraphToGraphLayout`:
   the `Ref` of the last corners, the starts for an engine that takes them, the
   order before `graph.constraints`. `_compute_zoom_map`: the correction at every
   zoom. Tests in the graph suite: an edit that makes a box larger keeps the
   corners of the other boxes; a box that grows into another one moves that box
   only; a new vertex gets a place and the old ones keep theirs; a drop still
   puts the vertex where the person dropped it; an engine without `:start` lays
   out as before. Run `test_graph()`.

   Done. Found in the work: the stage must keep only the corners that the engine
   chose by itself. A vertex that a `:pin` or a `:start` of the projection or of
   the graph placed keeps no corner, because otherwise the undo of a drop leaves
   the vertex at the dropped place (`the inverse of a drop puts the vertex back`
   failed). The pass that removes overlaps moves both boxes of a pair that hold a
   start by half each, so the test asserts that the two are apart and that a box
   which the grown box does not reach stays. Graph suite: 568 pass.
2. ✅ **Only a pane that is made to follow its end follows it.** `WidgetScrollPane`:
   the type and the default of `follow_end`, the docstring. `_scroll_pane_by` and
   the reader of the bar: the change between `true` and `false` only. The
   positional makers (`GraphGraphToWidgetScrollPane`, the panes of a table, the
   pane of a scroll layout) pass `Cell(nothing)`. Tests: a pane with the default
   does not follow its end after a turn to the end, and its content can grow under
   it; a pane made with `follow_end = true` keeps its three rules. Run the scroll
   pane tests, `test_platform()`, and `test_dataframes()`, because tables change.

   Done. The wheel already re-pinned only at `follow_end === false`; the bar
   re-pinned at `!following`, which now reads `=== false`. The scroll pane tests,
   the evaluator test (250 pass) and the assistant test (191 pass, 4 broken as on
   `main`) pass. `test_platform()` and `test_dataframes()` run after step 3,
   because step 3 changes the platform too.
3. ✅ **A zoom keeps the point under the pointer.** `KeepPointOperation` with
   `get_wrapped_operation`, `rewrap_operation` and `evaluate_operation`, in the
   widget slice of the platform. The scroll pane turns it into its inner operation
   and a scroll, beside `ShowSelectionOperation`. `_pane_scroll_x` clamps as it
   reads. `_read_ctrl_wheel` answers the wrapped zoom. Tests: in a pane, a notch in
   and a notch out over a box keep that box at the same point of the window, and
   over empty room they keep the point of the layout; in nested panes only the
   inner one scrolls; without a pane, the zoom works as before. Run the scroll pane
   tests and `test_graph()`.

   Done. `KeepPointOperation.jl` in the widget slice. `_show_pane_selection`
   takes the wrapper off and adds `_scroll_pane_with_point`, which scrolls from
   the offset that the pane draws with and clamps at 0 only. `_compute_zoom_move`
   finds the box under the pointer with its padding (`_find_node_at`). The test of
   a box runs in a window of 360 × 300 px, so the drawing is larger than the view,
   and checks that the pane scrolled. The zoom tests: 38 pass.
4. ⬜ **The example works when you do all of it together.** A headless test in the
   graph suite that does the steps of the problem: the zoom, the scroll to the
   end, the click, the text, one more turn and one more notch. After each step the
   JSON box stays at its point of the window, the scroll does what the turn asked,
   and the caret stays in the key. Pictures of `graph_example`,
   `graph_services_example` and the study map, looked at before the landing. The
   guides: `graph.md`, `graph-layout.md`, `widget.md` and the guides that name
   `follow_end`. Run `test_graph()`, `test_research()`, and `test_example` for the
   two graph examples.

## Notes

The work happens in the worktree `projectured-julia-graph-view` on the branch
`graph-view`.
