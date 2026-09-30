# A table scrolls its own parts

> **Kind:** plan · **Status:** done, 2026-09-30, on the branch `data-frame`, which
> is not on `main`. Every phase is implemented, and §4 records what the
> implementation found. The owner accepted the plan with the recommendations of
> §5. · **Stands on:**
> [widget.md](../../documentation/package/widget/widget.md),
> [view-and-edit-a-data-frame.md](../pending/view-and-edit-a-data-frame.md),
> [widget-sizing-rules.md](../done/widget-sizing-rules.md),
> [one-table-widget.md](../done/one-table-widget.md)

`WidgetTable` becomes the outer widget of a table. It draws its header row, its
header column and its cells each in a region that scrolls like a pane, and it
keeps one offset for the three. The table synchronizes the regions, and for a
table whose rows are a list, it moves the head of the list when a scroll goes
far from it. The scroll pane loses its frozen regions, because only tables use
them.

## 1. The request

The owner, 2026-09-29, while phase 2 of
[view-and-edit-a-data-frame.md](../pending/view-and-edit-a-data-frame.md) needed the row at
the top of a pane for a scroll bar and for a relocation of the rows:

- "the graphics image of the row already has a height, no?"
- "It's not the scroll pane who does the relocation, it's the table widget who
  modifies the scroll pane scroll operation"
- "The table should be outside and the header row and column should be their
  own widgets, they have to be scrolled on their own scroll pane, just like the
  cells in its scroll pane in both directions. Synchronization can be done by
  the table. Scroll relocation also."
- On the eager and the lazy table, and on a plan of its own before the rest of
  phase 2: "Yes for both".
- "Don't have to introduce types for row header and column header, unless
  necessary", and on the shape of the headers today: "Keep this shape if
  possible for the header row and the header column".

## 2. What exists now

