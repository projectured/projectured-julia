# The assistant reads and changes a pivot

> **Kind:** plan · **Status:** pending, written 2026-10-20. D1 decided the same
> day. No step is started. ·
> **Stands on:** [pivot-table-next-steps.md](pivot-table-next-steps.md) (P6),
> [pivot.md](../../documentation/package/domain/pivot/pivot.md),
> [the-assistant-uses-the-whole-editor.md](../done/the-assistant-uses-the-whole-editor.md) (D8),
> [orientation.md](../../documentation/guide/orientation.md)

## 1. The request

On 2026-10-20 the user asked if the assistant can access a pivot table with the
`execute_julia_code` tool. A check showed that it can only in part (§2). The user
then said yes to a plan for P6 of the next steps of the pivot: "The assistant
moves a dimension, sets a measure and chooses a view through the operations of
the pivot, so undo and the gesture log see each step."

The plan has three parts:

- The model finds the pivot names.
- The model reads a pivot.
- The model changes a pivot with the operations that the UI makes.

## 2. What exists

Two probes measured this on main 636013c86. Each probe opened the pivot of
`make_pivot_document_example()` in a tab of a headless application window. The
window had the tool set of `start_application!`. Each probe then called
`execute_julia_code!` as a model does. An external MCP client gets the same
answers, because `McpServer` uses the same `editor.tools`.

| What the model writes | Result |
| --- | --- |
| `search_api("pivot")` | "No API matches". `PivotModule` calls no `register_assistant_api!`, so no pivot name is declared and the system text has no sentence about the pivot. |
| `get_edited_document(find_pane("Sales pivot"))` | Works: a `ReferencedDocument{PivotTable}`. |
| `pivot_1.row_dimensions`, `pivot_1.measures`, `pivot_1.totals` | Work. |
| `pivot_1` | A dump of the source and every field, trimmed to its start and end. It shows no value of a cell. |
| `print_natural_text(pivot_1)` | Fails: "no natural text for PivotTable". |
| `print_pred_text(pivot_1)` | Fails: "cannot write a PivotCrossTable at cross_table". |
| `make_pivot_table`, `PivotMeasure`, `compute_pivot_measure` | `UndefVarError` for each. |
| `compute_pivot_measure(pivot_1.source, rows, measure)` | Fails: the table interface has no method for a `ReferencedDocument`. |
| `replace_referenced_value!(pivot_1.measures[1], PivotMeasure("amount", :mean))` | Works, one undo step. The constructor was reached by reflection. |
| `replace_referenced_value!(pivot_1.row_dimensions[2], PivotDimension("country"; order = :measure, descending = true, limit = 1))` | Works, one undo step. The cross table follows. |
| `insert_elements!(pivot_1.measures, 2, [PivotMeasure("", :count)])` | Works, one undo step. |
| `delete_elements!` and then `insert_elements!` to move "country" from Rows to Columns | Works, but two undo steps. The drag makes one `MoveRangeOperation`, which keeps the cell of the dimension. |
| `replace_referenced_value!(@reference(pivot_1, totals), true)` | Fails: the path is `.totals`, not a path from the root. |
| The same with `concat_references(get_reference(pivot_1), @reference(get_document(pivot_1), totals))` | Works, one undo step. `concat_references` is not declared. |
| The same for `cell_view`, whose value is `nothing` | Fails: a path to a field that holds `nothing` is not fully typed, so `_refuse_stale` refuses it. |
| `describe_commands(pivot_1)` | Only "Show the menu of the pivot: Right click". The keys of the bar act on the item that the person selected, so a command can not reach them without a move of the selection, which D8 forbids. |
| `parentmodule(typeof(get_document(pivot_1))).PivotMeasure(…)` | Works. The declared list is not a fence. |

The UI changes a pivot with these operations:

- A drag or Alt+arrow of a field: a `MoveRangeOperation` between two zones.
- A measure: a splice of `ReplaceReferencedValueOperation` on `measures`.
- The menus: `ReplaceReferencedValueOperation(document, field, value)` on a field
  of the pivot (`totals`, `cell_view`, `collapsed`), of a dimension (`order`,
  `descending`, `limit`, `bin`, `hidden_values`) or of a measure (`aggregate`).

The workflow domain is the precedent for a domain verb of the assistant. Its verb
makes the operation of the UI and lets `find_rooted_operation` carry it from the
part to the root, so the history of the tab records it
(`source/domain/workflow/WorkflowEdits.jl`).

## 3. The design

**Find.** `PivotModule.__init__` calls `register_assistant_api!` with the names
below and with one paragraph for the system text. The paragraph has an example
for each part, because the rehearsals of the assistant showed that a worked
example in the system text helps a model and a docstring alone does not.

- The documents: `make_pivot_table`, `PivotDimension`, `PivotMeasure`, and the
  cell views `PivotNumberView`, `PivotRowsView`, `PivotBarChartView`,
  `PivotLineChartView`, `PivotPieChartView` and `PivotGroupView`.
- The values of a key: `PivotTotal`, `PivotBin` and `PivotMonth`.
- The two new verbs of this plan, `find_pivot_value` and `move_pivot_field!`.

**Read.** Two parts:

- A `text/plain` display of a `PivotTable`. Its first line names the zones as the
  bar shows them: Rows, Columns, Cells, Values, the totals, and the number of
  rows of the source. The lines after it show the grid of values as the table
  shows it, with the keys of the rows and the columns and `format_pivot_value`
  for each value. The display obeys `:limit` and `:displaysize` of its IO
  context, as the REPL display of a data frame does, so it shows the first rows
  and says how many it leaves out. The display of a `ReferencedDocument` already
  forwards to the display of its document. So `pivot_1` in a call answers the
  grid, and a person in the REPL sees the same grid.
- `find_pivot_value(pivot, row_key, column_key; measure = 1)`: the value of a
  measure in one cell, the same value that the cell shows, or `nothing` when no
  row of the source has both keys. It is the counterpart of GETPIVOTDATA of a
  spreadsheet, for a pivot too large for the display. It takes a referenced
  pivot and reads the document under it, so the table interface does not need a
  `ReferencedDocument`.

**Change.** The model makes the operations that the UI makes. No verb moves the
selection of the person (D8).

- A field to another zone: `move_pivot_field!(pivot, column, zone; place = nothing)`.
  `zone` is `:fields`, `:columns`, `:rows` or `:cells`, the names of the bar.
  `place` is the 1-based place in the zone, and `nothing` puts the field at the
  end. The verb makes the `MoveRangeOperation` of a drag, without the
  `ReplaceSelectionOperation` that the keys add, and evaluates it as the
  workflow verbs do. One call is one undo step.
- A measure: `insert_elements!`, `delete_elements!` and `replace_referenced_value!`
  on `pivot.measures`, with a `PivotMeasure`. These work now (§2) and need only
  the declared constructor.
- The settings of a field or a measure: `replace_referenced_value!` with a new
  `PivotDimension` or `PivotMeasure`. This works now (§2).
- The settings of the pivot itself (`totals`, `cell_view`, `collapsed`), and any
  other plain field: `replace_referenced_value!(part, field, value)`, a new
  method of the declared verb in the pane slice (D1). It makes
  `ReplaceReferencedValueOperation(get_document(part), String(field), value)`,
  the operation of a menu item, and roots it at the place of `part` with
  `find_rooted_operation`. So it also writes a field that holds `nothing`.
  Example: `replace_referenced_value!(pivot_1, :totals, true)`.

**What it adds.** One display, two pivot verbs, and one method of
`replace_referenced_value!`. It adds no event, no payload, no reader method and
no step of the editor loop.

## 4. Decisions

- **D1. Decided by the owner, 2026-10-20: (a).** The owner answered "Agreed" to
  the recommendation below. How the model writes a setting of the pivot itself:
  - (a) A general method `replace_referenced_value!(part, field, value)` in the
    pane slice. It makes `ReplaceReferencedValueOperation(get_document(part), String(field), value)`,
    the operation of a menu item, and roots it at the place of `part` with
    `find_rooted_operation`. It writes a field of any document, also one that
    holds `nothing` or a plain value. Example:
    `replace_referenced_value!(pivot_1, :totals, true)`.
  - (b) Two pivot verbs, `show_pivot_totals!(pivot, shown)` and
    `change_pivot_cell_view!(pivot, view)`, in the pivot domain. They make the
    same operation. `collapsed` gets no verb.

  Recommendation of the writer: (a). The write is the operation of the menu
  item in both options. (a) also serves every other document with a plain
  field, such as a widget or a chart, and it needs no new name. (b) keeps the
  change inside the pivot domain.

## 5. The steps

Each step works in a worktree, ends with its tests, and ends with a commit.

- [ ] **1. Read.** The `text/plain` display of a `PivotTable` and
  `find_pivot_value`, each with its docstring and an example. Test: the display
  of the pivot of the example names its zones and shows the value of each cell.
  A display with a small `:displaysize` says how many rows it leaves out.
  `find_pivot_value` answers the value that the cell shows, a total, and
  `nothing` for a key that does not occur.
- [ ] **2. Change.** `move_pivot_field!` and the method
  `replace_referenced_value!(part, field, value)`. Test: in a headless window,
  each verb is one undo step, `undo` takes it back, and the selection of the
  person does not change. `replace_referenced_value!(pivot_1, :cell_view, …)`
  works while the field holds `nothing`.
- [ ] **3. Declare.** `register_assistant_api!` in `PivotModule.__init__` with the
  names of §3 and the paragraph. Test: the calls of §2 through
  `execute_julia_code!`, with the tool set of `start_application!`, find the
  names, read the grid, read one value, move a field, add a measure, change an
  aggregate and change the totals. `search_api("pivot")` answers the pivot names.
- [ ] **4. Check the neighbours.** Run `test_pivot()`, `test_application()` and
  `test_referenced_document_editor()`, because a new declared docstring can move
  the rank of `find_pane` in a search. Search omnet-julia for a method of
  `replace_referenced_value!` before the step ends, because a new platform
  method can collide with a method that omnet-julia defines.
- [ ] **5. Document.** A section "The assistant" in
  [pivot.md](../../documentation/package/domain/pivot/pivot.md) with the
  examples of the paragraph. Mark P6 done in
  [pivot-table-next-steps.md](pivot-table-next-steps.md).

## Not in this plan

`print_natural_text` and `print_pred_text` of a pivot; the table interface for a
`ReferencedDocument`; a rehearsal of a pivot task with the real model; P1 to P5.
