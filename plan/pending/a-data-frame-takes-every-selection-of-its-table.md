# A data frame takes every selection of its table

Status: pending. Written 2026-11-12.

## The ask

The probes after the plan
[a-list-starts-at-its-first-node-in-view.md](../done/a-list-starts-at-its-first-node-in-view.md)
found two faults of the table of a data frame, and a stall. The owner asked for
a plan for the two faults first, with the stall in a second step.

## What the probes found

`main` `73774bb0a`, the data frame of 1000 rows of `test_scroll_work`, an editor
that gets its events as a person gives them: `MouseMove`, `MouseDown`,
`MouseUp`, `MouseScroll`.

1. **A press in the field of a filter fails.** The table answers
   `Compound[Select(column_headers[2].children[2].content{0}), StartDragOperation]`.
   The data frame passes the selection on in the paths of the table, and the
   root refuses it with a `SelectionMismatchException`. Each press in a field of
   the filter row fails, also as the first press after the print.
2. **A selected cell stops the wheel at the move of the head.** When the row at
   the top is more than 200 rows from the head of the list
   (`_TABLE_RELOCATION_DISTANCE`), the table moves its head to that row
   (`_add_top_row`). Its answer holds the write of `cells` and the selection
   shifted to the new head, `Select(cells[-200][2].value{5})`. The data frame
   passes that selection on in the paths of the table, and the root refuses it.
   With no selection in the table, the wheel goes on.
3. **The move of the head stalls the wheel.** In real windows, the frame of that
   notch takes about 395 ms: about 300 ms outside the paint and 95 ms in the walk
   of the paint. A plain notch takes 9 to 13 ms. It is the same before and after
   the plan of the list. With the SDL backend on the offscreen driver:

   | Notch | Rows made new | Rows taken from the list before | Cells computed |
   | --- | --- | --- | --- |
   | A plain notch | 2 | 0 | about 491 |
   | The move of the head | 203 | 38 | 3818 |

   The headless backend reads the whole drawing in each frame, so it links each
   row and does not show this cost: there the move takes 799 rows and makes none.

The present test of a press in a field of the filter row
(`DataFrameFilterTest.jl`) reads one `MouseClick` from the projection, and the
table answers that click with a selection alone. So the test passes, and it
does not see fault 1.

## The cause

**Faults 1 and 2 have one cause.** The data frame reads an answer of its table
in `read_intent` of `DataFrameViewToWidget`:

- A selection alone takes the full conversion
  (`read_intent(…, ::ReplaceSelectionOperation)`): a cell, a row, a column, a
  header, the field of a filter and the corner each go to their path in the
  view, and a path that names no part of the view gives no operation.
- A part of a compound goes through `_convert_table_write`. It converts a
  selection only when `_find_cell_view_path` finds a cell in the rows of the
  view. Any other selection falls through to `return operation`, and it goes on
  in the paths of the table.

In fault 1 the selection is in the field of a filter, which is not a cell. In
fault 2 the selection names a cell, but `_find_frame_row` counts its row from
the anchor that the view has before the compound. The compound moves the head
200 rows on, and the table counts the selection from the new head, so the row
is before the first kept row and the conversion finds no cell.

**The stall.** The view builds a new list of rows from its new anchor
(`_make_row_list`), and the grid of the table keeps the print of each row by the
row (`KeptListPrints`). For each new head, `start_kept_list_head!` keeps the
lowest and the highest count that the head before linked, and
`_count_kept_list_elements` walks from the new head as far as those counts. The
counts are from the old head, but the walk takes them from the new head. After a
move of 200 rows forward:

| Rows | Count from the old head | Count from the new head | The walk now |
| --- | --- | --- | --- |
| 1 to 200 | 1 to 200 | -199 to 0 | not reached: the walk goes back only as far as the new head links |
| 201 to about 250, in view | 201 to 250 | 1 to 50 | reached |
| about 251 to 450 | not linked | 51 to 250 | reached, so the view makes these rows |

So the walk makes about 200 rows that no link needs and the view does not show,
and it does not reach the rows before the new head, whose prints it could keep.

## The way of the change (my proposal)

1. **One conversion for each selection of the table.** `_convert_table_write`
   gives a selection to the same conversion as a selection alone, wherever it
   is in the compound. A selection that names no part of the view gives no
   operation. A selection of the table never goes on in the paths of the table.
