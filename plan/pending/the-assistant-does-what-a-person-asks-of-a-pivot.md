# The assistant does what a person asks of a pivot

> **Kind:** plan · **Status:** pending, written 2026-10-21. Every decision is
> made. No step is started. ·
> **Stands on:** [the-assistant-reads-and-changes-a-pivot.md](../done/the-assistant-reads-and-changes-a-pivot.md),
> [pivot.md](../../documentation/package/domain/pivot/pivot.md),
> [collection.md](../../documentation/package/platform/collection/collection.md),
> [reference.md](../../documentation/package/kernel/reference.md)

## 1. The request

On 2026-10-21 the owner asked if the documentation of the pivot verbs is good
enough, with use cases, for the assistant. The answer was no (§2). The owner
said yes to a plan with four parts, and rejected a special case in
`make_pivot_table`: "I don't want weird exceptions the verbs should combine
nicely". The owner then agreed to the general fix of §3.

The four parts:

- A table that a read answers works with every table verb.
- The paragraph of the system text shows a worked example for each common request.
- The display of a pivot names the fields that a write needs.
- The rehearsal of the assistant measures pivot tasks before and after.

## 2. What exists

A probe on main 6e04fdcd1 opened three tabs in a headless application window and
called `make_pivot_table(get_edited_document(find_pane(title)); rows = ["region"])`
through `execute_julia_code`:

| The tab holds | `get_edited_document` answers | `make_pivot_table` |
| --- | --- | --- |
| a `DataFrame`, from `open_pane!(frame)` | the `DataFrame` | works |
| a `DataFrameView`, as the display of a frame makes it | `ReferencedDocument{DataFrameView}` | fails: "a pivot needs a table" |
| a vector of named tuples | `ReferencedDocument{Vector{…}}` | fails: "a pivot needs a table" |

`get_edited_document(find_pane("View")).frame` answers the plain `DataFrame`,
because a referenced read wraps only a document, a vector, a dict or a tuple
(`_is_referenced_value`, `ReferencedDocument.jl`).

The causes:

- The table functions of the collection slice are `is_table`,
  `get_table_row_count`, `get_table_column_names`, `get_table_column_type`,
  `get_table_value`, `find_table_column`, `make_table_part` and
  `make_table_document` (`TableInterface.jl`). None has a method for a
  `ReferencedDocument`, and `is_table(::Any)` answers `false`. The orientation
  guide says that a referenced document acts like its document, and indexing,
  iteration, `print_natural_text` and `search_documents` follow it.
- A `DataFrameView` holds its frame in the field `frame`. The data frame adapter
  gives the table functions to `AbstractDataFrame` only (`DataFrameTable.jl`).
- The rule that the tree never holds a referenced document is a comment at
  `_get_stored_value` (`ReferencedDocument.jl`). The verbs that write keep it with
  their own call of `get_document`: `insert_elements!` (`DocumentEdits.jl`),
  `open_pane!` and `replace_referenced_value!` (`PaneProgram.jl`). A maker, such
  as `make_pivot_table`, does not.
- The document layer is layer 10 of the kernel, and the reference layer is layer
  11. The constructor that `@document` generates (`_emit_autowrap_ctor`,
  `DocumentMacro.jl`) is in layer 10, so it can not name `ReferencedDocument`.
- No field of a document in `source/` is typed `ReferencedDocument`.

What the model has now for each request, from the paragraph of the system text
and the docstrings:

| The person asks | What the model has |
| --- | --- |
| "Make a pivot of the table in this tab" | fails, see above |
| "Show the top 5 countries" | the docstring of `PivotDimension` only |
| "Hide Canada", "by month", "in bins of 10" | prose in the docstring of `PivotDimension` only |
| "Show the cells as bar charts" | the docstrings of the view types only |
| "Remove this measure" | nothing; `delete_elements!(pivot_1.measures, 1)` works |
| "Which rows are behind this cell?" | nothing; `find_pivot_part_rows` is not declared |
| The field names, such as `row_dimensions` | one example in `PivotDimension`; the display uses the words of the bar |

