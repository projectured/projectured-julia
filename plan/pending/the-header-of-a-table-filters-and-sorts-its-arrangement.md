# The header of a table filters and sorts its arrangement

Status: pending. Written 2026-10-29. Work on the branch `table-header` (worktree
`projectured-julia-table-header`).

Applies to projectured-julia. omnet-julia uses it for the table of a run and the
tables of the matches of a runner: step 5 of its plan
`plan/pending/a-runner-for-each-kind-of-test.md`, decision D5.

## The ask

D5 of the omnet plan, decided by the owner on 2026-10-29: *"can we also have per
column filter and sort like in the data frame table?"*, then *"Option a, but the
task and test result filter should also be fast"*. The table of a run and the
table of the matches of a runner each get the bar of the arrangement and the
parts of the data frame table: a filter field under each column header, the sort
arrow in each header (a click: off, ascending, descending; a Shift+click adds the
next key), and "Filter by values…" in the menu of a header. These parts and their
filter language move from the DataFrames adapter to the platform, and the data
frame table and the task tables use the same parts. The field under a header and
the chip in the bar show the same condition of the arrangement.

The speed is done: `plan/done/a-roster-and-its-arrangement-cost-what-changed.md`.

## What exists

- The filter language is in `source/adapter/dataframes/DataFrameFilter.jl`:
  `_parse_column_filter(text, type)` gives `nothing` for an empty text, a
  condition (`_MissingCondition`, `_MatchCondition`, `_EqualCondition`,
  `_NotEqualCondition`, `_OrderCondition`, `_RangeCondition`), or the reason why
  the text does not parse. The forms: `abc`, `/re/`, `= a, b`, `!= a`, `> 30`,
  `10..20`, `missing`.
- The header of a column of the data frame table is a label, the sort glyph
  (`DataFrameSort.jl`) and the field of the filter (`DataFrameFilterRow.jl`).
  "Filter by values…" (`DataFrameColumn.jl`, `DataFrameValueList.jl`) opens a
  dialog of the values with their counts, and Apply writes `= a, b` into the
  field. The state is `DataFrameQuery`: one `DataFrameColumnFilter(column, text)`
  for each column, and the `DataFrameSortKey`s.
- The arrangement has `ArrangementCondition(key, operator, value)` with seven
  operators and no text form. Its chips read the arrangement from the printer
  context (`:arrangement`), as the stage of each place prints.
- The roster table `RosterRowsToWidget` draws the header as one label for each
  key, a cell as text or as the document of the item, and an equal share of the
  width for each column. The roster slice already uses the arrangement slice.
- The table of a task group (`_build_table` in `TaskGroupToWidget.jl`) is a
  `WidgetTable` of its own: a state label in colour, a progress ring, live labels,
  a share of the width for each column, a list from the anchor, the row of the
  task of the detail marked, and the choice `all · running · unexpected`.

## Decisions

**D1. A condition holds the filter text.** The owner, 2026-10-29, "agreed" to
option (a). The arrangement gets the operator `:matches`, whose value is the
text in the filter language, and the parser moves to the platform. A field under
"status" with `= failed, error` is `ArrangementCondition(status, :matches,
"= failed, error")`, and its chip shows `status: = failed, error`. The other
choice was the seven operators, one more for each form they can not say, and a
field that writes the conditions back as text.

**D2. The table of a task group becomes a roster of its tasks with an
arrangement.** The owner, 2026-10-29, "agreed" to option (a). The header parts
are made once, in the roster table, so every roster table gets them. The roster
table learns a widget in a cell, a share of the width for each column, and a
marked row, so the page of a group looks as it does now. The other choice was
the group table as it is, with the arrangement and the header parts in its own
code.

Decisions of the design (mine, not the owner's):

- **D3.** A `String` value in a filter pair is the filter text:
  `filter = ["status" => "= failed"]` in `make_arrangement_entry`,
  `filter_collection!` and `show_roster!` gives a `:matches` condition. Such a
  value throws an `ArgumentError` now, so no call changes meaning.
- **D4.** The field of a column shows the condition of that column in the first
  filter of the entry: the text of a `:matches` condition, or the filter text of
  another operator (`= v`, `!= v`, `< v`, `> v`, `<= v`, `>= v`, and the text of
  `:contains`). An edit of the field writes a `:matches` condition in its place,
  or adds one. So a filter of the assistant shows in the field (§5.6 of the omnet
  plan).
- **D5.** The parser of the platform takes no type: a form of numbers holds only
  for a number value, and a text form compares the text of the value. The data
  frame table gives the type of its column, as now.

## The steps

Each step is one commit on the branch, with its test.

- [ ] **Step 1 — The filter language in the platform, and `:matches`.** The
  parser and its conditions move to a fragment of the arrangement slice. The
  arrangement reads a `:matches` text once, when the conditions change, and
  tests each item with the condition that it made. A text that does not parse
  keeps every item. `describe_arrangement_part` writes the text. D3. The data
  frame table uses the parser of the platform.
  Tests: `test_data_frame_filter`, `test_arrangement_filter_sort` and a new
  testset of `:matches`.
- [ ] **Step 2 — The header parts in the platform.** The sort glyph, the field of
  a filter with its reason, and the dialog of the values move to the platform.
  Each part takes where its text is written, the sort keys and the operation
  that writes them, and the values of its column, so it knows nothing of a data
  frame. The data frame table uses them.
  Tests: `test_dataframes`, because a change of a table can break its cells.
- [ ] **Step 3 — The header of a roster table with an arrangement.**
  `RosterRowsToWidget` reads the arrangement of its place from the printer
  context. Each header gets the parts of step 2 over the entry: the field edits
  the condition of its column (D4), the glyph edits the sort keys, and "Filter
  by values…" lists the values of the column over all rows of the roster. A
  caret in a field is a path in the header, which an introduced step holds, as
  the chips hold theirs. A roster table with no arrangement keeps its plain
  header.
  Tests: `test_roster`, `test_arrangement`, a new test with real presses, and
  `test_task_views`.
- [ ] **Step 4 — A widget in a cell, a share of the width, a marked row.** The
  roster gets a function of its interface that makes the widget of a cell for an
  item and a key, whose default is the cell of now. A roster holds a share of the
  width for each column, and the table marks the row of an item that the printer
  context names.
  Tests: `test_roster`, `test_roster_table`.
- [ ] **Step 5 — The page of a task group shows a roster.** The table of the pane
  is a roster of the tasks of the group with an arrangement, under the bar of the
  arrangement. The columns, the cells and the shares are those of now. The
  choice `all · running · unexpected` chooses the tasks that the roster lists. A
  press on a row writes `selected`, the row of `selected` is marked, and the list
  starts at the anchor.
  Tests: `test_task_group`, `test_task_views`, `test_task_pages`, and an image of
  the pane before and after, which must show the same table.
- [ ] **Step 6 — Measure, and the documents.** The filter and the sort of a group
  of 22,731 tasks through its page: the first open, and the end of one task.
  The documents of the arrangement, the roster, the task slice and the DataFrames
  adapter.

## Tests

The narrowest test of each step, above. Step 2 and step 5 also run
`test_dataframes` and `test_task_group` whole, because each changes a table.

## Not in this plan

- The tables of the matches of a runner in omnet-julia, and the measurement
  there: step 5 of the omnet plan, after this plan lands.
- The table of typed columns for a task table. The owner: "Let's wait with the
  data table change until we are sure we can't make it fast otherwise."
