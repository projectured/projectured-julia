# Pivot table: the next steps

> **Kind:** plan · **Status:** pending, 2026-10-06. A list of proposals and
> limits that wait for the owner. The owner moved them out of the first plan on
> 2026-10-06 ("later plan"). No item is decided. ·
> **Stands on:** [pivot-any-table.md](../done/pivot-any-table.md),
> [pivot.md](../../documentation/package/domain/pivot/pivot.md),
> [widget.md](../../documentation/package/platform/widget/widget.md)

The first plan built the pivot: the table interface, the domain
`ProjecturedPivot`, header levels in `WidgetTable`, the bar of zones with
drag and keys, the number, rows, bar, line, pie and group views, totals and
closed runs, the order by a measure, the first N values and bins. This plan
holds what the first plan did not do. Each item needs a decision of the owner
before work starts.

## 1. Proposals

These came from the review of existing pivot tools in the first plan (§5). The
owner did not choose among them.

- **P1. Rename a header value.** An edit of a label in a header changes the
  value in every row of the source that holds it. It is an edit of the source
  through the cross table, with one inverse for all rows.
- **P2. Drag a table header into the bar.** A drag of a column header or a row
  header of the table onto a zone of the bar moves its dimension, as a drag of a
  badge does.
- **P3. Copy as code.** A menu item writes the Julia code that makes the same
  result with DataFrames: `groupby`, `combine` and `unstack`.
- **P4. A heat map cell view.** A number cell gets a background color by its
  value, on one scale for the whole table.
- **P5. A pivot of a database query.** The cross table of a SQL source is
  computed with `GROUP BY` on the server, so the rows do not come to the
  editor. It needs a table kind of the table interface for a query.
- **P6. Tools for the assistant.** The assistant moves a dimension, sets a
  measure and chooses a view through the operations of the pivot, so undo and
  the gesture log see each step.

## 2. A question that the work found

- **Q1. A `GroupedDataFrame` in the group layout.** The data frame adapter
  must not depend on the pivot (P9 of the first plan), and the pivot must not
  depend on DataFrames. So the display of a `GroupedDataFrame` needs a place
  where both meet.
  - (a) A small package, `ProjecturedPivotDataFrames`, that `AutoIntegration`
    loads when `ProjecturedPivot` and `ProjecturedDataFrames` are loaded. It
    adds `make_value_document(group::GroupedDataFrame)`, a pivot of
    `parent(group)` by its group columns in `PivotGroupView`.
  - (b) The adapter depends on the pivot. P9 rejected this.
  - (c) No display. A program calls
    `make_pivot_table(parent(group); rows = groupcols, cell_view = PivotGroupView())`
    itself.

  Recommendation of the writer: (a), because it composes as the owner asked on
  2026-09-30. It is a new package, so the owner decides.

## 3. Known limits

The first plan recorded these limits. Each one can become a step.

- **L1. The width of a level of the row headers** measures the labels of the
  first 64 rows from the head of the list. A wider label further down is cut at
  the edge of its level.
- **L2. The head of the list.** The table moves the head of its list after a
  scroll of 200 rows. The row numbers of the pivot count from the head, so the
  toggle of a run and the group layout can name the wrong row in a pivot of
  more rows. The pivot must follow the head, or keep stable row numbers that it
  maps.
- **L3. A run of columns does not close.** Enter closes a run of rows only.
- **L4. The PDF writer** does not walk a canvas whose elements are a list, so a
  table of a list, the pivot too, shows no rows in a PDF. This limit is older
  than the pivot.

## 4. A fact about main

In a layout, an Alt+press on a header of a table that is a plain value, a
string or a number, selects the whole table. The layout keeps the answer of an
Alt+press of its child only when the answer names a document
(`convert_to_whole_selection` in `source/platform/focus/WholeSelection.jl`).
The pivot gives its labels as `WidgetLabel` documents, so it is not concerned.
Any other table with plain-value headers in a layout is. This is not a pivot
item; it is recorded here because the pivot work found it.
