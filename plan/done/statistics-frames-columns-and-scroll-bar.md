# The frames table takes the width of its content and has a scroll bar

> **Status:** done on 2026-10-05 on the branch `statistics-columns-and-scroll-bar`,
> rebased on `main` at `41a303c3b`; it waits for the owner to land it. Written
> on 2026-10-05 at the owner's request: "for 2, yes, plus a scroll bar". The
> decisions below are Claude's, and D2 changed in step 3. The narrow tests of
> the branch pass, 1346 of 1346.

## 1. The request

After [statistics-tab-shows-two-tables.md](../done/statistics-tab-shows-two-tables.md)
landed, the owner showed the Statistics tab of a build with no performance
counters: the frames table had one column, `frame_time (ms)`, as wide as the
whole tab, so the numbers sat far from their frame numbers. Claude offered:
"Columns sized to their content when the frames table has few columns". The
owner answered: "for 2, yes, plus a scroll bar".

## 2. The facts (2026-10-05)

1. Every column of the frames table takes a share of the width
   (`_FRAME_COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)` in
   [FrameStatisticsToWidget.jl](../../source/platform/statistics/FrameStatisticsToWidget.jl)).
   With one column, that column is the whole tab.
2. A list table measures its headers and no cell, because its rows are built
   as a walk reaches them
   ([WidgetTableParts.jl:126](../../source/platform/widget/WidgetTableParts.jl#L126),
   `_get_cells_column_policy` with no `widest` at line 706). A column with no
   share is as wide as its header, and a value wider than the header is cut.
3. The owner rule of 2026-09-17: no width chosen by hand, because it depends on
   the screen and the font. A width comes from the container or from the
   content.
4. `compute_line_box(measure, text, font).width` is the width of a text.
5. The data frame view puts a `WidgetScrollBar` beside its table in a
   `GridLayout`, `[Fill, Fixed(scroll_bar_width)]`, where the width is the
   `scroll_bar_thickness` of the widget theme
   ([DataFrameViewToWidget.jl:94](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L94)).
   Its value is the place of the top row among the rows that do not fit; its
   thumb is the share of the rows that the table shows. The rows that the table
   shows are counted from the offered height and the step of a row, less the
   rows of the parts above. A write of the value of the bar becomes a jump:
   `anchor` to the row, `top_row` to 1, the offset to 0 down
   (`jump_to_row`, [DataFrameView.jl:226](../../source/adapter/dataframes/DataFrameView.jl#L226)).
6. The two computations of the bar are private to the data frame view:
   `_get_scroll_bar_value` and `_get_scroll_bar_row`.

## 3. The decisions (Claude's)

- **D1. A frames column is as wide as its header and its widest value, and
  takes no share.** The width is `Fixed(w)`, where `w` is the measured width of
  the header text and of the formatted maximum of the column, the widest
  number in it. It comes from the content, not from a hand-chosen number, and
  it changes only when a wider number arrives. This holds for any count of
  columns: a table wider than the tab scrolls to the side, as a list table
  does. With no measure, as in a test that prints without one, a column is as
  wide as its header.
- **D2. The scroll bar sits at the right edge of the frames region** (changed
  in step 3: first beside the table), in a `GridLayout` of two columns, as in
  the data frame view. Its width is the
  `scroll_bar_thickness` of the widget theme of the appearance.
- **D3. The bar works as in the data frame view.** Its value is the place of
  the top row, `head + top_row - 1`, among the rows that do not fit; its thumb
  is the share of the rows shown. The rows shown are the offered height of the
  tab divided by the step of a row, less the rows above the table: the head
  line, two titles, the header and the rows of the summary and the header of
  the frames. A press or a drag on the bar writes its value, and the reader
  makes that a jump: `anchor` to the row, `top_row` to 1, the offset to 0 down,
  all as view state.
- **D4. One copy of the computations of the bar.** `_get_scroll_bar_value`
  and `_get_scroll_bar_row` move from the data frame view to the widget slice
  as `compute_scroll_bar_value(top_row, count, visible)` and
  `compute_scroll_bar_top_row(value, count, visible)`, beside
  `WidgetScrollBar`. The data frame view calls them.

## 4. Steps

- [x] **Step 1. Move the computations of the bar (D4).** Done:
  `test_dataframes()` passes, 556 of 556.
- [x] **Step 2. Columns as wide as their content (D1).** Done: the test prints
  the tab at 800 and 1600 pixels and finds the same places, checks the widths
  `Fixed(15 * 8)` and `Fixed(7 * 8)` of a header column and of a column whose
  value is wider than its header, and checks that a header and a value end at
  the same right edge. Found: a header aligns as its column does, here right.
  The feed, tool view and tool theme tests pass, 258 of 258.
- [x] **Step 3. The scroll bar (D2, D3).** Done, with D2 changed:
  - **The bar sits at the right edge of the tab, not beside the columns.**
    With the grid column of the table `Content`, a table of nine columns at 920
    pixels was wider than the tab and pushed the bar out of view; with no
    width offered to the grid, `Fill` did not help. "As wide as the columns,
    but at most the offer" would need the width math of the table (paddings
    and rules) in the statistics slice. So the frames region takes the width of
    the tab (`width = Fill`), the grid is `[Fill, Fixed(scroll_bar_width)]`, and
    the table draws nothing to the right of its columns. A table wider than the
    tab stops at the bar and scrolls to the side.
  - The reader takes the rows shown from the thumb of the bar, which is that
    share of the frames, so the projection keeps its `SimpleIoMap`.
  - Tests: the bar follows `anchor` and `top_row`; a write of its value, with
    or without view state, is a jump to that row. The wheel test turns over the
    body of the table, because the table is only as wide as its columns. Found:
    a `Point2D` holds its coordinates in cells, so two equal points are not
    `==`. The feed, tool view and tool theme tests pass, 266 of 266. The images
    with one column and with nine show the bar at the right edge.
- [x] **Step 4. Documentation and the image.** Done: `statistics.md`
  describes the widths and the bar, and the limit "no scroll bar" is gone;
  `widget.md` names `compute_scroll_bar_value` and
  `compute_scroll_bar_top_row`. The guards give the same findings as on
  `main`. The images of the tab at 920 pixels, with one column and with nine,
  show the widths and the bar.
