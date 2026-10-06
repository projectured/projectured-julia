# A table has rows, columns, headers and cells

> **Kind:** plan · **Status:** pending, 2026-10-06; the owner agreed to the
> shape, the path of a cell and P1, P3 and P4, and no step has started. ·
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
  The left and the right side of a cell come from its column, the top and the
  bottom from its row ("P1: agree with your suggestion").
- **More data on a row and a column waits** ("P2: later").
- **The collection that only counts holds the count** ("P3: if the columns are
  not present it still contains a WidgetTableColumns(n), no?"), so
  `column_count` goes.
- **Each direction can be lazy on its own** ("P4: should be able to be lazy in
  both directions independently of columnr or row major, no?").

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
  `:row_major` (the default) or `:column_major`. Each direction can be lazy on
  its own, whatever the order: the outer vector can be a `ListNode`, and each
  inner vector can be a list too, which moves in step with the list of the
  headers of its direction. The order only decides which list is the outer
  one. A long and wide table of a data frame is row-major with a list of rows
  and a list of columns, as now.
- **`rows`** and **`columns`** mirror each other, and both are optional.
  - With no data, each holds a collection that only counts:
    `WidgetTableColumns(n)` and `WidgetTableRows(n)`, which hold the count, or
    `nothing` for a direction that is an endless list. Its `[k]` gives a
    `WidgetTableColumn(k)` or a `WidgetTableRow(k)` with the defaults of the
    table, so `columns[c]` and `rows[r]` select a whole column and a whole row
    also when no data was given. The count replaces `column_count`.
  - With data, each holds a vector of `WidgetTableRow` or `WidgetTableColumn`
    documents, or a list of them that moves in step with the outer list of
    the cells.
- **A `WidgetTableColumn`** holds the data of its column: its size policy, its
  alignment, its cell policy, and its padding. **A `WidgetTableRow`** holds its
  size policy and its padding. A field that is `nothing` takes the default of
  the table. The drag of the edge of a header writes the size policy of its
  column.
- **The padding of a cell** (P1, decided): the left and the right from its
  column and the top and the bottom from its row, because a column sets widths
  and a row heights; a side that neither gives takes `cell_padding` of the
  printer.
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

- **P2, later.** What more a row and a column hold: a style, a mark
  "read-only", or the open cells of the owner.

P1, P3 and P4 are decided (§2).

## 7. Steps

Each step keeps the behaviour of every table that does not use the new parts,
checked against main before the step (`test_platform`, the markdown, the data
frame and the book suites, and omnet-julia).

The order changed when the implementation started (2026-10-06, mine): the body
must leave `rows` before `rows` can hold the data of the rows, so `cells` comes
first.

Decisions of the implementation (mine):
- The keyword constructor takes the body as `cells`. Its keyword `rows` takes
  the data of the rows, so a body that a caller still passes in `rows` raises an
  error that says the cells go in `cells`. The convenience constructor
  `WidgetTable(headers, rows)` keeps its positional rows of values, which are
  the cells.
- The keywords of the parallel vectors (`column_policies`, `column_align`,
  `column_cell_policies`, `row_policies`) and `column_count` go: a caller gives
  `columns` and `rows` data. omnet-julia uses them in four files and two tests,
  so it follows in a branch of its own, tested against this one, and lands with
  it.

- [x] **1.** `cells` holds the body, and the path of a cell is `cells[r][c]`;
  `rows` holds a `WidgetTableRows`, which `rows[r]` steps through: the readers,
  the printer, the selection, the open cells, and every user of §3, with the
  tests. Done 2026-10-06:
  - `WidgetTable` has `cells` (the body) where `rows` was, and a new `rows`
    after it, which holds a `WidgetTableRows()`; `rows[r]` gives a
    `WidgetTableRow(r)`, as `columns[c]` gives a `WidgetTableColumn(c)`.
  - The keyword constructor takes `cells`; a `rows` that a caller gives raises
    an error that names `cells`. The convenience constructor is as it was.
  - The cell path is `cells[r][c]` in the eager and the list form (the split,
    the steps, the reference, the forward map, the selection band, the light
    of the row of a cell, the head moves of a list, which write `cells`, and
    the shifts of a path). A whole row stays `rows[r]`.
  - The users: the data frame view (its table paths and the head moves; its
    own paths stay `rows[r][c]`), the markdown table (`rows[k].elements[j]` is
    `cells[k][j]`), the statistics table (its head move), the cell table, and
    the positional constructions; the examples that passed the body as `rows`
    (the table, the math table, the invoice table, the graph, the chart and the
    sequence chart examples); the guides `widget.md` and `markdown.md`.
  - Tests: 16 files follow. Markdown 236, data frames 556, book 33, and of the
    umbrella the table selection 25, the navigation 66, the cell editing 14,
    the referenced document 110 and the frame statistics feed 134, each as on
    main. The platform: one failure, in the pane of the MCP log, which has no
    table, while juliaup moved Julia from 1.13.0 to 1.13.1 between the baseline
    and this run; checked on the base commit with 1.13.1 below.
- [ ] **2.** `WidgetTableRow`, `WidgetTableColumn` with data,
  `WidgetTableRows(n)` and `WidgetTableColumns(n)`; `rows` and `columns` hold
  the data, and the parallel vectors and their writers move into them, also
  `SetTableColumnWidthOperation`; `column_count` goes.
- [ ] **3.** `cell_order = :column_major`, `cells[c][r]`, and a test table of
  each order that draws the same, also lazy in each direction and in both.
- [ ] **4.** The padding of a row and of a column (P1).
- [ ] **5.** The guides: `widget.md` and the docstrings of the table.
- [ ] **6.** omnet-julia follows: its calls of the constructor and its tests.

## 8. Risks

- Every table changes its fields and its cell paths: a reader that still names
  `rows[r][c]` finds nothing, and a selection there goes nowhere. Step 2 must
  find every user, also in omnet-julia (`omnet follows renames`).
- A table of markdown is edited by the paths of its cells, so its edit must be
  checked in a running editor.
- The lazy table of the data frame view, long and wide, is the hardest user of
  the lists.
