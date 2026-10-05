# The statistics tab shows two tables

> **Status:** pending. Written on 2026-10-05 at the owner's request. The owner
> chose the look on 2026-10-05 (D1), and agreed to the other decisions and to
> the answers of section 6 the same day. No question is open. The owner said
> "implement" on 2026-10-05. The work is on the branch `statistics-tab-tables`.

## 1. The request

The owner wrote on 2026-10-05:

> in projectured-julia frame statistics numerical view, can we have the
> detailed numerical data in a table or something?

Claude gave two options: a summary in a real table, or a table with one row for
each frame. The owner asked for both:

> can we have both the summary and the detailed table? show me how it would
> look like

Claude drew a mockup with the real widgets (`WidgetTable`, `WidgetToggle`,
`WidgetScrollPane`, `VerticalLayout`, `HorizontalLayout`), invented numbers and
`ProjecturedSDL.write_image`. The owner answered: "looks good, plan it".

The mockup shows the Statistics tab, from top to bottom:

1. A head line, "1234 frames, the tables cover the last 1000", and a **Pause**
   button.
2. "Summary": one row for each measurement. The columns are measurement, unit,
   frames, minimum, maximum, mean, deviation and total. The numbers align
   right.
3. "Frames, newest first": one row for each frame, with the frame number as the
   row header. It has one column for each measurement, `frame_time (ms)`,
   `evaluate_time (ms)`, `print_time (ms)`, `read_time (ms)`, `computes`,
   `invalidations`, `layout_passes`, `reads` and `writes`. It scrolls under a
   header row that stays in place.

## 2. The facts (2026-10-05)

