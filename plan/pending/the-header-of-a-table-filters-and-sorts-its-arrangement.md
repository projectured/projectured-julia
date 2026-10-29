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

**D9. One value for each name.** The owner, 2026-10-29: "there should have been
separate fields: result is the actual result, expected result is the expected
result, expected true or false if the two are equal". A task has the values
`result` (the actual code, `FAIL`), `expected_result` (the expected code, `PASS`)
and `expected` (`true` when the two are equal). The kind column `expected` of the
omnet opp tests and validation tasks, which shows the expected code, becomes
`expected_result`. The column `result` of the table of a group shows the actual
code, and the reason is a column of its own, `reason`, so each filter tests the
value that its cell shows.

**D10. The columns of a kind are values of its tasks, and a label has no
underscore.** The owner, 2026-10-29, agreed that each kind of task gives its
columns as values of its tasks, so `queue2` under "test" keeps the task queue2,
and said: "don't use underscores for column labels for humans". The header of a
column shows its name with a space for each underscore (`expected result`,
`process id`), and the name in the code stays `expected_result`.

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
- **D6.** The header parts are a fragment of the widget slice, and their six
  styles move from `DataFrameTheme` to `WidgetTheme`, because the data frame
  table and the roster table share them. The widget slice already holds parts of
  the header of a table (`WidgetTableHeaderLevels.jl`, `WidgetTableParts.jl`).
- **D7.** The widget of a cell comes from the interface function
  `make_roster_cell(cells, item, key, value)`. `RosterRowsToWidget` holds `cells`,
  whose default is `nothing`, and the method for `nothing` makes the cell of now.
  The cells of a task need the colors of the scaled `TaskTheme`, and no projection
  holds an `Appearance`. So a page that draws other cells puts its own
  `RosterRowsToWidget`, whose `cells` holds its styles, in the dispatch of its
  widgets, as the task slice already builds its own dispatch for its panes.
- **D8.** A `Roster` holds `shares`, a weight of the width for each column or
  `nothing` for equal shares, and `marked`, the item whose row the table marks or
  `nothing`. The table reads them through the context property `:roster` of step
  3, so the page gives them with no new property of the context.
- **D11.** A roster finds whether a column is a value of an item once for each
  type of item. Every task is a `TaskDocument`, but the kinds of task have other
  columns. So the roster slice gets two interface functions: `get_item_facet_type(item)`,
  the type whose facets the item has (default `typeof(item)`), which keys the check,
  and `has_item_facet(item, name)` (default: the facets that the type declares),
  which the check calls on the first item of that type. A task answers a type of its
  kind, and has the facets of a task and the columns of its kind
  (`get_task_columns`), whose value is `format_task_column`. A facet of a task
  wins over a column of its kind with the same name. The facet `expected_result`
  is the expected code of the result after the task ends, and before that the
  column `expected_result` of its kind, or `nothing` when the kind has none.

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
    of the widget slice, which does not use the arrangement slice: the table of
    the slice edges (`test_platform_slice_edges`) does not allow it. So the
    dialog takes `is_ticked(value)` and `write(values, ticked)`, and its caller
    gives the filter language (`is_value_listed`, `make_value_list_text`).
    Exported names:
    `find_sort_state(keys, name)`, `compute_clicked_sort_keys(keys, name, adding)`,
    `make_sort_glyph(keys, name, unsorted_color, make_operation; domain)`,
    `make_filter_field(text, range, reason, width, invalid_filter; language,
    placeholder)`, `make_field_child_reference(path)`,
    `make_labeled_field(label, field)`, `compute_value_counts(column; limit)` and
    `make_value_list_dialog(name, column, is_ticked, write; widget)`.
    `keys` is a vector of `(name, descending)` pairs, `make_operation(adding)` and
    `write(values, ticked)` give the operations, and `domain` names the gestures in the
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
    the docstring of `WidgetLink`). After the dialog stopped using the arrangement
    slice: `test_platform_slice_edges` 1, `test_widget_column_header` 48,
    `test_dataframes_layering`, `test_data_frame_filter` and
    `test_data_frame_columns` 123.