The rehearsals of the assistant measured that a worked example in the system text
changes what a model does, and a docstring alone does not
(`tool/assistant/rehearsal.jl`, `make_application_system`).

## 3. The design

**A table that a read answers is a table.** The collection slice gives each of
the eight table functions a method for a `ReferencedDocument`, which answers what
the function answers for its document. It is the forwarding that
`ReferencedDocument.jl` has for `print_natural_text`. Then every table verb takes
a table that a read answers: `make_pivot_table`, `compute_pivot_measure(pivot_1.source, …)`
and the others.

**A data frame view is a table.** The data frame adapter gives the table
functions to `DataFrameView`: the rows of a view are all the rows of its frame,
not only the rows that its filter shows, as a spreadsheet makes a pivot of its
whole source range. `make_table_part` of a view is a part of its frame, so a cell
of the rows view still edits the frame.

**A document keeps the document of a referenced document.** The constructor that
`@document` generates stores, for each raw value, the document of a referenced
document. Then a maker and a verb need no call of `get_document` to keep the rule.
How layer 10 does it is D3.

**The text.** The paragraph of the pivot domain gets a worked example for each
request of §2, in one or two lines each:

- a pivot of the table of a tab: `make_pivot_table(get_edited_document(find_pane("Sales")); …)`;
- the top 5: `replace_referenced_value!(pivot_1.row_dimensions[1], PivotDimension("country"; order = :measure, descending = true, limit = 5))`, one write and one undo step;
- a hidden value, a field by month and a field in bins: `replace_referenced_value!(…, :hidden_values, …)` and `replace_referenced_value!(…, :bin, …)`;
- the cells as bar charts: `replace_referenced_value!(pivot_1, :cell_view, PivotBarChartView())`;
- the removal of a measure: `delete_elements!(pivot_1.measures, 1)`;
- the rows behind a cell: `find_pivot_part_rows`, which the pivot domain declares, with a docstring for a model.

The first line of the display names the field beside the word of the bar, such
as `Rows (row_dimensions): region, country`, so a model writes the path that a
change needs.

**The rehearsal.** `tool/assistant/rehearsal.jl` gets a window with a data frame
tab "Sales" and its pivot in a tab "Sales pivot", and six tasks of one prompt,
each with a check: make a pivot of the Sales tab; read the value of NY in 2025;
show the top 2 countries; leave Canada out; show the cells as bar charts; put the
years down and the countries across. It runs seeds 1 to 5 of each task. It counts
what the model does, not how fast, so it needs no idle machine.

**What it adds.** Methods of existing functions in the collection slice and in
the data frame adapter, the rule in the generated constructor, the move of the
generic function of D3 down one layer, one more declared name, and text. No
event, no payload, no reader method and no step of the editor loop.

## 4. Decisions

- **D1. Decided by the owner, 2026-10-21.** No special case in a verb: the verbs
  combine through the general fix of §3.
- **D2. Decided by the owner, 2026-10-21.** The rows of a `DataFrameView` as a
  table are all the rows of its frame.
