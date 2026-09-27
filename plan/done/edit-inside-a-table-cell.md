# Edit inside a table cell

## Problem

A click in a cell of a `WidgetTable` puts the caret in the cell, but no key
edits the cell. Measured on 2026-09-27 with a table of four cells — a
`JsonString`, an `XmlElement`, a `WidgetText` and a `TextBlock`: the click
gives `.rows[1][c].…`, and `KeyPress('X')`, Right and Backspace each give
`nothing`.

Two causes, both in the readers of `WidgetTableToGraphicsCanvas`:

1. The eager table (`rows` is a vector) sends a key to its own `GridLayout`.
   The grid routes a key to the child that the grid's own `selection` names.
   The table makes that grid inside its printer, so the grid has no selection,
   and the key goes nowhere.
2. Both forms keep only a `ReplaceSelectionOperation` from a cell. The eager
   form drops every other operation. The list form returns it without the
   `rows[k][c]` prefix, so a text edit points at the wrong place.

The backward map of the table (`children[i].…` → `rows[r][c].…`) is correct and
does not change.

## Design

The table does what `WidgetComposite` and `WidgetSplitPane` do with their
children:

- An event with a position (a press, a move, a scroll) goes to the cell under
  the pointer, as it does now.
- An event with no position (a key, a character) goes to the cell that the
  selection of the table is in, and to no other cell.
- The answer of the cell goes up through `reroot_operation` with the steps from
  the table to the cell. A selection, a text edit and a value replace all get
  the prefix; an operation that carries its own document stays as it is.

A selected row, column or whole table is in no cell, so a key there goes to no
cell. A whole selected cell (`rows[r][c]∅`) is in its cell, so a key that the
table does not take (a character, Backspace) goes to the cell with the whole
selection, as a layout sends a key to a whole selected child.

No new event, payload or channel.

## Steps

- [x] 1. The eager table sends an event with no position to the selected cell,
      and reroots every answer of a cell (key, click, Enter).
- [x] 2. The list table reroots every answer of a cell.
- [x] 3. A test: a JSON, an XML, a `WidgetText` and a `TextBlock` cell take a
      character, an arrow and Backspace, in both forms of the table.
- [x] 4. Run the table tests and the REPL loop of the table examples.
- [x] 5. A cell of a list table gets the caret. The owner gave permission for
      the sealed `selection/SelectionDefaults.jl` on 2026-09-27.

## What was done

- `_wt_find_grid_steps(gidx, geom)` gives the steps from the table to a grid
  child (`rows[r][c]`, `column_headers[c]`, `row_headers[r]`, nothing for the
  corner). `_wt_grid_ref_to_table` uses it, and so does the new route, so the
  backward map and the route can not disagree. `_wt_get_cell_steps(r, c)` gives
  the steps to a body cell; the list form uses it too.
- `_wt_route_event` splits the events that the table does not take: one with a
  position goes to the grid as before, one with none goes to
  `_wt_route_to_selected_cell`. The route reads the shape of the selection with
  `_wt_selection_shape` (a band routes nowhere) and the cell with
  `_wt_ref_to_grid_index`, the forward map of the table.
- An operation that reaches the table from a later stage still goes to the
  grid, as before.
- The click route and the Enter route of both forms now reroot every answer
  with `reroot_operation`, not only a selection.
- A header cell with a caret in it (`column_headers[c].…`) also gets its keys,
  but a click on a header selects the column, so no caret reaches a header by a
  click today.
- `widget.md` says that the table gives a key to the cell its selection is in.

## Test results (2026-09-27)

- `test_widget_table_cell_editing()` (substrate): 42 pass, 2 broken (the list
  form, fixed in step 5). `test_table_cell_editing()` (umbrella, JSON and XML cells):
  pass.
- The table suites of the substrate and `test_table_selection`,
  `test_table_navigation`: the same counts as `main` (`TableSelection` has 9
  failures and 1 error on `main` too).
- `test_example` + `test_repl` on fresh examples, `main` → branch:
  `table` 2536 / 169 fail / 9 broken → 2713 / 1 / 0; `math_table`
  3969 / 46 / 15 → 3993 / 28 / 9; `widget_table` and `widget_table_frozen`
  unchanged; every REPL loop 225 pass on both. No failing case is new on the
  branch; 186 cases of `main` ("insert produced nothing" in a cell) pass.
- The 28 `math_table` failures that remain are edits of a `MathVariable` name.
  The same edit gives `nothing` outside a table, so they belong to the math
  projection.

## Step 5: the selection walk steps into a list

`set_selection!` walks the path with `_selection_child` in
`source/kernel/selection/SelectionDefaults.jl` (🔒). For a range step it needed
`applicable(length, document)`, and a `ListNode` has no `length` (it can be lazy
and endless), so the walk stopped at the list and the cell's own `selection`
stayed `nothing`. The reference evaluation of the same step
(`evaluate_reference_step`) indexes with `document[start + 1]` and has no such
check.

`_find_indexed_child(document, index)` now answers the child: a sequence with a
length is checked against it as before; one with none is indexed as
`evaluate_reference_step` indexes it, and a `BoundsError` means no child. The
kernel can not name `ListNode`, which lives in the collection package, so the
check is by what the node answers, not by its type. The other types with an
integer `getindex` and no `length` of their own are `HiddenElements`, an
`AbstractVector` that has a length, and `_Repeated`, a helper of the reflection
walk that no selection passes. The owner gave permission for the sealed file.

Results on the branch rebased on `main` at 4d9f08e3, against the same sets on
`main` in the same process: `test_widget_table_cell_editing()` passes in both
forms; `test_kernel()` has the six known failures of `main`; `test_substrate()`
has only the `AnchorPointTest` and `SplitPaneDragTest` failures that `main` has;
the table and `collection` examples have the counts of the first run.

`lazy_example` is left out of the sweep: its reader never ends on `main` too.
`read_intent` of `TextToGraphics` calls `_has_caret_span`, which runs `any` over
an endless `ListNode` of text. That is not part of this change.

## Not done

- **A drag in a cell does not reach the cell.** The table takes every
  `MouseMove` for its hover band, and `_wt_grid_passthrough` gives the grid
  table coordinates, not grid coordinates, for `MouseDown`, `MouseUp` and
  `MouseScroll`. So a text selection by drag inside a cell does not work. The
  owner chose to leave it out on 2026-09-27.
