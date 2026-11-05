# The assistant fills a live table

> **Kind:** plan · **Status:** a plan, written 2026-11-05. Nothing is built. · **Stands on:**
> [roster.md](../../documentation/package/platform/roster/roster.md),
> [operation.md](../../documentation/package/kernel/operation.md),
> [the-assistant-finds-its-names-by-reflection.md](the-assistant-finds-its-names-by-reflection.md),
> gap G5 of `inet-cpp/plan/pending/ieee80211-chart-baseline-evolution.md` §9.3

This plan closes gap G5. With it, the assistant of a window makes a table of its own records. It
adds a row while a long work runs and changes one value of a row later. The table survives a
restart of the window. The plan changes projectured-julia only. omnet-julia gets the names through
the mark `For the assistant.` and needs no change of code.

## 1. The goal

An investigation of about 5 hours runs in the window of `omnet_ide`. The assistant drives it, and
the person follows a ledger of the work. The ledger has one row for each measured commit. Its
columns are number, commit, subject, group, state, count of changed charts, a picture and a link to
the page of the event. The state of a row
changes later. The owner decided on 2026-11-05 to close G1, G3, G4, G5 and G9 first, each in its
own plan, and G8 after them.

When this plan is done:

1. The assistant makes a table of records with offered names only, and keeps it in a `.pred` file.
2. A new record is a new row at once. A change of one value makes a new row for that record only.
3. Each change is an operation: the history of the file records it, and Ctrl+Z takes it back.
4. A new window opens the file and shows the same rows.
5. The person filters, sorts and groups the rows in the bar and under the headers, as in a roster.

## 2. What exists

The rows were checked on main `6b93bfcf3` of projectured-julia and on main `a1dfa5af3` of omnet-julia
on 2026-11-05. The owner decided on 2026-11-05 that steps 1 to 4 of `reflection-api` land on main
first, and that this plan starts from main after that, with only the mark `For the assistant.` Steps
1 to 4 landed on main `2bbc18fb5` (omnet-julia `991a89b4f`) on 2026-11-05; both are in `origin/main`. On main, the
mark is the only way that a name of the editor reaches the assistant. `make_editor_api` reads the
marks of the loaded modules, and `register_assistant_api!` serves only the foreign packages of an
adapter and the sentence of a domain.

| Fact | Where |
|---|---|
| `show_roster!(source; title, columns, filter, sort, group, aggregates, first)` shows a roster in a tab and answers it as a part. | `source/platform/roster/RosterProgram.jl:5-51` |
| `CollectionItems(reference)` reads the collection in a computation and gives each item with its place `<reference>[j]`. A `CellVector` of plain values follows each insert and each slot write. | `RosterSource.jl:7-45` |
| The roster keeps one row for each item, by the identity of the item. Two equal plain values are one item. | `RosterDocument.jl:515-519` |
| The first column is a link that opens the item. An `ImageFile` value in a later column shows the picture, at most `table_picture_height` high (120 px by default). | `RosterToGraphics.jl:411-436`, `widget/WidgetTheme.jl:212` |
| A page can hold a roster of its own collection: `OpenFileList` keeps `files` and a `table` whose roster reads `files` through its link. Its reader keeps the arrangement and opens a row at its place. | `fileformat/OpenFileList.jl:28-31, 81-89`, `OpenFileListToWidget.jl:67-78` |
| `StoreRecords(name)` reads `_ROSTER_SOURCES`, a table of the process that a slice fills in its `__init__`. `register_roster_source!` is exported and has no mark. | `RosterSource.jl:148-235` |
| A write of a field of a plain immutable value copies the value and writes the copy into the slot above. The inverse puts the old value back. | `operation.md:104-111` |
| The pred notation prints and reads a named tuple. | `serialization/PredFile.jl:269-273, 431-442` |
| A read through a part answers a part for a document, a vector, a dictionary and a tuple. A named tuple comes back plain, so the field form of `replace_referenced_value!` can not take it. | `kernel/reference/ReferencedDocument.jl:114-117`, `pane/PaneProgram.jl:623-645` |
| A field step reads a field by `getfield`, or an entry of a dictionary. | `kernel/reference/ReferenceStep.jl:177-181, 192-193` |
| `insert_elements!` and `delete_elements!` are edits of the editor through `find_rooted_operation`. | `kernel/editor/DocumentEdits.jl:178-275` |
| `write_document_file` and `read_document_file` carry the mark. A `FilePage` that saves its own file ignores the change of the disk that its save makes. | `fileformat/DocumentFile.jl:48-103`, `FilePage.jl:223-249, 324-327` |
| Only `run_application` keeps the explorer content in a file. The campaign window of `omnet_ide` does not. | `application/Application.jl:595-606`, omnet-julia `ide/CampaignWindow.jl:302` |
| Code of `execute_julia_code` resolves only the names that the marks offer. On main `CellVector` has the mark, and `@document` has none. | `kernel/tool/CodeExecution.jl:185-229`, `collection/CellVector.jl:28`, `kernel/document/DocumentMacro.jl:738` |
| `RefreshDataFrameViewOperation` refreshes a data frame view after a change in place. The edits of a data frame are reached only by its context menu. | `adapter/dataframes/DataFrameRefresh.jl:102`, reflection plan, step 3 notes |
| Main has `open_file!(path)`, which opens a file with its history and takes no focus, `save_file_to_disk!(tab)`, `find_open_file_document(path)`, `make_change`, `apply_change!` and `get_stored_value`. The first five carry the mark. | `filesystem/FileSystemDocument.jl:229-259`, `fileformat/FilePage.jl:223-249`, `fileformat/OpenFileList.jl:109`, `kernel/editor/DocumentEdits.jl:81, 163`, `kernel/document/DocumentMacro.jl:331` |