2. **A part of a compound counts from the head that the parts before it leave.**
   When the compound writes `cells`, a move of the head by `k - 1` rows, the
   conversion counts the rows of the parts after that write from the anchor that
   it writes, `view.anchor + k - 1`. So the shifted selection names the same row
   of the frame as before the move.
3. **The walk of the counts measures the old extent from the new head.**
   `start_kept_list_head!` keeps the extent of the head before, and the walk
   moves it by the count that the head before gave to the element of the new
   head, minus 1. If the head before did not link that element, the walk keeps
   the extent as it is now.

## Decisions (my proposal)

- **D1. Every selection of the table goes through the full conversion.** The
  other way is to add the field of a filter to `_convert_cell_operation`. That
  leaves the same gap for each other part of the table in a compound: a header,
  a row, the corner.
- **D2. The conversion counts each part from the anchor that the compound
  leaves before it.** The other way is to drop the shifted selection, because
  the selection of the view names a row of the frame, and a move of the anchor
  does not change it. That is shorter, but it holds only while the shift is the
  sole selection in a compound that moves the head. D2 holds for any order.
- **D3. The kept prints shift the old extent, and the view keeps its new list.**
  The other way is a view that moves its head inside the list that it has, and
  makes no new list. That keeps the nodes, so the paint would also keep their
  records, but it changes how the view builds its rows, and the walk of the
  counts must be right in any case.
- **D4. The new tests run through a real editor** with `MouseDown`, `MouseUp` and
  `MouseScroll`, as `DataFrameCellTest.jl` does, because the fault is in the
  answer to a press, which a `MouseClick` read from the projection does not
  give. The guard of the stall runs with the SDL backend on the offscreen
  driver, because the headless backend links every row.

## Keep

- A press on a cell, a row, a column and a header selects as it does now.
- A key in the field of a filter edits the filter, as the present test shows.
- A move of the head keeps the row at the top in its place on the screen.
- The view makes a row only where a link of the list needs it.

## Rule of measurement

A time or a profile runs only on the word of the owner, in the lane
`taskset -c 28,30,31`, through `bounded-run`, with the load and the busy share
of the lane written beside it. The runs alternate as A B A B A, where A is the
base of the branch. A count needs neither.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [ ] **The tests, failing where they must.**
   - `DataFrameFilterTest.jl`: through a real editor, a press in the field of a
     filter puts the caret in the text of that filter, and a key then edits it.
   - `DataFrameTableTest.jl`: through a real editor, a frame of 1000 rows, a
     press on a cell of row 1, and the wheel down until the view moves its
     anchor. Assert that each frame runs, that the anchor moved, and that the
     selection still names row 1 and the same column.
   - `ScrollWorkTest.jl`: the data frame with the SDL backend on the offscreen
     driver, scrolled to the move of the head. Assert that the notch of the move
     makes no more new rows than a plain notch, read from the rows that the view
     keeps (`_MadeRows`).

   Mark each assertion that `main` fails with `@test_broken` and its reason.
   Commit.
2. [ ] **Every selection of the table reaches the view.** Points 1 and 2 of the
   way of the change. Promote the assertions of step 1 that pass. Run
   `test_dataframes()` and the table tests of `test_platform()`. Commit.
3. [ ] **The move of the head makes only the rows that a link needs.** Point 3.
   Promote the assertion of step 1, and write the counts of the move in this
   plan. Run `test_dataframes()`, `test_scroll_work()` and the tests of the kept
   prints and of the grid of a list in `test_platform()`. On the word of the
   owner, time the move of the head in real windows, and write what is left of
   the 395 ms. Commit.
4. [ ] **The guide and the end.** Describe the conversion of a compound and the
   extent of the kept prints in the documents of the data frame and of the
   collection package. Move this plan to `plan/done/`. Commit.

## Not in this plan

- The records of a new list in the paint: about 95 ms of the move of the head
  are the walk that records the nodes of the new list (875 guard reads). D3 of
  this plan does not change them.
- `hit_element_at` before the head of a list: it stops at the first element that
  starts before the point, before it tests it, so a point inside a row before
  the head hits only on the top line of that row. The table finds its rows with
  its own lookup, so a click in a table is right.
- The search for the shape of the pointer, which reads where each row starts
  from the head after each frame: 67 starts at the top of the table and 292 at
  60 notches down.

## As built

Nothing yet.
