# Pivot any table into a widget table

> **Kind:** plan · **Status:** pending, 2026-10-06. A design review and a list
> of stages. Nothing is implemented. The owner decided every question of §7
> on 2026-10-06. The work starts when the owner asks for it. ·
> **Stands on:** [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md)
> (D8, §4.6, §4.7),
> [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md),
> [packages-compose-by-seams.md](packages-compose-by-seams.md),
> [widget.md](../../documentation/package/platform/widget/widget.md),
> [chart.md](../../documentation/package/domain/chart/chart.md),
> [dragging.md](../../documentation/package/platform/dragging/dragging.md)

This plan is the "better design" that D8 of the data frame plan waits for. It
covers phase 7 (group) and phase 8 (pivot) of that plan.

## 1. The request

The owner, 2026-10-06:

> in projectured-julia, I would like to design a pivot table which can be
> projected to a widget table
>
> I envision the following:
>  - a pivot table has a set of dimensions
>  - dimensions are assigned to rows or columns or cells
>  - row dimensions are turned into nested row headers in the widget table
>  - column dimensions are turned into nested column headers in the widget table
>  - cell dimensions are used to select the appropriate cell document type:
>    e.g. a sub-table, a pie chart, a bar chart, a line chart, etc.
>
> the value of the pivot table can be anything, usually it's a DataFrame, let's
> see how it works for a data frame:
>  - dimensions are columns of the data frame
>  - valid values are the set of values in a given dimension
>  - each cell should contain the part of the frame which matches the values of
>    a selected column/row dimensions
>  - dimensions are displayed above the table in three rows: column, row, cell
>    dimensions
>  - user can drag them from one place to another and can reorder them
>
> review this design in light of existing solutions and suggest a staged
> development plan

## 2. Summary

The design is sound. It is the facet model of Polaris and Tableau, of trellis
displays, and of `facet_grid` in ggplot2. The row dimensions and the column
dimensions cut the data into parts, and each cell shows its part. This model is
more general than the pivot table of Excel, where a cell is always one number.
Here, a number is one kind of cell view among others.

A projectional editor adds one thing that the other tools do not have. A
sub-table in a cell takes edits, and each edit goes back to the source.

The writer recommends six changes. They are recommendations, not decisions:

1. **Separate the cell view from the cell dimensions.** The cell dimensions are
   the dimensions that the view uses inside the cell. The kind of the view
   (number, sub-table, bar, pie, line) is a choice of its own. It has an
   automatic default from the count and the kind of the cell dimensions.
2. **Add measures.** A number and a chart need a value: a column and an
   aggregate (count, sum, mean, minimum, maximum). The default is the count of
   rows.
3. **Add a pool of unused dimensions.** A dimension that is in no zone needs a
   place. A drag to the pool also removes a dimension from a zone.
4. **Give each dimension an order, a filter and a rule for `missing`.** A
   number or a date column needs bins before it is a good dimension.
5. **Make the pivot a stage over the table interface** of
   [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md).
   "The value can be anything" then means "any table": a data frame, a vector
   of named tuples, a `CellTable`, the result of a query. A cell holds a part of
   the same kind: a `SubDataFrame` for a data frame, a view by indices for the
   others. Decision 2 of that plan already says this.
6. **Close D8 with one model.** A group is a pivot with row dimensions only,
   and with a cell view that puts the rows of each group in line under its
   header.

The nested headers need one new feature of `WidgetTable`: a header that merges
a run of equal labels at each level. The table finds a run from the neighbours
of the visible rows, so the merge also works on the lazy table.

## 3. What exists

Read from the tree on 2026-10-06.

**The table.**

