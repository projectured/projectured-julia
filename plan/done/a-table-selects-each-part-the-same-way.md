# A table selects each part the same way

> **Kind:** plan · **Status:** done, 2026-10-06, on the branch `table-parts`.
> The owner asked to implement it without an answer to Q1, Q2 and Q3 (§5), so
> the implementation follows the recommendation of each, none of which changes
> what a table does now. ·
> **Stands on:** [widget.md](../../documentation/package/platform/widget/widget.md),
> [a-table-has-rows-columns-and-cells.md](../done/a-table-has-rows-columns-and-cells.md),
> [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md)

## 1. The request

The owner (2026-10-06) asked: "can a table currently light (mouse target) a
row/column/cell? is it possible to currently select a whole row/column/cell?",
then "including header rows and header cells?", and after the answer: "can we
make this more consistent and symmetric?"

The goal: a row and a column, and a row header and a column header, are lit,
pressed, selected and moved through by the same rules, in the eager form of
`WidgetTable` (`WidgetToGraphics.jl`) and in the form that scrolls its own parts
(`WidgetTableParts.jl`).

## 2. What exists

The light (the band that follows the mouse target), from
`_find_wt_lit_reference(w, target)`, the same in both forms:

| The pointer is over | The light |
|---|---|
| a cell | its row, `rows[r]`; never the cell alone |
| a row header | its row |
| a column header | its column, `columns[c]`; never the header alone |
| the corner | nothing |
| the edge of a column, list form | the edge, `columns[c].policy`, as a bar |

A press, the same in both forms except where the table says so:

| The press | What it selects |
|---|---|
| plain, on a cell | the content of the cell first; if the content declines, the row |
| Alt, on a cell | the cell, `cells[r][c]` (`cells[c][r]` in a column-major table) |
| plain, on a column header | the content of the header first; if it declines, the column |
| Alt, on a column header | the header, `column_headers[c]` |
| plain or Alt, on a row header | always the row; the content of the header gets no press |
| on the corner | list form: the corner document first; if it declines, the table. Eager form: the table (it draws its corner as graphics) |

The keys, in both forms (`_wt_key_navigate` and `_read_table_parts_key`):

- From a cell, Shift+Space selects its row and Ctrl+Space its column.
- The arrows move a selected row, column or cell. From a row, Right goes to its
  first cell; from a column, Down goes to its first cell (eager) or to the cell
  of the top row (list). Alt+arrow makes a caret in a cell the whole cell.
- Return enters a cell, or goes from a row or a column to its first cell.
- Ctrl+Alt+Home selects the table.
- A selected header takes no key in either form.

The drawn shapes of a selection (`_wt_selection_shape`): the table, a row, a
column, a cell, `column_headers[c]` and `row_headers[r]`. No path names the
whole header row or the whole header column, so neither can be selected, and
`column_headers` with no index has no shape. No reader makes `row_headers[r]`,
although its band exists.

## 3. The model

The parts of a table and their paths. Two paths are new as targets, but they
are plain field paths, so no new kind of reference step is needed:

| Part | Path |
|---|---|
| the table | `∅` |
| a row, a column | `rows[r]`, `columns[c]` |
| a cell | `cells[r][c]`, or `cells[c][r]` |
| a row header, a column header | `row_headers[r]`, `column_headers[c]` |
| the header column, the header row | `row_headers`, `column_headers` (new targets) |
| the corner | `corner` |

The rules (mine, proposed 2026-10-06):

1. **A plain press goes to the content of the part first.** If the content
   declines it, the press selects the line of the part: a cell its row, a row
   header its row, a column header its column, the corner the table.
2. **An Alt+press selects the part itself:** the cell, `row_headers[r]`,
   `column_headers[c]`, or `corner`.
3. **The light shows what a plain press selects.** This is true now, and it
   stays.
4. **Shift+Space selects in the row direction, and Ctrl+Space in the column
   direction, from any part.** From a cell, its row and its column, as now. From
   a row header, Shift+Space its row and Ctrl+Space the header column
   (`row_headers`). From a column header, Ctrl+Space its column and Shift+Space
   the header row (`column_headers`).
5. **The arrows move between parts of the same kind, and step into the cells as
   a row and a column do now.** Left and Right move along the column headers,
   and Down goes into the cells of the column. Up and Down move along the row
   headers, and Right goes into the cells of the row.

## 4. What changes

| | Now | After |
|---|---|---|
| A plain press on a row header | always the row | the content first, then the row |
| An Alt+press on a row header | the row | `row_headers[r]` |
| An Alt+press on the corner, list form | the corner document, then the table | `corner` |
| The header row, the header column | no path, no shape | `column_headers`, `row_headers`, each a band over its strip |
| The keys on a selected header | none | rule 4 and rule 5 |

Everything else of §2 stays.

## 5. Open questions

