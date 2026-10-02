# View and edit a data frame

> **Kind:** plan · **Status:** pending, 2026-09-29. Phase 0 is done (§6.1).
> Every decision of §5 is made, except group and pivot, which wait for a
> design of their own (D8). ·
> **Stands on:** [concepts.md](../../documentation/design/concepts.md),
> [domain-anatomy.md](../../documentation/design/domain-anatomy.md),
> [package-rules.md](../../documentation/rule/package-rules.md),
> [reflection.md](../../documentation/package/reflection/reflection.md),
> [widget.md](../../documentation/package/widget/widget.md),
> [chart.md](../../documentation/package/chart/chart.md),
> [undo.md](../../documentation/package/undo/undo.md)

A new package shows the native structures of DataFrames.jl in the editor and
edits them. The data stays in the `DataFrame` of the program. The editor shows
it, sorts it, filters it, finds values in it, groups it and pivots it, and an
edit in the view writes the `DataFrame` itself.

## 1. The request

The owner (2026-09-29): "let's write a plan for creating a projectured package
for supporting displaying DataFrames stuff". The ideas of the owner:

- view and edit native data structures from the DataFrames package;
- large data frames with lazy tables;
- filtering, sorting, grouping;
- automatic refreshing;
- pivot tables with selectable dimensions for row headers, column headers and
  cells (containing sub-tables or plots);
- finding things in the table.

§4 adds the features that the plan proposes beyond this list. Each one is
marked "proposed".

## 2. What exists now

These facts were read from the tree on 2026-09-29.

**Tables.**