No file that this plan changes is sealed. `SEALING.md` seals only files of `source/kernel/` in the
layers fault, performance, cell, struct and clock. `CellVector` is in `source/platform/collection/`,
and `kernel/document/DocumentMacro.jl` and `kernel/reference/ReferencedDocument.jl` are not sealed.

## 3. The gap

- No document holds records that the assistant writes and shows them as a table. A roster shows
  the items of other places.
- A record of the assistant can not be a `@document` type. The scratch module does not resolve
  `@document`. A type that the assistant defines lives in the scratch module of one process. So a
  `.pred` file that names it does not read after a restart. A new type also moves the world age
  under the loop of the editor, and a renderer builds its dispatch table once. These facts come
  from the code and the notes, and no run checked them.
- The assistant can not change one value of a named tuple record, because a read of the row
  answers no part.
- `StoreRecords` can not hold records of the assistant. A store is code of a slice in a table of
  the process, and a registration by the assistant is global state.

## 4. The design

Proposed by the assistant. §5 gives the reason of each part.

**A table of records is a document, `RecordTable`.** Its fields are `title`, `columns`, `records`
and `table`. `records` is a `CellVector` with one plain cell for each record. `table` is an
arrangement around `Roster(CollectionItems(@reference(records)); columns, title)`, and the link of
the roster is the record table itself, as in `OpenFileList`. So the record table has every part of
a roster: the bar, the filters under the headers, the sort and the group. It also has the link of
the first column, the open of a row and the picture cell. A file keeps the title, the columns and the records.

**A record is a named tuple, or any document**, for example
`(number = 12, commit = "fd436d7", state = "waiting", changed_charts = 0)`. A key of a column
names a field, as a key of any roster does.

**A named tuple is a part, as a tuple is.** `ledger.records[7]` answers a part with the path
`records[7]`. So `replace_referenced_value!(ledger.records[7], :state, "equal")` writes the field.
The write copies the named tuple into its slot, and the roster makes a new row for it.

**The file is the store, and its page saves it.** The flow of the assistant:

```julia
path = joinpath(folder, "measured-commits.pred")
write_document_file(RecordTable("Measured commits"; columns = ["number", "commit", "subject",
                    "group", "state", "changed_charts", "picture", "event"]), path)
tab = open_file!(path)
show_pane!(tab)
ledger = get_edited_document(tab)
insert_elements!(ledger.records, length(ledger.records) + 1,
                 [(number = 1, commit = "fd436d7", subject = "…", group = "A", state = "waiting",
                   changed_charts = 0, picture = nothing, event = nothing)])
replace_referenced_value!(ledger.records[1], :state, "equal")
save_file_to_disk!(tab)
sort_collection!(ledger, "number")
```

After a restart, `open_file!(path)` shows the same rows. The assistant applies the sort again,
because a file does not keep an arrangement.

