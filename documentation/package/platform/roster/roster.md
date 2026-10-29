# Roster

> **Kind:** design · **Status:** current · **Stands on:** [cell.md](../../kernel/cell.md), [collection.md](../collection/collection.md), [natural.md](../natural/natural.md), [pane.md](../pane/pane.md), [widget.md](../widget/widget.md)

The roster slice of `ProjecturedPlatform` shows the members of one kind, gathered from anywhere in a window or a session, as a table: the files with edits, the documents of each type, the errors of the log. This document says how the rows of a roster follow their items at the cost of what changed, how a slice adds a source and a key, and how code and the assistant make a roster.

## How it works

A `Roster` holds a **source**, the **columns**, a **title**, the **rows** and a **link**. The source says where the items come from. Each column is a key, which names one value of an item. The rows are one `CellVector{RosterRow}`, and each row holds its item. The link is the document of the window that shows the roster, which a source reads, such as the tabs of the window.

```julia
roster = Roster(TabDocuments(FileDocument); columns = ["name", "folder", "has_edits"], title = "Files")
link_roster!(roster, editor.document)
[row.values[1] for row in roster.rows]       # the names of the files of the tabs
```

A roster with no link has no rows. A window links a roster when it shows it, with `show_roster!`. No document holds the editor, and the link is the document of the window, not the editor.

**The parts of a source.** A source gives its items in parts, through two generics: `collect_roster_parts(source, link)` gives the parts, such as the tabs of a window, and `collect_roster_items(source, link, part)` gives the items of one part, each as a `RosterItem(item, within)`. The roster keeps one computed cell for the items of each part, by the identity of the part. So an edit inside one file gathers the items of that file again, and of no other file. `collect_roster_parts` must read only what says which parts exist, such as the tabs, and not what is inside a part.

**The inside of an item.** A source that finds items inside items answers `get_roster_item_inside(source, entry)`: the inside of the item of `entry` as a part of its own. The roster keeps one computed cell for the inside of each item, by the identity of the item, and the search of a part stops at each item that it finds and reads nothing inside it (`walk_document(...; enter_matches = false)`). So the start of one task in a group of 22,731 tasks walks the inside of that one task, and not the group. `ItemsWithin` answers it; the default is `nothing`.

**Where a search goes.** `ItemsWithin(source, type; descend, enter_field)` holds the two functions of `walk_document` of the same names, and gives them to each search of a part and of an inside. `enter_field(parent, name)` decides before the walk reads a field, so a refused field is not read and a computed field is not computed. A search for tasks passes `is_task_search_field` of the task slice: from a task it reads only the inner group, and from a group only its tasks and its preparation. Without it, the search of the inside of each task walks the value of the task, so 22,731 tasks that name one large project walk that project 22,731 times. A file writes the functions by their names.

**One row for each item.** The roster keeps the row of each item, by the identity of the item, so a row whose item stays keeps its cells when other items come or go. An item that two parts give is one row. A row holds one computed cell for each column, which `compute_roster_value` computes. A value cell reads only what its key reads of its item, so a change of one item computes the cells of its row and of no other row.

**The place of an item.** A source gives each item with its place, when it knows it: `RosterItem(item, within, place)`, where `place` is the path of the item from the link. `CollectionItems` of a reference knows the index of each item while it walks the collection, so it gives `<reference>[j]`, such as `files[2]`. The other sources give `nothing`. The roster keeps the places where it computes its rows: its computed field `index`, a `RosterIndex`, holds the place of each item and the index of its row, by the identity of the item. It computes again after the rows do, when a reader reads it. `get_roster_item_place(roster, k)` answers the place of the item of row `k`, and `find_roster_row(roster, item)` the index of the row of an item. Neither searches. When an item before an item goes out, the part gathers again, so that item gets its new place, and its row stays the same object.

