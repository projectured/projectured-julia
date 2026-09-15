# One table widget, lazy or not

> **Kind:** plan · **Status:** pending · **Stands on:**
> [../../documentation/rule/layout-rules.md](../../documentation/rule/layout-rules.md),
> [../../documentation/package/widget/widget.md](../../documentation/package/widget/widget.md)

`WidgetTable` and `WidgetLazyTable` are two widgets for one idea. This plan
makes them one, and repairs what each got wrong on its own.

## 1. What is there now

`WidgetTable` holds `rows`, a `CellVector` of rows, and each row is a
`CellVector` of **documents**. The printer builds a `GridLayout` of every cell
and reads the grid's geometry to draw the rules, the header strip and the
selection band. A cell can be any widget, a click can land inside a cell, and a
reference can name a cell or a caret inside it.

`WidgetLazyTable` holds `row_count`, `row_height` and a `cell(row, column)`
function that answers a **String**. The printer emits a `ListNode` of row
canvases; the renderer walks it and stops at the bottom of the viewport, so the
cost is the rows a person can see. The caller states every column width.

Both declare a frozen extent, so an enclosing `WidgetScrollPane` holds the
header still. Both answer the same row selection, so a projection that reads one
table's rows reads the other's unchanged.

## 2. What is broken

1. **The grid never clips a cell, and a row now grows instead.** `GridLayout`
   emits no `GraphicsViewport`, so §3b — the container that handed out a bounded
   extent must clip it — is unmet. Since prose began to break at the width it is
   offered, the symptom changed rather than went away. Measured: an eager table
   of two `Fixed(80)` columns, one cell holding a sentence, draws that cell as
   **six stacked lines** and the row is 137 pixels tall. The words are no longer
   lost, and the table is no longer a table. A cell that is not text — an image,
   a nested card — still draws over its neighbour, because nothing clips.

   So a table cell needs to say which it wants, and today it cannot. A data
   table wants one line, clipped. A document table wants the prose to wrap. The
   lazy table picked the first by hand as of `A table cell keeps the same gap on
   both sides of its column`; the eager one now picks the second by accident.

2. **Every cell is built, even in a column that is never measured.** This is the
   part that is worse than it looks. `_gl_extents_cell` already skips the cells
   of an offered column — a `Fixed(n)` column is told `n` and its cells are not
   read — so a table of declared widths measures nothing. But `_wt_grid_children`
   still returns one child per cell for every row, and `_grid_build` recurses
   all of them. The eager cost is the **build**, not the measurement.

3. **A lazy cell is a String.** The runner cannot put a progress bar, a status
   badge or an editable field in a cell, which is the first thing a table of
   runs wants.

4. **A lazy table maps no reference.** `map_reference_forward` and
   `map_reference_backward` answer `nothing` always. The only selection it can
   produce is the whole row its click computes. Nothing can address a cell.

5. **Two row heights that disagree.** Measured: the eager row pitch is 37
   pixels for a twenty-pixel line, which is the cell plus the gap of
   `2 * padding + border_width`. The lazy row is whatever the caller passed, and
   both omnet callers passed 22, which left one pixel above and below the text.

6. **Two paddings that disagree.** The eager table reads `w.padding`, a document
   field whose default is 8. The lazy table reads the projection's `padding`,
   which the factory fills from the theme's `pad_x`, which is 14.

7. **The geometry is duplicated in the callers.** omnet states a row height and
   a column width list twice, in
   `source/legacy/simulator/presentation/SimulationFilterToWidget.jl` and in
   `source/legacy/result/presentation/SimulationResultFrameToWidget.jl`.

8. **The runner's table test is dark and has been failing since 2026-09-12.**
   Commit `6d91cb2b` moved the runner from `WidgetTable` to `WidgetLazyTable`
   and did not move `test_filter_run_table`, which still asserts
   `column_count`, `column_headers`, `rows` and `row_headers` — four fields the
   lazy table does not have. Measured on the landed main: 16 passed, 2 failed,
   12 errored. Nobody saw it because the `OmnetLegacyTest` environment of the
   main checkout could not load at all: its manifest was stale and `Pkg.resolve`
   died on an internal assertion, so the manifest had to be deleted and built
   again before the suite would run.

## 2b. What the callers actually do

Counted across the three repositories. `inet-julia` has none of either type, so
the merge touches two repositories.

| | sites | cells hold |
| --- | --- | --- |
| `WidgetTable` | 21 | strings at 14, whole documents at 7 |
| `WidgetLazyTable` | 5 | strings at all 5 |

Three facts from that count bear on the design.