**Where G5 meets G3.** G3 gives a picture as a document. A record that holds an `ImageFile` in a
column after the first shows it as a thumbnail, with no change of this plan. The owner decided on
2026-11-05 that a picture is a file document that a person does not edit (G3 D1, model B), and that
a `.pred` file saved alone writes `file("…")` for it. Another plan, a file saved alone names the
files that it holds, makes that save work. G5 depends on it for a record with a picture. Until it
lands, the column `picture` holds a path as text.

**Where G5 meets G6.** Only the first column of a roster is a link, and it opens the record. A cell
whose value is a document shows that document. G6 can give a link value that names a document
or a file. A record then holds it in the column `event`, with no change of this plan.

## 5. Decisions

The owner decided D2, D3, D4 and D5 on 2026-11-05. The assistant proposed D1, D6 and D7.
A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. One document holds the records and their table.** Rejected: two tabs, a `.pred` file of a
  `CellVector` and `show_roster!` over a reference to it. A roster over a reference can not be
  saved (roster.md, Limits), and the person sees the raw list beside the table.
- **D2. A record is a named tuple.** The owner decided D2 and D3 on 2026-11-05 (option A). The kernel already treats a named tuple as the plain record.
  Write rule 3 copies it, and the pred notation keeps it. The table interface reads a vector of
  them, and the store `:frames` gives them to a roster. Rejected: a generic record document with fields
  by name. It needs a new kind of field step in the kernel, because a field step reads by
  `getfield`. Rejected: a `@document` type of the assistant, for the reasons of §3.
- **D3. A named tuple is a part.** `_is_referenced_value` answers `true` for a `NamedTuple`, and
  `get_stored_value` stores the document of each field of a named tuple. So the field form of
  `replace_referenced_value!` takes a record, and no verb is added. Rejected: a verb of its own,
  such as `change_record!`, because the verbs combine.
- **D4. The file is the store, and `save_file_to_disk!` saves it.** The owner decided on 2026-11-05
  (open question 5, option A) that the assistant saves after each change, as a person presses
  Ctrl+S. Rejected: a save by the editor of every file page after each edit, which is a general
  feature for its own plan, and a `RecordTable` that saves itself, which is a special case of it. A page knows the hash of what
  it saved, so its own save shows no band "changed on disk". The person can edit and save the
  file too. Rejected: a plain tab that `write_document_file` copies to disk after each change. The
  tab and the file are then two copies with no link, and nobody can tell which is newer. Rejected:
  an entry of the explorer, because `omnet_ide` does not save the explorer content. Rejected: a
  data frame, whose edits the assistant can not make as operations, and whose view needs a
  refresh of the whole frame. Rejected: `StoreRecords`, for the reason of §3.
- **D5. The type lives in the roster slice** (decided by the owner on 2026-11-05, with the name
  `RecordTable`), in two new files, `RecordTable.jl` and
  `RecordTableToWidget.jl`. The slice already uses the arrangement, collection, serialization and
  widget slices, so no dependency rule changes. Rejected: a new slice, which needs a gate and holds
  only two files.
- **D6. The names reach the assistant by the mark.** The docstring of `RecordTable` ends with the
  line "For the assistant.", and the mark offers its type. Every other name of the flow carries the
  mark on main: `open_file!`, `save_file_to_disk!`, `show_pane!`, `get_edited_document`,
  `insert_elements!`, `replace_referenced_value!`, `sort_collection!`, `filter_collection!` and
  `write_document_file`. No list names `RecordTable`.
- **D7. This plan starts from main after steps 1 to 4 of the reflection plan.** They landed as
  `2bbc18fb5`. Main has the mark as its only rule for a name, the two file verbs and
  `get_stored_value`. It also holds the `ReferencedDocument.jl` that D3 widens, so this plan has no
  conflict with the branch.

## 6. Steps

Each step is one commit in a worktree of projectured-julia, on main.

1. **A named tuple is a part.** Widen `_is_referenced_value` in `ReferencedDocument.jl` and
   `get_stored_value` in `DocumentMacro.jl`. The code tool shows a part of a named tuple as the
   tuple. Tests: `test_referenced_document()` asserts the path `records[2]` of a read and the
   stored fields. `test_referenced_document_editor()` asserts that
   `replace_referenced_value!(records[2], :state, "equal")` replaces the record in its slot, and
   that one undo puts it back.