- **Q1. A plain press on a cell selects its row, never its column.** This is
  the one rule that favours rows ("a table of text is a table of rows"), and
  the data frame view and the run and task lists of omnet-julia use it.
  Recommendation (mine): keep it.
- **Q2. The header row and the header column are selected only by a key.** An
  option: an Alt+press on the corner selects the header row, and an
  Alt+Shift+press the header column. Recommendation (mine): keys only, and the
  corner keeps rule 2.
- **Q3. The light never marks the cell under the pointer.** An option: a faint
  mark on that cell inside the band of its row. Recommendation (mine): no, so
  that the light shows exactly what a press selects.

The owner said "implement this plan in worktree" with no answer, 2026-10-06.
The implementation follows the three recommendations: a plain press on a cell
selects its row, the strips are selected by a key only, and the light marks no
cell. Each can change later on its own.

## 6. Steps

Each step changes the eager form and the list form together, and adds a test
of each rule in each form.

- [x] **1. The shapes.** `column_headers` and `row_headers`, with no index,
  draw a band over the header row and the header column: in the eager form
  through `_wt_selection_shape` and the band of the geometry, and in the list
  form through `_find_named_part` and the bands of the header panes. Done
  2026-10-06: `_wt_field_terminal(sel)` reads a whole field; the shapes are
  `:header_row` and `:header_column`. The eager band of the header row spans
  the column headers and not the corner, and the band of the header column the
  row headers. The list form bands the header row in the header pane and the
  header column in each row of the header column.
- [x] **2. The press.** A plain press on a row header goes to its content
  first, as a column header does (`_wt_mouse_select`,
  `_read_table_parts_press`). An Alt+press on a row header selects
  `row_headers[r]`, and on the corner of the list form `corner`. Done
  2026-10-06: `_wt_route_header_click` and `_read_table_header_press` take the
  header and its line, so one function serves both headers in each form.
  Facts found: the list form sent a key only into a column header that holds
  a caret, and the eager form into both, so the list form now sends it into a
  row header too (`_find_header_in_selection` gives the field and the index).
  A selected corner drew no band, so the corner region of the list form draws
  one for the corner and for the table.
- [x] **3. The keys.** Rule 4 and rule 5 for a selected header. The two key
  readers decide from the same named part; a shared function of the rules of
  §3, which both readers call, is to be decided at this step (mine). Done
  2026-10-06, with no shared function (mine): each form keeps the habit of its
  own reader at an end, the eager form stays on the last header and the list
  form answers nothing, as their rows and cells already do. Down from a column
  header goes to the first row in the eager form and to the row at the top in
  the list form, as from a column.
- [x] **4. The owners of tables.** The data frame view maps a header to its
  column or its row of the frame, and the corner to the view
  (`_find_view_path`). The header row and the header column have no place in a
  frame, so the view declines them (mine). Done 2026-10-06 with no change to
  the view: `_find_view_path` already gives `nothing` for a path with no index,
  and the view declines a selection that it can not map. A test shows that an
  Alt+press on a row header and on a column header of the view selects the row
  and the column of the frame. The statistics table and the
  omnet-julia tables are checked with their tests; their row headers are
  labels, which decline a press, so a press there still selects the row.
- [x] **5. The guide.** `widget.md` and the docstrings of the table state the
  rules of §3. Done 2026-10-06.

Tests, 2026-10-06: `test_widget_table_part_selection` (69) runs each rule in
both forms: a row header of a label, of a checkbox and of a text field, the
corner, the bands of the header row and of the header column, and the keys.
The data frame paths 19 (two checks of an Alt+press on a header of the view).
The platform: 98,409 pass, 8 broken and 2 fail, both in `test_interface_api`,
which fail the same way on main (b7709ef1d): the interface lists
`WidgetProgressRing`, so it has 32 names and not 31, and that docstring has no
"Use it to" line. Markdown 236, data frames 558, book 33; the umbrella
table tests 25, 67, 14, 110 and 134.

Fact found: the row headers of the math table example
(`TableDocumentExample.jl`) are strings, which take a press, as its column
headers are. A plain press there now puts the caret in the row header, as a
press on its column header already did, and an Alt+press selects the header;
`TableNavigationTest` expects that now. Every other table with row headers
gives them labels, which decline a press, so a press there still selects the
row: the data frame view, the statistics table, the widget example, and the
runs table of omnet-julia.

## 7. Risks

- A row header whose content takes a press, such as a checkbox or a button,
  gets the press after step 2, where the row was selected before. No table in
  projectured-julia or omnet-julia has such a row header now; a search before
  step 2 must confirm it.
- An Alt+press on a row header selects the header and no longer the row. A
  test or a user that relies on the old answer changes.
- The two forms have separate readers, so a rule can drift between them. The
  tests of each step run each rule in both forms.