- **D3. Decided by the owner, 2026-10-21: (a).** The owner answered "I agree" to
  the recommendation, and asked for a better name than `get_stored_value`. How
  the constructor of layer 10 keeps the rule, when it can not name
  `ReferencedDocument` of layer 11:
  - (a) A generic function of the document layer that answers its argument, and
    that the reference layer extends for a `ReferencedDocument`. The generated
    constructor calls it for each raw value. It is an extension point between
    two layers. Julia compiles a constructor for the types of its arguments, so
    the call should resolve when it compiles and cost nothing when it runs; step
    3 measures the cost of a build to make sure.
  - (b) No rule in the constructor. A pivot of a referenced table keeps the
    referenced document as its source, and it works through the forwarding of
    §3. The tree then holds a referenced document, which the rule forbids.

  **The name, decided by the owner, 2026-10-21:** no new name. The owner
  answered "yes" to the proposal of the writer. The function is `get_document`. It has two methods now, both in the reference
  layer (`ReferencedDocument.jl`): `get_document(x::ReferencedDocument)` answers
  its document, and `get_document(x) = x` answers anything else as it is, which
  is the rule. The verbs that write already call it for this purpose. Step 3
  moves the generic and its fallback to the document layer, and the method for a
  `ReferencedDocument` stays in the reference layer. So the owning module of the
  exported name moves from `ReferenceModule` to `DocumentModule`, and the
  declaration of the names of the assistant (`PaneProgram.jl`) names it under
  `DocumentModule`. No code names `ReferenceModule.get_document`, and
  omnet-julia defines no method of it (checked 2026-10-21).

## 5. The steps

Each step works in a worktree, ends with its tests, and ends with a commit.

- [ ] **1. The rehearsal of a pivot.** The window and the six tasks of §3 in
  `tool/assistant/rehearsal.jl`. Run seeds 1 to 5 on main as the baseline, and
  record the count of each task in this plan.
  - Facts that the work found: the window of S2 no longer built on main,
    because the application window opens on the Explorer, and `prepare_window!`
    looked for a tab "Files". It now closes the Explorer tab and selects the
    content of `people.json`, as the video recorder does for a take with files.
  - The rehearsal prints the window once, before the model starts, so the two
    pivot tabs are added before that print (`prepare_pivot_window!`); a tab that
    is added later is not reached by the readers, and its edits are not recorded.
  - The runner takes `make_editor` and `count_steps`, so the pivot tasks reuse
    `run_task_rehearsals`; a change of the pivot is checked in the history of the
    window, which records the edits of a tab that shows no file.
  - The first baseline ran 2 of 30 runs: the rehearsal skips a run below 13 GB
    of free memory, and other sessions held the memory. The baseline runs again
    from the environment of the main checkout, with the rehearsal file of this
    branch, so it runs the code of main.
- [x] **2. A table that a read answers.** Done 2026-10-21. The methods of the
  table functions for a `ReferencedDocument` in the collection slice, and for a
  `DataFrameView` in the data frame adapter. Test: each table function answers
  the same for a table and for a referenced read of it; `make_pivot_table` takes
  the table of each tab of §2; a cell of the rows view of a pivot of a data frame
  view edits the frame. Run the collection test, `test_dataframes()` and
  `test_pivot()`.
  - What was built: the eight forwarding methods at the end of
    `TableInterface.jl`; the eight methods of a view in `DataFrameView.jl`, after
    the type, because `DataFrameTable.jl` is included before the type exists. A
    view gives every column of its frame too, also a column that it hides.
  - Tests: `test_table_interface` 58 of 58, `test_data_frame_table` 30 of 30,
    `test_pivot_data_frame` 47 of 47 (a pivot of a view and of its referenced
    document, and the rows view of it edits the frame). `test_dataframes()` runs
    with the comparison of step 3.
