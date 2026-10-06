# Pivot domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [collection.md](../../platform/collection/collection.md), [widget.md](../../platform/widget/widget.md)

`ProjecturedPivot` cuts a table into parts by the values of its dimensions. The values of the row dimensions make the row headers, the values of the column dimensions make the column headers, and each cell shows the part of the table where its row and its column meet. This document says what a pivot holds, how it finds the parts, and what it reads of its source.

## How it works

### The source

A pivot reads its source through the table interface of the collection slice: `is_table`, `get_table_row_count`, `get_table_column_names`, `get_table_column_type`, `get_table_value`, `find_table_column` and `make_table_part`. So any table pivots alike:

- a vector of named tuples, and a named tuple of vectors of one length, which the collection slice reads;
- a `TablePart`, the rows of a table by their numbers, which is a table itself;
- a data frame, which `ProjecturedDataFrames` reads. Its part is a `SubDataFrame`, so an edit in a part writes the frame.

The pivot does not depend on DataFrames, and `ProjecturedDataFrames` does not depend on the pivot. The pivot depends on the chart domain, because its cells hold charts.

### The documents

| Document | What it holds |
| --- | --- |
| `PivotTable` | `source`, the five zones, `cell_view`, `source_version`, and the computed `cross_table` and `cells` |
| `PivotDimension` | `column`, `order` (`:natural` or `:first`), `descending`, and `hidden_values` |
| `PivotMeasure` | `column` and `aggregate`: `:count`, `:sum`, `:mean`, `:minimum`, `:maximum` or `:distinct_count` |
| `PivotNumberView` | a kind of `PivotCellView`: the cell shows the value of each measure |
| `PivotCells`, `PivotCellRow` | what the path `cells[r][c]` steps through |

The five zones of a `PivotTable` are `CellVector`s, in the order of the rows of the bar above the table:

- `unused_dimensions`: the dimensions that no zone uses;
- `column_dimensions`: one level of column headers each;
- `row_dimensions`: one level of row headers each;
- `cell_dimensions`: the dimensions that the view of a cell uses inside it;
- `measures`: what a cell computes from its part.

A zone is a `CellVector`, so the move of a dimension from one zone to another is a `MoveRangeOperation` of the dragging slice. It keeps the cell of the dimension and has an inverse.

`make_pivot_table(source; rows, columns, cells, measures)` makes a pivot whose zones hold the named columns, and puts every other column of the source in `unused_dimensions`. It also sets the two computed fields: `cross_table`, the cross table of the source, computed again when a zone, a dimension or `source_version` changes, and `cells`.

### The parts

`compute_pivot_cross_table(pivot)` gives a `PivotCrossTable`: the row keys, the column keys, and the rows of the source in each cell. A key is the tuple of the values of the dimensions of its axis. Only the keys that occur in the source are there. An axis with no dimension has one key, the empty tuple.

The computation makes one pass over each dimension, and reads the column as a vector when the kind of table holds one:

1. Each value of a dimension gets a code, in the order in which the values first occur. A hidden value gets the code 0, and its rows are in no part.
2. The codes of the dimensions of an axis make the code of a combination: one `Int` in mixed radix, or a vector of codes when the counts of the values do not fit in an `Int`.
3. The keys sort by the order of each dimension, the first dimension first. `:natural` is the order of `isless`, and two values that `isless` does not compare sort by their texts. `missing` is a value of its own, last in either direction.
4. A stable sort of the rows by their cells gives the part of each cell as a range of one vector, in the order of the source.

`find_pivot_part_rows(cross, r, c)` gives the rows of a cell, or `nothing` for a cell that no row reaches. `make_table_part(source, rows)` gives the part itself.

The cost, measured on 2026-10-06 with a data frame and three dimensions of 4, 40 and 10 values: 0.07 s for one million rows and 1.0 s for ten million rows. The `groupby` of DataFrames takes 0.05 s and 0.66 s for the same groups.

### The cells

A path names a cell of a pivot by its row and its column in the cross table: `cells[r][c]`, and `cells[r]` names the row. `PivotCells` and `PivotCellRow` are what the path steps through, as the rows of a data frame view are. The document of a cell is made by the view of the pivot when a path or the table first reaches it, and `PivotCells` keeps it by the key of its row, the key of its column and the kind of the view. So a change of the pivot that keeps both keys keeps the document, and a selection inside it. A new cross table drops the documents of the keys that it does not have.

`get_pivot_cell_view(pivot)` is the kind of view of the cells: the `cell_view` of the pivot, or the one that follows from its cell dimensions. With no cell dimension the cells show numbers, and with cell dimensions they show rows. The kinds:

- `PivotNumberView` shows the value of each measure of the part, with `format_pivot_value`: a whole number with no fraction, any other number with at most two decimal places. A pivot with no measure shows the count of the rows.
- `PivotRowsView` shows the rows of the part as a table, in the columns of the cell dimensions, or in every column when there is none. The package of the source gives the table through the seam `make_table_document` of the collection slice: a data frame gives a `DataFrameView` of its `SubDataFrame`, so an edit in the cell writes the frame. Any other source gives a `PivotPartTable`, which `PivotPartTableToWidget` draws as a read-only table whose rows are a list. The corner of the table shows the count of the rows of the part.

- `PivotBarChartView`, `PivotLineChartView` and `PivotPieChartView` show a chart of the first measure over the values of the first cell dimension in the part, with a series for each value of the second. The data of every chart is computed in one pass over the parts, so every cell has the same categories and the same range of values, and the charts can be compared; a line has its x from values that are numbers, and a pie gives a value the same colour in every cell. The cell holds a `PivotChartCell`, which the chain of the chart domain draws at the size of the cell, with no title, no legend and no labels of the axes.