**A roster that a page holds.** A page that keeps a roster of its own collection in a field, alone or in an arrangement, with the page as the link, opens the item of a row at its place. `find_held_item_path(holder, step, path)` maps `table.document.rows[k].item.<rest>` to the place of the item of row `k` with the rest after it. `retarget_held_row_open(operation, holder, step)` retargets each open of a page in an answer whose path reaches an item through a row, and the reader of the page calls it. So the open of a row, by its link or by a double click, names the place of the item, and the address of the page of the item names its place, not the arrangement, the roster and the row. The page of the open files and the page of the log of the background work open their rows so.

The selection of a row stays the path of the row. Each document on the path of the selection holds its part of the path, and the printers of the table read the selection of their own documents, so a selection at the place of the item would reach no row of the table, and the table would show no selected row.

**The table.** `RosterToGraphics` prints the rows through the recursion of the renderer at the path `rows`. So an entry of an arrangement at `rows` puts a filter, a sort, a group or the first items before the printer of the rows, as at any collection, and the bar shows the chips. A pick of a filter or a sort keeps the element type of a `CellVector`, so the picked rows are a `CellVector{RosterRow}` too, and `RosterRowsToWidget` prints them as a `WidgetTable`: a header with the key of each column, and one row of cells for each row. While a key of a filter or a sort is a provisional value, such as a value that a task still reads, the pick keeps its last final rows that still name items of the input, so the table keeps its order until the sort is final.

**A table with a height.** Where the context gives the rows an exact height, as a tab does, the body of the table is a list of the rows from the row at its head (`_RosterTableView.anchor`), built with `make_index_list`. The table builds only the rows that it shows, fills the height and scrolls its rows. The cells of a row are the same object while the row stays, so the grid of the list keeps the print of a row that a filter or a sort keeps. Every column takes an equal share of the width, and the width of its header at least, because a table of a list measures no cell for a column. A row is as tall as its cells. Where no height is given, as in a print with no window, the body is a vector of every row, and a column is as wide as its widest cell. A filter that keeps no row gives a body of `nothing`, a list with no rows.

When the table moves its head more than 200 rows from the head, it writes `cells`. The roster turns that write into a write of `anchor`, and it drops the shift of the selection, because the selection of the rows names a row of `rows` and the maps place it from the anchor.

**A page from a row.** A double click on a row opens its item as a page. The first press selects the item, as a single click does. The second press adds `OpenPageOperation(nothing, <path of the item>)` to the answer, so the nearest navigator shows the item as a page and Back returns to the table. The page is the page of the type of the item: a row of the `:tasks` source opens the page of the task ([task.md](../task/task.md)). With no navigator around the table, the editor opens a new tab with a navigator ([navigator.md](../navigator/navigator.md)). `RosterRowsToWidget` makes this answer in its own `read_intent`, the reader that also answers an operation that a route brings to a row. A press with a modifier key, and a press on a cell that holds a document, do not open a page. The roster slice does not name the navigator, because the operation is a type of the widget slice.

