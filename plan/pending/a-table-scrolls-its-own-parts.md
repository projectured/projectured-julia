# A table scrolls its own parts

> **Kind:** plan · **Status:** pending, 2026-09-29. Nothing is implemented. P1
> is made; the other points of §5 wait for the owner. · **Stands on:**
> [widget.md](../../documentation/package/widget/widget.md),
> [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md),
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
[view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md) needed the row at
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
`get_frozen_elements` (`71c55b297`) it keeps its header apart from its rows.
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

`column_headers` and `row_headers` stay `CellVector` fields, and a header stays
any document. No type is added for the header row or the header column. For a
list table, `row_headers` can also be a `ListNode`, anchored at the same row as
`rows`; the constructor then stops refusing row headers on a list.

One field is added: `scroll_position::Point2D`, the one offset of the table,
view state as the offset of a pane is. A projection that owns the table can
share the cell, as the data frame view shares the cell of its pane today.

### 3.2 Four regions

The table draws four regions, as the pane draws them today for a frozen extent:

```
[ corner        | header row: follows x          ]
[ header column | cells: follow x and y          ]
[ follows y     |                                ]
```

Each of the three parts is the content of a `WidgetScrollPane` of its own (P1),
and the table lays out the corner and the three panes. The offset of each pane
comes from the one offset of the table: the cells at `(x, y)`, the header row
at `(x, 0)`, the header column at `(0, y)`. The corner does not move. Each pane
scrolls as a pane does today, with the wheel step, the clamp at the extent of
an eager table, and `_clamp_to_list_ends` for a list.

### 3.3 The table synchronizes

A wheel event over any part scrolls the pane of that part, and the scroll
operation of that pane goes up through the reader of the table, which holds
the pane. The table turns it into a write of its one offset: a turn over the
header row moves `x`, a turn over the header column moves `y`, and a turn over
the cells moves both. Each pane draws its part of the offset, so the three
never disagree.

### 3.4 Shared geometry

The header row and the cells share the width of each column. The header column
and the cells share the height of each row.

- **The eager table.** One grid measures both today. In the new form the table
  measures the width of each column in the header row and in the cells, takes
  the larger, and gives both parts that width; the same for the height of each
  row. A column whose cells wrap needs a width before its cells have a height,
  so it keeps its policy, `Fixed` or a weight, and is not measured. Point P2.
- **The list table.** Every column has a `Fixed` width or a weight already, so
  the header row and the cells take the same widths from the same policies. A
  row of the header column must be as tall as its row of cells: with `Fixed`
  rows it is arithmetic; with `Content` rows the table takes the larger of the
  cells and the header of the row. Point P3.

### 3.5 Relocation of a list

The scroll operation of the pane of the cells passes up through the reader of
the table. When the top row
of the new offset is more than about 200 rows from the head (point P4), the
table answers one compound of view state:

- `rows` written to the node of the top row, and `row_headers` to its node when
  it is a list;
- the offset rebased by the offset of that row from the old head, so the same
  row stays at the same place on the screen.

The table walks from its head with the heights of its row canvases, as the
clamp does, to find the top row and its offset. A projection that owns the
rows, such as the data frame view, turns the write of `rows` into its own edit
(`anchor += k - 1`) and builds a new list from its data, so the old rows are
freed. A plain list gets its head moved, and its old nodes stay reachable
through `prev`.

### 3.6 The row at the top

After each scroll the table knows its top row. The scroll bar of the data frame
view needs it. Point P5 asks how the view learns it.

### 3.7 Size

The table fills the size that it is offered on an axis and scrolls there, as a
scroll pane does. With no offer on an axis, it is as large as its content on
that axis and does not scroll on it. So a small table in a page, in a graph
vertex or in a grid of charts draws as it does now.

### 3.8 References, selection and keys

The paths stay what they are: `rows[r][c]`, `column_headers[c]`,
`row_headers[r]`, and the shapes of a selection: a cell, a row, a column, the
table. The regions are output structure and name nothing in the document:

- A press goes to the region under it, then by the offset of the region into
  its part.
- A key goes by selection, as today. A move from a header into the cells, or
  back, crosses regions inside the table.
- The band of a selected row spans the header column and the cells; the band
  of a selected column spans the header row and the cells.

### 3.9 What goes away

`get_frozen_extent`, `get_frozen_elements`, `_pane_frozen_region`,
`_get_frozen_height`, the `frozen_h` parameter of `_pane_scroll_y` and
`_clamp_to_list_ends`, the entry of `get_frozen_extent` in the argument guard
(`test/suite/arguments.jl:41`), and the sentence of
[sdl.md](../../documentation/package/sdl/sdl.md) on the four regions of a frozen
pane.

### 3.10 The callers that wrap a table in a pane

A table in a pane that gives it no offer is as large as its content and does
not scroll, so the pane around it goes on working, but its header scrolls away
with the rows. Point P7 asks what each caller does.

## 4. Phases

Each phase ends with its tests and a commit, in the worktree of the data frame
plan.

- [ ] **1. The list table.** The four regions and the one offset, the
  synchronized wheel, the clamp of a list per region, row headers on a list,
  and the relocation. The tests of the list table move from the frozen pane to
  the scrolling of the table.
- [ ] **2. The eager table.** The four regions with the measured, shared
  geometry of §3.4.
- [ ] **3. Selection, keys and bands across the regions.** `test_table_selection`,
  `test_table_navigation`, `test_table_cell_editing`, `test_widget_table`.
- [ ] **4. The pane loses its frozen regions.** §3.9, the frozen example,
  `test_frozen_table_headers` becomes a test of the table,
  `DirtyRectTest`, `WidgetColorTest`, widget.md, sdl.md.
- [ ] **5. The callers.** The data frame view drops its pane and shares the
  offset of the table. `omnet-julia` builds, and `WatchExampleTest` and
  `IdeSelectAndPasteTest` pass there (P7).

The substrate suite must stay at its baseline: 3 fail and 2 error in the split
pane drag, and 2 errors in `test_anchor_point()`, as on `main`.

## 5. Points for the owner

Each recommendation is the view of the writer of this plan.

**P1. The regions are `WidgetScrollPane` documents.** The owner (2026-09-29):
"A CellVector is a document, also the header column must be a lazy list also.
It can draw a layout, no?" So each part is the content of a real pane, with no
new type: the header row is a `GridLayout` of one row over the cells of
`column_headers`, with the column widths of the table as its policies, as
`CellVectorToVerticalLayout` shares the cells of a `CellVector`;
`HorizontalLayout` does not fit, because it has one `child_width` for all its
children. The header column is a layout of one column over `row_headers`, with
the heights of the rows. The table synchronizes the offsets of the three panes.

**P8. A layout that draws a list.** No layout draws a `ListNode` today; only
the list printer of the table and the SDL walk do. The lazy header column and
the lazy cells need one: for example, `VerticalLayout` with a `ListNode` as its
`children`, walked lazily as the list table walks its rows now. Waits for the
owner.

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

## 6. Risks

- **The selection across regions** is the largest part: the readers of the
  eager table route by one grid today.
- **The measured widths of an eager table** read the sizes of both parts; a
  wrap column must not enter that measure, or the widths depend on themselves.
- **The dirty rectangles of SDL** key a record on its placement; a region that
  moves with the offset must not reuse a record of another region.
- **`omnet-julia`** follows the API of this repository; a change of the
  constructor or of the shape of the output needs its build checked.
