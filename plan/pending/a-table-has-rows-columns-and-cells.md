# A table has rows, columns, headers and cells

> **Kind:** plan · **Status:** pending, 2026-10-06; the owner agreed to the
> shape and to the path of a cell, and no step has started. ·
> **Stands on:** [widget.md](../../documentation/package/platform/widget/widget.md),
> [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md) (R3, the paths
> of a table), and it comes before
> [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md)

## 1. The goal

`WidgetTable` gets a symmetric structure, the owner's (2026-10-06):

- `rows` — the data that belongs to whole rows;
- `row_headers` — cells of their own, which do not scroll horizontally;
- `columns` — the data that belongs to whole columns;
- `column_headers` — cells of their own, which do not scroll vertically;
- `cells` — the cells, in row-major or in column-major order.

"just like WidgetTableColumn we need WidgetTableRow type / this should be
symmetric, some of those fields are optional, for example, rows can be omitted
if no special data is given. I see WidgetTableColumns type also, maybe that
should also be mirrored."

The owner foresaw a real column document on 2026-10-02: "there may be
additional data that needs to be stored on the column … some tables are better
expressed by columns not rows."

## 2. The owner's decisions (2026-10-06)

- **The shape of §1.**
- **The path of a cell follows the structure** ("I agree with you totally,
  it's (a)"): `cells[r][c]` in a row-major table and `cells[c][r]` in a
  column-major table. This changes the rule of 2026-10-02, which made a cell
  `rows[r][c]`. A whole row stays `rows[r]`, a whole column `columns[c]`, a
  header `row_headers[r]` and `column_headers[c]`. No new reference step.
- **A row and a column can hold a padding that applies to all their cells**
  ("how about row/column padding for example which applies to all cells?").

## 3. What exists

- `WidgetTable` holds the body in `rows`: a `CellVector` of rows, or a
  `ListNode` of rows for a long table, each row a `CellVector` of cells. A
  cell is `rows[r][c]`.
- `columns` holds a `WidgetTableColumns()`, which holds nothing: `[c]` gives a
  `WidgetTableColumn(c)` that holds only its number, so `columns[c]` names a
  whole column.
- The data of a column is spread over parallel vectors of the table:
  `column_policies`, `column_align` and `column_cell_policies`; the rows have
  `row_policies`. The defaults are `column_policy`, `row_policy` and
  `cell_policy`. `SetTableColumnWidthOperation`, which the drag of the edge of
  a header writes, writes `column_policies`.
- The padding of a cell is `cell_padding` of the printer, from the theme
  (`control_padding`), the same for every cell.
- A wide table makes its columns a list through `column_headers`, a
  `ListNode`, and the readers and the printer of the parts know it
  (`column_list`).
- The renderer builds `GridLayout`s of the parts and gives them their own
  `column_policies` and `row_policies`, which it makes from the table's.
- The users of the fields and of the paths: `WidgetToGraphics.jl` and
  `WidgetTableParts.jl` (the readers, the printer, the selection bands, the
  open cells, the drag of a column edge), `CellTableToWidgetTable.jl`,
  `MarkdownToLayout.jl` (a table of markdown, edited by its paths),
  `FrameStatisticsToWidget.jl`, `EvaluatorToWidget.jl`, `ObjectToWidget.jl`,
  the data frame view (`DataFrameViewToWidget.jl`, `DataFrameFilterRow.jl`,
  and the paths of the view that it maps), 16 test files, and 5 uses of the
  column vectors in omnet-julia. A table made by the two-argument constructor
  does not change.

## 4. The model

- **`cells`** holds the body, and **`cell_order`** says which index is outer:
  `:row_major` (the default) or `:column_major`. The outer vector can be a
  `ListNode`, so the outer direction is the one that can be lazy: a long table
  is row-major with a list of rows, as now. In a wide table each inner vector
  can be a list too, as the data frame view has for more than 64 columns.
- **`rows`** and **`columns`** mirror each other, and both are optional.
  - With no data, each holds a collection that only counts:
    `WidgetTableColumns()` as now, and a new `WidgetTableRows()`. Its `[k]`
    gives a `WidgetTableColumn(k)` or a `WidgetTableRow(k)` with the defaults
    of the table, so `columns[c]` and `rows[r]` select a whole column and a
    whole row also when no data was given.
  - With data, each holds a vector of `WidgetTableRow` or `WidgetTableColumn`
    documents, or a list of them that moves in step with the outer list of
    the cells.
- **A `WidgetTableColumn`** holds the data of its column: its size policy, its
  alignment, its cell policy, and its padding. **A `WidgetTableRow`** holds its
  size policy and its padding. A field that is `nothing` takes the default of
  the table. The drag of the edge of a header writes the size policy of its
  column.
- **The padding of a cell** (open point P1): mine, the left and the right from
  its column and the top and the bottom from its row, because a column sets
  widths and a row heights; each side that neither gives takes the other one's,
  then `cell_padding` of the printer.
- **The headers** stay cells of their own, as now.
- **The printer** makes the `GridLayout`s of the parts from the rows and the
  columns, and lays out a column-major table as a row-major one by its index
  map, so the grids do not change.
- **The readers** name a cell by its path in `cells`, in the order of the
  table, and map a point to it by the same index map.

## 5. The paths, before and after

| Part | Before | After |
|---|---|---|
| A whole row | `rows[r]` | `rows[r]` |
| A whole column | `columns[c]` | `columns[c]` |
| A cell, row-major | `rows[r][c]` | `cells[r][c]` |
| A cell, column-major | (none) | `cells[c][r]` |
| A header of a row | `row_headers[r]` | `row_headers[r]` |
| A header of a column | `column_headers[c]` | `column_headers[c]` |

The data frame view keeps its own paths, `rows[r][c]` of the frame, and maps
them to the new paths of its table. A table of markdown changes its cell paths
with its table.

## 6. Open points

- **P1.** The rule of the padding of a cell, when its row and its column both
  give one (§4).
- **P2.** What more a row and a column hold: a style, a mark "read-only", or
  the open cells of the owner.
- **P3.** Whether `column_count` stays: with the data of the columns it is
  their count; with no data it is still needed.
- **P4.** Whether a column-major table can be lazy in its columns, a list of
  columns, and in its rows at the same time.

## 7. Steps

Each step keeps the behaviour of every table that does not use the new parts,
checked against main before the step (`test_platform`, the markdown and the
data frame suites, and omnet-julia).

- [ ] **1.** `WidgetTableRow`, `WidgetTableRows`, and `WidgetTableColumn` with
  data; `rows` and `columns` hold the data, and the parallel vectors and their
  writers move into them, also `SetTableColumnWidthOperation`.
- [ ] **2.** `cells` holds the body, and the path of a cell is `cells[r][c]`:
  the readers, the printer, the selection, the open cells, and every user of
  §3, with the tests.
- [ ] **3.** `cell_order = :column_major`, `cells[c][r]`, and a test table of
  each order that draws the same.
- [ ] **4.** The padding of a row and of a column (P1).
- [ ] **5.** The guides: `widget.md` and the docstrings of the table.

## 8. Risks

- Every table changes its fields and its cell paths: a reader that still names
  `rows[r][c]` finds nothing, and a selection there goes nowhere. Step 2 must
  find every user, also in omnet-julia (`omnet follows renames`).
- A table of markdown is edited by the paths of its cells, so its edit must be
  checked in a running editor.
- The lazy table of the data frame view, long and wide, is the hardest user of
  the lists.