- [x] **Step 3 — The header of a roster table with an arrangement.**
  `RosterRowsToWidget` reads the arrangement of its place from the printer
  context. Each header gets the parts of step 2 over the entry: the field edits
  the condition of its column (D4), the glyph edits the sort keys, and "Filter
  by values…" lists the values of the column over all rows of the roster. A
  caret in a field is a path in the header, which an introduced step holds, as
  the chips hold theirs. A roster table with no arrangement keeps its plain
  header.
  Tests: `test_roster`, `test_arrangement`, a new test with real presses, and
  `test_task_views`.

  **Done.** What the work found and decided:
  - No new mechanism. The mechanisms that exist carry it. The printer context
    gives `:arrangement` and `:arranged_picks` (the entry of the place), and the
    roster adds the property `:roster` next to `:roster_columns`. An edit is an
    `ArrangeCollectionOperation` (`at` the rows) or a `CompoundOperation` of one
    and a `ReplaceSelectionOperation`. The caret of a field is an introduced
    step of the table (`make_introduced_reference`, as the bar holds the caret of
    a chip).
  - New names in the arrangement slice (`ArrangementColumns.jl`):
    `is_arranged_place(context)`, `find_arranged_entry(context)`,
    `find_column_filter_text(entry, name)`, `make_column_filter(entry, name,
    text)`, `get_column_sort_keys(entry)`, `make_column_sort(entry, keys)` and
    `collect_column_values(items, name)`. `find_arranged_entry` finds the entry
    that the dispatch chose: the items print below the steps that the bar puts
    above them, so it takes the source of the pick that has the path of the
    table. A key is read and made with `_make_key`, so the field of `"status"`
    is the condition that `filter_collection!(…, "status" => …)` writes.
  - `RosterRowsToWidget` has a field `widget`, the scaled widget theme of the
    natural renderer, for the six styles of step 2 and for the size of the
    dialog. Its IO map has `is_filtering` and `entry` (a cell of the entry). The
    roster slice does not use the appearance slice, so the opener of the dialog
    (`_open_value_list!`) takes the theme from the projection and not from the
    editor.
  - Header of column `c` of a table that prints in an arrangement:
    `make_labeled_field(WidgetContextMenu(key, glyph), field)`. The field is
    `children[2]` of the header. A header that depends on the sort of the entry is
    made again when the sort changes. The text and the reason of the field read
    the entry in a cell, so a typed character makes no new header.
  - A part of a header makes its operation at its own path in the table. The
    table puts such an `ArrangeCollectionOperation` or `OpenContextMenuOperation`
    at the rows (`_retarget_header_operation`). A path into a header maps back to
    an introduced reference, which the gesture routes through.
  - A key in the field is a `ReplaceStringRangeOperation`. The table makes the
    new whole filter (`make_column_filter`) and the caret after the new text as
    one compound. `ArrangingProjection` now makes the edit of each part of a
    compound that arranges a collection (`_make_arranged_change`), so the caret
    and the filter are one step of undo. A run of typing joins one step.
  - "Filter by values…" is in the `WidgetContextMenu` around the key and the
    glyph. The dialog lists the values of `roster.rows`, all rows, which
    `collect_column_values` reads with the key of the filter. "Apply" finds the
    roster in the editor document (`search_references`, as `show_roster!` does) and
    posts `make_filter_collection_operation` with the conditions of the new
    filter, so it does not depend on the path of the printer context: a path of
    the context is not a path from the root of the editor when the editor has a
    wrapper around its document.
  - Not done: a header edit that takes the last description away also takes the
    arrangement away, as a chip does, and a table that is then outside an
    arrangement has a plain header. A typed edit keeps the arrangement because it
    is a compound. The holder of a table that must keep its header calls
    `keep_held_arrangement`. The headless backend does not draw a window of a
    popup (the menu and the dialog), so the test presses the right click and
    checks the menu window, and takes the boxes and "Apply" of the dialog from its
    widgets.
  - A sort glyph of more than one key draws the place of each key, so the digits
    of a header are in the drawn texts of a table. `test_roster` skips them.
  - Results: `test_roster_header` 41 (new file
    `test/platform/roster/RosterHeaderTest.jl`), `test_roster` 69,
    `test_roster_table` 37, `test_roster_program` 21, `test_arrangement` 10,
    `test_arrangement_natural` 11, `test_arrangement_filter_sort` 27,
    `test_arrange_collection_operation` 20, `test_arrangement_menu` 32,
    `test_arrangement_program` 13, `test_task_views` 70, `test_task_group` 84,
    `test_background_work` 21, `test_explorer` 294,
    `test_widget_column_header` 48, `test_platform_slice_edges` 1;
    `test_platform_layering` 6 of 7 (the fault of main).