- [x] **3. A document keeps the document.** Done 2026-10-21, but for the
  measurement of the build cost, which waits for the owner. The rule in the generated constructor,
  by D3: the generic `get_document` and its fallback move to the document layer,
  and the constructor calls it for each raw value. Before the change, check by a
  search of the source that no code builds a document with a referenced document
  on purpose. Test: a document built from
  a referenced document holds its document. Then `test_kernel()` and
  `test_platform()` against a baseline of main. A measurement of the build cost
  on the JSON benchmark, before and after, waits for an idle machine and the
  owner's word.
  - What was built: the generic `get_document` and its docstring are in
    `DocumentInterface.jl`, its fallback `get_document(x) = x` in
    `DocumentDefaults.jl`, and `DocumentModule` exports it. `ReferencedDocument.jl`
    keeps the method of a referenced document, and `ReferenceModule` imports the
    generic and no longer exports it. The declaration of the assistant's names
    (`PaneProgram.jl`) names it under `DocumentModule`.
  - The generated constructor stores `get_document` of each raw value
    (`raw_value` in `_emit_autowrap_ctor`), and the generated setter stores
    `get_document` of its value: a write of a field is the other half of the same
    rule, so it is in this step too.
  - `_get_stored_value` of `ReferencedDocument.jl` did what `get_document` now
    does, so its four writes call `get_document` and the private function is gone.
    The field form of `replace_referenced_value!` calls `get_document` too.
  - The search of the source: every construction of a `ReferencedDocument` outside
    the reference layer is the answer of a verb, and none goes into a field;
    `open_page!` keeps only the reference.
  - Tests: `test_referenced_document` 61 of 61, with a document whose constructor,
    whose write and whose list field get a referenced document.
  - The comparison with main, in a worktree pinned to the branch point 3f8b6a126,
    one process at a time:

    | Suite | Main | Branch |
    | --- | --- | --- |
    | `test_kernel()` | 4875 | 4881 |
    | `test_platform()` | 165673, 7 broken | 165690, 7 broken |
    | `test_dataframes()` | 612 | 628 |
    | `test_application()` | 385, 2 broken | 385, 2 broken |
    | `test_referenced_document_editor()` | 109, 2 fail | 109, 2 fail |

    No fail or error is on one tree only. The more passes are the new
    assertions: 6 in the kernel, 17 in the table interface, 16 in the data frame
    table. The 2 failures of the referenced document editor are the known ones of
    main, in "a long file tab scrolls…".
- [x] **4. The text.** Done 2026-10-21. The worked examples of the paragraph, the
  field names in the first line of the display, and `find_pivot_part_rows`
  declared with a "Use it to" line, an example and a "See also" line. Test:
  `test_pivot()`, `test_assistant_documentation()` and `test_application()`.
  - The display names each zone with its field: `Rows (row_dimensions): region,
    country`, `Cells (cell_dimensions, cell_view)`, `Closed runs (collapsed)`.
  - The paragraph shows a pivot of the data of a tab, a value and its rows of the
    source, a move, a new and a removed measure, an aggregate, the totals, the
    cells as bar charts, a hidden value, bins, and the top 5 as one write of a
    new `PivotDimension`. A field name such as row_dimensions is written without
    backticks, because `test_assistant_documentation` asks that each name in
    backticks is a declared name.
  - "Which rows are behind this cell?" is `find_pivot_part_rows`, which answers
    the numbers of the rows in the source. Its two method docstrings became one
    docstring on the generic function.
  - Tests: `test_pivot` 354 of 354 (with a pivot of a tab of named tuples made
    through `execute_julia_code`, whose source is the plain vector),
    `test_assistant_documentation` 374 of 374, `test_assistant_verbs` 56 of 56.
    `test_application()` runs with the comparison of step 3.
- [ ] **5. The rehearsal after, and the documents.** Run seeds 1 to 5 of the six
  tasks again, and record the counts beside the baseline. Update
  [pivot.md](../../documentation/package/domain/pivot/pivot.md),
  [collection.md](../../documentation/package/platform/collection/collection.md)
  and [reference.md](../../documentation/package/kernel/reference.md).
  - The documents are done, 2026-10-21: the three above, and `document.md` and
    `macros.md` of the kernel, which list the generic functions of a document and
    what the constructor and the setter do with a raw value.
  - The rehearsal waits for memory. With the model loaded, the machine keeps
    about 9 GB free beside the other sessions, and a run needs 13 GB; two
    attempts ran 2 of 30 runs each. Both of the two baseline runs of "make" on
    main failed: "no new pivot in a tab" (seeds 1 and 2 of the second attempt).

## Not in this plan

The rank of `make_pivot_table` in `search_api("pivot")`; `print_natural_text` and
`print_pred_text` of a pivot; P1 to P5 of the next steps of the pivot.