**The pane is outside, the table inside.** "The table reports a width and no
height, so it goes inside a `WidgetScrollPane`"
([widget.md](../../documentation/package/widget/widget.md)). The decision is
recorded on `get_frozen_extent`: "The pane freezes and the content declares,
rather than the other way round"
([WidgetToGraphics.jl:4649](../../source/widget/WidgetToGraphics.jl#L4649)). It
came from [widget-sizing-rules.md](../done/widget-sizing-rules.md) (`67c08360b`).

**The frozen regions of the pane.** A content that declares a frozen extent is
drawn in four regions (`_pane_frozen_region`): the corner, the top strip, the
left strip and the body. The eager table declares the extent of its header row
and header column; the list table declares its header height, and with
`get_frozen_elements` (`529d326d2`) it keeps its header apart from its rows.
`_get_frozen_height` feeds the clamp of a list. Only tables declare an extent.
The dirty-rectangle walk of SDL keys a record partly on its placement, because
"the four regions of a frozen pane share their content"
([sdl.md:43](../../documentation/package/sdl/sdl.md)).

**The headers today.** `column_headers` and `row_headers` are `CellVector`
fields of `WidgetTable`, and a header is any document
([WidgetDocument.jl:2220](../../source/widget/WidgetDocument.jl#L2220)).

- The eager printer puts the headers into the one `GridLayout` of the table:
  the header row is grid row 1, the header column is grid column 1, and the
  corner is an empty label
  ([WidgetToGraphics.jl:8184](../../source/widget/WidgetToGraphics.jl#L8184)).
  So the grid shares the column widths and the row heights of the headers and
  the cells.
- The list printer prints the headers into a header canvas at the edges of the
  columns, above the body list
  ([WidgetTableList.jl:300](../../source/widget/WidgetTableList.jl#L300)). A list
  table can have no row headers: the constructor refuses them
  ([WidgetDocument.jl:2318](../../source/widget/WidgetDocument.jl#L2318)).

**The order of a wheel event.** The pane gives the event to its content first;
the table declines it; the pane then makes its own scroll operation, which goes
up from the pane
([WidgetToGraphics.jl:5110](../../source/widget/WidgetToGraphics.jl#L5110)). So
the operation never passes through the table.

**The users of the table.** In this repository:

- In a pane: the data frame view (a list), the frozen example
  (`make_widget_table_frozen_document_example`), and the tests.
- With no pane: the markdown page table (the page scrolls), `CellTableToWidgetTable`
  (its caller decides), and the examples of a table as a graph vertex, a grid
  of charts and a grid of sequence charts.

In `omnet-julia`, seven source files build a table:

- `SimulationFilterToWidget` has a list of rows.
- `SimulationResultFrameToWidget` puts the table in a pane inside a vertical
  layout.
- `SimulationOptimizationToWidget` puts it in a pane with a height of 420 when
  it has more than 12 rows.
- `SimulationWorkflowToWidget` has row headers.
- The others are plain.

`WatchExampleTest` reads `row_headers` from a printed panel. `inet-julia` builds
no table.

## 3. The design

### 3.1 The document keeps its shape

`column_headers` and `row_headers` stay fields of the table, and a header stays
any document. No type is added for the header row or the header column. Each
list of the table can be lazy: `rows`, `row_headers` and `column_headers` can
each be a `ListNode` as well as a `CellVector`, and so can the cells of one row.
A lazy `row_headers` is anchored at the same row as `rows`, and a lazy
`column_headers` at the same column as the cells of the rows. The constructor
stops refusing row headers on a list.

One field is added: `scroll_position::Point2D`, the one offset of the table,
view state as the offset of a pane is. A projection that owns the table can
share the cell, as the data frame view shares the cell of its pane today.

### 3.2 A layout for each part, in a pane of its own

The table lays out a corner and three panes:

```
[ corner        | header row: follows x          ]
[ header column | cells: follow x and y          ]
[ follows y     |                                ]
```

Each part is a layout that prints its documents through the recursion, as the
eager table prints its one grid today, and each layout is the content of a
`WidgetScrollPane` of its own:

- **The header row** is a `GridLayout` of one row over `column_headers`, with
  the width of each column as its `column_policies`. The owner (2026-09-29): "A
  grid layout is fine."
- **The cells** are a `GridLayout` over the cells of `rows`.
- **The header column** is a layout of one column over `row_headers`.

The owner (2026-09-29): "The header row is a horizontal layout recursively
printing, the cells is a grid layout recursively printing, the header column
likewise. [...] Lazy or not, should work in both cases."

The offset of each pane comes from the one offset of the table: the cells at
`(x, y)`, the header row at `(x, 0)`, the header column at `(0, y)`. The corner
does not move. Each pane scrolls as a pane does today, with the wheel step, the
clamp at the extent of an eager part, and `_clamp_to_list_ends` for a lazy one.

**The rules and the bands.** A layout positions and draws nothing. The owner
(2026-09-30): "A layout is a layout, so it's only about positioning, not about
appearance. This should be documented for the layout domain. The appearance of
a widget is complicated in style and we don't want to push that to the
layout. Can we put graphics around the layout relative to cells positioned by
the grid?" So the table draws the rules, the header bands, the hover band and
the selection band as graphics placed relative to the cells that the grid
positioned:

- For an eager grid, as today: over the edges of the columns and rows that the
  grid's IO map gives as cells.
- For a lazy grid: a graphics list that mirrors the list of rows that the grid
  placed. Each node reads the position and the height of its row, and the
  edges of the columns, and draws that row's rules and bands. The renderer
  walks it as it walks the rows, so only visible rows get graphics.

The graphics and the grid share one pane: its content is a `StackLayout` of
them, which positions its layers and draws nothing. The grid's IO map gives its
row list and its column edges for this.

### 3.3 Lazy layouts, in both directions

A layout draws a `ListNode` of children lazily, in the direction of its axis:
`VerticalLayout` down, `HorizontalLayout` to the side, and `GridLayout` in both,
with its rows from one list and the cells of a row from another. The owner
(2026-09-29): "Also, lazy lists should be supported horizontally too." A layout
walks its list from the head in both directions and builds only the children
that the viewport shows, as `WidgetTableList.jl` walks the rows today; that
file then goes away, because the eager and the lazy table print the same
layouts. The ends of a list stop the pane, as phase 1 of the data frame plan
made them do.

A lazy axis has no count. So its sizes are `Fixed` or `Content`, never a
weight: a weight divides an offered extent by a count. And a lazy column can
not be as wide as its content, because it would read cells that are never
built, so a lazy column is `Fixed`, as a list column must be `Fixed` or a
weight today.

### 3.4 The table synchronizes

A wheel event over any part scrolls the pane of that part, and the scroll
operation of that pane goes up through the reader of the table, which holds
the pane. The table turns it into a write of its one offset: a turn over the
header row moves `x`, a turn over the header column moves `y`, and a turn over
the cells moves both. Each pane draws its part of the offset, so the three
never disagree.

### 3.5 Shared geometry

The header row and the cells share the width of each column. The header column
and the cells share the height of each row. Today one grid shares them.

- **A `Fixed` or a weighted column** takes the same width in both parts from
  the same policy. A weight shares the same offer, because the header row and
  the cells have the same width.
- **A column as wide as its content** (an eager `Content` column) measures
  differently in the two parts. The table measures the header row and the
  cells, takes the larger width of each column, and gives both parts that
  width. A column whose cells wrap needs a width before its cells have a
  height, so it keeps its policy and is not measured (P2).
- **Rows** are the same: a `Fixed` row is arithmetic; a `Content` row takes the
  larger of its cells and its header (P3).

### 3.6 Relocation of a list

The scroll operation of the pane of the cells passes up through the reader of
the table. When the top row of the new offset is more than about 200 rows from
the head (P4), the table answers one compound of view state:

- `rows` written to the node of the top row, and `row_headers` to its node when
  it is a list;
- the offset rebased by the offset of that row from the old head, so the same
  row stays at the same place on the screen.

The same holds to the side for lazy columns: `column_headers` and the cells of
the rows move their head to the first visible column. The table finds the top
row, or the first column, by a walk from its head with the heights of the row
canvases, as the clamp does. A projection that owns the rows, such as the data
frame view, turns the write of `rows` into its own edit (`anchor += k - 1`) and
builds a new list from its data, so the old rows are freed. A plain list gets
its head moved, and its old nodes stay reachable through `prev`.

### 3.7 The row at the top

After each scroll the table knows its top row. The scroll bar of the data frame
view needs it. Point P5 asks how the view learns it.

### 3.8 Size

The table fills the size that it is offered on an axis and scrolls there, as a
scroll pane does. With no offer on an axis, it is as large as its content on
that axis and does not scroll on it. So a small table in a page, in a graph
vertex or in a grid of charts draws as it does now.

### 3.9 References, selection and keys

The paths stay what they are: `rows[r][c]`, `column_headers[c]`,
`row_headers[r]`, and the shapes of a selection: a cell, a row, a column, the
table. The regions are output structure and name nothing in the document:

- A press goes to the region under it, then by the offset of the region into
  its part.
- A key goes by selection, as today. A move from a header into the cells, or
  back, crosses regions inside the table.
- The band of a selected row spans the header column and the cells; the band
  of a selected column spans the header row and the cells.

### 3.10 What goes away

`get_frozen_extent`, `get_frozen_elements`, `_pane_frozen_region`,
`_get_frozen_height`, the `frozen_h` parameter of `_pane_scroll_y` and
`_clamp_to_list_ends`, `WidgetTableList.jl` (§3.3), the entry of `get_frozen_extent` in the argument guard
(`test/suite/arguments.jl:41`), and the sentence of
[sdl.md](../../documentation/package/sdl/sdl.md) on the four regions of a frozen
pane.

### 3.11 The callers that wrap a table in a pane

A table in a pane that gives it no offer is as large as its content and does
not scroll, so the pane around it goes on working, but its header scrolls away
with the rows. Point P7 asks what each caller does.

## 4. Phases

Each phase ends with its tests and a commit, in the worktree of the data frame
plan.

- [ ] **1. Lazy layouts.** `VerticalLayout`, `HorizontalLayout` and
  `GridLayout` draw a `ListNode` of children lazily in their axes (§3.3), with
  the clamp at the ends. Tests with lists of ten million children in each
  direction, and a grid lazy in both.
  - [x] **1a. The linear layouts** (`39a760f34`). A `VerticalLayout` or a
    `HorizontalLayout` whose `children` is a `ListNode` draws the children
    that a viewport shows, each after its neighbour, in `LayoutList.jl`. The
    main axis takes no weight; the cross axis takes a `Fixed` policy or the
    offered extent. A press goes to the child under the pointer and a key to
    the selected child, rooted at `children[k]` from the head. Every field of
    a `@document` is a cell, so `children` holds a list with no change of the
    document; the printer picks the list form when `children` is a list. The
    scroll pane stops at the ends of a list in either direction
    (`_find_list_canvas`, `_clamp_to_list_ends` with an axis, `_pane_scroll_x`).
  - [x] **1b. The grid with lazy rows** (`b02ba2a7b`). A `GridLayout` whose
    `children` is a `ListNode` of rows, each a vector of the cells of its
    columns, in `GridList.jl`. Every column is `Fixed` or a weight of the
    offered width; a row is `Fixed` or as tall as its cells. A press is rooted
    at `children[k][c]`. `GridLayoutListIoMap` gives the placed rows and the
    column edges, for the graphics of a container.
  - [x] **1c. A layout positions and draws nothing** (`6fb4644d4`), written as
    a design decision in [layout.md](../../documentation/package/layout/layout.md).
  - [ ] **1d. The grid with lazy columns.** Moved to just before phase 6: the
    table of phase 2 needs lazy rows and a lazy header column, and only a very
    wide data frame needs lazy columns. A row is then a `ListNode` of cells
    anchored at one column, `column_policies` a `ListNode` anchored with it,
    the rows `Fixed` (a row as tall as its cells would change while the pane
    scrolls sideways), and the grid places a list of the column positions
    that draws nothing, so the pane stops at the first and the last column.
    Implementation design, 2026-09-30:
    - **The grid.** A `GridLayout` whose rows are a list, and whose rows are
      each a `ListNode` of cells, draws both ways lazily. Its canvas holds two
      lists one level down: the rows, down, and the columns, to the side: a
      canvas for each column, as wide as the column and drawing nothing,
      placed after its neighbour from the head column at 0. The pane finds
      each list by its axis (`_find_list_canvas`) and stops at its ends.
    - **The widths.** Every column is `Fixed`: from `column_policies` when it
      is a `ListNode` anchored with the cells, else from `column_policy`. A
      weight has no count to divide by. The rows are `Fixed`.
    - **A row** draws its cells as a list to the side, each cell at the place
      of its column: the node of cell `c` pairs with the node of column `c`,
      so a walk of the cells walks the columns with them. The renderer stops
      at the edges of the clip, so a row builds the cells that show.
    - **References.** `children[k][c]`, with `c` counted from the head column
      as `k` is from the head row; `find_grid_list_cell(iomap, k, c)` gives
      one cell.
    - **The table.** `column_headers` is a list anchored with the cells. The
      policy of a column is `Fixed`, at least as wide as its header, from a
      list that mirrors the headers, and the header row and the cells take
      the same list, so their columns agree. The header row is a grid of one
      row, as tall as the header at the head column: a header clips to one
      line. The graphics of a row are a list to the side too, one piece for
      each column with its rules and bands, so only the visible columns have
      graphics.
    - [x] **1d-a. The grid** (`2f5f7d735`), in `GridColumnList.jl`: a grid
      whose `column_policies` is a `ListNode` draws its columns as a list, and
      each row is a `ListNode` of cells. `get_grid_list_column_head` and
      `find_grid_list_cell` give the columns and one cell to a container. The
      cells of a row whose columns are a list are all offered the width of
      their column, unless `column_offers` holds one `false`, which keeps it
      from every cell: a list has no index to name one column by. A column
      that is not `Fixed` fails when its width is first read, because the
      policies are built as the walk reaches them.
    - [x] **1d-b. The table** (`99a7167ee`) with `column_headers` and the
      cells of its rows as lists, in `WidgetTableParts.jl`:
      - `column_headers` a `ListNode` makes the columns a list; the keyword
        constructor takes one, and `column_align` as a list too. Every column
        is `column_policy`, which must be `Fixed`, at least as wide as its
        header, from a list of policies that mirrors the headers and that
        the header row and the cells share. The header row is a grid of one
        row, as tall as the header of the head column; a grid of a list
        reports no height, so the pane of the header row is offered it.
      - `GridLayout` whose columns are a list takes `row_offers` with one
        `false`, which measures each cell at its own height, and a
        `column_align` that is a list; it reads its row policy without a
        dependency at print, as the other grids read their policies.
      - The readers, the bands and the keys find a column through
        `_find_table_column_at` and `_get_table_column_span`, which walk the
        columns that the cells placed. A whole row, and the whole table, band
        the box of the pane of the cells, because a list has no last column
        to end at. The rules of the columns are one list for each region,
        down the whole pane, where a vector draws a segment in each row.
- [x] **2. The table of layouts.** Implementation design, 2026-09-30:
  - **The parts.** The cells are a `GridLayout` over `rows` (a flat vector
    of the cells for an eager table, the list of rows for a lazy one), with
    the gaps of the table (`2 × cell padding + border`). The header row is a
    `GridLayout` of one row over `column_headers`. The header column is a
    `GridLayout` of one column over `row_headers`. Each is the content of a
    `WidgetScrollPane` that the table prints through the recursion.
  - **The shared widths and heights (P9).** The column policies of the cells
    grid take a minimum from the natural width of each header (a header
    clips, so that width does not depend on the column), and the header grid
    takes the widths of the cells grid as `Fixed`. The grid reads the values
    of its policies inside its cells, so a policy that is a computed cell
    follows what it reads; the kind of a policy, `Fixed`, a weight or
    `Content`, stays what it was at the print.
  - **The graphics.** A `StackLayout` wraps each layer in a canvas of its own,
    so a list inside it would be two levels deep and the pane would not find
    it to clamp. So the content of a pane is the grid alone, and the table
    draws its rules and bands in a viewport of its own behind each pane, with
    the box of the pane and the offset that the table owns: over the edges of
    an eager grid, and in a list that mirrors the rows of a lazy grid.
  - **The offset.** The pane of the cells shares the `scroll_position` cell of
    the table; the panes of the headers read a computed cell of it, `(x, 0)`
    and `(0, y)`. A wheel over any part goes to the pane of the cells, so the
    pane clamps it at the ends of its lists, and the header panes follow.
  - **The readers.** The table keeps its readers: a click on a header selects
    its column, a click in a cell goes to the cell or selects its row, an
    Alt+click selects the cell, the hover names a row, and the keys move over
    rows and cells. They read the geometry that the grids report, shifted by
    the offset.
  - [x] **2a. The table of a list** (`a94a5700e`). `WidgetTableParts.jl`
    replaces `WidgetTableList.jl`; the eager table prints as before until 2b.
    Facts and decisions of the implementation:
    - **The kind of a policy is read with `peek`.** Both grid printers read
      the kind of a column or row policy at print with no dependency, and its
      numbers in the extent cells. A tracked read made the print of the
      enclosing table depend on every width, and the width cells that are set
      after the print invalidated it at once.
    - **The order of the print.** The header row prints first, with
      `Fixed(widths[c])`, where `widths` are plain cells; the cells print
      next, with the natural width of each header as the floor of a weighted
      column; then each `widths[c]` gets the computation of the width of
      column `c` of the cells. A header whose column wraps is offered the
      width and gives no floor, else the floor would read itself.
    - **The paddings of the panes.** The pane of the header row has the
      padding `bw + pad` above and to the sides and `pad` under it; the pane
      of the cells `bw + pad` on all four sides. So the rules sit in the
      padding and the gaps, and the grid is at the place of the eager grid.
      The panes have a transparent `content_color`, because the table draws
      its bands behind them.
    - **A row cut by an edge** shows its rules and bands up to the edge of
      the table and its text only up to the edge of the viewport, which is
      `bw + pad` inside. A pane that clips at its padding box, as CSS does,
      would remove the difference; not done.
    - **The pane wraps a list canvas by its field.** The pane decided from
      the value of `elements` of its content whether to draw them one by one
      or to draw the canvas; that read made the print depend on the head of
      the list, and a list that came after an empty vector never reached the
      viewport. It now decides by the field: a cell is a list layout, drawn
      as its canvas.
    - **The grid of a list gives two readers**, `get_grid_list_head` and
      `find_grid_list_row`, and every entry of a row is `(x, y, iomap)`.
    - **The readers.** A press goes to the cell through
      `find_grid_list_row`, in the coordinates of the cell. A turn of the
      wheel over either part goes to the reader of the pane of the cells, at
      a point moved into its viewport. A button down or up still goes to the
      selected cell as it did (phase 4).
    - The data frame view draws the table with no pane and shares its
      `scroll_position` with the table. The test is
      `WidgetTablePartsTest.jl`.
  - [x] **2b. The eager table** (`2dfd33453`), on the same parts, with a
    header column, and `row_offers` on `GridLayout` (P9). Facts and decisions:
    - **The readers keep the geometry of the whole table**, `WTGeometry`, as
      if it were not scrolled: the widths from the grid of the cells (of the
      header row when there are no rows), the heights from the grids of the
      cells and of the header row. A point over a part that scrolls moves by
      the offset that the pane of the cells draws with. So the hit test, the
      hover, the bands, the keys and the selection shapes of the old printer
      stay as they were, and `test_table_selection`,
      `test_table_navigation`, `test_table_cell_editing` and
      `test_widget_table` pass.
    - **One list of graphics, four regions.** The table draws its rules, its
      header bands and its two bands once, in the coordinates of the
      geometry; the corner, the header row, the header column and the cells
      each show that list behind their pane, moved by their own offset and
      clipped to their box, as the regions of a frozen pane showed one
      content. So the band of a row spans the header column and the cells,
      and the band of a column the header row and the cells.
    - **The parts are built again when the table changes its shape**, in one
      computed cell, as the old printer built its grid again.
    - **The floors.** A column that is its content takes the width of its
      header as its `min`; a weighted column that clips takes the larger of
      its header and its widest cell, read after the cells print; a column
      whose header is offered its width and wraps has no floor. A `Content`
      row takes the height of its header as its `min`; a weighted row takes
      none, as before. `GridLayout` now clamps every extent to the `min` and
      the `max` of its policy when no weight shares the offer too; before, a
      `min` without a weight was ignored. No caller had such a policy.
    - **The table fills its offer.** A table that was offered less than its
      columns need was wider than the offer; it now is as wide as the offer
      and scrolls its cells. `test_widget_table_content_floor` and
      `test_widget_table_cell_policy` read the geometry now.
    - **The table no longer declares `get_frozen_extent`**, because it holds
      its headers itself. `test_frozen_table_headers` tests the four regions
      of the table and the offsets of its parts. The frozen code of the pane
      has no user left; phase 5 removes it.
    - **Events.** The wheel goes to the pane of the cells. A button down or
      up goes to the cell under it, a header as well, in the coordinates of
      the cell, and any answer is rooted under the cell. An operation from
      below gets no answer, as before: the grid that had it had no selection.
    - The IO map of the list table is `WidgetTableListIoMap` again.
    - `test_table_selection` failed on `main` already (9 fail, 1 error): its
      filter compared the alpha of a band with `0x40 / 255`, and the theme
      makes it 0.25. The filter reads the graphics of the regions now and
      compares with 0.25; 21 pass.
    - A stored `x` past the end of the columns shows empty space at the
      right, because a pane clamps `x` only as it scrolls.
- [ ] **3. Relocation** in both directions (§3.6), and the row at the top
  (§3.7).
  - [x] **3a. The rows** (`05f16b96f`). Facts and decisions:
    - `WidgetTable` has the field `top_row`, view state (P5): the row at the
      top of the cells, counted from the head of the list. The list table
      writes it with the answer to a turn of the wheel when it changes. The
      row at the top is the row whose box holds the top edge of the cells.
    - When that row is more than 200 rows from the head (P4), the answer is
      one compound of view state: `rows` written to the node of that row,
      the offset less the place of that row, `top_row` 1, and a selection or
      a hover of a row moved by the same number of rows, so it names the
      same row. The same row stays at the same place on the screen.
    - The data frame view turns the write of `rows` into a write of its
      `anchor`: it finds the index of the new head by a walk from the head
      of its list, by identity, at most 10,000 rows each way, and builds a
      new list from the frame. A plain list keeps its old nodes, reachable
      through `prev`.
    - The eager table writes no `top_row`: all its rows are built.
    - The data frame view does not share `top_row` yet; its scroll bar
      (step 2.4 of the data frame plan) will.
  - [x] **3b. The columns** (`9ee1fd3c4`). When the column at the left edge
    of the offset is more than 200 columns from the head column, the answer
    to a turn of the wheel writes `column_headers` and a list `column_align`
    to their nodes of that column, `rows` to a list that mirrors the rows
    with each row from that column on, and the offset less the place of that
    column; a selection or a hover of a column or a cell moves with it. A
    plain table cannot move the head of every row, so the mirror walks each
    row to the new head column once, when the row shows. A projection that
    owns the columns turns the write of `column_headers` into an edit of its
    own and builds its rows from its anchors, so it walks nothing. When the
    rows and the columns are both far, the rows move first, and the columns
    at the next turn.
- [x] **4. Selection, keys and bands across the parts.** `test_table_selection`,
  `test_table_navigation`, `test_table_cell_editing`, `test_widget_table`,
  `test_widget_table_list`. The eager table has them since 2b. The table of a
  list (`ec8a2392d`):
  - A selected or hovered column, and the selected table, band the header row
    and every row; a row and a cell band their own row. The pointer over the
    header row hovers its column, as in the eager table.
  - Left and Right move a selected column; Down and Return go to its cell in
    the row at the top (`top_row`), where the eager table goes to row 1,
    because the head of a list can be far above the view. Ctrl+Space goes
    from a cell to its column.
  - A press of another button than the left, a button down or a button up
    goes to the cell under it, a header too, in the coordinates of the cell,
    in both tables.
- [x] **5. The pane loses its frozen regions.** §3.10, the frozen example,
  `test_frozen_table_headers` becomes a test of the table,
  `DirtyRectTest`, `WidgetColorTest`, widget.md, sdl.md. Done (`7fad18a5f`):
  - `get_frozen_extent`, `get_frozen_elements`, `_pane_frozen_region` and
    `_get_frozen_height` are gone, and so are the parameter of the frozen
    strip of `_pane_scroll_y` and `_clamp_to_list_ends`, the export, and the
    entry in the argument guard. `test_frozen_table_headers` became a test of
    the table in 2b.
  - `_find_list_canvas` looks on to the next element canvas when a list runs
    along the other axis, where it stopped at the first list.
  - The frozen example keeps its pane, as the container that gives the table
    its size; the offset is on the table now. Without the pane the table
    fills the window and has nothing to scroll. This changes P7 for the
    example.
  - The comments of `Sdl.jl`, `DirtyRectTest` and `is_infinite_canvas`, and
    sdl.md, name the regions of a table where they named a frozen pane.
- [x] **6. The callers.** The data frame view drops its pane, shares the offset
  of the table, and gets lazy columns. `omnet-julia` builds, and
  `WatchExampleTest` and `IdeSelectAndPasteTest` pass there (P7).
  - [x] **6a. The data frame view** (`1dd1a1459`). It dropped its pane and
    shares its offset in 2a. A frame of more than 64 columns now draws its
    columns as a list from the column `column_anchor`, a new field of the view:
    each column is 120 pixels wide and at least as wide as its header, and each
    row is as tall as a line of the font of the table, from
    `compute_line_box`, which `make_data_frame_view_projection` measures. A
    narrower frame keeps the columns that share the width of the table. When
    the table moves its head column, the view moves `column_anchor` and builds
    the headers, the alignments and the rows again from its anchors, so it
    drops the writes of `rows` and `column_align` that come with it.
  - A cell that a grid of a list builds gets a context whose path is typed by
    a walk of `children[k][c]` from the heads, so a cell costs as many steps
    as it is far from the head: at most about 200 in each direction, because
    the table moves its heads there. A test that walks 400 columns of 100 rows
    took six minutes; the test of the wide frame has three rows.
  - [x] **6b. `omnet-julia`.** Its four tables in a `WidgetScrollPane` work
    as they are: the pane gives the table its size, and the table fills it
    and scrolls, so they keep their pane and this changes P7 for them. The
    check (2026-09-30, `omnet-julia` at `ecfbb8a2`): a scratch environment of
    its `environment/all` with the projectured packages at the worktree
    builds, and the watch tests of `WatchExampleTest` and
    `test_select_and_paste` give 377 pass, 3 fail and 2 errors, the same as
    the same environment at `main`: `test_adaptive_search` (2 errors),
    `test_topology_card` (2 fail) and `test_sim_control_panel` (1 fail).
    `test_parallel_sim_dashboard_panel` hangs at the stop of its parallel
    engine with two threads, and draws no table; the check leaves it out.

The substrate suite must stay at its baseline: 3 fail and 2 error in the split
pane drag, and 2 errors in `test_anchor_point()`, as on `main`.

## 5. Points for the owner

The owner (2026-09-29), on the plan with these recommendations: "Looks good,
the WidgetTable keeps its shape down to its cells including headers, adding
lazy list." So P2 to P8 are made as recommended: the document of the table
keeps its fields down to its cells and headers, and `rows` and `row_headers`
can each be a lazy list.

**P1. The regions are `WidgetScrollPane` documents.** The owner (2026-09-29):
"A CellVector is a document, also the header column must be a lazy list also.
It can draw a layout, no?" So each part is the content of a real pane, with no
new type: the header row is a `GridLayout` of one row over the cells of
`column_headers`, with the column widths of the table as its policies, as
`CellVectorToVerticalLayout` shares the cells of a `CellVector`;
`HorizontalLayout` does not fit, because it has one `child_width` for all its
children. The header column is a layout of one column over `row_headers`, with
the heights of the rows. The table synchronizes the offsets of the three panes.

**P8. Layouts that draw a list.** Made: the layouts draw a `ListNode` lazily,
in both directions (§3.3).

**P2. The width of an eager column whose cells wrap.** It keeps its policy and
is not measured (§3.4). Recommendation: yes.

**P3. The height of a list row with `Content` rows.** The larger of the cells
and the header of the row. Recommendation: yes.

**P4. When the table relocates.** At about 200 rows from the head. A small
number rebuilds the visible rows often; a large one keeps more rows. Recommendation: 200.

**P5. How a projection learns the top row.** The table writes it as view state
in a field `top_row`, and a projection shares the cell. Recommendation: yes; it
is the field that the scroll bar of the data frame view reads.

**P6. A header column on a list.** `row_headers` as a `ListNode`, anchored with
`rows` (§3.1). Recommendation: yes; the frozen key columns and the pivot of the
data frame plan need it.

**P7. The callers that wrap a table in a pane.**
- The data frame view drops its pane and shares the offset of the table.
- The frozen example drops its pane.
- In `omnet-julia`, `SimulationResultFrameToWidget` and
  `SimulationOptimizationToWidget` drop their pane, so that their header stays.

Recommendation: yes, and a check that `omnet-julia` builds and its tests of
tables pass.

**P9. Details of the shared geometry, accepted by the owner (2026-09-30:
"Continue").**
- The cells grid is the master of the shared geometry. The header row is a
  `GridLayout` of one row with the column widths of the cells grid as `Fixed`
  widths, and the header column a `GridLayout` of one column with its row
  heights. Each header sets a minimum on its column or row. A header cell
  clips, so its natural size does not depend on what it is given.
- `GridLayout` gets `row_offers`, as it has `column_offers`: a row told its
  height does not pass it to its cells, so a `Content` row can be measured.
- A lazy table with a header column has `Fixed` rows: the header column and
  the rows are two lazy lists, and only a `Fixed` row keeps them the same
  height. This changes P3 for a lazy table.

## 6. Risks

- **The selection across regions** is the largest part: the readers of the
  eager table route by one grid today.
- **The measured widths of an eager table** read the sizes of both parts; a
  wrap column must not enter that measure, or the widths depend on themselves.
- **The dirty rectangles of SDL** key a record on its placement; a region that
  moves with the offset must not reuse a record of another region.
- **`omnet-julia`** follows the API of this repository; a change of the
  constructor or of the shape of the output needs its build checked.