- [x] **Step 4 — A widget in a cell, a share of the width, a marked row.** The
  roster gets a function of its interface that makes the widget of a cell for an
  item and a key, whose default is the cell of now (D7). A roster holds a share of
  the width for each column, and the table marks the row of the item that the
  roster names (D8).
  Tests: `test_roster`, `test_roster_table`.

  **Done.** What the work found and decided:
  - New names: `make_roster_cell` (interface of the roster slice, exported), the
    fields `RosterRowsToWidget.cells`, `Roster.shares` and `Roster.marked` (keywords
    `shares = nothing`, `marked = nothing`), and the private helpers `_make_row_path`,
    `_map_selection_or_mark` and `_set_column_shares!`. No new event, property or
    registry: the table reads the roster through `:roster` of step 3.
  - `make_roster_cell(cells, item, key, value)` gets `value` as the value cell of the
    column of the row, as the cell code reads it. The method for `nothing` makes the
    label of the text. The table itself keeps what depends on the column number and
    on the type of the value for `cells === nothing`: the link of the item in column 1
    and the document that follows a value that is a document. A method for another
    `cells` value makes the whole cell, and the table gives its widget the mouse target
    of the row, so a press there selects the item of the row as for a label.
  - Shares: the table sets its `columns` cell to a `WidgetTableColumn` for each column
    with `SizePolicy(nothing, nothing, nothing, weight)`, a weight of 1 for a column
    beyond the weights. The width is the minimum of the header and the share of the
    rest, so the ratio of the drawn widths is the ratio of the weights only above the
    floors of the headers; the test offers 6000 pixels.
  - Marked row: `follow_output_selection!` of the table follows
    `_map_selection_or_mark`, the selection of the rows when it is in the rows, else
    the whole row of the item that `marked` names. The editor selection and the mark
    do not conflict: the selection wins while it is in the rows, and the mark shows
    when it is not. The row is counted from the head of the list as for the editor
    selection (`_make_row_path`), so a row before the head has a number of zero or
    less. The row is found by identity in the rows that print (a filtered list too).
  - `pred_arguments` of a roster still writes the source, the columns and the title:
    a file keeps no `shares` and no `marked`.
  - omnet-julia: both calls of `Roster(` (`CampaignExplorer.jl`,
    `LegacyResultFile.jl`) pass keywords only, so no call breaks.
  - Results: `test_roster` 69, `test_roster_table` 54 (17 new), `test_roster_header` 41,
    `test_roster_program` 21, `test_task_views` 70, `test_explorer` 294,
    `test_background_work` 21, `test_platform_slice_edges` 1, `test_platform_layering`
    6 of 7 (the two files of main).
- [x] **Step 5a — The values of a task and the labels of a header.** The header
  of a roster column shows its name with a space for each underscore (D10). The
  roster slice gets `get_item_facet_type` and `has_item_facet` (D11). A task gets
  the facets `expected_result` (D9, D11), `state`, `progress`, `elapsed`,
  `process`, `processor` and `memory`, each the value that the cell of the group
  table shows, and the columns of its kind. The facets of now keep their meaning.
  Tests: `test_roster`, `test_roster_table`, `test_roster_header`,
  `test_task_views`, and a new testset that filters and sorts a roster of tasks by
  a column of their kind and by `expected_result`.

  **Done.** What the work found and decided:
  - New names: `format_roster_column_label` (roster slice, exported), `get_item_facet_type`
    and `has_item_facet` (interface of the roster slice, exported, defaults in
    `RosterDefaults.jl`), the marker type `TaskKindFacets{T}` (task slice, not exported),
    and the facets `expected_result`, `state`, `progress`, `elapsed`, `process`,
    `processor` and `memory` of a task. The private helper `_get_task_state_word` is shared
    by the facet `state` and the cell of the group table (`_get_task_state` keeps only the
    colour); `_get_current_field` moved to `TaskDocument.jl` because the facets read it.
  - The `facets` cache of `_RosterKey` is keyed by `get_item_facet_type(item)`, and the
    first item of each such type answers `has_item_facet(item, name)`. The other callers of
    `_has_item_facet(typeof(...))` (`_get_column_path`, `_make_item_edit`) go through
    `has_item_facet` too, so a kind column takes the facet path everywhere; it takes no edit.
  - A `TaskDocument` answers `TaskKindFacets{typeof(task)}`; the task of a document does not
    change (no write to the field `task`). A declared facet wins over a kind column of the
    same name, and a field of the document wins over both (the kind `TaskGroup` has a column
    `group`, which stays the field). The value of a kind column is
    `format_task_column(task, name)`. Because the generic method for a `Val` and a
    `TaskDocument` is ambiguous with the facet `type` of `Document`, `type` is forwarded by
    `invoke`.
  - Decision on `elapsed` (the coordinator): `nothing` while the task runs or before it
    starts, and `end_time - start_time` in seconds after it ends. The cell of the table
    reads the summary of the group to count on with each drain; a facet that read it would
    make every task of a roster compute again at each drain. So `elapsed` reads no group
    and no clock.
  - `expected_result` is the expected code of the result after the task ends, before that
    the kind column `expected_result` when it is not empty, else `nothing`. `expected`
    keeps its meaning (true or false after the end).
  - Labels (D10): the plain header, the label above the field of the arranged header and the
    name in the dialog "Filter by values" show `format_roster_column_label(key)`; the key,
    the filter key and the chips do not change.
  - omnet-julia (read only): `LegacyValidationTask`, `LegacyOppTestTask` and
    `LegacyProgramTestTask` answer the kind column `expected`
    (`source/legacy/simulator/`); the declared facet `expected` wins over it in a roster, so
    they rename the column in the later omnet step. Tests there assert the column list.