The automatic choice: no cell dimension gives numbers; one cell dimension of numbers a line chart; one cell dimension of eight values or fewer a bar chart; two cell dimensions a bar chart with a series for each value of the second; anything else rows. A pie chart is a view that a person chooses in the menu.

A cell that no row reaches is empty. A row of the table is as tall as the lines that the view takes, `get_pivot_cell_view_lines`: one for numbers, five for a chart, ten for rows. Any view but numbers is offered the width of its column (the `:wrap` cell policy). `get_pivot_cell_key` says what the document of a cell depends on beside its keys: nothing for numbers, which read their part when they draw, and the rows and the columns for a table, which are fixed when it is made.

**The menus.** A right click on a measure chooses its aggregate. A right click on the pivot chooses the view of the cells: the automatic one, or a kind. `collect_pivot_cell_views()` lists the kinds from the method table of `describe_pivot_cell_view`, so a kind that a package adds is in the menu with no registry. The Cells row of the bar starts with an outlined badge that names the view, such as `as rows (automatic)`.

**An edit in a cell.** An edit in a cell changes the source, which no computation of the pivot reads, so the reader of the view adds a write of `source_version` to any answer of the table that is not a selection, view state or a part of a drag. The pivot then computes its parts again.

### The view

`PivotTableToWidget` draws a pivot as a grid of two rows:

- **The bar** has a row for each zone: Fields, Columns, Rows, Cells and Values. Each row shows the name of the zone and a badge for each dimension or measure in it. An empty Values row shows a muted `count` badge.
- **The table** is a `WidgetTable` that scrolls its own parts. Its rows are a list, so it builds only the rows that it shows. The header of a column is a `CellVector` of the labels of its key, and so is the header of a row, so the table draws one level for each dimension and merges a run of equal labels; see the headers with levels in [widget.md](../../platform/widget/widget.md). The corner names the row dimensions. With no column dimension, the one column is headed by the names of the measures; with no row dimension, the one row is headed `all`.

`cells[r][c]` of the pivot maps to `cells[r][c]` of the table, and `cells[r]` to `rows[r]`. A part of the table that the pivot does not name, such as a run of headers, maps back as a `ProjectionReferenceStep` of the projection, and a selection of the pivot that holds one shows in the table.

### The bar

The badge of the selected item is filled, and the others are muted. The bar is a `WidgetComposite` that holds one grid: a change of a zone or of the drag builds a new grid, and the composite prints it again, because a layout prints its children once and a composite keeps a child by its identity. The selection builds no grid: each badge reads it.

`<zone>[i]` of the pivot, such as `row_dimensions[2]`, maps to the badge of the item, and `<zone>` to the row of the zone. A point on a badge maps back to its item, and a point on the name of a zone or beside the badges to the zone. So the mouse target of the pivot names the item or the zone under the pointer.

- **A press** on a badge selects its item.
- **A drag** of a badge moves its item. The pivot keeps the state of the drag in its field `drag`, view state: the item, the point of the press, and the place where a drop puts the item now. A held move of 5 pixels starts the drag, and the drag tracker sends `DragMove`, `DragEnd` and `DragCancel` to the pivot by its path. A move over a badge puts the item before it, and a move over the name of a zone puts it at the end; the bar shows the place as an outlined badge. A dimension dropped in Values stays where it was and gives a new measure of its column: the sum of a column of numbers, and the count of any other column. A measure dropped outside Values goes out of the pivot.
- **The keys** move the selected item: Alt+Left and Alt+Right one place in its zone, Alt+Up and Alt+Down to the zone above or below, at the same place. Alt+Down from Cells gives a new measure. Delete puts a dimension back in Fields and takes a measure out of the pivot. The keys are the gesture table of `PivotTable`, so the gesture help lists them.

Each edit is an operation with an inverse: a move is a `MoveRangeOperation`, which keeps the cell of the item, and a new or a removed measure is a splice of `ReplaceReferencedValueOperation`. The selection follows the item to its new place.

`make_pivot_table_projection(; measure, appearance)` gives the projection with the row height of the font of the widget theme, and the pivot domain gives it to the natural renderer through the seam `make_graphics_projection`. So a pivot draws in a tab, and inside any document that the natural renderer draws.

### The measures

`compute_pivot_measure(table, rows, measure)` computes a measure over a part. A `missing` value counts for `:count` and for nothing else. `:sum` of no value is `0`; `:mean`, `:minimum` and `:maximum` of no value are `missing`.

## Usage

```julia
using ProjecturedPivot

sales = [(region = "EU", year = 2024, amount = 12.0),
         (region = "US", year = 2024, amount = 5.0),
         (region = "EU", year = 2025, amount = 15.0)]
pivot = make_pivot_table(sales; rows = ["region"], columns = ["year"],
                         measures = [PivotMeasure("amount", :sum)])
cross = compute_pivot_cross_table(pivot)
cross.row_keys                                  # [("EU",), ("US",)]
rows = find_pivot_part_rows(cross, 1, 2)        # the rows of EU in 2025
compute_pivot_measure(sales, rows, PivotMeasure("amount", :sum))   # 15.0
```

The example `pivot` draws the sales of `make_pivot_sales_rows()` by region and country down and by year across: `run_example("pivot")`.

The narrowest tests are `test_pivot_cross_table()`, `test_pivot_table_projection()` and `test_pivot_zone_edits()`, `test_pivot_cell_views()` and `test_pivot_chart_views()`; the test of the package is `test_pivot()`. `test_pivot_data_frame()` of the umbrella test package pivots a data frame and compares each sum with `groupby` and `combine` of DataFrames.
