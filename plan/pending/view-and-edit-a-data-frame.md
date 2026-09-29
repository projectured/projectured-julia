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

A path in the view names the **source row index** and the **column name**:
`rows[row].columns[name]`, then the caret in the text of the cell. So the
selection survives a sort, a filter, a column move and a switch to another
view of the same frame. A row of a data frame has no identity other than its
index. An insert or a delete by the view moves the selection with it. An
insert or a delete from the REPL can put the selection on another row. The
chart domain already has its own reference step (`ChartSampleReferenceStep`),
so a domain step for a row and for a column is not a new mechanism.

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
- **Another thread (`Threads.@spawn`).** The window stays live. A read of the
  view during a write of the REPL is a data race. So the hook keeps a **busy
  flag** from the start of an input to its end. While the flag is set, the
  view does not read or write the frame, it shows a mark, and it takes no
  edit.

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
  `:age > 30 && startswith(:city, "B")`. The Julia domain edits it.
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
  editor task is pinned to one thread.
- **D12 is (a)** (the owner, 2026-09-29). `ProjecturedDataFrames`, its example
  package and its test package go into `environment/all`, and the umbrella
  suite loads them, as for the other packages with a third-party dependency.
- **D8 is deferred** (the owner, 2026-09-29): "(a) but let's defer this for a
  better design". The direction is one query model with two layouts. Group and
  pivot (§4.6, §4.7, phases 7 and 8) wait for a design of their own.

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
- [ ] **2. The package and a read-only view.** The stem with its example and
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
  - [x] **2.1 The packages** (`303cb9ed2`). `ProjecturedDataFrames`,
    `ProjecturedDataFramesExample` with `make_data_frame_example`, and
    `ProjecturedDataFramesTest` with `test_dataframes()`. The module is
    `DataFramesModule`. The package root binds the modules of the packages
    below it, as a domain package does, and it exports the names of the
    module, as `ProjecturedOdbc` does, because a person loads it by name. The
    layering guard needs `extra_aliases` for the bound modules, as the chart
    guard has.
  - [x] **2.2 The read-only view** (`7652621aa`). `DataFrameView` holds the
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
  - [x] **2.2a A widget fix** (`71c55b297`). Found in a picture of the
    view at its last row: the rows before the head, at a negative offset,
    showed through the frozen header, and the header showed in the body.
    `get_frozen_elements` lets a content say what the held strip draws; the
    list table answers its header.
  - [x] **2.3 The horizontal clamp** (`1cafec743`), found in phase 1.
  - [ ] **2.4 The scroll bar and the re-anchor.** They need the row at the
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
    have no other user. Open: whether the eager table changes too, and
    whether this is a plan of its own before the rest of phase 2.
  - [x] **2.5 The display** (`c4cb7c877`). The editor task is pinned to one
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
- [ ] **3. Refresh.** The three levels of §4.3. The triggers A, B with the
  busy flag, and D. C is a keyword that is off by default (D3).
- [ ] **4. Edit.** The pending text, the operations of §3.6 with their
  inverses, undo, the write-through of a `SubDataFrame`, the `DataFrameRow`
  form. If phase 0 puts the editor on another thread, the busy flag of §4.3
  comes with this phase, because an edit writes the frame. D11 is (b), so the
  busy flag and the REPL hook that sets it come with this phase.
- [ ] **5. Sort and filter.** The query document, the header gestures, the
  quick filters, the expression filter, column hide and move. The sort and
  the filter again on a commit (D6), and the selection after it (D10). Column
  freeze needs frozen columns on a list in the widget substrate (§3.5).
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
  another thread (D11), so the busy flag of §4.3 is necessary.
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