- [x] **Step 5b — The page of a task group shows a roster.** The table of the pane
  is a roster of the tasks of the group with an arrangement, under the bar of the
  arrangement, held in a field of the group as the Background work log holds its
  table. The columns are those of now and `reason` (D9); the column `result` shows
  the actual code. The cells and the shares are those of now, through
  `make_roster_cell` (D7). The choice `all · running · unexpected` chooses the
  tasks that the roster lists. A press on a row writes `selected`, the row of
  `selected` is marked (D8), and the list starts at the anchor.
  Tests: `test_task_group`, `test_task_views`, `test_task_pages`, and an image of
  the pane before and after, which must show the same rows.

  **Done.** What the work found and decided:
  - New names. `TaskGroupDocument` has two fields at its end, `shown` and `table`.
    `shown` is a cell with a computation: the `tasks` collection itself for `all`,
    else a new collection of the task documents that the choice keeps, in the order
    of the group. `table` is `ArrangementDocument(roster, ArrangementEntry[])`, made
    and linked in `wrap_task_group_document` (`_make_task_group_table!`), whose
    source is `CollectionItems` of the field `shown`. `Roster` has a field `anchor`
    (D-anchor below). The task slice has the type `TaskCells` (the colours of the
    pane) with `make_roster_cell` methods, and private helpers. The one positional
    construction of `TaskGroupDocument` is in `wrap_task_group_document`; omnet-julia
    has none, and no source of it uses a helper that this step removed.
  - Decision 1 (coordinator, a widening of the step 4 contract): `make_roster_cell`
    may return `nothing`, which means the default cell of the table. `_make_row_cells`
    then makes the link in column 1 and the cell that follows a document value, as for
    `cells` of `nothing`. `TaskCells` returns `nothing` for an item that is no
    `TaskDocument`, so a roster of other items that prints inside a task pane draws
    as it draws elsewhere. Stated in the docstrings of `make_roster_cell` and
    `RosterRowsToWidget`; test in `RosterTableTest.jl`.
  - Decision 2 (coordinator): `Roster.anchor` holds an item, in the way of `marked`;
    `nothing` keeps the private head of the table. The group computes it: the first
    task at or after `tasks[anchor]` that the choice shows. The table takes its head
    row as the row of that item in the arranged rows, else row 1. A scroll far from
    the head writes the item to `anchor` of the roster, as view state, and the pane
    turns that write into the write of `anchor` of the group, by the identity place of
    the item in `tasks`. `RosterRowsToWidgetIoMap` has the fields `head` (a cell) and
    `roster`.
  - Decision 3 (coordinator): the place of an item of the source is `shown[j]`, which
    changes with the choice. The pane names a task by `tasks[i]` in every answer: an
    open of a page at a row, at `shown[j]`, a press, a double press and a Ctrl+press,
    by the identity of the task. The reader of the pane calls `keep_held_arrangement`
    and `retarget_held_row_open` with the step `table`, then `_retarget_task_open` and
    `_convert_table_answer`. For the table of an inner group in the detail, the two
    held-arrangement calls name a field of the pane's group, so only the identity
    conversion applies there; the removal of its last description takes its
    arrangement away.
  - Decision 4 (coordinator): the pane maps `table.<rest>` of the group, and the same
    path of the group of its detail (`tasks[i].inner_group.table`,
    `preparation.table`), to the place of each table in its output, as the cards are
    mapped. The table stands directly in the constraint of the split, with no scroll
    pane, because a list table scrolls itself. The pane follows the mouse target down
    to the table but not into it: the table is a document that holds its own.
  - Decision 5 (coordinator): the cells of `processor` and `memory` keep the text of
    now (`NN%`, `format_memory_size`); the facets keep the raw values. The kind columns
    that are no facet (such as `configuration`) show the text that `format_task_column`
    gives, which is also what a field of the document, such as the column `group` of a
    task that is a group, needs.
  - Decision 6 (coordinator): the table of the slice edges in
    `test/platform/PlatformSuite.jl` has "arrangement" in the row of "task". It follows
    D2 (the table of a group is a roster with an arrangement), and the order of the
    slices permits it: arrangement comes before task, and backgroundwork uses it too.
  - The columns and shares, in the order of the table: `state` 1, the columns of the
    kind with their weights, `progress` 2, `elapsed` 1, `process` 1, `processor` 1,
    `memory` 1, `result` 1, `expected` 1, `reason` 4. The column `result` shows the
    actual code only, `expected` shows true or false, and `reason` the reason (D9).
    The headers come from `format_roster_column_label`.
  - Fact: the text that the old `result` cell gave (`_format_task_outcome`: the result
    in the words of `opp_repl`, such as `ERROR (unexpected) (Non-zero exit code: 1)`,
    and the last output line while a task runs) is no longer in the table. The detail
    of the task still shows the result in those words. A task that runs shows nothing
    in `result` and `reason`.
  - Removed with the old table: `_build_table`, `_build_whole_table`, `_build_table_row`,
    `_compute_shown_indices` (the source is `shown`), `_get_head_place`,
    `_find_selected_row`, `_format_task_outcome`, `_make_table_columns`,
    `_collect_group_tables`, `_convert_head_write`, the tooltip of the old table, and
    the scroll pane around it.
  - `_RosterTableView` keeps the head of a roster that has no `anchor`; a group's roster
    always has one while the group has tasks.
  - The widgets of the pane now dispatch through `make_arranged_dispatch` with the rows
    of the arrangement and the roster before the widget rows, and `RosterRowsToWidget`
    with the `TaskCells` for `CellVector{RosterRow}`.
  - Tests: `test/platform/task/TaskGroupTableTest.jl` (new, `test_task_group_table`):
    the columns and shares, the choice, a press and the marked row, a double press and
    a Ctrl+press, an open at `shown[j]`, a filter typed under `test` and one undo, a
    click on the sort glyph of `elapsed`, the choice `running` with a filter, the
    arrangement that stays, and the head and a scroll. `TaskGroupToWidgetTest.jl`: the
    press test reads `marked` of the roster, and the test of a scrolled list moved to
    the new file. `RosterTableTest.jl`: a method that returns `nothing`.
  - Results: `test_task_group_table` 39 (new), `test_task_views` 65, `test_task_group` 84,
    `test_task_pages` 48, `test_task_document` 128, `test_task_kind_facets` 27,
    `test_task_result` 115, `test_task_group_verbs` 40, `test_roster` 69, `test_roster_table`
    57 (3 new), `test_roster_header` 41, `test_roster_facets` 30, `test_roster_program` 21,
    `test_background_work` 21, `test_explorer` 294, `test_system_process` 80,
    `test_assistant_wake` 17, `test_arrangement_natural` 11, `test_arrangement_filter_sort` 27,
    `test_roster_sources` 19, `test_platform_slice_edges` 1; `test_platform_layering` 6 of 7
    (the two files of main). All pass. The ranking script of the assistant searches keeps
    its six first names. The image of the pane before and after (30 probe tasks, 15 done,
    3 unexpected, 4 running, 8 waiting) shows the same rows, state colours and marked row;
    it differs in the header (sort glyphs and filter fields) and in the columns of item 3.

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
