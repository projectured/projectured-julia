# Pivot domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [collection.md](../../platform/collection/collection.md), [widget.md](../../platform/widget/widget.md)

`ProjecturedPivot` cuts a table into parts by the values of its dimensions. The values of the row dimensions make the row headers, the values of the column dimensions make the column headers, and each cell shows the part of the table where its row and its column meet. This document says what a pivot holds, how it finds the parts, and what it reads of its source.

## How it works

### The source

A pivot reads its source through the table interface of the collection slice: `is_table`, `get_table_row_count`, `get_table_column_names`, `get_table_column_type`, `get_table_value`, `find_table_column` and `make_table_part`. So any table pivots alike:

- a vector of named tuples, and a named tuple of vectors of one length, which the collection slice reads;
- a `TablePart`, the rows of a table by their numbers, which is a table itself;
- a data frame, which `ProjecturedDataFrames` reads. Its part is a `SubDataFrame`, so an edit in a part writes the frame.

The pivot does not depend on DataFrames, and `ProjecturedDataFrames` does not depend on the pivot.

### The documents

| Document | What it holds |
| --- | --- |
| `PivotTable` | `source`, the five zones, `cell_view`, and `source_version` |
| `PivotDimension` | `column`, `order` (`:natural` or `:first`), `descending`, and `hidden_values` |
| `PivotMeasure` | `column` and `aggregate`: `:count`, `:sum`, `:mean`, `:minimum`, `:maximum` or `:distinct_count` |
| `PivotNumberView` | a kind of `PivotCellView`: the cell shows the value of each measure |

The five zones of a `PivotTable` are `CellVector`s, in the order of the rows of the bar above the table:

- `unused_dimensions`: the dimensions that no zone uses;
- `column_dimensions`: one level of column headers each;
- `row_dimensions`: one level of row headers each;
- `cell_dimensions`: the dimensions that the view of a cell uses inside it;
- `measures`: what a cell computes from its part.

A zone is a `CellVector`, so the move of a dimension from one zone to another is a `MoveRangeOperation` of the dragging slice. It keeps the cell of the dimension and has an inverse.

`make_pivot_table(source; rows, columns, cells, measures)` makes a pivot whose zones hold the named columns, and puts every other column of the source in `unused_dimensions`.

### The parts

`compute_pivot_cross_table(pivot)` gives a `PivotCrossTable`: the row keys, the column keys, and the rows of the source in each cell. A key is the tuple of the values of the dimensions of its axis. Only the keys that occur in the source are there. An axis with no dimension has one key, the empty tuple.

The computation makes one pass over each dimension, and reads the column as a vector when the kind of table holds one:

1. Each value of a dimension gets a code, in the order in which the values first occur. A hidden value gets the code 0, and its rows are in no part.
2. The codes of the dimensions of an axis make the code of a combination: one `Int` in mixed radix, or a vector of codes when the counts of the values do not fit in an `Int`.
3. The keys sort by the order of each dimension, the first dimension first. `:natural` is the order of `isless`, and two values that `isless` does not compare sort by their texts. `missing` is a value of its own, last in either direction.
4. A stable sort of the rows by their cells gives the part of each cell as a range of one vector, in the order of the source.

`find_pivot_part_rows(cross, r, c)` gives the rows of a cell, or `nothing` for a cell that no row reaches. `make_table_part(source, rows)` gives the part itself.

The cost, measured on 2026-10-06 with a data frame and three dimensions of 4, 40 and 10 values: 0.07 s for one million rows and 1.0 s for ten million rows. The `groupby` of DataFrames takes 0.05 s and 0.66 s for the same groups.

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

The narrowest test is `test_pivot_cross_table()`; the test of the package is `test_pivot()`.