- `WidgetTable` is the one table widget
  ([WidgetDocument.jl:2220](../../source/widget/WidgetDocument.jl#L2220)). A
  cell holds any document, a chart or a nested table too.
- `rows` is a `CellVector` (eager) or a `ListNode` (lazy). In the lazy printer
  [WidgetTableList.jl](../../source/widget/WidgetTableList.jl#L7), **the head
  is the anchor**: the table walks `prev` up and `next` down from it, and it
  builds only the rows that the viewport shows. A new head drops the built rows
  and starts again.
- A node that is built from its index alone can be the head at any row, and
  the list stays lazy in both directions. `make_primes_around(10^12)` is such a
  list. So a jump to any row of a data frame is a new head, and it costs the
  visible rows.
- Three limits of the lazy table remain:
  - `is_infinite_canvas` is true for every canvas whose elements are a
    `ListNode` ([GraphicsCaching.jl:18](../../source/graphics/GraphicsCaching.jl#L18)).
    So the scroll pane does not clamp at the first or the last row of a finite
    list, and a wheel can scroll past the ends into an empty area.
  - `WidgetTableListState.built` keeps every row that the walk built since the
    last new head. A long scroll keeps all the rows that it passed.
  - A list draws no row headers (`_wtl_check`,
    [WidgetTableList.jl:72](../../source/widget/WidgetTableList.jl#L72)), and
    only its header strip is frozen, so no column is frozen.
- A scroll pane has no scroll bar: `WidgetScrollBar` is a separate slider with
  a `value` and a `thumb_size`, and nothing attaches it.
- Range selection is not done. [table-selection.md](../done/table-selection.md)
  deferred it as phase 4. Column resize and a sort indicator do not exist.
- A key in a cell goes to the document in the cell
  ([edit-inside-a-table-cell.md](../done/edit-inside-a-table-cell.md)).
  `UpdateDatabaseCellOperation` and `InsertDatabaseRowOperation`
  ([DatabaseDocument.jl:28](../../source/database/DatabaseDocument.jl#L28))
  have no producer and no evaluator.

**Native values and change.**

- The value viewer keeps a **shadow** of a native value and a `ReflectionFeed`
  that syncs the shadow once per frame. A sync writes only what changed
  ([reflection.md](../../documentation/package/reflection/reflection.md)).
- The feed list of an editor is fixed when the editor is made
  ([editor.md](../../documentation/package/kernel/editor.md#the-feeds)).
- `post_operation!` and `run_on_editor_task!` are the door from another task
  into a running editor. The docstring names a timer and a file watcher as
  producers ([Inbox.jl](../../source/kernel/editor/Inbox.jl)).
- No refresh command, key or poll exists in `source/`.
- `run_example` runs `run_editor!` in the foreground, so it blocks the REPL.
  One test runs the loop in a task, `@async run_editor!(editor)`
  ([WaitTest.jl:130](../../test/kernel/editor/WaitTest.jl#L130)). No code runs
  an SDL editor beside the REPL yet.
- Undo stores the inverse of each operation. `make_inverse_operation` is
  declared by the package of the operation
  ([undo.md](../../documentation/package/undo/undo.md)). So an edit of a
  native value can be undone if its operation declares an inverse.

**Charts and evaluation.**

- A chart series holds whole columns, and any `AbstractVector{<:Real}` is a
  column. A data frame column goes into a series with no copy
  ([ChartDocument.jl:9](../../source/chart/ChartDocument.jl#L9)).
- The evaluator keeps a result live only when it `isa Document`. Any other
  value becomes printed text
  ([Evaluator.jl:431](../../source/conversation/Evaluator.jl#L431)).
- `register_natural_graphics!` adds a row to `NaturalToGraphics`, so a
  document type draws in a tab, an evaluator result, a card and a table cell.

**Packages.**

- No package uses DataFrames or package extensions. `ProjecturedOdbc` uses
  `Tables`.
- A package with a third-party dependency is a stem of its own, and the
  umbrella does not load it ([package-rules.md](../../documentation/rule/package-rules.md)).
- DataFrames is the largest source of invalidation in the sessions of this
  author
  ([package-convention-repl-leaves.md:563](package-convention-repl-leaves.md)).
- "Frame" already names a render frame: `FrameStatistics`, `FramePlot`,
  `FrameStatisticsFeed`. The new types can not use the prefix `Frame`.

## 3. The model

### 3.1 The data stays native

The package never copies a data frame into cells. Ten million rows of twenty
columns are 200 million values, and a cell for each is not possible. The view
reads the native columns, and it keeps a shadow of the **visible cells only**.

```
DataFrame (native, in the program)
   │  sync: the structure, and the visible cells
   ▼
DataFrameView (document)  ── query, layout, pending edit, find state
   │  DataFrameViewToWidget  (printer: visible rows; reader: edits → operations)
   ▼
WidgetTable whose rows are a ListNode ── WidgetToGraphics ── screen
```

### 3.2 The view document

`DataFrameView` is an `@document`. Its fields:

| Field | What it holds |
| --- | --- |
| `source` | the native value: `DataFrame`, `SubDataFrame`, `GroupedDataFrame` or `DataFrameRow`; or a global binding that the view follows (§4.3) |
| `query` | a `DataFrameQuery` document: the filter, the sort keys, the group keys, the hidden and the moved columns |
| `layout` | the column widths, the frozen columns, the row height |
| `pending_edit` | the cell under edit and its text, or `nothing` |
| `find` | a `DataFrameFind` document: the pattern, the mode, the scope, the current match |
| `structure_version`, `column_versions` | counters that the sync and the edits write, so a computed cell knows when a column changed |

The query is a document, so a person, a key and the assistant change it with
the same edits, and a query can be saved.

### 3.3 The row order

The query gives a `Vector{Int}` of source row indices in a computed cell. The
cell reads the versions of the columns that the query reads, and nothing more.
So an edit of a column that the query does not read does not sort again. The
sort, the filter and the grouping use the native DataFrames functions
(`sortperm`, `findall` over columns, `groupby`). The generic
`SortingProjection` and `FilteringProjection` read one cell per element, so
they do not scale to this size.

### 3.4 The selection

A path in the view names a **row of the frame** and a **column of the frame**,
by their numbers, with the steps of a table and no step of its own:
`rows[5][3]` is the cell of row 5 and column 3 of the frame, then the caret in
the document of the cell, `rows[5][3].value{2}`. `rows[5]` is a row and
`columns[3]` a column. So the selection survives a sort, a filter, a hidden
column and a scroll. A row of a data frame has no identity other than its
index. An insert or a delete by the view moves the selection with it. An
insert or a delete from the REPL can put the selection on another row or
column. The view maps its paths to the paths of its table, whose numbers count
the shown rows and columns (R3 of phase 4).

### 3.5 Lazy rows: a list anchored at any row

The rows of the view are a `ListNode`, and the lazy table of today draws them.

- The node of position `p` holds the row at position `p` of the row order,
  which is the source row `row_order[p]`. The node is built from `p` alone.
  Its `prev` and its `next` are computed when they are first read, as in
  `make_primes_around`. The `prev` of position 1 and the `next` of position
  `n` are `nothing`.
- A **jump** to position `p` writes a new head at `p`. The table drops the rows
  that it built and builds the visible rows around `p`. These actions are
  jumps: "go to row", the next match of a find, a drag of the scroll bar,
  Ctrl+Home, Ctrl+End, and a new row order after a sort or a filter. After a
  new row order, the head goes to the position of the row under the selection.
- The widget reference `rows[k]` counts from the head. The reader of the view
  maps it: the position is `head + k - 1`, and the source row is
  `row_order[position]`. So a new head does not change the path of §3.4.
- **Re-anchor.** The table keeps each row that it built until the head
  changes. If the top visible row is more than about 500 rows from the head,
  the view writes a new head at that row. It also writes the scroll offset
  that keeps the row at the same place on the screen. So the view keeps at
  most about 500 rows plus the visible rows.
- **The scroll bar.** The view knows the row count, and the list does not. So
  the view puts a `WidgetScrollBar` beside the pane. Its `value` is the
  position of the top visible row divided by the row count, and its
  `thumb_size` is the count of visible rows divided by the row count. A drag of
  the thumb is a jump.

The same list serves a grouped view, a pivot and a find result. A database
cursor with an offset can use it later in the same way.

Two changes of the lazy table remain in the widget substrate:

1. **The ends of a finite list.** The pane must clamp at the first and the
   last row. It clamps when its walk reaches a node whose `prev` or `next` is
   `nothing` (D2).
2. **Frozen columns and row headers on a list.** A key column, the group
   headers and the row dimensions of a pivot stay on the screen while the
   table scrolls to the side.

### 3.6 An edit goes back

A key in a cell edits the **pending text** of the cell, not the data frame.
Enter, Tab or a move out of the cell parses the text into the element type of
the column and writes the value. If the parse fails, the text stays, the cell
shows an error mark, and the reason is in its tooltip. Escape drops the
pending text. So "12." and "-" are states that the view can hold, which
PR-INTERMEDIATE-STATES asks for. D5 chose this model.

A `PrimitiveNumber` today is written and parsed again after each key.
`splice_number` gives `nothing` for a text that does not parse, such as `-` or
`1e` ([PrimitiveDocument.jl:184](../../source/primitive/PrimitiveDocument.jl#L184)).
So a write on each key can not hold such a text, and a column of a data frame
also has a fixed element type.

The operations, each with its inverse for undo:

- `SetDataFrameValueOperation`
- `InsertDataFrameRowOperation`, `DeleteDataFrameRowOperation`
- `InsertDataFrameColumnOperation`, `DeleteDataFrameColumnOperation`
- `RenameDataFrameColumnOperation`, `MoveDataFrameColumnOperation`
- `ConvertDataFrameColumnOperation`, which changes the element type and allows
  or forbids `missing`

A query edit is an ordinary edit of the query document, so it needs no new
operation type. The evaluation of a data operation writes the native frame and
then increments the version of the column it wrote.

## 4. Features

### 4.1 View the native structures (the owner)

- `DataFrame`: the table.
- `SubDataFrame`: the table. An edit writes through to the parent, because that
  is what DataFrames does. Row insert and delete are off, because DataFrames
  forbids them on a view.
- `DataFrameRow`: a form with one field for each column.
- `GroupedDataFrame`: the grouped view of §4.6.
- Each cell draws by its element type: a number aligned right, `missing`
  muted, a `Bool` as a check box, a categorical value (`PooledArray`,
  `CategoricalArray`) with a list of its levels, a date, and a nested value
  (a vector, a struct) through the value viewer in place.
- A column with an immutable vector (a range, an Arrow column) is read-only,
  and its header says so.
- The header of a column shows its name and its element type.

### 4.2 Large data frames (the owner)

- The anchored list of §3.5, with its jumps, its re-anchor and its scroll bar.
- **Proposed:** lazy columns, so a frame with a thousand columns prints only
  the visible columns. The lazy table builds every column of a visible row now,
  so this needs a change of the list printer.

### 4.3 Refresh (the owner)

A program changes a data frame outside the editor. The sync has three levels
of cost:

1. **The structure**: the row count, the column names, the element types and
   the identity (`objectid`) of each column vector. The cost is one read for
   each column.
2. **The visible cells**: compare each visible value with its shadow, and
   write only what differs. The cost is one read for each visible cell.
3. **The derived results**: the row order, the groups and the pivot depend on
   whole columns. An in-place write such as `df.a[5] = 3` on a row that is not
   visible changes none of the checks above. Only a hash of the columns that
   the query reads finds it. The cost is linear in the row count.

The triggers that can run a sync:

- **A.** An edit through the view. It knows what it wrote.
- **B.** A hook in the Julia REPL posts a sync after each input.
- **C.** A timer posts a sync every half second while a view is on the screen.
- **D.** A key recomputes all three levels at once.

Decision D3 asks which triggers to build.

**In the normal Julia REPL.** The users work there (§5.1), so B is the main
trigger. The hook wraps each input, so it knows when an input starts and when
it ends. After the end, it posts a sync with `post_operation!`. It also sees a
change by a function that the input calls. It does not work in IJulia or in a
script. Phase 0 checks the REPL of VS Code.

The REPL task runs the code of the user, and the editor runs in a background
task (D4). Phase 0 finds out which case is possible:

- **The same thread (`@async`).** The editor runs only while the REPL waits
  for input, so no race is possible. The window does not paint or scroll
  during a long input.
- **Another thread (a task pinned to it).** This is the case (phase 2.5).
  The window stays live, and it takes input during a long input of the REPL.
  The view reads the frame only when it builds rows: on a scroll, a jump, a
  resize or a refresh. If an input changes the structure of a shown frame in
  place (`push!`, `deleteat!`, `select!`, `sort!`) while the person scrolls
  it, the view can show a wrong row until the next refresh, or the fault
  barrier can catch an exception. In very rare cases the process can crash,
  because DataFrames reads the columns with `@inbounds` after it checks the
  first column. The display states this in its docstring. There is no busy
  flag (D3, §5.1).

C is for a writer that is not the REPL, such as a task that appends rows. It
is safe only when nothing writes the frame at the same time.

- **Proposed:** a view can follow a global binding, for example `Main.df`, so
  `df = filter(...)` in the REPL moves the view to the new frame.

### 4.4 Sort and filter (the owner)

- A click on a header sorts by that column: ascending, descending, off.
  Shift+click adds a key. The header shows an arrow and the order of the key.
- A quick filter on each column, opened from the header: a text or a regular
  expression; a range for a number; a list of the values with their counts
  when a column has few distinct values; "missing" or "not missing".
- An expression filter: a Julia expression over the column names, for example
  `age > 30 && startswith(city, "B")`. The Julia domain edits it.
- Hide, show, move and freeze columns.
- While the text of a cell is pending, the row stays where it is. The commit
  writes the frame, and the view sorts and filters again at once (D6). D10
  says where the selection and the view go.
- **Proposed:** "copy as code" gives the query as DataFrames code (`subset`,
  `sort`, `select`, `groupby`, `combine`), so a person moves a view into a
  script.

### 4.5 Find (the owner)

- Ctrl+F opens a find bar in the view. The pattern is a text, a regular
  expression, or an exact value. The scope is all visible columns, the
  selected column, or the selected range.
- Enter and Shift+Enter move the selection to the next and the previous match,
  in the order of the view, from the current selection. The table scrolls to
  the match with the jump of §3.5.
- The view marks the visible matches. Only visible cells are tested for this.
- The find bar shows "match k of n". For a large frame, the count is computed
  in slices with a time limit in each frame, and it shows "k of at least n"
  until it is complete.
- "Filter to matches" turns the find into a quick filter.
- **Proposed:** replace, and replace all in the scope, as one undo step. The
  replacement is parsed into the element type of each column.

### 4.6 Group (the owner)

- Group by one or more columns. The rows show in group order. A header row
  for each group shows the key values, the row count, and one aggregate for
  each column (sum, mean, minimum, maximum, count).
- A group opens and closes. A closed group is one row.
- A `GroupedDataFrame` from the program shows in this view.

### 4.7 Pivot (the owner)

- A `DataFramePivot` document holds the **row dimensions**, the **column
  dimensions** and the **cell content**. It reads the filtered rows of a view.
- A field list shows the columns of the frame as chips. A chip moves between
  the three zones by a drag (`ProjecturedDragging`) and by keys.
- The cell content is one of these:
  - an aggregate of a column: a number, read-only. A click opens the rows of
    the group.
  - a sub-table: a nested `DataFrameView` of the `SubDataFrame` of the group,
    in a card that shows "123 rows" when it is closed. An edit in it writes the
    source frame.
  - a chart: a `Chart` with the columns of the group, the size of a sparkline
    in the cell, full size when opened.
- Row headers and column headers have one level for each dimension. A row
  level opens and closes, and it can show a subtotal.
- **Proposed:** sort the pivot rows by an aggregate, and keep only the top N.
- The rows of a pivot are an anchored list too. The columns of a pivot can
  also hold many distinct keys, and they need the lazy columns of §4.2.
- The widget substrate needs two new things: row headers on a lazy table
  (§3.5), and a column header that spans columns.

### 4.8 Proposed features

- **A column summary.** A strip under the header shows, for each column, the
  missing count and a small histogram or the top values. It is computed only
  for the visible columns. The tooltip shows the full `describe` row.
- **Range selection and the clipboard.** Select a rectangle, copy it as
  tab-separated text, Markdown or a Julia literal, and paste tab-separated
  text into a range. This needs phase 4 of
  [table-selection.md](../done/table-selection.md).
- **Column resize and fit.** Drag the edge of a header. A double click fits
  the column to its visible values.
- **A quick chart.** Select columns, and a chart opens in a split pane. The
  selection is linked both ways: a point in the chart selects its row in the
  table, and a row range in the table marks its points in the chart.
- **Two views of one frame.** Two tabs on the same frame, with different
  queries. An edit in one shows in the other.
- **An edit log as code.** The edits of a session as Julia statements, for
  example `df[5, :price] = 12.5`, so a manual correction is reproducible.
- **The assistant.** The assistant reads the schema, the query and the visible
  rows, and it changes the query with the same edits: "the ten largest orders
  in each region".
- **Any Tables.jl table.** `DataFrame(table; copycols = false)` wraps a
  `CSV.File`, an Arrow table or a query result with no copy. It is read-only
  where the columns are immutable.
- **Compare two frames.** Show the rows that were added, removed and changed
  between two frames, for example before and after a transformation.

### 4.9 Out of scope

- Write a file (CSV, Arrow). The program of the person does it. It needs a
  third-party package.
- Data that is not in memory (DuckDB, a Parquet file on disk). The anchored
  list is the seam for it later: a node reads its row from the store with an
  offset.
- Formulas in cells. [excel-julia-formulas.md](excel-julia-formulas.md) is the
  spreadsheet idea.

### 4.10 As few dependencies as possible (the owner)

The owner (2026-09-30): "Remove the ProjecturedSdl dependency, backends should
register themselves and automatically used if there's only one and none was
given. I would also remove the wrapper package dependencies if possible too.
And they would also register and map to a keyword argument in the run editor
function somewhere. The point is to have as few dependencies as possible."

Today `ProjecturedDataFrames` depends on three packages only to open its
window (phase 2.5):

- `ProjecturedSdl`, for `SdlBackend()`, the default of `display_in_editor`.
- `ProjecturedScreen`, for `make_editor`, which puts the document in a window.
- `ProjecturedPane`, for `PaneTree`, `PaneGroup`, `PaneTab` and
  `PaneToWidget`, which put each frame in a tab, and for `open_pane!`,
  `find_pane` and `focus_pane!`.

The other dependencies are what the view is: `DataFrames`, `ProjecturedKernel`,
`ProjecturedCollection`, `ProjecturedProjection`, `ProjecturedLayout`,
`ProjecturedWidget`, `ProjecturedStyle`, `ProjecturedPrimitive`, and
`ProjecturedNatural`, whose registry takes the natural row of the view.

The direction:

- **A backend registers itself.** The `__init__` of a backend package adds
  its backend to a registry, as a domain adds its natural row today. A run
  function that is given no backend takes the one registered backend; with
  none, or with more than one, it says so and names the registered ones. This
  reverses a rule that `ProjecturedScreen.make_editor` states now: "`backend`
  is a CONSTRUCTED backend, so this package depends on none of them [...]
  There is no reflection over the loaded backends here". The reflection that
  exists, `default_backend()` of `ProjecturedExample`, finds a loaded backend
  by the subtypes of `Backend` and a fixed order of preference; the registry
  replaces it.
- **A wrapper registers itself too, and maps to a keyword of the run
  function.** The window of `ProjecturedScreen` and the tabs of
  `ProjecturedPane` wrap a document and add a rule to the projection. Each
  registers what its keyword does, so a caller asks for tabs with a keyword
  of the run function and does not load the package that makes them.

The points to settle are D13. The owner made them on 2026-09-30, and then
chose seams in place of registries (§5.1). The design is in
[packages-compose-by-seams.md](packages-compose-by-seams.md).

## 5. Decisions

### 5.1 Made

- **The rows are the `ListNode` that exists**, anchored at any row (§3.5). The
  plan adds no new kind of row source. A fact, from the owner (2026-09-29):
  "The lazy table uses the ListNode and the list head can be at any index in
  the table and still be lazy in both directions, so it can absolutely jump to
  any row in a large data frame."
- **D2 is (b)** (the owner, 2026-09-29). The pane clamps when its walk reaches
  a node whose `prev` or `next` is `nothing`. The options are kept below.
- **The re-anchor of §3.5 is part of the plan** (the owner, 2026-09-29). It
  keeps the rows that a long scroll builds to a bound.
- **Frozen columns and row headers on a list are part of the plan** (the
  owner, 2026-09-29). They are a change of the widget substrate, in phase 5
  and phase 8.
- **The users work in the normal Julia REPL** (the owner, 2026-09-29): "I
  expect the user's to use the data frame display from normal julia repl, not
  the projectured repl." So the evaluator of the editor is not the place where
  a data frame is shown or changed.
- **D1 is (b)** (the owner, 2026-09-29). The first delivery is phases 0, 1, 2
  and 4: the facts, the ends of a finite list, the read-only view, and edit.
  Refresh, sort and filter, and find come next.
- **D4 is (b)** (the owner, 2026-09-29). A data frame reaches the screen by
  `display(df)` through a `ProjecturedDisplay`, into an editor that runs in a
  background task beside the REPL. The other two options are not built.
- **D5 is (a)** (the owner, 2026-09-29). The text of a cell is pending until
  Enter, Tab or a move out of the cell. Then the view parses it and writes the
  value, as one undo step.
- **Only an explicit call opens the window** (the owner, 2026-09-29): "only
  on explicit display(df)". A result at the prompt, such as `df`, prints text
  as before.
- **D9 is (a)** (the owner, 2026-09-29). The package pushes no display. The
  explicit call names the display: `display(ProjecturedDisplay(), df)`, or a
  short function of the package that makes this call. Phase 2 names the
  function by the naming rules.
- **D3 is A, B with the busy flag, and D; C is a keyword that is off by
  default** (the owner, 2026-09-29: "agreed").
- **D10 is the proposal of §5.2** (the owner, 2026-09-29). The view keeps the
  row of the selection at its place on the screen. Enter selects the row that
  was below the edited row before the sort. Tab selects the next cell of the
  edited row, and the view follows the row. If the filter hides the edited
  row, Tab acts as Enter.
- **D6: the view sorts and filters again when the edit is committed to the
  data frame** (the owner, 2026-09-29): "when the change is committed back in
  the data frame". While the text of a cell is pending, the row stays where it
  is. D10 says where the selection and the view go after the commit.
- **D7 is (a)** (the owner, 2026-09-29). The package is
  `ProjecturedDataFrames`, and the types take the prefix `DataFrame`.
- **D11 is (b)** (the owner, 2026-09-29). The editor runs on the default pool,
  and SDL starts on that thread. The busy flag of §4.3 is necessary, and the
  editor task is pinned to one thread. On 2026-09-30 the owner withdrew the
  busy flag (D3 changes, below).
- **D12 is (a)** (the owner, 2026-09-29). `ProjecturedDataFrames`, its example
  package and its test package go into `environment/all`, and the umbrella
  suite loads them, as for the other packages with a third-party dependency.
- **D13** (the owner, 2026-09-30): "I agree with your recommendation except
  for D13.5, that should be done (a) with a new plan but here." So: the
  registry of the backends, the registry of the wrappers and the run function
  are in the kernel, and the window is one more registered wrapper (13.1 b); a
  wrapper registers its keyword with a function that wraps the document and
  the projection, a layer for its order, and the keywords it excludes (13.2 a);
  two backends loaded and none named is an error that names both (13.3 a);
  the code that runs the editor beside the REPL is a keyword of the run
  function (13.4 a); and every caller moves to the registries in the same
  change, in a plan of its own, worked in this worktree (13.5 a).
- **D13 with seams, and the composition** (the owner, 2026-09-30). The
  owner: "The data frames package should not depend on panes [...] I want
  composition, the user loads packages and gets more features which may
  combine by default or can be combined. Data frames can be displayed with or
  without panes." Then, on the shape with seams only: "Sounds good", "I agree
  with your recommendations". So:
  - The registries of D13 are seams: generic functions that a low package
    declares, and to which the owner of a type adds a method. There is no
    registry table and no package extension.
  - A backend says whether it draws windows or text, and the run function
    counts only the backends that draw its output (Q5 a).
  - This package is the view and its projection only. A new generic package,
    `ProjecturedDisplay`, shows a value from the REPL; the tabs come from the
    pane package when it is loaded.
  - The natural renderer asks the seam `make_graphics_projection` before its
    tables. The other natural tables move to seams in a later plan.
  - There is no busy flag (D3 changes, below).

  The plan: [packages-compose-by-seams.md](packages-compose-by-seams.md).
- **D3 changes: B has no busy flag** (the owner, 2026-09-30): "So what are we
  trying to solve here with pause? Because it takes away the usefulness of
  the UI a lot." The editor loop runs on its own thread during an input and
  takes input as usual. After each input, the display asks each shown
  document to refresh (B). The key (D) does the same for a change that a
  background task makes. The rare race of §4.3 is stated in the docstring of
  the display.
- **D8 is deferred** (the owner, 2026-09-29): "(a) but let's defer this for a
  better design". The direction is one query model with two layouts. Group and
  pivot (§4.6, §4.7, phases 7 and 8) wait for a design of their own.
- **The filter comes next** (the owner, 2026-10-01): "I would rather focus on
  data frame tables. Especially the filtering of rows and columns." The
  points F1 to F5 were put to the owner with the recommendations of the
  writer, and the owner decided:
  - **F1. To filter columns** is (a) to hide and show one column from its
    header, and (b) a filter on the column names, a text or a regular
    expression, as `select(df, r"price")` does. A filter on the element type
    is not part of it. "show hidden columns on table context menu at header
    corner": the context menu of the corner of the table, where the header
    row and the header column meet, lists the hidden columns and shows them
    again.
  - **F2. A row filter is edited** (a) in a filter row under the header, a
    cell for each column, and (c) from the context menu of a header, which
    offers the list of the values with their counts and "Hide column". There
    is no funnel icon.
  - **F3. The language of a cell of the filter row** is a short text that the
    element type of the column parses: `> 30` and `10..20` for a number,
    `abc` for "contains", `/re/` for a regular expression, `= x` for an exact
    value, `missing` and `!missing`. A condition that does not parse shows a
    mark. The filters of all columns combine with "and".
  - **F4. The expression filter**, such as `age > 30 && startswith(city,
    "B")` (a bare name since 5.6b; it was `:age` first), is (a) a bar above the table with a plain text field, and (c) the
    Julia domain gives the bar its editor through a seam when it is loaded.
    The data frame package does not depend on the Julia domain. The
    expression compiles once into a function of the columns that it names,
    which runs over the column vectors.
  - **F5. The order of the work**: the path of a column (E1), then the query
    document with the row filters, the column filters and the expression,
    then sort on the same vector of rows, then refresh (phase 3) and edit
    (phase 4). This changes D1, which put edit before sort and filter.
  - **F6. Column resize** (the owner, with F1 to F5): "Plus drag column
    headers for resize". A drag of the edge of a header sets the width of
    the column; the widths are view state of the view (`layout` in §3.2).
    Deferred until the drag refactor lands (step 5.7).
  - **G1, G2 and G4** (the owner, 2026-10-01: "yes, agreed", to the
    recommendations of the writer): the row headers show the source row
    number of each row (G1); the pattern of the column names is typed in a
    text field in the corner cell of the filter row (G2); "Filter by
    values…" writes the picked values into the filter row as `= a, b`, for a
    column of at most 1,000 distinct values (G4).

### 5.2 The options, for the record

Every decision below is made or deferred (§5.1). Each keeps its options and
the recommendation of the writer of this draft, so the reason stays readable.

**D1. The first delivery. Made: (b), see §5.1.** The recommendation was phases
1 to 6.

**D2. The ends of a finite list. Made: (b), see §5.1.** The pane scrolls past
the first and the last row now (§2).
- (a) The list says how many rows are before and after its head. With a fixed
  row height, the pane then has a real extent, and it clamps. This needs a
  count, which a data frame has and the list of primes does not.
- (b) The pane clamps when its walk reaches a node whose `prev` or `next` is
  `nothing`. This needs no count, and it works for every list, also for rows
  of different heights. An end is always reached when its row is visible, so
  the clamp comes in time.

Recommendation: (b). It holds for every list, and a list still has no extent.

**D3. The refresh triggers. Made, see §5.1.** A, B, C and D of §4.3. B is a new mechanism: a
hook in the Julia REPL (`Base.active_repl_backend.ast_transforms`). C uses the
inbox, which already names a timer as a producer. Recommendation: A, B with
the busy flag of §4.3, and D. C is a keyword that is off by default.

**D4. How a data frame reaches the screen. Made: (b), see §5.1.**
- `run_data_frame_viewer(df)`, like `run_value_viewer`. No kernel change.
- `display(df)` through a `ProjecturedDisplay <: AbstractDisplay` and
  `pushdisplay`. It opens a tab in a running editor, or updates the tab of the
  same frame. It needs an editor that runs beside the REPL, and phase 0 must
  find out whether that works today.
- The evaluator shows a data frame as a table. Today the evaluator keeps only a
  `Document` live, so either a person writes `DataFrameView(df)`, or the
  evaluator gets a way to turn a value into a document. The second is a change
  of the evaluator.

Recommendation: the first two, and `DataFrameView(df)` by hand in the
evaluator until the evaluator change is decided on its own.

**D5. The edit model. Made: (a), see §5.1.** Pending text with a commit on
Enter, Tab or a move out
(§3.6), or a write on each key. Recommendation: pending text. A write on each
key can not hold "12." in a `Float64` column.

**D6. A sorted view after an edit. Made: the row stays while the text is
pending, and the commit sorts again, see §5.1.** The row stays and the order shows as out of
date, or the view sorts again at once and the row moves away from the caret.
Recommendation: the row stays.

**D7. The names. Made: (a), see §5.1.** The package is `ProjecturedDataFrames`, named for its
third-party package as `ProjecturedOdbc` and `ProjecturedTulip` are. The slice
is `dataframes`. The types take the prefix `DataFrame` (`DataFrameView`,
`DataFrameQuery`, `DataFramePivot`), because `Frame` names a render frame here.
None of these names is exported by DataFrames.

**D9. Only an explicit `display(df)`. Made: (a), see §5.1.** The REPL shows the result of an input
with `display(val)` (`__repl_entry_display` in the `REPL` stdlib of Julia
1.13). An explicit `display(df)` is the same call. So a `ProjecturedDisplay`
on the display stack gets both, and it can not tell them apart.
- (a) Push no display. The explicit call names the display:
  `display(ProjecturedDisplay(), df)`, or a short function of the package
  that makes this call.
- (b) Push the display, and set `specialdisplay` of the `LineEditREPL`, a
  field of the `REPL` stdlib. The REPL then shows a result through that
  display and not through the stack. It walks the display stack as `display`
  does, and it skips the `ProjecturedDisplay`. A plot at the prompt still goes
  to the display of Plots. The risk: the field is internal to the `REPL`
  stdlib, and the display of every result goes through the new code.
- (c) Push the display, and look at the stack trace for
  `__repl_entry_display`. It depends on a private name of the REPL, so it is
  not an option.

Recommendation: (b), if phase 0 shows that a plot of Plots and a figure of
Makie at the prompt behave as before. If not, (a).

**D10. The selection and the view after a commit. Made: the proposal, see
§5.1.** The commit sorts and
filters again (D6), so the edited row can move far away or disappear.
Proposal: the view keeps the row of the selection at its place on the screen.
- Enter selects the row that was below the edited row before the sort. That
  row stays near its place, so a person corrects a column row by row.
- Tab selects the next cell of the edited row. The view moves the head to the
  new position of the row, and the rows around it change.
- If the filter now hides the edited row, Tab acts as Enter.

**D11. The thread of the editor. Made: (b), see §5.1.** Phase 0 measured both
(§6.1).
- (a) On the thread of the REPL, with `@async`. No race is possible, and no
  busy flag is needed. The REPL takes about 10 ms for each character that it
  reads, and the window stops during a long input.
- (b) On the default pool, with the loop and the start of SDL on that thread.
  The REPL keeps its speed, and the window stays live during an input. The
  busy flag of §4.3 is necessary. The task must be pinned when the default
  pool has more than one thread, and plain `julia -t N,0` needs a thread that
  is not the one of the REPL.

Recommendation: (b). A REPL that takes 10 ms for each character is too slow
for daily work.

**D12. The test environment. Made: (a), see §5.1.** Phase 0 counted 999 invalidated method
instances when DataFrames loads after the editor stack (§6.1).
- (a) As the other packages with a third-party dependency:
  `ProjecturedDataFrames`, its example package and its test package go into
  `environment/all`, and the umbrella suite loads them. Every `test_all` then
  loads DataFrames at its start.
- (b) An environment of its own. `test_data_frames()` runs alone, and
  `test_all` does not load DataFrames.

Recommendation: (a), because it is the rule that the other packages follow.
A test run that is slower after the change goes back to D12.

**D13. The registries of the backends and of the wrappers (§4.10). Made, see
§5.1.** The direction is the owner's. The points, with my recommendations as
they were put:

1. Where the two registries and the run function live. My recommendation:
   the backend registry beside `Backend` in the kernel (`EditorModule`), and
   the run function and the wrapper registry in `ProjecturedScreen`, which
   every window needs. The data frame package then keeps one dependency to
   open a window, `ProjecturedScreen`, or none if the run function goes into
   the kernel as well.
2. What a keyword maps to. My recommendation: a function that takes the
   document and the projection and gives both back wrapped, registered under
   the name of the keyword (`tabs = true` for `ProjecturedPane`), and an
   error that names the registered keywords for a keyword that nothing
   registered.
3. Two backends loaded and none given. The owner's words say "automatically
   used if there's only one". My recommendation: an error that names both,
   and no order of preference, so a program does not change its backend when
   one more package is loaded.
4. The code that runs the editor beside the REPL (the pinned thread, the
   session, `invokelatest`, phase 2.5) is not about data frames. My
   recommendation: it moves to the run function as a keyword too, for any
   package that shows a value from the REPL.
5. The callers of `make_editor(...; backend)` and of `default_backend()`
   (`ProjecturedExample`, the gallery, the builder of the binary) move to the
   registry in the same change, so one mechanism is left.

**D8. Group and pivot. Deferred, see §5.1.** One query model and two layouts: a grouped table with
header rows (§4.6), and a cross table (§4.7). Or the grouped table as a pivot
with no column dimension and a sub-table in each cell. Recommendation: one
model, two layouts. A group row aligns with the columns of its members, and a
sub-table in a cell does not.

## 6. Phases

Each phase ends with its own tests and a commit. The work is done in a
worktree. The first delivery is phases 0, 1, 2 and 4 (D1).

- [x] **0. Facts.** Find out: can an SDL editor window run in a background
  task beside the normal Julia REPL, on the same thread and on another thread
  (D4)? If it can not, stop and ask the owner, because D4 depends on it. What
  does `hash` cost for a column of ten million `Int` and ten million `String`
  values (§4.3, level 3)? What does `using DataFrames` cost in load time and
  invalidation, and must the test environment keep it out of
  `environment/all`? **Done 2026-09-29; §6.1 has the answers.**
- [x] **1. The ends of a finite list.** The clamp of D2 in the widget
  substrate. The test uses a list of ten million rows that ends at both sides,
  with no DataFrames. **Done 2026-09-29.**
  - The clamp is in the scroll pane
    ([WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl)).
    `_clamp_to_list_ends` walks from the head down to the bottom of the
    viewport and up to the frozen strip, and it stops where `next` or `prev`
    is `nothing`. The last row stops at the bottom of the viewport, and the
    first row stops under the frozen header. The first row wins, so a list
    shorter than the viewport starts at its top.
  - The pane clamps in two places. `_pane_scroll_y` clamps the offset that the
    printer and the reader of a press use. `_scroll_list_by` starts a wheel
    turn from that drawn offset, so a turn past an end answers `nothing`, and a
    turn back moves at once. A stored offset past an end stays stored, and the
    pane draws the end.
  - The tests are in
    [WidgetTableListTest.jl](../../test/substrate/projection/WidgetTableListTest.jl):
    a list of ten million rows with its head at the first row and at the last
    row, a stored offset far past an end, and a list shorter than the pane.
    Against the code before this phase, the four new test sets fail with 11
    failures.
  - The checks: the list and scroll pane tests pass, 119 of 119. The whole
    substrate suite gave 86850 pass, 3 fail, 4 error and 1 broken. All seven
    failures and errors are on `main` too: the split pane drag has 3 fail and 2
    error, and `test_anchor_point()` has 2 errors with the code before this
    phase. The suite ran before a cleanup that moved the frozen height into
    one helper; the list and scroll pane tests ran after it. The naming guard
    passes, and the argument guard reports the same 6 lines as on `main`.
  - Found and left for phase 2: over a list, `_scroll_room` answers `nothing`
    for both axes, so a horizontal wheel turn is not clamped either. A wide
    data frame needs that clamp.
- [x] **2. The package and a read-only view.** The stem with its example and
  test packages, `DataFrameView`, the anchored row list with its jumps, its
  re-anchor and its scroll bar (§3.5), the visible shadow,
  `DataFrameViewToWidget`, cells by element type, the natural row, the
  `ProjecturedDisplay` and its short function (D9) with the editor in a
  background task (D4), and a row in the third-party table of
  package-rules.md. The editor task runs on the default pool, pinned to one
  thread, and it handles `julia -t N` and `julia -t N,0` (D11). Every call
  that the REPL posts goes through a closure that calls `invokelatest`
  (§6.1). The three packages go into `environment/all`, and the umbrella suite
  loads them (D12).
  - [x] **2.1 The packages** (`27ae31df0`). `ProjecturedDataFrames`,
    `ProjecturedDataFramesExample` with `make_data_frame_example`, and
    `ProjecturedDataFramesTest` with `test_dataframes()`. The module is
    `DataFramesModule`. The package root binds the modules of the packages
    below it, as a domain package does, and it exports the names of the
    module, as `ProjecturedOdbc` does, because a person loads it by name. The
    layering guard needs `extra_aliases` for the bound modules, as the chart
    guard has.
  - [x] **2.2 The read-only view** (`c02d5fe2f`). `DataFrameView` holds the
    frame, `anchor` and `scroll_position`; the pane shares the cell of
    `scroll_position`. `DataFrameViewToWidget` draws a `WidgetTable` of a
    `ListNode` in a `WidgetScrollPane`. A header reads `price :: Float64`,
    and `discount :: Float64?` for a column that allows `missing`, as a
    data frame prints in the REPL. A column has a weight and no minimum,
    so the table gives it the width of its header at least; `Fill` has a
    minimum of 0 and would not. A number aligns right. A cell is a
    `WidgetLabel` of the compact print, cut at 200 characters. Ctrl+Home
    and Ctrl+End are `@gestures` of the view, and `jump_to_row` writes the
    anchor and the offset as view state. The natural row is a chain of the
    view projection and the scroll pane printer, because a type dispatch
    does not print an output again, so a row must end in graphics.
  - [x] **2.2a A widget fix** (`529d326d2`). Found in a picture of the
    view at its last row: the rows before the head, at a negative offset,
    showed through the frozen header, and the header showed in the body.
    `get_frozen_elements` lets a content say what the held strip draws; the
    list table answers its header.
  - [x] **2.3 The horizontal clamp** (`773abcb75`), found in phase 1.
  - [x] **2.4 The scroll bar and the re-anchor.** They need the row at the
    top of the pane. Each row is a canvas with its own height, and the pane
    reads those heights in its walk from the head, but the view is a
    projection above the widgets and must not read the state of another
    projection. The owner (2026-09-29): "the graphics image of the row
    already has a height, no?", then: "It's not the scroll pane who does the
    relocation, it's the table widget who modifies the scroll pane scroll
    operation", and: "The table should be outside and the header row and
    column should be their own widgets, they have to be scrolled on their
    own scroll pane, just like the cells in its scroll pane in both
    directions. Synchronization can be done by the table. Scroll relocation
    also." So the table is the outer widget with three panes of its own —
    the header row (sideways), the header column (up and down), the cells
    (both) — and a corner. A scroll of any pane goes up through the table's
    reader; the table keeps one offset, gives each pane its part, and
    relocates the head of its rows. The pane then needs no frozen regions:
    `get_frozen_extent`, `get_frozen_elements` and `_pane_frozen_region`
    have no other user. The eager table changes too, and
    this is a plan of its own before the rest of phase 2. Both yes (the
    owner, 2026-09-29): [a-table-scrolls-its-own-parts.md](../done/a-table-scrolls-its-own-parts.md)
    comes first, and it also gives the lazy columns of §4.2.
    Done (`c875e6452`), after the table plan:
    - **The re-anchor** is the relocation of the table (phase 3 of the table
      plan): at 200 rows from the head, where §3.5 said about 500, the table
      writes `rows`, and the view turns it into its `anchor`. A wide frame
      moves its `column_anchor` the same way.
    - **The row at the top.** `DataFrameView` has the field `top_row`, which
      it shares with the table (P5 of the table plan); `jump_to_row` writes it
      back to 1.
    - **The scroll bar.** The view draws a `GridLayout` of one row: the table,
      which fills, and a vertical `WidgetScrollBar` 12 pixels wide. Its value
      is `(anchor + top_row - 2) / (rows - visible)`, and its thumb the share
      `visible / rows`, where `visible` is the offered height in rows less the
      header row. A row is a line of the font with the padding of a cell and a
      rule, `row_step`, which `make_data_frame_view_projection` measures; the
      natural renderer draws the table with its own theme, so the count of the
      visible rows is an estimate. A write of the value of the bar is a jump
      to the row at that value.
    - **`WidgetScrollBar`** takes the extent that its parent offers along it
      and the `thickness` of its projection across it, unless it authors a
      size; its track and its thumb read the value in cells, so a scroll
      moves the thumb and prints nothing again; and a button down or a move
      with the left button held moves the thumb as a press does. It writes
      nothing when the value does not change. Test: `test_widget_scroll_bar`.
    - The second step of the natural row of the view is the printer of a grid,
      which prints the table and the bar through the recursion.
  - [x] **2.5 The display** (`00c20f7eb`). The editor task is pinned to one
    thread with the internal `jl_set_task_tid`, as `Threads.@threads :static`
    does (the owner, 2026-09-29: "(a)"). A test fails when a release of
    Julia changes it.
    - `display_in_editor(df; title, backend)` and `ProjecturedDisplay`; the
      package pushes no display. `close_data_frame_editor!()` stops the
      editor. The editor is `ProjecturedScreen.make_editor` of a `PaneTree`,
      drawn by `PaneToWidget` and `NaturalToGraphics`; a new frame is
      `open_pane!`, a frame shown again is `focus_pane!` of its tab.
    - The thread is the last thread of the default pool that is not the
      caller's. With no such thread, the editor runs on the caller's thread
      with `@async`.
    - The session keeps each frame by identity (`IdDict`). A `WeakKeyDict`
      compares with `isequal`, so two frames with equal rows were one tab,
      and a lookup hashed every row.
    - A closed window ends no loop, so a display after the window closed
      ends that loop and starts a new editor.
    - The package depends on `ProjecturedSdl`, `ProjecturedScreen` and
      `ProjecturedPane` too.
    - Checked in a real REPL (plain `julia`) with a real SDL window: the
      window shows the table in a tab; the loop runs on thread 2, sticky; the
      REPL answers an input in 1.2 ms with the editor open, as without it;
      a second frame opens a second tab; the close ends the loop. A call that
      the REPL posts to the editor directly fails with "method too new",
      which is why the package posts through `invokelatest`. The SDL window
      has an empty `WM_NAME`, so a tool that finds a window by that name does
      not find it; the driver found it by its class and its size.
  - [x] **2.6 As few dependencies as possible** (§4.10, the owner,
    2026-09-30). The registries and the run function of D13, then
    `ProjecturedDataFrames` without `ProjecturedSdl`, `ProjecturedScreen` and
    `ProjecturedPane` where D13 allows it. D13 is made; the work is the plan
    [packages-compose-by-seams.md](packages-compose-by-seams.md). Its steps
    1 to 7 are done (2026-09-30): the package depends on DataFrames,
    Collection, Kernel, Layout, Primitive, Projection, Style and Widget; the
    display moved to `ProjecturedDisplay` as `display_in_editor(value)` and
    `EditorDisplay`; the natural row is the method of
    `make_graphics_projection`. Serialization leaves the closure with
    Widget's part of step 4a, which waits for the owner.
    Done 2026-10-01: the fold of the internal packages put every slice that
    the package used into `ProjecturedPlatform`, so the package depends on
    DataFrames, `ProjecturedKernel` and `ProjecturedPlatform`, and it adds no
    backend, no pane and no display. At the owner's word it exports
    `display_in_editor` and `close_display_editor!` of the display slice.
- [x] **3. Refresh.** The three levels of §4.3, as the method of
  `refresh_document!` for `DataFrameView`. The triggers A, B and D, with no
  busy flag. C is a keyword that is off by default (D3).
  Done 2026-10-01 (the owner: "do phase 3, refresh"), except B, which is
  deferred (the owner, 2026-10-01: "defer trigger B now"):
  - `DataFrameRefresh.jl`: a snapshot of the three levels (the structure;
    a hash of 100 rows from the top row and 64 shown columns; the full
    content of the columns that the query reads, because `hash` of an array
    reads only a few elements). The view has `frame_version`, which every
    computation of the data of the frame reads, and `frame_snapshot`. A
    refresh moves the version when the snapshot differs; the first refresh
    moves it in any case, so a new view reads no cell for a refresh (a
    snapshot in the constructor read 100 cells, which the tests that count
    the reads of a frame of ten million rows found). A new column gets a
    filter in the query.
  - D: F5 is `RefreshDataFrameViewOperation`, which reads at every level
    whether the snapshot changed or not. The owner, 2026-10-01: "we need a
    refresh button somewhere on the table, no?", then "yes" to the
    suggestion of the writer: the glyph `refresh-cw` at the right end of the
    top bar, a flat toolbar item whose tooltip names F5. The top bar is a grid
    of one row now, label, field, room and glyph, with the label centred on
    the field.
  - C: `display_in_editor(value; refresh_every)`, a timer of the display that
    is off by default; and `refresh_display_editor!()`, which refreshes every
    shown document and waits, for a person in the REPL (mine: a name that the
    plan did not have, and the step that B also calls).
  - A comes with phase 4: an edit through the view moves the version itself.
  - B is deferred: the REPL has no hook after an input; the recommendation
    of the writer, kept for when B is taken up, is a task that an `ast_transforms` entry
    starts with each input and that waits until
    `Base.active_repl_backend.in_eval` is false, an internal field, and does
    nothing when a later Julia renames it.
  - Tests: `test_data_frame_refresh()` (no change, a written value, a pushed
    row, a value that a filter reads and the table does not show, a new
    column, F5) and the display (a call and the timer); 203 data frame and
    21 display tests pass.
  - The duplicate (the owner, 2026-10-01, after a check in a live window:
    "the table display tab pane should support duplication protocol (the
    little +) on the header"). `DataFrameView`, `DataFrameQuery`,
    `DataFrameColumnFilter` and `DataFrameSortKey` declare a duplicate. The
    duplicate of a view shares the frame and owns a copy of the query, the
    anchors, the scroll position and the top row (mine: the place is what a
    person controls in a view, as the duplicate protocol says). Its two
    computed fields, the result of the expression and the kept rows, get new
    computations over its own query, by the helper that the constructor uses;
    its version starts at 0 with no snapshot, so its first refresh reads the
    frame. Tests: `test_data_frame_duplicate()` (the shared frame, an
    independent filter and anchor, both read a change after a refresh, the tab
    duplicates into the next tab); 256 data frame tests pass. A picture shows
    the "+" on the tab.
- [ ] **4. Edit.** The pending text, the operations of §3.6 with their
  inverses, undo, the write-through of a `SubDataFrame`, the `DataFrameRow`
  form. There is no busy flag (D3 changes, §5.1). An edit writes the frame
  from the thread of the editor. A write of one value does no harm to an
  input that reads the frame. A row insert or delete while an input reads the
  same frame is the rare race of §4.3 in the other direction.
  The first design (2026-09-30, points E1 to E6) put a new reference step
  `DataFrameCellReferenceStep(row, column)` on each cell, a map of pending
  texts in the view, and a `WidgetText` in every cell. The owner rejected it
  in a review, 2026-10-02:
  - No new reference step type. If the state is in the view, the path points
    there as normal and the printer maps it forward as usual. If the state is
    in the widget stage, the path points into the stage that the projection
    made, whose headers, rows and cells are already part of the document.
  - No widget in a cell for the edit: a value is edited as the document that
    presents it, which can be a primitive document. So a widget table with
    JSON in a cell is edited the same way.
  - Most of the table of a data frame must be generic widget table code, so
    other domains do not repeat it.

  Facts of the review (2026-10-02, from the code):
  - The table already gives a key to the document in its selected cell, in
    both forms, and reroots the answer
    ([edit-inside-a-table-cell.md](../done/edit-inside-a-table-cell.md)).
  - `rows` of the table of the view is a computation over the anchor, the kept
    rows, the shown columns and the version of the frame, so a scroll, a sort,
    a filter, a refresh and a column move make new cell documents. A text
    typed into a cell document of the widget stage is lost at the next scroll.
  - An introduced path evaluates to its output path, not to the output
    document, and a reader declines an edit whose path has an introduced
    step. To edit a document of the widget stage by its path is a new
    mechanism.
  - `rows[k]` of a list table counts from the head of the list, so a kept path
    into the widget stage names another row after a scroll.
  - A number document holds a number or `nothing`, so `-` and `1e` are lost.

  **The owner's decisions, 2026-10-02:**
  - **R1. The state is in the view** (the owner: "in the view").
  - **R2. A number that can not show a key becomes a type-in**, instead of a
    string document in the view for a number cell. The owner first said "fix
    the number instead", then rejected a number that keeps its text: "it would
    be better to store the number when it's parsed", with a `PrimitiveInsertion`
    "when it's a type-in", which "could have a parameter to limit what it can be
    turned into". The plan is
    [a-number-becomes-a-type-in.md](a-number-becomes-a-type-in.md); it is
    step 4.0.
  - **R3. The paths of a table mean the obvious, and no new step** (the owner,
    2026-10-02). A first R3, a cell named `column("price")[5]` with the column
    step of 5.2, was rejected: "we only introduce new reference steps if we
    must because the current steps cannot represent what is needed", and "a
    table widget definitely doesn't need a special column reference step". A
    path on a table is `column_headers[3]` for a column header, `row_headers[3]`
    for a row header, `columns[3]` for a column, `rows[4]` for a row and
    `rows[4][3]` for a cell. The owner agreed with the rest of R3 as the writer
    proposed it:
    - **The numbers.** In the data frame view a number names the row and the
      column in the frame: `rows[5][3]` is row 5 and column 3 of the frame, so
      a sort, a filter, a hidden column and a scroll do not change what a path
      names. In the widget table a number names the row in the whole table, not
      counted from the head of the list: a list table gets the number of its
      head row from its owner, which knows it (the anchor of the view). A row or
      a column that the REPL inserts moves the selection to another one, as
      §3.4 says.
    - **The fields.** A field step reads a field of a struct or an entry of a
      dictionary, so each name of a path is a field. The widget table gets a
      computed field `columns`, whose `[3]` gives a column. The view gets two
      computed, read-only fields: `rows`, whose `[5]` gives a row and whose
      `[5][3]` gives the document of the entry of the cell when it has one, and
      otherwise the value in the frame; and `columns`, whose `[3]` gives the
      `DataFrameColumn`, which keeps its menu of 5.2.
      `DataFrameColumnReferenceStep` goes.
    - **The clicks.** A click on a column header selects `columns[c]`; a click
      in its text field puts the caret in `column_headers[c]…`. A click on a row
      header selects `rows[r]`. Now a whole column is `column_headers[c]` and a
      row header can stand for its row, so the selection shapes of the table and
      their tests change, and the markdown table and the cell table follow.
    - **All the paths:**

      | Category | In the widget table | In the data frame view |
      |---|---|---|
      | the whole table | `∅` | `∅` |
      | the corner | `corner` | `∅` |
      | the pattern of the names | `corner.….content{k}` | `.query.column_pattern{k}` |
      | a column header | `column_headers[3]` | its column, `columns[3]` |
      | the text of a filter | `column_headers[3].….content{k}` | `.query.column_filters[i].text{k}` |
      | a row header | `row_headers[4]` | its row, `rows[5]` |
      | a column | `columns[3]` | `columns[3]` |
      | a row | `rows[4]` | `rows[5]` |
      | a cell | `rows[4][3]` | `rows[5][3]` |
      | a caret in a cell | `rows[4][3].value{2}` | `rows[5][3].value{2}` |
      | the expression | a child of the grid, not of the table | `.query.expression{k}` |

      A header holds no state of its own in the view, so it maps to its column
      or its row. A whole row has a path, so 4b needs no step for it. A hidden
      column and a row that a filter hides keep a path in the view. A range,
      `rows[2:5]` or `columns[1:3]`, fits the same steps when range selection
      comes.
    - **A column of a table can become a real document later** (the owner's
      note, 2026-10-02): "there may be additional data that needs to be stored
      on the column. the column header is a distinct thing from the column
      itself … some tables are better expressed by columns not rows." Now the
      data of a column is spread over the parallel fields `column_policies`,
      `column_align` and `column_cell_policies`, beside `column_headers`. A
      `WidgetTableColumn` document can hold them, and the cells too for a table
      that is better expressed by columns. The path `columns[3]` is the same
      when the field is computed and when it holds documents, so 4a does not
      wait for it (mine).
  - **R4. A column whose element type has no primitive document**, such as a
    `Date`, a `Symbol` or a type of another package: the cell shows the value
    as now and takes no key, and its tooltip says why (the recommendation of
    the writer; the owner: "I agree with the unsupported Date cell plans").
  - **R5. The picture of 4a** (the owner accepted it, 2026-10-02, except its
    path, which R3 replaces): the walk of the keys through a number cell
    below; each key in an entry is a step of undo, as a key in a filter field
    is, and the undo of a commit puts back the old value but not the text of
    the edit; a `missing` value shows "missing" as the placeholder of the
    primitive document of its cell.

  The design that follows from R1 to R5 (each point mine unless the owner made
  it above):
  - **A cell holds the primitive document of its value**: a `PrimitiveNumber`,
    a `PrimitiveString` or a `PrimitiveBool`. The table edits it as it edits
    any cell document.
  - **The view keeps an entry for each cell that a person opened and did not
    commit**: a field `edits`, a list of documents, each with the row and the
    column in the frame and the primitive document of the cell. The view finds
    an entry by its cell, and `rows[5][3]` of the view gives the document of
    the entry, so the selection never names a place in the list. The printer
    shows the document of the entry in its cell.
  - **A click in a cell opens an entry**, which holds a primitive document of
    the value in the frame, so the caret has a `value` to stand in:
    `rows[5][3].value{2}`. (The recommendation of the writer, because the
    path of R3 needs it: without an entry, `rows[5][3]` gives the value in the
    frame, which has no `value`. The owner, 2026-10-02: "Yes, agreed".) The path stays the same through every key,
    also when a key turns the number into a type-in, or the type-in into a
    number, because the document of the entry is replaced in place.
  - **A move out of the cell commits the entry.** An entry with no change goes
    away and writes nothing. After a commit and after Escape the whole cell is
    selected, `rows[5][3]`. So at most one entry has no change, the one with
    the caret; any other entry is an edit whose commit failed.
  - **The commit is generic.** Enter, Tab and a move out of the cell make the
    table write an operation that commits the cell, which the owner of the
    table converts, as the width of a column of 5.7 is written by the table and
    converted by the view. A table that no owner converts commits nothing,
    because its cell documents are the documents themselves.
  - **The commit of the view** first commits a type-in of the entry, as Enter
    in the type-in does (R2), and converts the value of the entry to the
    element type of the column. When it converts, one operation writes the
    frame, so the commit is one step of undo:
    `SetDataFrameValueOperation(frame, row, column, value)`, whose inverse
    writes the old value (E4 stays); the entry goes away as view state. When it
    does not convert, the entry stays and the cell shows a mark, with the
    reason in a tooltip. The mark and its tooltip are generic, a part of a cell
    of the widget table.
  - **An empty text** writes `missing` where the column allows it.
  - **A `DataFrameRow`** shows as a table of two columns, the name and the
    value, whose cells are primitive documents as above (E5, in 4b).
  - **E6. The busy flag. Withdrawn** (the owner, 2026-09-30, D3 changes in
    §5.1). The editor takes input during a REPL input. After the input, the
    display calls `refresh_document!` on each shown view (phase 3).

  The walk of the keys (R5). Cell `price`, row 5 of the frame, holds `12`;
  the person clicks after `12`:

  | Key | The cell shows | The document of the cell | The selection in the view |
  |---|---|---|---|
  | click | `12` | entry: `PrimitiveNumber(12)` | `rows[5][3].value{2}` |
  | Backspace | `1` | `PrimitiveNumber(1)` | `rows[5][3].value{1}` |
  | Backspace | the placeholder | `PrimitiveInsertion("")` | `rows[5][3].value{0}` |
  | `-` | `-`, red | `PrimitiveInsertion("-")` | `rows[5][3].value{1}` |
  | `5` | `-5` | `PrimitiveNumber(-5)` | `rows[5][3].value{2}` |
  | Enter | `-5` | a primitive document of the frame value | the row below (D10) |
  | Ctrl+Z | `12` | — | — |

  Enter writes `-5` to the frame with `SetDataFrameValueOperation`, the
  version of the frame moves (trigger A), and the view sorts and filters
  again (D6). A text that does not parse, such as `1e`, stays red after Enter,
  with the mark; Escape drops the entry.

  Open:
  - The cost of a primitive document in each shown cell, in place of a label,
    for a scroll of the frame of ten million rows. Measure it in 4.3.

  Steps of 4a, the edit of a cell, each with its tests:
  - [x] **4.0** A number that can not show a key becomes a type-in
    ([a-number-becomes-a-type-in.md](a-number-becomes-a-type-in.md)).
    Done 2026-10-02 in the primitive and the syntax slices, with no code of the
    data frame: the type-in is on in `PrimitiveToSyntax`, which the natural
    renderer of a cell uses. One point is open there: the `.pred` text can not
    write the limit of a type-in.
  - [ ] **4.1** The paths of a table (the widget table, generic): the computed
    field `columns`; a number of a list table counts in the whole table, from
    the number of its head row that its owner gives; a click on a column
    header selects `columns[c]`, a click on a row header selects `rows[r]`;
    the selection shapes; the markdown table and the cell table follow.
  - [ ] **4.2** The paths of the view: the computed fields `rows` and
    `columns`; `DataFrameColumnReferenceStep` goes and `DataFrameColumn` is
    `columns[c]`; the view maps its paths, in numbers of the frame, to the
    paths of the table and back.
  - [ ] **4.3** The cells are primitive documents, and a `Date` stays a label
    (R4); a click opens an entry; the cost of a scroll.
  - [ ] **4.4** The entries of `edits`: keys, a type-in in an entry, and the
    selection stays in an entry after a scroll.
  - [ ] **4.5** The generic commit, the mark and its tooltip, in the widget
    table.
  - [ ] **4.6** The commit of the view: `SetDataFrameValueOperation` and undo,
    the write through a `SubDataFrame`, and trigger A of refresh.
  - [ ] **4.7** The sort and the filter again after a commit (D6), and the
    selection after it (D10).

  4b, after 4a: the other operations of §3.6 (insert, delete, rename, move and
  convert of rows and columns) from a context menu on the header of a column
  and on a row, and the `DataFrameRow`.
- [ ] **5. Sort and filter.** The query document, the header gestures, the
  quick filters, the expression filter, column hide and move. The sort and
  the filter again on a commit (D6), and the selection after it (D10). Column
  freeze needs frozen columns on a list in the widget substrate (§3.5).
  Phase 5 comes before phases 3 and 4 (F5). The design below is of
  2026-10-01, from F1 to F6; a choice that the owner did not make is marked
  "mine".
  - **Facts found for the design** (2026-10-01):
    - A table whose rows are a list draws no row headers:
      `_check_table_parts` raises an error. With no row headers there is no
      corner. In the eager table, a click on the corner maps to the whole
      table (`_map_wt_point`, `kind === :corner`), and the corner is no
      widget. So the corner menu of F1 is `compute_context_menu` of the view
      itself, reached by the path of the whole table; it needs no widget of
      its own, but it needs row headers on a list.
    - A header can be any document, and the header row is as tall as its
      tallest header, so a header can be a label above a text field.
    - The context menu probe asks `compute_context_menu(node)` of the
      document that an Alt press selects. Only `WidgetShell` has a method
      now. A menu item holds an `Action` whose callback runs with the
      editor, so an item changes the query by posting an operation.
    - `ObjectFieldToWidget` is the one projection above the widgets that
      shows a `WidgetText` for a field of its own document: its reader turns
      the text write into a write of the field.
    - No table resizes a column, and the editor has no cursor shapes. The
      splitter of `WidgetSplitPane` is the model of a drag: view state
      `active_splitter` and `drag_anchor`, a start, a resize and an end
      operation, and a drag that routes every move to the splitter while it
      is active.
    - `FilteringProjection` reads one cell per element, so the view does not
      use it (§3.3).
  - **The model.**
    - `DataFrameQuery` is a document in the field `query` of the view
      (§3.2): the filter text of each column by name, the expression text,
      the hidden columns by name, and the pattern of the column names. It is
      a document, so a key, a menu and the assistant change it with the same
      edits, undo takes a change back, and a saved window keeps it.
    - The rows of the view are a computed cell `Vector{Int}` of the source
      rows that pass every filter, in the order of the frame. The list of
      rows, the jumps and the scroll bar work on its positions, and a row
      shows its source row number in its row header.
    - The columns of the view are the names that are not hidden and that the
      pattern keeps, in the order of the frame.
    - The widths of the columns are view state of the view, by name (F6).
  - **Steps**, each with its tests:
    - [x] **5.1 Row headers on a list** (the widget substrate): a list table
      draws a header column whose cells come from each row, and the corner
      where it meets the header row. A click on the corner maps to the whole
      table, as in the eager table. The view shows the source row number of
      each row there, as a data frame prints it (G1). The corner cell of the
      filter row holds the text field of the pattern of the names (G2).
      The design (mine, from the facts of the printer):
      - `row_headers` of a list table is a list that moves in step with
        `rows`: its head is the header of the head row. A list table with
        row headers needs a `Fixed` row policy, so the header column and the
        cells have the same rows; a vector of row headers on a list is an
        error, as now.
      - The header column is a third pane, a grid of one column that scrolls
        with the `y` of `scroll_position`. Its width is the widest of the
        corner and of the headers that the walk placed.
      - G2 puts a text field in the corner, so the corner is a widget: the
        new field `corner` of `WidgetTable`, a document or `nothing`. The
        corner is a floor for the width of the header column and for the
        height of the header row. A press on the corner goes to it, and a
        press that it does not take selects the whole table. A table whose
        rows are a vector draws its corner as graphics and takes no corner
        document; that is an error.
      - A move of the head of the list writes `rows` and `row_headers` to
        the nodes of the same row, and the view turns both into its anchor.
      - A press on a row header selects its row. The paths are
        `row_headers[k]…` and `corner…`.
      - Done 2026-10-01 (`ba85ec461`, and the view after it). Both list
        printers draw the corner and the header column, and the eager
        printer refuses a corner document. The view shows the row number of
        each row and, in the corner, the count of the rows (mine), so the
        header column is as wide as the widest row number. Every row of the
        view is `Fixed` now, also when its columns share the width. Tests:
        the list table (seven new sets: the places, the width, the presses,
        the paths both ways, the move of the head, the errors), the eager
        table, the markdown and the cell tables, and the data frames, 329
        pass. A picture of the view at row 1 and at row 995 shows the
        numbers at their rows.
      - Open, small: the row numbers align left; a data frame prints them
        aligned right. The header column has no alignment of its own yet.
    - [x] **5.2 The path of a column (E1).** The step goes in 4.2: the owner
      rejected it on 2026-10-02, and a column is `columns[c]` (R3 of phase 4).
      `DataFrameColumnReferenceStep(name)` evaluates on the view to a
      `DataFrameColumn` (the view and the name). The view maps the path of a
      header to it and back. `compute_context_menu(::DataFrameColumn)` gives
      "Hide column" (and "Filter by values…" in 5.5);
      `compute_context_menu(::DataFrameView)`, which the corner reaches,
      lists the hidden columns and shows one or all of them again.
      Done 2026-10-01:
      - `DataFrameQuery` starts here with `hidden_columns`, because "Hide
        column" needs a state; 5.3 adds the rest. The view shows the columns
        that the query does not hide, and the last shown column can not be
        hidden.
      - `DataFrameColumnReferenceStep(name)` evaluates to a `DataFrameColumn`
        on the view. It has no entry in the `@reference` language: the step
        names of that language are global, `row` is the sequence chart's, and
        the paths work without an entry.
      - A press on a header selects its column in the view; a press on the
        corner or on the whole table selects the view. The table shows the
        selection of the view, from a computed cell of its selection.
      - A menu item posts its operation with `post_operation!`, because a
        menu action is a callback with the editor.
      - Found: the printer of a list table read its column count once, so a
        hidden column stayed in the header. The table now builds its parts
        again when its shape changes, as the eager table does, in a cell
        that it only peeks at, so a move of the head and the rows that a grid
        walks are no change of shape (a test checks both).
      - Tests: the data frames (with the new `test_data_frame_columns()`:
        the press, the path, the menus, the chain of a right click through the
        context menu probe, the last column, a wide frame), the list table and
        the eager table, 290 pass.
      - Not checked: whether undo takes back a hide, because a posted
        operation is applied outside the reader of the window.
    - [x] **5.3 The query and the rows that pass.** `DataFrameQuery`, the
      computed vector of rows, the hidden columns and the pattern of the
      names (`abc` contains, `/re/` a regular expression).
      Done 2026-10-01:
      - `DataFrameQuery` holds `hidden_columns`, `column_pattern`,
        `column_filters` (a `DataFrameColumnFilter` of each column, by name,
        made with the view) and `expression` (read in 5.6).
      - The language of F3 is parsed in this step, because the rows can not
        be computed or tested without it (`DataFrameFilter.jl`): a text is
        read once into a callable struct, which runs over the column vector.
        Choices (mine): "contains" ignores case; `!= a` is part of it; a
        comparison and a range read a `Float64`; `= a, b` compares by value
        for numbers and `true`/`false`, else by the printed text, and a
        value in double quotes keeps its commas.
      - `kept_rows` is a computed field of the view, so the projection, the
        scroll bar and Ctrl+End read one vector. It runs in the newest world,
        because a value can print with a method that a later package adds.
        `anchor` is now a place among the kept rows.
      - The corner shows the count of the kept rows, padded with figure
        spaces to the digits of the count of all rows (mine), so the header
        column stays as wide as the widest row number.
      - Found: a grid chooses its form by the type of its children at the
        first print, so a table whose first print keeps no row could not
        draw rows later. Now a grid whose children are `nothing` is a list
        with no rows, and a corner makes a table of a list; a test prints a
        filter that keeps no row first.
      - Tests: `test_data_frame_filter()` (the language, missing, the
        reasons, the kept rows and the table, Ctrl+End, a first print with
        no row, the pattern), the data frames 131, the tables and the list
        layouts 252 pass.
    - [x] **5.4 The filter row.** Each header is the label above a
      `WidgetText` of the filter text of its column. The selection of the
      view goes into the text of the query, and the view maps it to the text
      field and back, so the caret shows there and a key edits the query.
      Each element type parses the language of F3; a text that does not
      parse shows a mark and its reason in a tooltip, and filters nothing.
      Done 2026-10-01, in two parts:
      - 5.4a, the table (`83ace697a`): a plain press on a header goes to the
        header and selects the column only when the header declines it; an
        Alt+press still selects the column. A key goes to the header that the
        selection is in.
      - 5.4b, the view (`DataFrameFilterRow.jl`): each header is a
        `VerticalLayout` of the label and a `WidgetText` of the filter text;
        the corner is the count above the field of the pattern. The view
        computes the selection of the grid, the table, each header and each
        field from its own selection, `query.column_filters[i].text[a:b]` or
        `query.column_pattern[a:b]`, as a printer computes the selection of
        its output. The reader turns a press in a field into that selection,
        and a text edit into a `ReplaceStringRangeOperation` of the text of
        the query, which moves the caret as any text edit does and which a
        history records.
      - Choices (mine): a field is 80 pixels wide, so an empty field has room
        for a press; a field whose text does not parse is pale red, and its
        tooltip says the reason; an edit of a field shows the result from its
        start (anchor, column anchor, offset and top row written back).
      - Tests: the press into a field, a key through the whole chain (twice,
        so the caret moves on), the mark and the reason, 145 data frame tests
        and 187 list table tests pass. A picture shows the filter row, a
        filtered result with its count, and a mark.
      - Open, small: the field does not fill its column, because the header
        grid gives a header no width; the mark colors the text area of the
        field, not the whole field.
    - [x] **5.5 The list of the values.** "Filter by values…" of the header
      menu opens a popup with the distinct values of the column and their
      counts, counted when it opens, for a column of at most 1,000 distinct
      values (G4). The choice writes the filter text, `= a, b` (G4), so
      the filter row stays the one place that holds a filter.
      Done 2026-10-01 (`DataFrameValueList.jl`): "Filter by values…" is the
      first item of the menu of a header. Its dialog, a window as every popup
      is, has a box, the value and its count for each distinct value, sorted,
      counted when it opens, with a stop at 1,000; a wider column gets a
      dialog that says to type a filter. "Apply" writes `= a, b`, quoting a
      value with a comma, or an empty filter when every value is ticked.
      Choices (mine): `missing` is not in the list, because the filter row
      has `missing` and `!missing`; the list starts from the values of a list
      filter, else with every value ticked; no value ticked changes nothing.
      Tests: the list, the counts, the text written and read back, the start
      from a filter, the limit; 154 data frame tests pass. Not checked: the
      dialog in a running editor.
    - [x] **5.6 The expression bar** (F4 a). A text field above the table.
      `Meta.parse`, then the symbols that name columns become the arguments
      of one function, which the view compiles once in a module of its own
      and calls with `invokelatest` over the rows of the column vectors. A
      result that is `missing` hides the row (mine). An error shows a mark
      and its reason.
      Done 2026-10-01 (`DataFrameExpression.jl`): the bar is the first row
      of the grid of the view, "Rows where" and a field 480 pixels wide (mine).
      `:name` that names a column becomes the element of its vector in one
      loop, compiled once for a text and its columns and cached, and called
      with one `invokelatest`. It compiles in `Main`, not in a module of its
      own as the design said, so the expression can call a function of the
      session (changed while implementing, mine). `missing` hides a row; a
      value that is not `true`, `false` or `missing` is an error. The result
      of the expression is the computed field `expression_result` of the
      view, so an edit of a column filter does not run the expression again;
      its reason marks the bar. Tests: the evaluation, missing, a symbol that
      names no column, a function of the session, the reasons, the expression
      with the column filters, a key in the bar; 170 data frame tests pass.
      A picture shows the bar and its result (59 rows of 1,200, correct).
      Open, small: the label is not centred on the field, and the bar row
      has the background of the cells.
    - [x] **5.6b A bare name is the column, and the empty bar shows an
      example.** The owner, 2026-10-01: "It expects :stem for a stem column.
      I could not guess that, why not just stem?", then "Yes" to the
      proposal of the writer:
      - A bare name that names a column is the column; `:name` still works,
        as DataFramesMeta.jl writes it. A name that Julia uses for something
        else stays: the function of a call or of a broadcast, the field after
        a dot, the name of a keyword argument (after a comma or a semicolon)
        and of a macro. `var"unit price"` names a column whose name is no
        identifier. A column wins over a global of the same name, and
        `Main.name` reaches the global.
      - Found while implementing (mine): with bare names, the typo
        `age = 30` for `age == 30` writes 30 into the column of the frame,
        because the name becomes the element of the column vector. `:age =
        30` did the same before. An expression that assigns to a column,
        with `=`, an update such as `+=`, or in a tuple on the left, does
        not compile now; its reason says "write == to compare".
      - The placeholder: `WidgetText` had none (`placeholder_color` is for
        images only). `WidgetText` has the field `placeholder` after
        `language`, and `WidgetTextToGraphicsCanvas` the style
        `placeholder_text` (the muted foreground of the theme). An empty
        field of plain text draws it where its text begins, below the
        content, so the caret draws over it, and the box is at least as wide
        as it. A press in the box puts the caret at the start, as before. It
        is no part of the content.
      - The example of the bar is made of the columns of the frame (mine):
        the first column of numbers compared with its first value that is
        not `missing`, and a test of the first letter of the first column of
        strings, such as `age > 30 && startswith(city, "B")`; `nothing` when
        the frame has neither. It reads `frame_version`, so a refresh with a
        new column makes it again.
      - Tests: bare names, `:name`, the call, the dot, the keyword names,
        `var"..."`, the column over the global and `Main.name`, the
        assignments, the example, and the placeholder (drawn, muted, below
        the content, gone with a text, a press at the start).
    - [x] **5.7 Column resize** (F6), in the widget substrate: a press within
      3 pixels of the right edge of a header starts a drag, as the splitter
      does, and the drag writes the width of the column. The view keeps it
      by name. **Deferred** (the owner, 2026-10-01): "defer the column drag
      until the drag refactor lands in main", the drag tracking of
      [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md)
      (D14, D20). How a person finds the edge (G3) is decided then.
      Taken up 2026-10-02 (the owner: "Let's do 5.7 first", after the drag
      refactor landed). The design (mine):
      - The widget table: a field `column_drag`, the drag of the edge of a
        column that is on (its column, the point and the width at the press),
        or `nothing`. A left press within 3 pixels of the right edge of a
        header starts it, as the divider of a split pane starts its drag: a
        write of `column_drag` as view state and a `StartDragOperation`. Each
        `DragMove` answers `SetTableColumnWidthOperation(table, column,
        width)` as view state, the width at the press plus the move, and at
        least a minimum; `DragEnd` ends the drag; `DragCancel` puts back the
        width of the press. A table whose columns are a vector keeps the width
        in `column_policies`; a table whose columns are a list takes its
        policies as a list beside its headers, as it takes its alignments, so
        the owner of the table keeps the widths. A width that the owner gives
        wins over "at least as wide as the header".
      - The view: a field `column_widths`, the width of each column by its
        name, as view state, so a filter, a sort or a scroll keeps it. Its
        reader turns the width operation of its table into a write of the
        field. A duplicate copies it.
      - G3, how a person finds the edge (asked 2026-10-02; recommendation of
        the writer: the edge lights under the pointer, and a rest there says
        "Drag to set the width"; the resize shape of the pointer later, for
        the edge and the divider together).
      - G3 decided (the owner, 2026-10-02: "Agreed, but c affects many other
        places, needs a plan"): (b) now, and the shape of the pointer (c) as
        a plan of its own. Done the same day: a point within 3 pixels of the
        edge maps back to `column_policies[c]`, the width of the column, so the
        edge is the mouse target and lights as a bar of 3 pixels in the ring
        color of the theme over its rule, a new stroke of the printer of the
        table; a rest there answers the tooltip "Drag to set the width". Found:
        the table of a data frame view had no mouse target of its own, because
        the view holds the mouse target as a path into its output, so no row,
        column or edge of it lit under the pointer. The view computes the
        mouse target of its table from its own now, as it computes its
        selection. Tests: the table 209, the data frames 267 (the edge is the
        mouse target after a move through a real editor), the platform suite
        84,646. A picture shows the lit edge and a lit row.
      - Done 2026-10-02 as designed.
        Found while implementing:
        - A part that a projection made is reached by the path of its input
          document: the route of a drag follows the inputs only, as the
          divider of a split pane is reached through its `PaneSplit`. So the
          table starts its drag from the view, and the view gives the parts of
          the drag to its table with `read_table_column_drag`. The table is
          the first column of the grid of the view, at its left edge, so a
          point has the same x in the view and in the table.
        - The general reader of the view passed every other operation of its
          table on unchanged: the start of the drag kept a path in the output
          of the view, and the width stayed inside its wrapper of view state.
          It maps both now.
        - A column narrower than its header clipped the header from the left
          when the column aligns at the right, so a column of numbers showed
          the end of its type. The grid of a vector clamps the offset of an
          aligned cell at zero, as the grid of a list already did (a separate
          commit of the layout slice).
        - A cancel writes the width of the press, so the view keeps an entry
          for the column even when it had none: the column is then `Fixed` at
          the width that it had.
        - Tests: the table 201 (the drag of the edge of a column of a vector
          and of a list), the grid 49, the data frames 265 (a drag through a
          real editor and its drag tracking, Escape, a sort and a duplicate
          keep the width), the platform suite 84,584 (8 broken, as on main),
          Markdown 222.
    - [x] **5.8 The editor of the Julia domain in the expression bar** (F4 c),
      through a seam that the data frame package declares and the Julia
      domain extends. Changed (the owner, 2026-10-01: "5.8: yes", to the
      recommendation of the writer): the Julia domain can not extend a seam
      of the data frame package without a dependency on DataFrames, so the
      seam is in the widget slice: `make_code_field(Val(:julia), …)`, a field
      for code in a language, which is the plain field by default and which
      `ProjecturedJulia` extends. The query keeps the expression as text.
      Done 2026-10-01, in a form that differs from the recommendation in one
      point (mine, and the fact that moved it): a seam that gives a whole
      field would put a function into a widget field, and a saved window can
      not write a function. So `WidgetText` has a field `language`, a symbol
      such as `:julia`, and the seam `compute_code_pieces(Val(language),
      text)` of the widget slice gives the pieces of the text, each a count of
      characters and a color; the default is one piece. `ProjecturedJulia`
      adds the method for `:julia`: a tokenizer, not a parse, so a text that
      does not parse yet has its colors, in the colors of the Julia domain.
      The field keeps its text, its caret and its edits as ranges of its
      content; a plain field keeps its one span as before. The expression bar
      is a field of `:julia`, so it has colors when the Julia domain is
      loaded, and the data frame package does not depend on it.
      Found: an empty field of code built a span with an index out of range;
      the data frame suite saw it only with the Julia domain loaded in the
      same process. Tests: a field of a language of the tests (its spans, an
      edit in its second piece, an empty field), the colors of Julia code, the
      bar asks for `:julia`; 243 widget, 419 Julia and 171 data frame tests
      pass. A picture shows the colored bar and its result (50 rows, correct).
    - [x] **5.9 Sort** on the same vector of rows: the header gestures of
      §4.4. The form (the owner, 2026-10-01: "yes, agreed", to the
      suggestion of the writer, after "we need small sort icons on the
      headers ascending/descending"): a small Lucide glyph after the name of
      the column on the label line, `arrow-up-down` in a faint color when the
      column does not sort, `arrow-up` for ascending and `arrow-down` for
      descending, and a small number after the arrow for the place of the key
      when there is more than one. The glyph is the target: a click cycles
      off, ascending, descending; Shift+click adds the column as the next
      key; Alt+click on the header selects the column, and the field filters.
      The query holds the sort keys, a column and a direction each.
      Done 2026-10-01 (`DataFrameSort.jl`): `DataFrameSortKey` (a column
      and `descending`) in `sort_keys` of the query; the kept rows are sorted
      by `sortperm` of DataFrames over a view of the kept rows, and values
      with no order between them keep the order of the frame. The glyph is a
      flat `WidgetToolbarItem` after the name, whose own gestures sort; its
      label is its tooltip, and a label after it shows the place of its key.
      A button was tried first, but it draws a surface and a shadow; a
      toolbar item is flat. The icon table has `arrow_up`, `arrow_down` and
      `arrow_up_down`, read from the glyph names of the bundled font. Every
      header is built again when the keys change. Found and changed (mine):
      a header with its glyph is wider than 120 pixels, so a list column is
      160 pixels wide now. Tests: the keys after a click and a Shift+click,
      the order, the filters with the order, a click on a glyph through the
      projection and the places; 188 data frame tests pass. A picture shows
      the glyphs and an order of two keys. The sort runs at once: the mark
      while a sort of ten million rows runs is not done.
  - **Landed** (the owner, 2026-10-01: "land first and run tests
    afterwards"): main `b3f539b0d`, rebased onto 50 commits of main (a
    conflict in the point reader of the list table, which main split into
    `_read_table_point_event` and `_read_table_point_cell`). Tests after the
    landing, on the landed code: the whole platform suite 84,447 pass, 8
    broken, no failure; data frames 190, Julia 419, widget text and list
    table 243; omnet-julia 262. The umbrella's `test_table_cell_editing`
    fails in "a JSON string", which the baseline of the fold lists as a
    failure of main; it uses the eager table, which this work does not
    change. inet-julia's presentation tests have 8 errors, all
    `make_natural_to_syntax_dispatch()` without the `appearance` that main's
    theme work (`b964b257f`) requires; inet-julia does not follow it yet.
- [ ] **6. Find.** §4.5, without replace.
- [ ] **7. Group.** §4.6. Deferred until group and pivot have a design of
  their own (D8).
- [ ] **8. Pivot.** §4.7, with row headers on a list and the spanning header
  in the widget substrate. Deferred with phase 7 (D8).
- [ ] **9. Charts in cells and the quick chart.**
- [ ] **10. The proposed features** that the owner keeps from §4.8.

### 6.1 The answers of phase 0

Measured on 2026-09-29 with Julia 1.13 and plain `julia`, which starts with
one default thread and one interactive thread. The scripts and logs are in
`/var/tmp/projectured-data-frame-phase0/`. A driver typed into a real REPL
through a pseudo-terminal (`pexpect`). Other sessions ran on the machine, and
the load was between 1.4 and 5. The timing runs used the cores 28, 30 and 31.

**An editor beside the REPL.** The REPL runs on thread 1, in the interactive
pool. The hook `Base.active_repl_backend.ast_transforms` works: it ran once
for each input.

| | Editor on the thread of the REPL (`@async`) | Editor on the default pool (`Threads.@spawn :default`) |
| --- | --- | --- |
| The loop runs on | thread 1, interactive | thread 2, default; SDL starts there too |
| A short input, without the editor → with it | 1.3 → 244 ms | 1.5 → 1.4–1.7 ms |
| An input with 60 more characters, with the editor | 866 ms | 3.8 ms |
| A probe posted 1 s into a computation of 3 s that does not yield | ran at 3.0 s | ran at 1.0 s |
| Frames and faults | not counted | 9 frames, 0 faults |

- On the thread of the REPL, the REPL reads each character in a turn of its
  own, and each turn waits for one SDL wait slice of 10 ms
  ([Sdl.jl:3466](../../source/sdl/Sdl.jl#L3466)): about 10 ms for each
  character. The window also stops during a long input. So the editor runs on
  the default pool (D11).
- On the default pool, the window stays live during an input. So the view can
  read the frame while the REPL writes it, and the busy flag of §4.3 is
  necessary there.
- **World age.** The loop task keeps the world of its start. A function that
  the REPL defines after that throws `MethodError` ("method too new to be
  called from this world context") when the loop calls it. The same function
  works through a closure that is defined before the loop starts and calls
  `Base.invokelatest`. So the package posts each call through such a closure.
  For the same reason, a cell value whose type comes from a package that is
  loaded after the window opens must be printed through `invokelatest`.
- A computation without a GC safepoint did not stop the editor in this run. A
  collection that the editor starts waits for every thread to reach a
  safepoint, so the risk stays (§8).
- Not checked: the REPL of VS Code; `julia -t N` with `N` of 2 or more, where
  a task of the default pool can move between threads while SDL needs one
  thread; `julia -t N,0`, where the REPL itself is on the default pool; the
  pixels of the window.

**A hash of a column.** `hash(::AbstractArray)` hashes every element only
below 32768 elements. From there, `_hash_fib` hashes about `log(n)` elements,
walking back from the end (`base/multidimensional.jl`, lines 2074, 2105 and
1985). A change of the middle element or the first element of ten million did
not change the hash, and a change of the last element did. So level 3 of §4.3
needs a full hash of its own. For ten million values, as the median of five
runs:

| Check | Time | Finds a change in the middle |
| --- | --- | --- |
| `hash(v)`, `Int` / `String` | 0.7 / 1.9 ms | no |
| A full hash, `h = hash(x, h)` for each element: `Int`, `Float64`, `String` | 18.7, 19.0, 50.1 ms | yes |
| `crc32c(reinterpret(UInt8, v))`, `Int` | 18.8 ms | yes |
| The structure fingerprint of 20 columns (level 1) | 2 µs | no, as expected |

**The cost of `using DataFrames`.** 0.27 s after precompilation, the median of
three fresh processes. It invalidates 487 method instances when it loads
alone, and 999 when it loads after `ProjecturedKernel`, `ProjecturedWidget`
and `ProjecturedSdl`. The ten largest trees are in the dependencies of
DataFrames: SentinelArrays, PooledArrays, InlineStrings, FixedPointNumbers
and LaTeXStrings. No tree in the top ten names a method of this repository.

**The test environment.** `environment/all` has no DataFrames today, not even
as an indirect dependency. `test_all` runs every suite in one process
([ProjecturedSuite.jl:382](../../test/projectured/ProjecturedSuite.jl#L382)).
The other packages with a third-party dependency, such as `ProjecturedOdbc`,
`ProjecturedTulip`, `ProjecturedVideo` and `ProjecturedAnthropic`, are in
`environment/all`, and the umbrella suite loads them. `ProjecturedDataFrames`
goes there too (D12).

## 7. Targets

These are proposed numbers for a frame of ten million rows and twenty
columns. A measurement needs an idle machine and the approval of the owner.

| Action | Target |
| --- | --- |
| The first frame of the view, after `using` | below 200 ms |
| A frame while scrolling | below 16 ms, the same for every row count |
| A jump to any row | below 16 ms |
| A sync with no change | below 0.5 ms |
| A filter on one column | below 300 ms |
| A sort by one `Int` column | about 1 s, with a mark while it runs |

## 8. Risks

- **Two tasks, one frame.** The REPL can change a frame while the editor reads
  it. On one thread the two tasks switch only where a task yields. With more
  threads, a read can see a `push!` that is half done. A sync that throws
  tries again on the next frame, as `ReflectionFeed` does. The editor runs on
  another thread (D11), and there is no busy flag (D3), so a scroll during an
  input that changes the structure of the same frame can show a wrong row,
  raise an exception that the fault barrier catches, or very rarely crash the
  process. A refresh after the input corrects the rows.
- **A computation without a safepoint.** A collection waits for every thread
  to reach a safepoint. A loop of the user that has none can stop the editor
  until it ends. Phase 0 did not see it, but it did not rule it out.
- **The thread of the editor.** SDL needs one thread. With `julia -t N` and `N`
  of 2 or more, a task of the default pool can move between threads, so the
  editor task must be pinned. With `julia -t N,0`, the REPL is itself on the
  default pool. Phase 2 handles both.
- **Load time.** DataFrames invalidates 999 method instances when it loads
  after the editor stack (§6.1). The stem must stay out of the `Projectured`
  package and out of every default session. D12 decides whether the test
  environment loads it.
- **Row identity.** An insert or a delete from the REPL moves the rows under
  the selection.
- **The re-anchor.** A new head must keep the top row at the same place on the
  screen, and it must keep the selection. If it does not, a long scroll jumps
  each time the view re-anchors.
- **World age.** An expression filter is compiled at run time, so its call
  needs `invokelatest`. The loop task keeps the world of its start, so every
  function that the REPL posts goes through a closure that calls
  `invokelatest` (§6.1).
- **Parse of a value.** A decimal comma, a date format and a categorical level
  that does not exist need clear errors.
