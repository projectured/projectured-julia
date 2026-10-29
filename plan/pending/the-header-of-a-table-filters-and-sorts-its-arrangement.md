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

- [x] **Step 1 — The filter language in the platform, and `:matches`.** The
  parser and its conditions move to a fragment of the arrangement slice. The
  arrangement reads a `:matches` text once, when the conditions change, and
  tests each item with the condition that it made. A text that does not parse
  keeps every item. `describe_arrangement_part` writes the text. D3. The data
  frame table uses the parser of the platform.
  Tests: `test_data_frame_filter`, `test_arrangement_filter_sort` and a new
  testset of `:matches`.

  **Done.** What the work found and decided:
  - The fragment is `source/platform/arrangement/FilterLanguage.jl`. It exports
    four functions, because the list of the values of the data frame table uses
    two of them, and the header field of step 3 needs them too:
    `parse_filter_text(text, type = Any)`, `parse_name_pattern(text)`,
    `make_value_list_text(values, ticked)` and `is_value_listed(text, value,
    type = Any)`. The list of values read an `_EqualCondition` before, which a
    qualified name of another module can not reach.
  - D5: for the type `Any`, a comparison and a range parse, and their conditions
    hold only for a value that is a number and no `Bool`. For a type of numbers
    that check is always true, so the data frame table keeps its behaviour.
  - `_read_conditions` reads a `:matches` text into a `_ParsedFilterText`, the
    text and its test, which is equal to another when the texts are. So the cells
    of the items of a filter stay while the text stays. A key that finds no
    value gives `nothing`, which the test reads as `missing`.
  - The adapter keeps `_is_number_type` for its example of an expression, and
    labels a value of the list with `string(value)`, which is the text that the
    filter reads.
  - The three testsets of the language moved from `DataFrameFilterTest.jl` to
    `test/platform/arrangement/ArrangementFilterLanguageTest.jl`
    (`test_arrangement_filter_language`), with a testset of the type `Any` and
    one of `:matches`.
  - Results: `test_arrangement_filter_language` 50, `test_arrangement_filter_sort`
    27, `test_arrangement_program` 13; `test_dataframes_layering`,
    `test_data_frame_filter`, `test_data_frame_sort` and
    `test_data_frame_columns` 140. `test_platform_layering` fails 1 of 7, the
    fault of main (`FileChangeModule.jl` and `ShellModule.jl`). The six searches
    of `test_referenced_document_editor` keep their first names after the
    docstring of `filter_collection!` changed.
- [x] **Step 2 — The header parts in the platform.** The sort glyph, the field of
  a filter with its reason, and the dialog of the values move to the platform.
  Each part takes where its text is written, the sort keys and the operation
  that writes them, and the values of its column, so it knows nothing of a data
  frame. The data frame table uses them.
  Tests: `test_dataframes`, because a change of a table can break its cells.

  **Done.** What the work found and decided:
  - The parts are in `source/platform/widget/WidgetColumnHeader.jl`, a fragment
    of the widget slice. `WidgetModule` now does `using ..ArrangementModule`, for
    `is_value_listed` and `make_value_list_text`. Exported names:
    `find_sort_state(keys, name)`, `compute_clicked_sort_keys(keys, name, adding)`,
    `make_sort_glyph(keys, name, unsorted_color, make_operation; domain)`,
    `make_filter_field(text, range, reason, width, invalid_filter; language,
    placeholder)`, `make_field_child_reference(path)`,
    `make_labeled_field(label, field)`, `compute_value_counts(column; limit)` and
    `make_value_list_dialog(name, column, filter_text, write; widget)`.
    `keys` is a vector of `(name, descending)` pairs, `make_operation(adding)` and
    `write(text)` give the operations, and `domain` names the gestures in the
    gesture help (the table sets "data frame").
  - `make_field_child_reference` is exported because the expression bar and the
    selection of the table of the adapter map a caret through the same second
    child as `make_labeled_field` does.
  - The opener of the dialog stays in the adapter. `find_editor_appearance` is in
    the appearance slice, which comes after the widget slice. The dialog takes a
    popup id `:value_list`, and the adapter opens its window with that id.
    `_make_value_list_dialog(view, column; widget)` of the adapter is a thin call
    of the platform function over the column and the filter text of the view.
  - The six styles moved from `DataFrameTheme` to `WidgetTheme`, in a new group
    "Header of a table": `header_field_width` (was `query_field_width`),
    `header_gap` (was `filter_gap`), `invalid_filter` (was `invalid_query`),
    `unsorted_glyph`, `value_list_size`, `value_list_window_size`, with the same
    defaults. `DataFrameViewToWidget` holds the first four under the new names and
    fills them from the widget theme; the expression bar and the find field read
    `invalid_filter` too. `DataFrameTheme` keeps `expression_field_width`,
    `find_field_width`, `expression_gap` and `list_column_width`.
  - The adapter keeps `_get_sort_keys(query)`, which makes the pairs, and
    `_make_sort_operation`, which computes its keys with the platform function.
    The structure of the header stays: a vertical layout of the label row above
    the field, so the field is `children[2]`.
  - Results: `test_widget_column_header` 48 pass (new file
    `test/platform/widget/WidgetColumnHeaderTest.jl`); `test_dataframes()` 603
    pass; `test_platform_layering` 6 of 7 (the fault of main, `FileChangeModule.jl`
    and `ShellModule.jl`); `test_widget_scales` 23, `test_widget_colors` 75,
    `test_appearance_tab` 126, `test_appearance_file` 22,
    `test_appearance_wrapper` 55, `test_settings` 107, `test_settings_tab` 55,
    `test_builder_appearance` 7, `test_widget_table` 17 all pass;
    `test_interface_api` 140 pass and 2 fail, the two of main (33 widget names,
    the docstring of `WidgetLink`).
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