2. **The document `RecordTable`.** `RecordTable(title::AbstractString; columns, records = [])`, the
   held roster with its arrangement, `pred_arguments`, `make_pred_document`, `get_document_title`,
   `get_document_decoration` with the count of records, and `get_arranged_collection_steps`. The
   typed `title` keeps the constructor apart from those that `@document` makes. Test: a new
   `test_record_table()` in `test/platform/roster/RecordTableTest.jl`, included in
   `ProjecturedPlatformTest.jl` and `PlatformSuite.jl`. It asserts four facts. An insert adds one row. A
   field write changes one row and keeps the other rows as the same objects. A `.pred` file gives
   back the same title, columns and records. Two equal records show as one row.
3. **The view `RecordTableToWidget`.** A line that counts the records, and the table under it, which
   fills the height. Its maps pass `table.<rest>`. Its reader calls `keep_held_arrangement` and
   `retarget_held_row_open`. `_make_roster_graphics_entries` registers it. Test: `test_record_table()`
   in a headless window. The header shows the labels of the columns, and an `ImageFile` value shows
   a picture cell. A click on the first cell opens `records[k]`.
   `filter_collection!(ledger, "state" => ==("event"))` keeps the rows of the events.
4. **The surface and the documents.** The docstring of `RecordTable` gets the full form, the example
   of §4 and the mark. `roster.md` gets a section on a table of records that a file keeps, and its
   layer structure lists the two files. Tests: `test_assistant_documentation()`,
   `test_referenced_document_editor()` for the rank of `search_api`, `test_documentation()` and
   `test_naming()`. In omnet-julia: `test_ide_documentation()`.
5. **The flow in a window.** A new case of `test_assistant_verbs()` in
   `test/projectured/editor/AssistantVerbsTest.jl` runs the code of §4 through `execute_julia_code`:
   three records, one changed state and one save. A second window opens the file and shows three
   rows with the changed state. Then a check by hand in `omnet_ide` through the internal MCP
   connection, on a copy of a project, with `take_picture` of the table.

## 7. Risks

- **D3 changes each read of a named tuple through a part.** Code that compares the answer with a
  named tuple, or tests `isa NamedTuple`, can break. `test_referenced_document_editor`,
  `test_assistant_verbs` and the verb tests of omnet-julia tell it.
- **Two equal records show as one row**, because the roster keys a row by the identity of its item.
  The docstring says that each record needs a field that no other record has, such as `number`.
- **A write of the open file from outside its page** makes the page show its band. The docstring
  says to save with `save_file_to_disk!`.
- **Ctrl+Z of the person** in the tab takes back the last record of the assistant, as it takes back
  any edit of the file.
- **A picture in a `.pred` file needs the save of a file alone.** G3 makes a picture a file
  document, and a `.pred` file saved alone writes `file("…")` for it. Another plan, a file saved
  alone names the files that it holds, makes that save work. Until it lands, the save of a record
  with an `ImageFile` can fail, and the tests of this plan use a path as text.
- **Each change gathers every record again**, because `CollectionItems` reads the whole collection.
  For 120 records the cost is small, and a table with a height builds only the rows that it shows.
- **omnet-julia records its precompile lists again** when the index of names changes, as §6 of the
  reflection plan says.

## 8. Open questions for the owner

1. Answered by the owner on 2026-11-05: yes, steps 1 to 4 land first. The question was: do steps
   1 to 3 of the reflection plan land first (D7, recommended)? The other way was a start
   of G5 on main before them, with an entry in a hand-kept list.
2. Answered by the owner on 2026-11-05: yes (D2). The question was: is a record a named tuple, with
   two equal records as one row (D2, recommended)? The other way is
   a later plan that keys the rows of plain items by their slot.
3. Answered by the owner on 2026-11-05: yes (D3). The question was: is a named tuple a part, as a
   tuple is (D3, recommended)? It is a change of a read rule of the
   kernel.
4. Answered by the owner on 2026-11-05: yes (D5). The question was: is `RecordTable` the right name,
   and the roster slice the right place (D5, recommended)?
5. Answered by the owner on 2026-11-05: yes, the assistant saves after each change (D4). The
   question was: does the assistant save after each change (D4, recommended)? A table that saves itself after each
   operation is a new mechanism, so this plan does not propose it.