- **No caller anywhere states a column or a row policy.** Every `WidgetTable`
  relies on the `Content` default. So the `Fixed` column path that makes
  laziness possible is, today, exercised by nothing but a test.
- **A cell already holds a whole document at seven sites** — a nested sequence
  chart, four charts, JSON values, a math operation. "Any widget in a cell" is a
  live feature and not a hypothetical, which is why the lazy form must gain it
  rather than the eager form losing it.
- **Five omnet callers wire `rows` reactively after construction**, with
  `set_cell_function!` on `getfield(table.rows, :elements)`. A capture view, the
  workbench run list, the optimisation observations, the federation view and the
  runner all grow their table this way. `LazyRows` must leave that pattern
  possible or those five have to change with it.

## 3. The design

**One widget, and `rows` is a `CellVector` or a `ListNode`.** The printer reads
the type of `rows` and nothing else says which table this is.

- `rows::CellVector` of rows, each a `CellVector` of documents — the eager form,
  unchanged.
- `rows::ListNode` — the lazy form. A node's `value` is a row, a `CellVector` of
  documents exactly like an eager row, so a cell is any widget in both forms
  and every projection below the table sees one shape. A node's `next` and
  `prev` are cells, so a neighbour is built when it is first read, and a list
  whose `next` never answers `nothing` is infinite. There is no count field:
  a finite list ends where `next` answers `nothing`.

**The head is the anchor, and a reference index is relative to it.** The
renderer already walks a list-backed canvas both ways from its head — `prev`
upward until a row is above the viewport, `next` downward until one is below —
so the head is not the first row, it is the row the table is looking at.
`rows[i][c]` counts from the head: the head is row 1, and `next` steps count
up. A row reached through `prev` is before the head, and the reference
vocabulary has to be able to say so (§4).

**A lazy table grows by growing its list.** Nothing installs a function on the
rows after the fact. When more data arrives, `next` answers a node it did not
answer before; when the data is replaced, the `rows` cell answers a new head.
The five omnet callers that wire `rows` today do this instead.

**A column that was given a width is not measured.** This already holds in the
grid and must keep holding: `Fixed(n)` and a weight both answer `_gl_offers`,
and the cells of such a column are never read.

**Laziness is not a mode the caller names. It is what `rows` and the policies
allow.** A `ListNode` in `rows` draws lazily when both are true:

- every column is offered — each is `Fixed` or carries a weight, so no column
  width depends on a cell;
- the row policy is `Fixed(h)`, so the y of row *n* is arithmetic.

A list whose table does not meet both is an error the printer states, not a
silent walk of every row. The existing vocabulary says both conditions, so the
widget gains no `lazy` flag and no second row-height field.

**A cell clips or wraps by the policy of its column, else of its table.** The
table carries one policy and a column may carry its own; a cell carries none
and falls back. The default is one clipped line, because a table is a data
table until someone says otherwise. A row of `Fixed` height cannot wrap in any
case, so the lazy form settles it by construction.

**Laziness lives in a set of functions both paths call.** It is not a property
of `GridLayout` and not a property of the table's printer. Splitting it into
five pieces shows that only two of them have two implementations at all, and
the arithmetic that the selection band, the rules and the click all read is
one piece with one implementation.

| piece | eager | lazy |
| --- | --- | --- |
| 1. the extents of an axis | measured from the cells | read from the policies |
| 2. the offsets of the bands | cumulative over the extents | the same |
| 3. the band at a coordinate | the inverse of 2 | the same |
| 4. the canvas of the content | a vector of cell canvases | a `ListNode` of row canvases that mirrors `rows` node for node |
| 5. the child iomap at (row, column) | a vector lookup | a walk from the head to the node |

Piece 1 is written once already: `_gl_extents_cell` reads a column's cells only
when the column was not offered, so it is the eager rule and the lazy rule in
one function. Pieces 2 and 3 exist twice today — `_gl_col_x_cell` against
`_lazy_column_edges`, and `_wt_hit_test` against a bare `event.y ÷ height` —
and each pair is the same arithmetic. Piece 4 is the definition of laziness and
has to have two forms. Piece 5 needs no cache and evicts nothing: the canvas
list mirrors the document list, a canvas node holds its row's cell iomaps, and
it lives exactly as long as the document node it mirrors is reachable.

Pieces 1 to 3 belong in `ProjecturedLayout` beside `allocate_axis`, which is
already the allocator the stacks, the split and the grid share. That precedent
is the argument: this codebase already puts layout arithmetic in a function
everyone calls rather than in the widget that needed it first. With them
shared, `GridLayout` can later take a `ListNode` of children of its own and
inherit piece 4 at the cost of nothing new.

