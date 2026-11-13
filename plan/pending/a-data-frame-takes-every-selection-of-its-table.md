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
3. **The view moves its head inside the list that it has.** When only the anchor
   of the view changes (the same frame, version, kept rows, columns and column
   anchor), the new head of the rows and of the row headers is the node of the
   list before at the new anchor, if a walk built it. So the nodes, their rows
   and their links stay. Else the view makes a new list, as now.
4. **The kept prints shift their reach only by a node that the head before
   linked.** `note_kept_list_link!` also notes the node of each link. When the
   new head is a node that the head before linked at the count `k`,
   `start_kept_list_head!` measures the extent of the head before from the new
   head: each count is `k - 1` less. A new head of another list, such as after a
   sort or a filter, keeps the extent as it is now.

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
- **D3. The view moves its head inside its list, and the kept prints shift only
  by a node that the head before linked.** Approved by the owner on 2026-11-13,
  after the first try failed. The first way was to shift the old extent by the
  count of the element of the new head, with a new list for each anchor. The
  element can not tell a list that moved under a view that stays from a new list
  under a view at its top, such as after a sort. Only the producer of the move
  knows it, and the same node carries it: a node of the same list keeps its
  neighbours, so each count moves by the same amount. See "Step 3, first try".
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

1. [x] **The tests, failing where they must.** Done; see [As built](#as-built).
   - `DataFrameFilterTest.jl`: through a real editor, a press in the field of a
     filter puts the caret in the text of that filter, and a key then edits it.
   - `DataFrameViewTest.jl`: through a real editor, a frame of 1000 rows, a
     press on a cell of row 1, and the wheel down until the view moves its
     anchor. Assert that each frame runs, that the anchor moved, and that the
     selection still names row 1 and the same column.
   - `ScrollWorkTest.jl`: the data frame with the SDL backend on the offscreen
     driver, scrolled to the move of the head. Assert that the list of rows
     from the new head is built no further than the list of a table at its top.

   Mark each assertion that `main` fails with `@test_broken` and its reason.
   Commit.
2. [x] **Every selection of the table reaches the view.** Done; see [As built](#as-built). Points 1 and 2 of the
   way of the change. Promote the assertions of step 1 that pass. Run
   `test_dataframes()` and the table tests of `test_platform()`. Commit.
3. [ ] **The move of the head makes only the rows that a link needs.** Points 3
   and 4. Promote the assertion of step 1, and write the counts of the move in
   this plan. Run `test_dataframes()`, `test_scroll_work()` and the tests of the kept
   prints and of the grid of a list in `test_platform()`. On the word of the
   owner, time the move of the head in real windows, and write what is left of
   the 395 ms. Commit.
4. [ ] **The guide and the end.** Describe the conversion of a compound and the
   extent of the kept prints in the documents of the data frame and of the
   collection package. Move this plan to `plan/done/`. Commit.

## Not in this plan

- The records of a new list in the paint: about 95 ms of the move of the head
  are the walk that records the nodes of the new list (875 guard reads). The grid
  of a list makes a new canvas node for each row at each new head, also when the
  head moves inside its list, so D3 does not change them. The proposal below
  ("A way that keeps what the producer knew") said that part 1 keeps them: that
  is wrong, as `_make_grid_list_node` in `GridList.jl` shows.
- `hit_element_at` before the head of a list: it stops at the first element that
  starts before the point, before it tests it, so a point inside a row before
  the head hits only on the top line of that row. The table finds its rows with
  its own lookup, so a click in a table is right.
- A drag across the text of a field of the filter row selects no range. The
  press puts the caret in the filter, but the start of the drag goes on in the
  paths of the table, so the move with the button held does not reach the field.
  It does not fail.
- The search for the shape of the pointer, which reads where each row starts
  from the head after each frame: 67 starts at the top of the table and 292 at
  60 notches down.

## As built

### Step 1: the tests, 2026-11-12

- `DataFrameFilterTest.jl`, "through a real editor, a press in a field of the
  filter row puts the caret in the filter, and a key edits it": the press, the
  caret at the end of the text `item` and the key `5` that makes it `item5` are
  three `@test_broken`. The press raises the `SelectionMismatchException`, which
  the test catches by its message.
- `DataFrameViewTest.jl`, "through a real editor, a selected cell stays selected
  when a far turn moves the anchor": a press on the text `row 1` selects
  `rows[1][2]…`, and turns of the wheel go on until the anchor moves. The turn
  that moves it fails, and the selection is not the same: two `@test_broken`.
  The anchor moves before the selection fails, so `view.anchor > 1` passes.
  `DataFrameTableTest.jl` tests the table interface of a frame, not the widget,
  so the test is beside "a scroll far from the anchor moves the anchor".
- `ScrollWorkTest.jl`, "a data frame at the move of the head of its table": the
  SDL backend on the offscreen driver, as `test_sdl` opens it.
  `_sw_count_built_rows` counts the nodes from the head whose links a walk
  built, and it reads no link that is not built. The test finds the table by
  `ProjecturedDataFramesTest._find_iomap_of`. The view keeps its `_MadeRows`
  only inside the computation of its rows, so the guard counts the built links
  of the list instead. At the top the list has 36 built rows; after the move of
  the head at notch 105, to the anchor 202, it has 238. One `@test_broken`.
- Results, Julia 1.13.1: the filters of a view 81 Pass and 3 Broken, a data
  frame drawn as a table 63 Pass and 2 Broken, a scroll costs what comes into
  view 25 Pass and 1 Broken.

### Step 2: every selection of the table reaches the view, 2026-11-12

- `read_intent` of a selection alone calls `_read_table_selection(iomap,
  operation, head)` with the head of the view now. `_convert_table_write` gives
  every `ReplaceSelectionOperation` of a compound to the same function, before
  the operations of a cell, so a selection that has no place in the view gives no
  operation. The branch of a selection in `_convert_cell_operation` is gone.
- `_convert_table_writes` walks the parts of a compound in order and keeps the
  place of the head. After a write of `cells` that does not come with a move of
  the columns, the head is `_get_head_place(view, anchor)` for the anchor that the
  write moves the view to (`_find_written_anchor`), and the parts after it count
  their rows from there. `_get_head_place`, `_find_frame_row`, `_find_view_path`,
  `_find_cell_view_path` and `_convert_cell_operation` take the head place, with
  the head of the view as the default, so every other caller is as it was.
- The five assertions of step 1 in `DataFrameFilterTest.jl` and
  `DataFrameViewTest.jl` pass, and the catch of the exception is gone from both
  tests.
- `test_dataframes()`: 621 Pass, where `main` gives 616 and the branch adds 5.
  Step 2 changes no file of the platform, so the table tests of
  `test_platform()` do not cover it, and they did not run.
- A probe of a drag across the text of a filter field: the press, the move with
  the button held and the release each run, and the caret stays at 4. See "Not
  in this plan".

### Step 3, first try: D3 is wrong, 2026-11-13

Not committed. `start_kept_list_head!(keep, head)` took the new head, read the
count at which the head before linked the element of `head` (`linked` of its
kept print), and moved the old extent by that count minus 1. The three layouts
(`GridList`, `GridColumnList`, `LayoutList`) passed their new head.

- `test_collection()` passed, with a new test of a head two rows further on.
- `test_layout_list()` failed 2 of its tests: "a row in the list two times
  prints at both places, each with the path of its place", and the same for a
  child in a column. The list changes from `[r1, r2, r1, r3]` to
  `[r2, r1, r3, r1]`, and the view shows the whole list. The new head `r2` was at
  count 2, so the walk moved its reach back by one and ended at count 3. It did
  not reach the second `r1` at count 4, did not find `r1` at two places, and the
  grid kept the old print of `r1` at count 2. The paths stay right, because a
  later walk under the same head reaches every link, but the rule "an element at
  two places is kept at neither" breaks.
- **The general fault of D3.** The shift is right only when the content moves
  under a view that stays: the move of the head of a table keeps the same rows at
  the same place on the screen. A sort or a filter makes a new list, and the view
  stays at its top. When the new head is a row that the head before showed, D3
  moves the reach although no row moved on the screen, so the rows in view print
  again instead of keeping their prints. The element of the new head can not tell
  the two cases apart. Only the producer of the move knows it.
- The code is undone. The guard of step 1 stays `@test_broken`.
  `_sw_count_built_rows` now counts with `_count_computed_links` of the
  collection package, which reads by `peek` and computes no link.

**A way that keeps what the producer knew.** Proposed in two parts, and approved
by the owner on 2026-11-13 ("Yes"); it is now points 3 and 4 of the way of the
change, and D3:

1. The view of a data frame moves its head inside the list that it has, when
   only its anchor changes: the same frame, version, kept rows and columns. The
   new head is the node of the old list at the new anchor, so the nodes, the rows
   and their links stay. This is the other way of D3. It also keeps the records
   of the paint, which are about 95 ms of the 395 ms.
2. The kept prints shift their reach only when the new head is a node that the
   head before linked: the same node, not only the same element. A node of the
   same list keeps its neighbours, so each count moves by the same amount. A
   sort or a filter makes new nodes, so its reach stays as it is now. For that,
   `note_kept_list_link!` also notes the node of each link.

### Step 3: the head moves inside the list, 2026-11-13

- **Point 4, the kept prints.** `KeptListPrints` has the field `nodes`, each node
  linked under this head with the count of its link. `note_kept_list_link!(keep,
  k, node)` notes it, and `start_kept_list_head!(keep, head)` takes the new head:
  when `nodes` holds it at `k`, the extent of the head before is `k - 1` less.
  `GridList`, `GridColumnList` and `LayoutList` pass their new head and the
  document node of each link. The reach of the walk always holds the head,
  because `lowest` starts at 1, so after a move of the head forward the walk
  also goes back over the nodes that the head before reached. They exist, so it
  builds none.
- **Point 3, the data frame.** `_MadeList` keeps the last list of the rows and
  of the row headers, with what it shows, the kept rows and the place of its
  head. `_make_row_list` and `_make_row_header_list` take the node at the new
  place with `find_computed_list_node`, a new function of the collection package
  that reads each link with `peek` and builds no node. When a link on the way
  does not exist, or the frame, its version, the kept rows, the columns or the
  column anchor are new, the view makes a new list as before
  (`_make_new_row_list`). `_MadeRows` starts a new set of rows only with a new
  list.
- The signatures of the exported `start_kept_list_head!` and
  `note_kept_list_link!` change. No other repository calls them. The released
  copy in `Projectured.jl` has them, so a release must take the change as a
  change of the interface.
- The recorded calls of the precompile workload that no longer resolve grow for
  the data frame package from 67 to 84, and a little for the packages that use
  the grid of a list. This is the known warning; the calls can be recorded again.
- Tests:
  - `CollectionDocumentTest.jl`: the present test passes the nodes, and a new
    test moves the head to the node of element 11 of a list of 40. The five
    elements in view keep their prints, the extent is `(-9, 5)`, and the walk
    builds no node past the view. A new list with its head at the same element
    keeps the extent `(1, 15)`.
  - `WidgetTablePartsTest.jl`, "far from the head, the table moves the head to
    the row at the top": the move builds no row, 401 before and after. Under the
    old rule the walk went as far as the head before linked, from the new head.
  - `DataFrameViewTest.jl`, "a scroll far from the anchor moves the anchor": the
    new head of the table is the node of row 301 of the list before.
  - `ScrollWorkTest.jl`: the guard of step 1 passes and is promoted.
- Results, Julia 1.13.1: `test_collection()` 205 Pass, `test_layout_list()` 101
  Pass, `test_widget_table_list()` 259 Pass, `test_scroll_work()` 26 Pass,
  `test_dataframes()` 622 Pass.
- **The counts of the move**, with the SDL backend on the offscreen driver, the
  frame of 1000 rows of `test_scroll_work`, at notch 105:

  | Notch | Rows made new | Cells computed |
  | --- | --- | --- |
  | A plain notch, before and after | 2 | about 491 |
  | The move of the head, step 2 | 203 | 3818 |
  | The move of the head, step 3 | 2 | 3018 |

  At the move the grids take 73 kept prints, print 4 rows that come into view,
  and print 1 row again whose count is off by 201. The computations that are left
  are mostly the 875 guards that the paint records for the new canvas nodes and
  589 lazy links of the new canvas lists.
- **Open: the header column builds 200 headers past the view.** After the move
  the list of rows has 37 built nodes and the list of row headers 236. The header
  column of the table mirrors the row headers with new nodes for each new head
  (`_make_header_row_node` in `WidgetTableParts.jl`), so its grid sees another
  list and takes the extent unshifted.
- **Open: the list keeps every row that the wheel passed.** A frame of 100,000
  rows, 3000 notches down: with point 3 the list holds 5645 built nodes behind its
  head, and the live memory after a full GC grows from 199 MB to 338 MB, about 10
  to 25 KB for each row passed. With point 3 switched off it holds 1 node behind
  its head and stays between 256 and 330 MB. A sort, a filter, an edit of the
  frame or a jump to a place that the list did not build makes a new list and
  frees it. A table over a plain lazy list keeps its nodes in the same way.