1. The Statistics tab is not a table now.
   [FrameStatisticsToSyntax.jl:44](../../source/platform/statistics/FrameStatisticsToSyntax.jl#L44)
   prints one monospace text line for each measurement, and aligns the
   columns with spaces. The natural row `:statistics` draws it through the
   Syntax → Text → Graphics path
   ([FrameStatisticsModule.jl:59](../../source/platform/statistics/FrameStatisticsModule.jl#L59)).
2. `FrameStatistics` holds `rows`, one `FrameStatisticsRow` for each
   measurement, and `frame_count`
   ([FrameStatisticsDocument.jl:27](../../source/platform/statistics/FrameStatisticsDocument.jl#L27)).
   It holds no number of a single frame. `flush_frame_statistics!` writes a
   field of a row only when its number changed
   ([FrameStatisticsDocument.jl:52](../../source/platform/statistics/FrameStatisticsDocument.jl#L52)).
3. `FrameTimeSeries` holds the frames of the ring, but only the time columns.
   `flush_frame_time_series!` skips each column whose unit is not `:second`
   ([FrameStatisticsDocument.jl:136](../../source/platform/statistics/FrameStatisticsDocument.jl#L136)).
   The chart of the Frame times tab draws it.
4. `collect_recent_frame_measurements(store)` gives every column of the ring,
   times and counts, with its name and its unit
   ([FrameMeasurement.jl:232](../../source/kernel/performance/FrameMeasurement.jl#L232)).
   `FrameMeasurement.jl` is sealed (`SEALING.md:67`). This plan does not need
   to change it.
5. A frame records `frame_time` always. When the performance counters are
   compiled in, it also records the times `evaluate_time`, `print_time` and
   `read_time`, and the counts `computes`, `invalidations`, `layout_passes`,
   `reads` and `writes`
   ([Feeds.jl:66](../../source/kernel/editor/Feeds.jl#L66)).
6. The feed flushes the table only when a view reads `frame_count` and the
   count of the store differs
   ([FrameStatisticsFeed.jl:47](../../source/platform/statistics/FrameStatisticsFeed.jl#L47)).
   It never wakes the editor. It gives a deadline while a document is due.
   Feeds drain before the read stage of a frame, so a press that changes the
   gate takes effect in the next frame.
7. A natural row that ends in widgets registers with
   `register_natural_graphics!`. The MCP log is the model: its row is
   `ChainingProjection(make_mcp_log_projection(...), VerticalLayoutToGraphicsCanvas())`
   ([McpLogToWidget.jl:110](../../source/platform/mcplog/McpLogToWidget.jl#L110)).
   The renderer already holds the rows of every widget, so a `WidgetTable` or a
   `WidgetToggle` inside the layout draws with no more registration.
8. The slice table of the layering guard does not let `statistics` use
   `widget` or `layout` now
   ([PlatformSuite.jl:94](../../test/platform/PlatformSuite.jl#L94)). The
   statistics slice loads after both, so the edge goes down and no cycle
   occurs.
9. A `WidgetTable` whose rows are a `ListNode` builds only the rows that a
   viewport reaches. When a scroll goes more than 200 rows from the head
   (`_TABLE_RELOCATION_DISTANCE`,
   [WidgetTableParts.jl:1273](../../source/platform/widget/WidgetTableParts.jl#L1273)),
   the table writes a new head into its own `rows`, together with
   `scroll_position` and `top_row`
   ([WidgetTableParts.jl:1292](../../source/platform/widget/WidgetTableParts.jl#L1292)).
10. The data frame view is the model for a table of many rows.
    `DataFrameView` owns `anchor`, `top_row` and `scroll_position`
    ([DataFrameView.jl:45](../../source/adapter/dataframes/DataFrameView.jl#L45)).
    The table shares the `top_row` and `scroll_position` cells of the view, and
    builds its rows from `anchor` with `_make_index_list`
    ([DataFrameViewToWidget.jl:142](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L142)).
    The reader turns a write of `rows` by the table into a write of `anchor`
    ([DataFrameViewToWidget.jl:651](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L651)).
11. `_make_index_list` is a private function of the data frames adapter
    ([DataFrameView.jl:339](../../source/adapter/dataframes/DataFrameView.jl#L339)).
    The platform can not call it, because the adapter is above the platform.
12. A press on a `WidgetToggle` writes its own `pressed` field with a
    `ReplaceReferencedValueOperation`
    ([WidgetToGraphics.jl:7949](../../source/platform/widget/WidgetToGraphics.jl#L7949)).
    When the toggle holds the cell of a field of another document, the press
    writes that field. The data frame view shares cells with its table in the
    same way.
13. A cell of a `WidgetTable` is a document, usually a `WidgetLabel`.
    `make_widget_table_row` turns a function of no arguments into a live label.
    The table has no style for one row. A label has its own `text_style`. The
    color set has the role `:warning_text`.
14. `WidgetTable` can not sort. Only `DataFrameView` sorts, with its own query.
15. These tests name the statistics view:
    - `test_frame_statistics_feed()`,
      [FrameStatisticsFeedTest.jl:80](../../test/projectured/editor/FrameStatisticsFeedTest.jl#L80):
      "the printer shows times in milliseconds, with a unit" reads the text
      lines of `FrameStatisticsToSyntax`.
    - `test_tool_views()`,
      [ToolViewTest.jl:50](../../test/projectured/projection/ToolViewTest.jl#L50):
      a render of `FrameStatistics()` holds "0 frames".
    - `test_tool_themes()`,
      [ToolThemeTest.jl:55](../../test/platform/projection/ToolThemeTest.jl#L55):
      a 1.5 scale of `FrameStatisticsTheme` scales the three text styles.
    - `test_window_shell()` and `test_window_wrappers()`: the toolbar buttons
      and the wrapper. This plan does not change them.
    - `make_frame_statistics_feed_projection_example()` in
      `example/projectured/FeedExamples.jl` builds the syntax chain.
16. No other repository uses `FrameStatisticsToSyntax`,
    `make_frame_statistics_projection` or `FrameStatisticsTheme`. The search
    corpus of omnet-julia names `FrameTimeSeries` by its docstring, which this
    plan does not change. `Projectured.jl` is the generated release copy, and
    the release makes it again.

## 3. The decisions

Claude proposed D2 to D8. The owner agreed to them on 2026-10-05.

- **D1. The look of the mockup.** One Statistics tab shows the head line with
  Pause, the summary table and the frames table, as in section 1. This is the
  owner's choice of 2026-10-05.
- **D2. `FrameStatistics` holds its own frames.** It gets `frames`, the frame
  numbers of the ring, oldest first, and `columns`, one column for each row of
  the summary, in the unit of the row. The rows and the columns use the order
  of the store, which only appends a name, so the column `i` belongs to the row
  `i`. The flush writes them from `collect_recent_frame_measurements`.
  - The other way is a field that holds the session `FrameTimeSeries`. Claude
    does not propose it: the series holds no counts, and a Pause of the table
    would then stop the chart in the other tab, with no button there to start
    it again.
- **D3. Rows from the newest frame, built as a list.** The frames table
  builds only the rows that it shows, as the data frame view does.
  `FrameStatistics` holds the view state that the table shares: `anchor`, the
  place of the head row counted from the newest frame, `top_row` and
  `scroll_position`. The reader turns a write of `rows` by the table into a
  write of `anchor`, wrapped in a `ReplaceViewStateOperation`, so the undo does
  not record it. The row headers are a list that moves in step with the rows.
- **D4. One index list for the platform and the adapter.** `_make_index_list`
  and `_make_index_node` move from the data frames adapter to the collection
  slice, as the public `make_index_list(count, at, value_of; computed = false)`
  in [ListNode.jl](../../source/platform/collection/ListNode.jl). The data
  frame view calls it. Two copies of the same list are not kept.
- **D5. Pause stops the Statistics document only.** `FrameStatistics` gets
  `paused::Bool`. The toggle holds that cell. While `paused` is true, the feed
  does not flush the table and gives no deadline for it. The Frame times chart
  continues, because it has its own document (D2).
- **D6. `FrameStatisticsToWidget` replaces `FrameStatisticsToSyntax`.** The
  projection prints a `VerticalLayout` of the head line, the two section
  titles and the two tables. The summary table is a vector of rows, with one
  live label for each number, so a flush changes only the labels whose
  numbers changed. The frames table is list-backed (D3) and takes the height
  that is left. The natural row `:statistics` registers with
  `register_natural_graphics!`, as the MCP log does. The projection is
  read-only: `map_reference_forward` uses `find_introduced_path` and no caret
  goes into a table, as in `CellTableToWidgetTable`.
- **D7. The text of a cell follows the formats of today.** A time shows in
  milliseconds with two decimals, and the total of a time with none. A count
  shows as a whole number, and its mean and deviation with one decimal. A
  value that a frame did not measure (`NaN`) shows "-". The header of a time
  column in the frames table says `(ms)`.
- **D8. `FrameStatisticsTheme` keeps its three text styles, with new places.**
  `header_text` draws the head line and the two section titles. `row_text`
  draws the cells of both tables. `empty_text` draws "no frame yet". The
  borders, the header rows and the scroll come from the widget theme of the
  appearance, as in every table.

## 4. What does not change

- The kernel. `FrameMeasurementStore` and `collect_recent_frame_measurements`
  already give every column.
- `FrameTimeSeries`, `flush_frame_time_series!` and the chart of the Frame
  times tab.
- The feed interval, the test for a view, and the rule that the feed never
  wakes the editor. Only the Pause gate is new.
- The toolbar buttons, the insertion names `statistics` and `frame times`, the
  `frame_statistics` wrapper, and `pred_arguments`, which saves nothing.
- `write_frame_measurements!` and the CSV text.

## 5. Steps

Do all the work in a worktree on the branch `statistics-tab-tables`. Make a
commit for each step. Do not land on `main` until the owner says so.

- [x] **Step 1. Move the index list to the collection slice (D4).** Done:
  `test_collection()` and `test_dataframes()` pass, 745 of 745.
  Add `make_index_list` with its docstring to `ListNode.jl`. Change the data
  frame view to call it, and delete the private copy. Test: the data frame view
  tests and the collection tests. Add one test of `make_index_list` in the
  collection tests: a walk down and back up meets the same nodes, and the walk
  stops at both ends.
- [x] **Step 2. The document holds the frames (D2, D3, D5).** Done:
  `test_frame_statistics_feed()` passes, 55 of 55.
  Add `frames`, `columns`, `paused`, `anchor`, `top_row` and
  `scroll_position` to `FrameStatistics`. Write `frames` and `columns` in
  `flush_frame_statistics!`. Test in `test_frame_statistics_feed()`: a flush
  writes the frames of the ring oldest first, and the column `i` belongs to
  the row `i`, also when a counter appears after the first frames.
- [x] **Step 3. Pause (D5).** Done: `test_frame_statistics_feed()` passes,
  67 of 67.
  `_is_frame_statistics_due` answers false while `paused` is true. Test: a
  paused table does not flush and gives no deadline, the plot still flushes,
  and the table flushes again after `paused` goes back to false.
- [ ] **Step 4. The projection (D6, D7, D8).**
  Write `FrameStatisticsToWidget.jl` and `make_frame_statistics_projection`
  for it, and delete `FrameStatisticsToSyntax.jl`. Register the row with
  `register_natural_graphics!`. Add `widget` and `layout` to the slice table of
  `statistics`, and remove `syntax` and `text` if the slice no longer uses
  them. Change the example in `FeedExamples.jl`. Tests:
  - Replace "the printer shows times in milliseconds, with a unit" with a
    test that reads the labels of both tables: the summary cells, the frames
    newest first, the `(ms)` headers and "-" for `NaN`.
  - A write of `rows` by the frames table becomes a write of `anchor`, and a
    press on Pause writes `paused`.
  - `test_tool_views()` still finds "0 frames".
  - Change `test_tool_themes()` to check the labels of the new projection.
  - `test_platform_layering()` and the slice edge test pass.
- [ ] **Step 5. Look at the real tab.**
  Draw the Statistics tab with `write_image` from a store with synthetic frames,
  and compare it with the mockup. Then open a live window with the frame
  statistics wrapper, and drive it with pushed SDL events: press Pause, check
  that the numbers stop, scroll the frames table more than 200 rows, and check
  that `anchor` moves and the rows stay correct. Tell the owner before the
  window opens. Read the `frame_time` row with the tab open and with the tab
  closed. Do not report this as a measurement: a real measurement needs an
  idle machine and the owner's word.
- [ ] **Step 6. A slow frame gets a color (Q2).**
  A row whose `frame_time` is more than two times the median of the ring shows
  its cells in `:warning_text`. Test: a slow frame and a frame below the factor
  in the same table.
- [ ] **Step 7. Documentation.**
  Update [statistics.md](../../documentation/package/platform/statistics/statistics.md):
  how it works, the theme, how it fits, usage and limits. Update the "See also"
  in the docstring of `FrameTimeSeriesToChart`, and the documents of the
  collection slice and the data frames adapter for `make_index_list`.
- [ ] **Step 8. Report.** Run the narrow tests of each step again on the
  branch. Report the commits, the test results, the blast radius and the
  command that lands the branch. Then stop and wait for the owner.

## 6. Answered questions

Claude recommended each answer below. The owner agreed to all five on
2026-10-05 ("agreed").

- **Q1. Does Pause stop only the Statistics tab?** Yes (D5).
  A pause that also stops the chart needs a button in the chart tab too.
- **Q2. Does a slow frame get a color?** Yes: a row whose
  `frame_time` is more than two times the median of the ring shows its cells
  in `:warning_text` (step 6).
- **Q3. Does a click on a column header sort the frames?** Not in this
  plan. `WidgetTable` can not sort, and the maximum in the
  summary already shows the slowest frame time.
- **Q4. Do the rows stay in place while you read them?** Without Pause, the
  rows move four times each second, because a row is a place counted from the
  newest frame. Another model keys each row by its frame number and follows
  the newest frame only while the table is at its top, as a log follows its
  end. That needs a follow rule in the reader that no table has now. Pause comes
  first (the mockup). The follow rule gets a separate plan if Pause is not
  enough.
- **Q5. Which font do the cells use?** The monospace font of
  `FrameStatisticsTheme` (DejaVu Sans Mono 13), so that the digits align. The
  mockup used the font of the widget examples.