**Padding and the row height come from the theme.** `w.padding` leaves the
document and becomes `Inset(theme.pad_y, …, theme.pad_x, …)` on the projection,
beside every other widget's. A `row_policy` left unset means the theme decides:
one line of the projection's font plus twice `pad_y`.

**`WidgetLazyTable` is deleted.** The name, the type, its printer, its reader
and its three helpers. Nothing takes its place under another name.

## 4. Open questions, to settle before any code

- **How does a reference name a row before the head?** `rows[i]` is a
  `RangeReferenceStep` with a zero-based start, and the head is row 1. A row
  the renderer reached through `prev` sits at a negative offset. Either the
  range step is allowed a negative start, or the table re-anchors its head so
  that no drawn row is ever before it. The second keeps the vocabulary as it is
  and puts the cost on scrolling.

- **How does a scroll pane scroll an infinite content?** A pane clamps its
  offset to `content_h - vh`, and a list-backed canvas has no `content_h`.
  Proposal: the offset of a list-backed content is measured from the head and
  is not clamped, and once it passes a whole row the table moves its head to
  that row and the offset shrinks by the row. Then a far row is reached by
  re-anchoring, never by a pixel count over an unbounded extent, and
  `follow_end` on such a pane means the head follows the last node. Who moves
  the head — the pane's reader or the table's — is the part to decide.

- **Does an eager `CellVector` table keep its whole-table height?** Yes, and it
  must: a page stacks it and needs its extent. Only a list-backed table has
  none, and only that table is walked.

- **Is `Fixed` the only row policy a list allows?** A weighted row policy
  divides an offered height among the rows, and an infinite list has no count
  to divide by. So a list allows `Fixed` and refuses a weight, and the error
  message says why.

## 5. Steps

- [ ] **Step 0 — the runner's table test stops being dark.** Rewrite
      `test_filter_run_table` against the type the runner actually builds, and
      say in the plan of record that the suite could not load. Repairs defect 8.
      The merge will rewrite these assertions again; they must pass in between,
      or the step that moves the caller has no baseline to compare against.
- [ ] **Step 1 — the grid clips what it allocated, and a cell draws by the
      policy of its column, else of its table.** A cell in an offered column is
      drawn in a viewport of that column's extent. The table gains the policy
      and a column may override it; the default is one clipped line. Eager
      table only. Repairs defect 1 and gives the eager table the gap the lazy
      one now has.
- [ ] **Step 2 — padding and the row height come from the theme.** Move
      `WidgetTable.padding` to the projection. Let an unset row policy mean one
      line plus twice `pad_y`. Delete both omnet `_ROW_HEIGHT` constants.
      Repairs defects 5, 6 and half of 7.
- [ ] **Step 3a — pieces 1 to 3 become functions in `ProjecturedLayout`.** The
      grid and both tables call them, and behaviour does not change. This step
      is a refactor and its test is that every existing table test still passes
      with the same numbers.
- [ ] **Step 3b — `rows` accepts a `ListNode`.** Pieces 4 and 5 gain their
      second form: a canvas list that mirrors the document list, and a walk from
      the head that answers a cell's iomap. The two open questions on the head
      and on scrolling are settled here. Repairs defects 2, 3 and 4.
- [ ] **Step 4 — the callers move.** The runner's table and the result table
      become `WidgetTable` with a `ListNode` in `rows` and their widths as
      `column_policies`; the five callers that install a function on `rows`
      grow a list instead. Repairs the rest of defect 7.
- [ ] **Step 5 — `WidgetLazyTable` is deleted**, with its printer, its reader,
      its helpers, its test file and its mentions in the guides of both
      repositories.

## 6. What the tests must say

- A cell wider than its offered column is drawn inside the column, with the same
  gap at both ends. One test for the eager table, one for the lazy form.
- A row of a table with a long cell stays one row tall. The measurement that
  found this drew six lines for one value.
- A table whose list is infinite builds a handful of rows, and a walk to the
  viewport's bottom is the whole cost. The existing lazy test says this for a
  count of 100,000 and must keep saying it for a list with no count.
- A widget in a lazy cell draws, and a click on it reaches it. This is new and
  is the reason the merge is worth doing.
- `rows[i][c]` on a list names the same cell the eager table names for the
  same data, and a row before the head is nameable, however §4 settles it.
- The same table, eager and lazy over the same data, draws the same pixels at
  the same size. That is the one test that says the merge did not fork.
- A list in a table whose columns are not all offered is refused, and the
  message names the column. A weighted row policy on a list is refused too.