- `WidgetTable` has one header for each column and one for each row
  ([WidgetDocument.jl:2516](../../source/platform/widget/WidgetDocument.jl#L2516)).
  No header spans more than one column or row, and a header has no levels.
- The paths are `rows[r]`, `columns[c]`, `cells[r][c]` (`cells[c][r]` in a
  column-major table), `column_headers[c]` and `row_headers[r]`.
- A table of a list builds only the rows that it shows. Its `row_headers` are a
  `ListNode` that moves in step with `cells`. When `column_headers` is a
  `ListNode` too, the columns are a list as well
  ([WidgetDocument.jl:2588](../../source/platform/widget/WidgetDocument.jl#L2588)).
  §3.5 of the data frame plan still lists row headers on a list as open, but
  the docstring says that they exist. Stage 0 checks it.
- A column and a row take a `SizePolicy`: `Fixed`, `Content`, `Relative` or
  `Fill`.
- A cell holds any document. The chart example puts four charts in the cells of
  a `WidgetTable`
  ([ChartDocumentExample.jl:138](../../example/domain/chart/ChartDocumentExample.jl#L138)).
  No example puts a table in a cell of a table.
- `WidgetCard` has `collapsed` and a chevron
  ([WidgetDocument.jl:1676](../../source/platform/widget/WidgetDocument.jl#L1676)).
- The owner deferred the padding of each row and column (step 4 of
  [a-table-has-rows-columns-and-cells.md](../done/a-table-has-rows-columns-and-cells.md)).

**The data frame view.**

- `DataFrameView` holds the `frame`, a `DataFrameQuery` and `kept_rows`. The
  query holds the hidden columns, the column pattern, the column filters, the
  expression and the sort keys.
- `DataFrameViewToWidget` makes a lazy `WidgetTable`. A cell is a
  `PrimitiveNumber`, a `PrimitiveString`, a `PrimitiveBool`, or a label.
- A refresh compares a snapshot of the frame and increments `frame_version`.
- The edit operations that exist: set a value, insert and delete a row, insert,
  delete and move a column, and refresh.
- The package depends on DataFrames, the kernel and the platform. It does not
  depend on Tables.jl. No `DataFramePivot` type exists.

**The charts.**

- The chart domain has line, scatter, bar, histogram and coloured strip series.
  It has no pie chart, no heat map and no sparkline.
- A series takes any `AbstractVector{<:Real}`, so a column of a frame goes in
  with no copy. No function makes a chart from a table.
- A chart draws at 120 × 80 pixels or more
  ([ChartPlotToGraphics.jl:1240](../../source/domain/chart/ChartPlotToGraphics.jl#L1240)).
  The default is 760 × 460.

**The drag.**

- `DraggingProjection` emits a `MoveRangeOperation`. It moves a range of cells
  from one `CellVector` to another, keeps the identity of each cell, and has an
  inverse ([Dragging.jl:66](../../source/platform/dragging/Dragging.jl#L66)).
  This is the move of a chip from one zone to another.
- `DraggingProjection` draws no drop mark. The pane draws one with a
  `WidgetHighlight`
  ([PaneToWidget.jl:206](../../source/platform/pane/PaneToWidget.jl#L206)).
  The move of a tab is the nearest model
  ([PaneSurgery.jl:627](../../source/platform/pane/PaneSurgery.jl#L627)).
- No chip widget exists. `WidgetBadge` is a pill that only prints
  ([WidgetDocument.jl:1558](../../source/platform/widget/WidgetDocument.jl#L1558)).
- No key moves an element of a list to another place or to another list.

## 4. The tools that exist

| Tool | Where the dimensions go | What a cell shows | What this plan takes |
| --- | --- | --- | --- |
| Lotus Improv (1991) | Named categories on tiles. A drag moves a tile between the row, the column and the page axis. | A number. | A dimension is a named thing that moves between axes. |
| Excel PivotTable | Filters, Columns, Rows, Values. The "Σ Values" field goes to the rows or the columns. | One aggregate. | The pool, a value filter on each field, the layouts (compact, outline, tabular), subtotals and totals. |
| PivotTable.js | A list of unused attributes, rows, columns, an aggregator menu and a renderer menu. | A number, a heat map colour, a bar, or one chart for the whole result. | The renderer is chosen apart from the dimensions. Each axis has an order button. |
| Tableau (Polaris) | The Rows and Columns shelves. A discrete field makes headers, a continuous field makes an axis. The Marks card (colour, size, label, detail) works inside each pane. | A chart pane. The mark type is a menu with "Automatic". "Show Me" proposes a chart from the selected fields. | Discrete against continuous. The cell dimensions are the marks of the cell. The automatic cell view. Only the combinations that occur ("nest"). |
| ggplot2 `facet_grid`, Vega-Lite `row`/`column`, AlgebraOfGraphics.jl `row`/`col`, trellis | One panel for each combination of the facet variables. | A plot of the part. The scales are shared by default ("fixed") or free. `margins` adds "(all)" panels. | Shared scales, so the cells can be compared. A total is the part for "all" values. |
| Perspective (FINOS) | `group_by`, `split_by`, `columns`, `aggregates`. | A plugin draws the whole result: a data grid, bars, lines, a heat map, a treemap. | Not taken. The dimensions feed one chart, not a grid of charts. It is an alternative for a later stage. |
| pandas `pivot_table`, DataFrames.jl `groupby` + `combine` + `unstack` | Arguments of a function. | An aggregate. | "Copy as code". The test oracle of stage 2. |

None of these tools takes an edit through a cell back to the source. Excel,
PivotTable.js and Perspective show a pivot that a person can not edit.

## 5. Review, point by point

**"A pivot table has a set of dimensions."** This holds. A dimension is a named
function from a row to a discrete value. At first, it reads a column. Later, it
can be a bin of a number column or a part of a date, as Tableau bins and the
date groups of Excel are.

**"Dimensions are assigned to rows or columns or cells."** This holds. Two
places are missing: the pool of unused dimensions and the measures (§2, points
2 and 3).

**"Row dimensions are turned into nested row headers."** This holds. Two
choices remain:

- Which combinations show. Tableau and Excel show only the combinations that
  occur on an axis ("nest"). A full product ("cross") shows many empty rows.
  The writer recommends the combinations that occur.
- The layout. "Tabular" gives each row dimension a header column of its own,
  with merged runs. "Compact" puts all levels in one column as an indented
  tree. The writer recommends tabular first, because it is what the request
  describes.

**"Column dimensions are turned into nested column headers."** This holds, with
the same two choices. A dimension with many values makes many columns. The
lazy columns of the table carry them.

**"Cell dimensions are used to select the appropriate cell document type."**
The writer recommends a change. The same dimensions can mean different views.
Two cell dimensions can be a bar chart with a series for each value of the
second, a sub-table, or a heat map. Zero cell dimensions can be a number or a
sub-table. So the kind of the view is a choice of its own, with an automatic
default. The proposed rule:

| Cell dimensions | Default cell view |
| --- | --- |
| none | the measure as a number; the count if no measure is given |
| one, with eight values or less | a bar chart; a pie chart on request |
| one, ordered (a number, a date) | a line chart |
| two | a bar chart with a series for each value of the second |
| any | the person can choose a sub-table of the part |

For a sub-table, the cell dimensions are the columns that the sub-table shows.
No cell dimension means all columns.

**"The value of the pivot table can be anything, usually it's a DataFrame."**
This holds with point 5 of §2. The pivot reads the source through the table
interface. A kind of table that has a native part gives it.

**"Dimensions are columns of the data frame."** This holds. A column with many
distinct values, such as a price, makes thousands of headers. The view must
show a warning and propose bins. It must not stop.

**"Valid values are the set of values in a given dimension."** The writer
recommends three additions:

- An order: the natural order of the values, the order of the levels of a
  categorical column, the order of the first occurrence, or the order of a
  measure.
- A filter: a list of the values with a check box each, on the menu of the
  chip, as Excel and PivotTable.js have.
- A rule for `missing`: a value of its own, shown as "missing", last in the
  order.

**"Each cell should contain the part of the frame which matches."** This holds.
The part is a native view with no copy, a `SubDataFrame` for a data frame. A
combination of a row and a column that does not occur has no part, and its cell
is empty.

**"Dimensions are displayed above the table in three rows."** This holds, with
the pool and the measures added. The writer recommends:

```
Fields:   [product] [customer] [price]
Columns:  [year]
Rows:     [region] [country]
Cells:    [bar chart ▾]  [quarter]
Values:   [sum(amount) ▾]
```

The owner chose this layout (P2, P3). The menu at the start of the cells row
chooses the cell view (P1).

**"User can drag them from one place to another and can reorder them."** This
holds. `MoveRangeOperation` already moves a cell from one `CellVector` to
another, with undo. The writer adds:

- keys for each move, because each edit must also work from the keyboard:
  Alt+Left and Alt+Right move a chip in its row, Alt+Up and Alt+Down move it to
  the row above or below, and Delete moves it to the pool;
- a drop mark, as the pane draws for a tab;
- a key that swaps the row and the column dimensions (proposed);
- a drag of a header of the table into the bar (proposed).

**What the design does not name yet.**

- **Totals and subtotals.** A total is the part for all values of a dimension.
  So any cell view works on a total: a total row of bar charts is possible.
- **Shared scales.** The charts of all cells use the same axis range by
  default. Without this, two bar charts side by side can not be compared.
- **Size.** The pivot makes one pass over the source to find the parts. A part
  is an index vector. The view builds a cell document only for a visible cell.
- **Edits.** An edit in a sub-table writes the source. An edit that changes the
  value of a dimension moves the row to another cell. The row stays while the
  text is pending, and the commit computes the pivot again, as D6 of the data
  frame plan does for a sort. A number cell is read-only.
- **Refresh.** The pivot reads the version of its source. A change computes the
  parts again.
- **Selection.** A selection must stay on its cell when the pivot changes. See
  P8 in §7.

## 6. The model (proposed)

The pivot is a stage of a chain, as the filter and the sort are in the any-table
plan:

```
source table ─▶ filter, sort ─▶ pivot ─▶ cross table ─▶ cell views ─▶ WidgetTable
                                  ▲                        ▲
                             PivotTable               PivotCellView
```

**The documents.** The names are tentative.

- `PivotTable` holds the configuration. Its zones are `CellVector`s of
  `PivotDimension`, so a drag moves a chip with `MoveRangeOperation`:
  - `unused_dimensions`, `column_dimensions`, `row_dimensions`,
    `cell_dimensions`;
  - `measures`, a `CellVector` of `PivotMeasure`;
  - `cell_view`, a `PivotCellView`, or `nothing` for the automatic choice;
  - the options: totals, shared scales.

  The configuration is a document, as `DataFrameQuery` is. So it is saved and
  undone, and the assistant edits it.
- `PivotDimension` holds the `column`, the `order`, `descending`, and
  `hidden_values`, which is the value filter. A bin comes later.
- `PivotMeasure` holds the `column` and the `aggregate`: `:count`, `:sum`,
  `:mean`, `:minimum`, `:maximum` or `:distinct_count`.
- `PivotCellView` is an abstract type, with one subtype for each kind of view:
  - a number;
  - a table of the part;
  - bar, pie and line. The pivot domain depends on the chart domain and holds
    these views itself, as the state machine domain holds Julia expressions
    (P4). A pie series is a new kind of series in the chart domain.

  The menu of the cell view lists the subtypes that are loaded, as the
  insertion buffer lists the loaded document types.
- The table of a part asks a seam for the view of the part (P9). The generic
  answer is a widget table by indices. The DataFrames adapter answers a
  `SubDataFrame` with a `DataFrameView`, so an edit in the cell writes the
  frame. This follows C1 of
  [packages-compose-by-seams.md](packages-compose-by-seams.md).

**The cross table.** The pivot stage computes it and does not store it in a
document:

- the row keys, a vector of tuples, in order;
- the column keys, in the same form;
- for each key pair that occurs, the index vector of the source rows.

Its IO map maps a cell to its source rows and back.

**The view.** A grid holds the bar of chips above the table, as
`DataFrameViewToWidget` puts a scroll bar beside its table. In the table:

- each column header holds the tuple of the labels of its column key;
- each row header holds the tuple of the labels of its row key;
- the table merges runs of equal labels, level by level;
- the corner names the row dimensions;
- a cell holds the cell view of its part, built only when it is visible.

## 7. Decisions (the owner, 2026-10-06)

- **P1. The cell view is a choice of its own** ("yes"), with an automatic
  default from the cell dimensions (§5).
- **P2. The measures are in a fourth row, "Values"** ("yes"). The other
  option was the cells row, after the view menu. A row with two groups of chips
  needs a drop at an exact place to tell a dimension from a measure, and Alt+Up
  and Alt+Down move a chip one row, which is simple only when each zone is a
  row. A drag into "Values" copies the field and does not move it, so a column
  can be a dimension and a measure at the same time. An empty "Values" row
  shows a muted "count" chip.
- **P3. The unused dimensions are in a row "Fields"** ("yes"), above the other
  rows. The other option was a "+" menu at the end of each row. A drag starts
  there, a drag back to it removes a dimension, and Delete on a chip sends the
  chip there. A frame with many columns makes a long row, so the row wraps, and
  a text filters it.
- **P4. The package is a domain** ("a domain slice, the data frame support goes
  into the adapter"). The writer reads this as a new domain package,
  `ProjecturedPivot`, in `source/domain/pivot/`. It depends on the chart
  domain, because it embeds charts. What is special to a data frame goes into
  `ProjecturedDataFrames`. The other option was a slice of the platform.
- **P5. Stage 1 builds the smallest form of step 1 of the any-table plan**
  ("yes"): the table interface and the view by indices. The other options were
  a protocol for the pivot alone, or Tables.jl.
- **P6. The nested headers are tabular** ("tabular"). Each row dimension has a
  header column of its own, and equal neighbours merge into one header cell:

  ```
  region │ country │ 2024 │ 2025
  ───────┼─────────┼──────┼─────
  EU     │ DE      │  12  │  15
         │ FR      │   8  │   9
  US     │ CA      │   5  │   7
         │ NY      │  11  │  13
  ```

  Column headers are tabular in the same way: one header row for each column
  dimension. The widget finds a merge from the visible neighbours, so it works
  on the lazy list. The compact layout, with all levels as an indented tree in
  one header column, is not part of this plan.
- **P7. Group is a layout of the pivot** ("yes"). Phase 7 of the data frame
  plan becomes stage 9 of this plan, and D8 closes with this model.
- **P8. The selection uses the paths that exist** ("use existing paths, I think
  no new step is needed, we will see"). A cell is `cells[r][c]`, and the IO map
  keeps the keys of each index, so a selection goes to the same keys after a
  change of the pivot. Inside a sub-table, the selection is a path of the
  source. Stage 0 checks this against
  [reference.md](../../documentation/package/kernel/reference.md) and
  [selection.md](../../documentation/package/kernel/selection.md).
- **P9. The table interface is in the `collection` slice of the platform**
  ("yes"), beside `CellTable`. The adapter implements it for
  `AbstractDataFrame`. It also adds a method to a seam that makes the view of a
  part: a `SubDataFrame` becomes a `DataFrameView`. So the adapter does not
  depend on the pivot domain, and the pivot domain does not depend on
  DataFrames. The filter and the sort stages of the any-table plan need the
  interface below every domain too. The other option was the interface in the
  pivot domain, with an adapter that depends on `ProjecturedPivot` and through
  it on `ProjecturedChart`. The owner answered P9 on the reading of P4 above.

## 8. Stages

Each stage ends with its own test and a commit. The work is done in a worktree.
The first delivery is stages 0 to 5: a pivot with number cells, nested headers,
and chips that move. Stages 6 and 7 complete the design of the request.

- [x] **0. Facts.** No product code. **Done 2026-10-06.**
  - Measure the pass that finds the parts: one million and ten million rows,
    one to three dimensions. Compare `groupby` of DataFrames with a generic
    pass over the table interface.
  - Check that a `WidgetTable` in a cell of a `WidgetTable` draws, scrolls and
    takes a key.
  - Check that row headers on a list draw, as the docstring says.
  - Draw a chart at 120 × 80 and list what a cell-size chart needs.
  - Read reference.md and selection.md, and check P8.

  The answers:
  - The measurement ran after stage 2, because the generic pass is the code of
    stage 2. A data frame with the dimensions region (4 values), country (40)
    and year (10), on the cores 28, 30 and 31, with a load of 8:

    | rows | dimensions | the pivot | `groupby` + `groupindices` |
    | --- | --- | --- | --- |
    | 1 000 000 | region | 0.019 s | 0.008 s |
    | 1 000 000 | region, country × year | 0.071 s | 0.052 s |
    | 10 000 000 | region | 0.283 s | 0.135 s |
    | 10 000 000 | region, country × year | 1.011 s | 0.660 s |

    So the generic pass is at most 2.1 times slower than `groupby`, and the
    pivot needs no path of its own for a data frame now. The pass runs once
    for each change of the dimensions, not for each frame. A change on a frame
    of ten million rows waits about one second.
  - A `WidgetTable` in a cell of a `WidgetTable` draws all its texts. A press
    inside it reaches the inner table: a press on a cell of the inner table
    answers `.cells[1][2].rows[1]`, and an Alt+press answers the outer cell,
    `.cells[1][2]`. The inner table did not scroll in this check, because it
    was small.
  - Row headers on a list draw, as the docstring says. The table needs a
    `Fixed` row policy for them, and it says so in an error otherwise.
  - A chart draws at 120 × 80 pixels or more: `_canvas_size` in
    `ChartPlotToGraphics.jl` takes the larger of the size that it is offered
    and that floor. A cell-size chart needs a lower floor, no title, no legend
    and fewer ticks (stage 7).
  - P8 holds. A path of the outer table goes on into the document of a cell,
    so a path of the pivot `cells[r][c]…` maps to the same path of the table.
- [x] **1. The table interface, smallest form.** The count of rows, the names
  and the types of the columns, a column as a vector, and a part by indices.
  The kinds: `AbstractDataFrame` in the adapter, with `SubDataFrame` as its
  part; a vector of named tuples and a named tuple of vectors, with the
  generic view by indices. The interface is in the `collection` slice (P9).
  The test: each kind gives the same parts. **Done 2026-10-06.**
  - `source/platform/collection/TableInterface.jl`: `is_table`,
    `get_table_row_count`, `get_table_column_names`, `get_table_column_type`,
    `get_table_value`, `find_table_column`, `make_table_part`, and the generic
    part `TablePart`. A part of a part is a part of the table.
  - The vector of named tuples takes its column names from the type of its
    elements, or from its first row when the elements have no one type; then
    the column types are `Any`.
  - `source/adapter/dataframes/DataFrameTable.jl`: the methods for an
    `AbstractDataFrame`. The adapter imports them from `CollectionModule` and
    does not depend on the pivot.
  - Tests: `test_table_interface()` (41) and `test_data_frame_table()` (14).
- [x] **2. The pivot core, with no screen.** The documents of §6, the cross
  table, the order of the values, `missing`, and the aggregates. The test: a
  fixed sales frame (region × year × product), compared with `combine` and
  `unstack` of DataFrames. **Done 2026-10-06.**
  - The new domain package `ProjecturedPivot`, with `ProjecturedPivotTest` and
    `ProjecturedPivotExample`, in `source/domain/pivot/`. It depends on the
    kernel and the platform only; the chart comes in stage 7. It is in
    `environment/all`, `ProjecturedAll`, `ProjecturedExample`,
    `ProjecturedTest`, the package graph test and the binary builder.
  - `PivotTable` has the field `source_version` from the start, because a field
    can not be added to a running session.
  - The cross table gives each value of a dimension a code, makes the code of a
    combination in mixed radix (a vector of codes when that does not fit in an
    `Int`), and sorts the rows by their cells once. A part is a range of one
    vector of row numbers, in the order of the source.
  - `missing` is last in either direction. Two values that `isless` does not
    compare sort by their texts.
  - The test compares each part with a direct filter of the rows, not with
    DataFrames, because the test package of a domain does not depend on
    DataFrames. The filter is an independent result of the same strength.
    `test_data_frame_table()` checks that a part of a data frame is a
    `SubDataFrame` that writes the frame.
  - Tests: `test_pivot()` (109).
  - The design document: `documentation/package/domain/pivot/pivot.md`. The
    count of the domains in the documents is now eighteen.
- [x] **3. Headers with levels in the widget table.** A header that holds a
  tuple of labels, merged runs at each level, in the eager form and in the
  list form. A run that starts above the visible rows shows its label at the
  top. A press on a run selects the rows or the columns of the run. The test:
  a widget test with no pivot. **Done 2026-10-06.**
  - A header with levels is a `CellVector` of labels, the outer level first.
    The code is in a new fragment, `WidgetTableHeaderLevels.jl`, and
    `WidgetTableParts.jl` calls it at a few points, because another session
    works on the presses of the same file (`a-table-selects-each-part-the-same-way.md`).
  - The header row is a grid of one row for each level. A run of columns is
    one child with `column_span`. The grid offers a spanning child the width of
    its columns, so a second print of the label at its own size gives the floor
    of a weighted column; reading the child in the grid made a cycle and a stack
    overflow. A `Fixed` column cuts a long run label, as it cuts a long header.
  - The header column is a grid of one column for each level. A run of rows
    shows its label in its first row and in the row at the top of the cells.
    A level is as wide as its corner label and the widest label of the first
    64 rows from the head; a wider label further down is cut (a known limit).
  - The last level never merges. `column_headers[c][l]` and `row_headers[r][l]`
    name a label and its run. A press on a run of an outer level selects the
    label of its first column or row, and the band covers the run.
  - Levels need columns that are a vector; the printer of list columns raises
    an error for them. The classic printer of an eager table has no levels.
  - The PDF writer does not walk a canvas whose elements are a list, so a table
    of a list shows no rows in a PDF. This limit is older than the pivot.
  - Tests: `test_widget_table_header_levels()` (31). `test_platform()`: 98 412
    passed, 8 broken, 2 failed. Both failures are in `InterfaceApiTest.jl`
    and come from `WidgetProgressRing`, which landed on main the same day: the
    test counts 31 widgets and finds 32, and the docstring of the ring lacks
    "Use it to". This branch adds no widget.
- [x] **4. The first view, read-only.** `PivotTable` to `WidgetTable`, with
  nested headers and number cells. The bar prints the chips, but they do not
  move yet. An example on a data frame and one on a vector of named tuples.
  The test: `test_example` of both. **Done 2026-10-06.**
  - `PivotTableToWidget` draws a grid of two rows: the bar, a `GridLayout` of
    the name of each zone and a `WidgetBadge` for each item, and the table, a
    `WidgetTable` whose rows and row headers are a list (`make_index_list`)
    and whose headers are `CellVector`s of the labels of a key. The corner
    names the row dimensions. `make_pivot_table_projection` gives the row
    height of the font, and the seam `make_graphics_projection` puts the pivot
    in the natural renderer.
  - `PivotTable` has two computed fields: `cross_table`, and `cells`, a
    `PivotCells` that the path `cells[r][c]` steps through. A cell document is
    kept by the key of its row, the key of its column and the kind of its view,
    so it survives a change of the pivot that keeps them. The cross table has a
    `row_index` and a `column_index` for this.
  - `cells[r][c]` of the pivot maps to `cells[r][c]` of the table and
    `cells[r]` to `rows[r]`. A run of headers maps back as a
    `ProjectionReferenceStep`, and its selection shows in the table.
  - The registered example `pivot` frames the pivot in a `WidgetScrollPane` of a
    fixed size, as `widget_table_frozen` frames its table, because the printer
    test offers no size and a table of a list needs an offered height. The atom
    `pivot/table` is the bare pivot. The printer, the reader and the REPL tests
    of the example pass (5829, 225, 225). Position navigation and type-in skip
    `pivot` as they skip `table`: a widget container gives Ctrl+Home no caret.
  - The data frame case is `test_pivot_data_frame()` in the umbrella test
    package, which now depends on DataFrames: each sum is the sum of
    `groupby` and `combine`, a part is a `SubDataFrame` that writes the frame,
    and the natural renderer draws it. The pivot test package does not depend
    on DataFrames.
  - Tests: `test_pivot()` (144); `test_pivot_data_frame()`;
    `test_catalog_coverage()` lists no pivot type (it fails on main for four
    other types); `test_natural_renders_every_atom()` and
    `test_natural_round_trips_every_atom()` pass.
- [x] **5. The bar of chips.** A chip widget that a person can select, with a
  menu. The rows Fields, Columns, Rows, Cells and Values. First the keys of §5
  and undo, then the drag with `MoveRangeOperation` and a drop mark. The test:
  the keys and a drag in a real editor. **Done 2026-10-06, without the
  menu**, which moves to stage 8 with the value filter, because both are menus of
  a chip.
  - The chip is a `WidgetBadge`, with no new widget type: muted (`:secondary`)
    at rest and filled (`:default`) when selected, and outlined (`:outline`)
    for the place of a drop and for the count of an empty Values row.
  - The bar is a `WidgetComposite` that holds one grid. A layout prints its
    children once, so a grid whose children were a computed `CellVector` did
    not draw a new zone row; a composite keeps a child by its identity and
    prints a new grid again. The selection builds no grid: each badge reads it.
  - A press and a drag read the mouse target of the pivot, as
    `DraggingProjection` does, and the pivot keeps the state of the drag in a
    new field `drag`, view state. `DraggingProjection` itself is not used,
    because it draws no drop place and would wrap the pivot in another document.
  - A drop over a badge puts the item before it, and a drop over the name of a
    zone at its end. A dimension dropped in Values gives a new measure and
    stays; a measure dropped outside Values goes out of the pivot.
  - The keys are the gesture table of `PivotTable`: Alt+Left, Alt+Right,
    Alt+Up, Alt+Down and Delete.
  - Tests: `test_pivot_zone_edits()` (31): the operations and their inverses,
    and a press, the keys and three drags in a real editor (`HeadlessBackend`).
    `test_pivot()`: 175.
- [x] **6. The cell views.** The view menu and the automatic rule. A sub-table
  cell: the generic table of the part, and the `DataFrameView` of the
  `SubDataFrame` in the adapter. A closed card shows "123 rows". The test: an
  edit in a sub-table cell writes the frame, and undo takes it back. **Done 2026-10-06.**
  - `PivotRowsView` shows the rows of a part in the columns of the cell
    dimensions. The automatic rule now gives numbers with no cell dimension and
    rows with cell dimensions; stage 7 adds the charts to it.
  - A seam in the collection slice, `make_table_document(table, columns)`,
    gives the document of a part (P9): `nothing` by default, and a
    `DataFrameView` with the other columns hidden in the DataFrames adapter.
    Any other source gives a `PivotPartTable`, a document of the pivot domain,
    which `PivotPartTableToWidget` draws with the row height of the theme; a
    widget made on the document side could not know that height.
  - No card with "123 rows": the corner of the table of a part shows the count
    of its rows, and a card in a row of a fixed height would only hide it.
  - The key of a cell document also holds what the view depends on
    (`get_pivot_cell_key`): the rows and the columns for a table, so a row that
    an edit moves to another cell gives both cells new documents.
  - A view that is not numbers gets the `:wrap` cell policy, so its column
    offers it a width. That made the width of a leveled header depend on its
    column, and reading it as a floor made a cycle; the floor now reads it only
    when the policy needs it (`_LevelHeaderWidth`), as a header with no levels is
    read.
  - The menus: a right click on a measure chooses its aggregate (the menu that
    stage 5 left), and on the pivot the view of the cells.
    `collect_pivot_cell_views()` reads the method table of
    `describe_pivot_cell_view`, because the direct subtypes of `PivotCellView`
    are the abstract families of `@document` and give no constructor.
  - An edit in a cell moves `source_version`, in the same step of undo.
  - Tests: `test_pivot_cell_views()`; `test_pivot()`: 204;
    `test_pivot_data_frame()` with a cell of a data frame, its edit and the
    inverse; the atom `pivot/part_table`.
- [x] **7. Charts in cells.** A compact chart style for a cell, with no title,
  no legend and few ticks. A floor below 120 × 80. Shared scales across the
  cells. The bar view and the line view, and a new pie series in the chart
  domain. The test: a pivot of 3 × 4 bar charts, where all cells have the same
  y range. **Done 2026-10-06.**
  - The pivot domain now depends on the chart domain (P4): the package, its
    test and example packages, the package graph test, and the domain
    documents, which count thirteen domains with no domain below them and five
    on one layer.
  - The chart domain: `ChartPieSeries`, drawn as a polygon for each slice with
    no axes, and listed slice by slice in the legend; and the least size as two
    fields of `ChartPlotToGraphicsCanvas`, `minimum_width` and
    `minimum_height`, 120 and 80 by default. `test_chart_pie()`; `test_chart()`:
    375.
  - The pivot: `PivotBarChartView`, `PivotLineChartView` and
    `PivotPieChartView`. A cell holds a `PivotChartCell`, a document of the
    pivot domain that holds the chart, because the chart domain registers no
    row in the natural renderer and the pivot must not add one for a type that
    it does not own. Its projection is the chain of the chart domain at 24 × 16
    or more, with no title, no legend and no labels of the axes.
  - Shared scales: one pass over the parts computes the value of each
    category and series in each cell, the categories of the whole source, and
    the range of every value and of zero. `PivotCells` keeps it in a memo, one
    value for each kind with what it is computed from, so a new cross table or
    a new measure computes it again and an old value does not stay.
  - The automatic choice now gives a line chart for one cell dimension of
    numbers, a bar chart for one of eight values or fewer and for two, and rows
    for any other. The test of stage 6 names three cell dimensions for its rows.
  - Tests: `test_pivot_chart_views()`: 3 × 4 bar charts with the same
    categories and the range 0 to 36, two series, a line over numbers, a pie on
    request, and 35 slices drawn; `test_pivot()`: 225. The atom
    `pivot/chart_cell`.
- [x] **8. Totals and order.** An "all" value at each level, which gives the
  subtotals and the totals. A run of headers opens and closes. The order of a
  dimension by a measure, the top N, and the value filter on a chip. **Done 2026-10-06**, with the
  open and closed runs on the rows only.
  - A total is a key whose value is `PivotTotal()` from some level on. The
    details sort by their prefixes, so a total covers a contiguous range of
    details, and the cross table keeps that range for each row and column. The
    part of a total is gathered from the parts of its details when it is read,
    so the totals add no pass over the source.
  - `PivotTable` has two new fields: `totals`, which the menu of the pivot
    turns on and off, and `collapsed`, the key prefixes of the closed runs of
    rows. Enter on a selected run of an outer level closes or opens it, and the
    selection follows the run to its new row. A closed run shows its subtotal
    row and a ▸ before its label. A run of columns does not close yet.
  - `PivotDimension` has a new field, `limit`, and a new order, `:measure`, the
    value of the first measure over the rows of each value.
  - The menu of a dimension is a part of the menu of the pivot, which reads the
    mouse target of the pivot, because a dimension does not know its pivot:
    the order, the direction, the first 5, the first 10 or every value, and a
    check for each of the first 20 values.
  - A known limit: the row numbers of the table count from the head of its
    list, and the table moves its head after a scroll of 200 rows, which the
    pivot does not follow yet; a pivot of fewer rows is not concerned.
  - Tests: `test_pivot_totals()` (29); `test_pivot()`: 255.
- [ ] **9. Group.** Row dimensions only, with the rows of each group in line
  under a header row. A `GroupedDataFrame` shows in this view. This is phase 7
  of the data frame plan.
- [ ] **10. Derived dimensions.** Bins of a number, and the year, the month or
  the day of a date. The warning for a dimension with many values.
- [ ] **11. Proposed.** A rename of a header value, which changes all rows with
  that value. A drag of a table header into the bar. "Copy as code" with
  `groupby`, `combine` and `unstack`. A heat map cell view. A pivot of a
  database query, with `GROUP BY` on the server. Tools for the assistant.

## 9. Risks

- The any-table plan is tentative. Stage 1 builds a part of it before its
  review. If the owner wants to wait for that review, stage 1 reads a data
  frame only, and the other kinds wait.
- No example puts a table in a cell of a table. The route of the events and the
  scroll inside such a cell can fail.
- A screen of chart cells can hold a hundred charts. The time of one frame can
  become too long. Stage 7 measures it.
- A dimension with many values makes a header that is very wide or very tall.
  The lazy rows and columns carry it, but the pass that finds the parts reads
  every row.
- A merged run on a lazy list must show its label when the run starts above the
  visible rows.
- A selection after a change of the pivot can go to the wrong cell, or be lost.