**The first cell is a link.** When the value of the first column of a row is not a document, its cell is a link, as a name on the page of a folder is: a click opens the item of the row, and Ctrl and a click open it in a new tab. The link is a `WidgetLink(content, EmptyReference())` ([widget.md](../widget/widget.md)), so a middle click opens it in a new tab too, and its text follows the value. Its open names the part itself, and `RosterRowsToWidget` maps the path of a cell that holds no document to the item of the row, so a click on the link opens the same page as a double click on the row. So a link opens on one click, and a row on a double click, as everywhere in the platform. A right click on the link opens the menu of the row. The part under the pointer in a cell of text is the item of the row and, below it, the cell as a part that the rows draw, `rows[k].item‹[c]›` ([mouse-target.md](../../kernel/mouse-target.md#the-innermost-part)). So the item stays the document under the pointer, the table lights the row, and each cell that the rows make reads its part from the mouse target of its row: the link of the first cell draws its line.

A cell whose value is a document shows that document, the same object as in its item, also in the first column. So a key in that cell edits the item through the reader of the document, and the history of the window records the edit. Any other cell whose value is not a document shows a label of its text. A press on a label selects the item of the row, so the context menu is the menu of the item. A label takes no key: no widget writes a field of a target as text. In a navigator, the menu of a row has Open as a page and Open in a new tab, and Ctrl+Return opens the selected item, at the place where the content holds it when its domain answers it ([navigator.md](../navigator/navigator.md)).

**A count where the roster is named.** A row of a tree, a tab or an item of an address bar that names a roster shows its icon and a pill with the count of its rows (`get_document_decoration`). An arrangement around a roster counts the rows that it shows, the number of "1 of 18" in its bar. The pill takes the colour that all the counted items share: a row says what its item says, and `find_shared_decoration_tint` answers the tint that every item has, or none. So a view of the tasks that failed is red, a view of the tasks that run is blue, and a roster of files is quiet. A roster with no rows, and an arrangement that shows none, show no count.

The count runs the search of the source when the name is drawn first and when a part changes. The search walks the documents of the parts, and it stops at what is no document, such as the scheduler and the processes of a group of tasks (`is_walk_opaque`). A walk into the closure of a scheduler would reach the window that draws the name, and the cell of the name would read itself.

**A file.** A file that keeps a tab with a roster saves its source, its columns and its title (`pred_arguments`), and no row and no link. The sources `CollectionItems`, `ItemsWithin`, `StoreRecords` and `TabDocuments` say that a file can build them (`is_pred_constructible`).

## Sources

| Source | Its items | Its parts |
| --- | --- | --- |
| `TabDocuments(type)` | the documents of `type` that the tabs of the window show: the first layer of the content of a tab that is a `type`, from the outside inward | one part for each tab |
| `CollectionItems(collection)` | the items of a collection inside a document, given by a `Reference` from the document of the window, each with its place `<reference>[j]`, or as the collection itself, with no place | one part |
| `ItemsWithin(source, type)` | the documents of `type` inside each item of `source`, at any depth, each with the item that holds it as `within` | one part for each item of `source`, and one for the inside of each document that it finds |
| `StoreRecords(name)` | the records of a store of the session that a slice registers under `name` | the parts of the source of the store |
| `SystemProcesses(tree)` | every process of a `SystemProcessTree`, a parent before its children, each with its parent as `within` ([systemprocess.md](../systemprocess/systemprocess.md)) | one part, the tree |

The slice of a kind of item adds its own source, as `SystemProcesses` shows. The slices that own the stores register them in their `__init__`, with `register_roster_source!(name, link -> source; description)`:

| Name | Records |
| --- | --- |
| `:faults` | the lines of the fault log of the session |
| `:log` | the lines of the message log of the session: `level` and `message` |
| `:mcp_log` | the calls of the MCP log of the session |
| `:tasks` | the tasks of the open groups of the session of the editor, each with its group as `within` |
| `:frames` | the recent frames of the session: `frame`, and the time of each measurement in seconds |

The frames are a named tuple for each frame of the series of frame times. The part of the frames reads `names` of the series, which is the probe of the frame statistics feed for a view. So the series flushes while a roster shows the frames, and only then.

`describe_roster_sources()` lists the kinds of sources that the loaded slices give, from the methods of `collect_roster_parts`, and the names of the stores.

## Keys and facets

A key is names with dots between them:

- A first name that is a **facet** of the type of the item names the value of the facet, and the names after it a path of fields inside that value.
- `within` names the item of the outer source, and the names after it a key of that item, so `"within.name"` is the name of the file of a call.
- Any other key is a path of fields inside the item, as for `filter_collection!`.

A facet is a value of an item that the slice of its type computes. A slice declares the facets of a type with a method of `get_item_facets` for that exact type, and gives each value with a method of `compute_item_facet`. `collect_item_facets(type)` reads the facets of the type and of each of its supertypes. A field of the type of the item wins over a facet of the same name that a supertype declares. A facet that a type declares with the name of one of its own fields is an `ArgumentError`.

| Type | Facets |
| --- | --- |
| `Document` | `type`: the name of the type of the document that a person sees, through the layers that wrap it |
| `FileDocument` | `name`, `folder`, `has_edits`: whether the history of the file has a step that the file does not hold, and `state`: the words of its conditions, such as "unsaved edits" or "read only" |
| `FilePage` | `name`, `folder` and `has_edits` of its file, and `state`: the words of the conditions of the page, which also says "changed on disk" and the conflict ([fileformat.md](../fileformat/fileformat.md)) |
| `Assistant` | `title`, `turn`, `tokens`, `plan` (the completed steps over all the steps of its first plan with steps, such as `3/7`), `subagents` and `background_tasks` (how many run) |
| `AgentWork` | `tokens` |
| `SystemProcess` | `load`, `elapsed` |
| `WorkPlanStep` | `blocked` |
| `TaskDocument` | `name`: the task in one line, as the list of tasks writes it; `status`: the status of its current execution; `result`: the code of the result of that execution; `expected`: whether that result is the expected one; and `reason`: why the result is what it is. The last three are `nothing` before the execution ends |
| `TaskGroupDocument` | `kind`: the name of the group, which the list of groups shows as its kind |

A row of `StoreRecords(:tasks)` is a task within its group, so `within.kind` filters the tasks by the kind of their group, and `within.title` names the group: `filter = ["within.kind" => ==("fingerprint test")]` keeps the tasks of the fingerprint tests of the session.

`has_edits` reads the history that a file keeps in its `content`. An `UndoBuffer` keeps `saved_entry`, the step that was newest at the last save, which `SaveFileOperation` records through `record_saved_state!`. `has_unsaved_edits` compares it with the newest step. A key press reads no text of the file. A file that keeps no history answers `nothing`.

In a filter, a sort and a group, a key of a row reads the value cell of its column, through `find_arrangement_key_value`. A domain whose documents are values adds a method of `get_arrangement_value`, so a condition compares the value: the Julia domain compares an identifier by its name.

## The verbs of code and of the assistant

```julia
roster = show_roster!(TabDocuments(FileDocument); title = "Files with edits",
                      columns = ["name", "folder", "has_edits"],
                      filter = ["has_edits" => ==(true)], sort = ["name"])
sort_collection!(roster, "folder")
edit_shown_items!(roster, "status" => "checked")
```

- `show_roster!` makes the roster, links it to the window, makes the entry of its arrangement from the keywords with `make_arrangement_entry`, and shows it in a tab. It makes the entry itself, because a verb of the arrangement reads the IO map that the last frame printed, and the new tab is not in it yet.
- It answers the roster in its window, as a `ReferencedDocument`. Its `show` prints `describe_roster`: the title, how many rows show of all, the parts of the arrangement, the columns and the first 20 rows. The summary reads the arrangement through the link of the roster, so it needs no editor.
- The verbs of the arrangement take the roster for its rows, through `get_arranged_collection_steps(::Roster)`.
- `edit_shown_items!` gives one value to the key of the item of each row that the roster shows, as one `CompoundOperation`. `find_rooted_operation` carries it through the readers, so the history records it as one step. With a group in the arrangement of the roster, the call throws an `ArgumentError`.
- `describe_item_facets(type_or_source)` lists the keys of the items.

`make_editor_api` declares these verbs, `TabDocuments` and the three other sources for the assistant of every window, and `EDITOR_SYSTEM` names them.

## The cost of a change

The cell engine computes only what a change invalidated and what the screen reads. A change of one item computes the value cells of its row, and a part that changed walks its own item again, and no other part. Three things set the cost of a change that the table shows:

- **A value of text.** It has a cell that holds its label, and only the text of the label reads the value. So a new value draws its label again, and no other cell of the table.
- **The grid of the table.** It holds the heights of all rows in one cell and the widths of all columns in another. A label that draws again keeps its size when its text keeps its width, and a computation that gives the plain value that it had stops the walk there: the grid places nothing again. A label that changes its size makes the grid place again the rows below it, or the columns after it.
- **A new list of rows.** A change that a filter or a sort sees makes a new list of rows. A table with no height prints every row again, at about 44 computations for each row. A table with a height keeps the print of a row that stays, as the paragraph above says.

A change that gives a value that a reader already has costs nothing more when it is plain data, by a write or by a computation. The undo buffer writes `has_unsaved_edits`, so a key in a file that has edits invalidates no row.

A table with a height keeps the print of a row that a new list of rows keeps. The cost was measured per step with 50 files and a filter that a save moves file 1 in or out of, in a window, on 2026-10-15. A change then costs about 1572 computations, where a print of the whole table again costs about 2179. A save moves every row after file 1, so the path of each of those rows computes again, and the dispatch of each cell chooses again. The same choice stops at the dispatch: the IO map of the cell, its output and their readers stay. On an idle machine on 2026-10-16, the median time of such a step is about 9.4 ms, where a print of the whole table again takes about 32 ms. A table with no height takes about 16 ms for the same step, where it took about 24 ms.

The measure of [kept-children.md](../../../../plan/done/kept-children.md), on 2026-10-17, counts the same step with a newer probe: about 1650 computations and a median of about 10.2 ms, where they were about 2290 and 11.5 ms before a row that moves kept its IO maps and its output. A filter of a data frame of 10,000 rows in a window takes about 7.4 ms, where it took about 22 ms before the view kept its rows. Inside a pane every path is a computation, because the panes have a cell of their index, so a fresh print there makes a cell for each path and two for each dispatch by path: the roster of the calls of one function, grouped by file, prints its table again on each change, at about 835 computations where it took 731, and about 5.2 ms where it took 5.1 ms.

The counters measured this on a headless window, with the walk of the paint counted, for each step after the first:

| | rows | reads | computes |
| --- | --- | --- | --- |
| 50 files, a key in one file, no roster | 0 | 2833 | 16 |
| the same, with the roster of the files with edits | 50 | 3910 | 18 |
| 50 files with edits, a save of one file, with the same roster | 50 | 53057 | 2212 |
| 200 files, the edits of one file change, with a roster with no filter | 200 | 15974 | 8 |
| a change of one call, no roster | 0 | 149 | 0 |
| the same, with the roster of the calls of one function, grouped by file | 571 | 33047 | 737 |

The plan in [roster-table-cost.md](../../../../plan/done/roster-table-cost.md) holds the probe that found these causes, and [computed-cell-stop-measure.md](../../../../plan/done/computed-cell-stop-measure.md) the measure of the stop of a computed cell.

## Limits

- The table builds a row of widgets for each row of the roster. A table with no height, as in a print with no window, builds every row, and a roster of more than about 1000 rows is slow there. A table with a height builds only the rows that it shows.
- A file can not keep an arrangement: an entry holds a `Reference`, and the pred notation can not write a kernel `Reference`. A `CollectionItems` with a `Reference` can not be saved for the same reason.
- A source can not join the items of two sources.
- A cell whose value is not a document takes no key.

## Layer structure

The slice is the folder [source/platform/roster/](../../../../source/platform/roster/), and `RosterModule` is its module. It loads after `natural`, and the slices that own a source, a store or a kind of item load after it.

```
roster/RosterModule.jl      (RosterModule): the module, its exports and its include order
    ├─ RosterInterface.jl   : the generics of a source and of a facet
    ├─ RosterDefaults.jl    : their fallback behaviours
    ├─ RosterDocument.jl    : Roster, RosterRow, RosterItem, the value of a key, the facets, the save
    ├─ RosterSource.jl      : CollectionItems, ItemsWithin, StoreRecords and the stores
    ├─ RosterToGraphics.jl  : the print of a roster and of its rows as a table
    └─ RosterProgram.jl     : the verbs of code and of the assistant
```

## Try it

```julia
using Projectured
runs = CellVector([...])                                    # any collection of records
roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"]), runs)
[collect(row.values) for row in roster.rows]
```

## Design decisions

The options, the examples and the steps are in [cross-cutting-views.md](../../../../plan/done/cross-cutting-views.md).
