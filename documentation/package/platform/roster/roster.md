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

**One row for each item.** The roster keeps the row of each item, by the identity of the item, so a row whose item stays keeps its cells when other items come or go. An item that two parts give is one row. A row holds one computed cell for each column, which `compute_roster_value` computes. A value cell reads only what its key reads of its item, so a change of one item computes the cells of its row and of no other row.

**The table.** `RosterToGraphics` prints the rows through the recursion of the renderer at the path `rows`. So an entry of an arrangement at `rows` puts a filter, a sort, a group or the first items before the printer of the rows, as at any collection, and the bar shows the chips. A pick of a filter or a sort keeps the element type of a `CellVector`, so the picked rows are a `CellVector{RosterRow}` too, and `RosterRowsToWidget` prints them as a `WidgetTable`: a header with the key of each column, and one row of cells for each row.

A cell whose value is a document shows that document, the same object as in its item. So a key in that cell edits the item through the reader of the document, and the history of the window records the edit. A cell whose value is not a document shows a label of its text. A press on a label selects the item of the row, so the context menu is the menu of the item. A label takes no key: no widget writes a field of a target as text.

**A file.** A file that keeps a tab with a roster saves its source, its columns and its title (`pred_arguments`), and no row and no link. The sources `CollectionItems`, `ItemsWithin`, `StoreRecords` and `TabDocuments` say that a file can build them (`is_pred_constructible`).

## Sources

| Source | Its items | Its parts |
| --- | --- | --- |
| `TabDocuments(type)` | the documents of `type` that the tabs of the window show: the first layer of the content of a tab that is a `type`, from the outside inward | one part for each tab |
| `CollectionItems(collection)` | the items of a collection inside a document, given by a `Reference` from the document of the window, or as the collection itself | one part |
| `ItemsWithin(source, type)` | the documents of `type` inside each item of `source`, at any depth, each with the item that holds it as `within` | one part for each item of `source` |
| `StoreRecords(name)` | the records of a store of the session that a slice registers under `name` | the parts of the source of the store |

The slices that own the stores register them in their `__init__`, with `register_roster_source!(name, link -> source; description)`:

| Name | Records |
| --- | --- |
| `:faults` | the lines of the fault log of the session |
| `:log` | the lines of the message log of the session: `level` and `message` |
| `:mcp_log` | the calls of the MCP log of the session |
| `:tasks` | the tasks of the groups of the session, each with its group as `within` |
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
| `FileDocument` | `name`, `folder`, and `has_edits`: whether the history of the file has a step that the file does not hold |
| `Assistant` | `title`, `turn`, `tokens` |

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

`make_application_api` declares these verbs, `TabDocuments` and the three other sources for the assistant of the application, and its system text names them.

## The cost of a change

The cell engine computes only what a change invalidated and what the screen reads. So a change of one item computes the value cells of its row, and a part that changed walks its own item again, and no other part. A step of the arrangement reads all rows again when one of its inputs changes. A row that did not change is a cell that is up to date, but the pick makes a new slot for each row that it keeps, and the table then lays out every row again.

The counters measured this on a headless window, with the walk of the paint counted, for each step after the first:

| | rows | reads | computes |
| --- | --- | --- | --- |
| 50 files, a key in one file, no roster | 0 | 2827 | 16 |
| the same, with the roster of the files with edits | 50 | 10678 | 360 |
| a change of one call, no roster | 0 | 149 | 0 |
| the same, with the roster of the calls of one function, grouped by file | 571 | 32836 | 732 |

So a roster on the screen costs about 7 computations for each row at each change that reaches its filter, also when the value that the filter reads does not change: a key in a file writes the newest step of its history, and `has_edits` computes again. The plan in [cross-cutting-views.md](../../../../plan/pending/cross-cutting-views.md) names what can lower it.

## Limits

- The table builds a row of widgets for each row of the roster. A roster of more than about 1000 rows needs the lazy rows that a table of a list has, which the roster table does not use yet.
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

The options, the examples and the steps are in [cross-cutting-views.md](../../../../plan/pending/cross-cutting-views.md).
