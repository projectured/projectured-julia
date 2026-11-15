# Architecture review: Collections — lists, tables, trees, rosters, arrangement

Commit 3a9b4fae4. Reviewer area key: collections.

## Scope

Paths: `source/platform/{collection,arrangement,roster,tree,outline,inspector,explorer}`, the table, list and tree code of `source/platform/widget`, `source/adapter/dataframes`, `source/domain/pivot`, `source/domain/dbcatalog`, `source/platform/pane/PaneRoster.jl`, and the users of the roster in other slices.

Read in full (about 5,800 lines):

- Documents: `concepts.md`, `architecture-decisions.md`, and the package documents of collection, roster, tree and outline.
- Collection: `ListNode.jl`, `TableInterface.jl`, `CellTable.jl`, `CollectionModule.jl`, `CollectionDocument.jl`.
- Arrangement: `ArrangementModule.jl`, `ArrangementDocument.jl`, `Arranging.jl`, `ArrangeCollectionOperation.jl`, `Grouping.jl`, `ArrangementBar.jl`.
- Roster: `RosterDocument.jl`, `RosterToGraphics.jl`, `RosterSource.jl`, `RecordTable.jl`, `RecordTableToWidget.jl`.
- Widget: `ObjectToWidget.jl`, `ObjectFieldToWidget.jl`, `CellTableToWidgetTable.jl`.
- Others: `OpenFileListToWidget.jl`, `PaneArrangement.jl`, `PaneRoster.jl`, `ExplorerFilter.jl`, `ExplorerSearchToWidget.jl`, `PivotPartTableToWidget.jl`, `DbCatalogDocument.jl`.
- Plans: `an-insert-moves-the-paths-after-it.md`, `pivot-table-next-steps.md`.

Sampled (about 4,500 lines, by section or by grep with the lines around a hit):

- `WidgetDocument.jl` (the list, table and tree types, lines 390–490 and 3000–3670), `WidgetTableParts.jl` (head, the wheel and the readers), `WidgetToGraphics.jl` (the table section head, its printer and its reader, the list printer), `WidgetChoiceList.jl` (head), `WidgetTableHeaderLevels.jl` (outline only).
- `DocumentTreeToWidgetTree.jl` (lines 1–330), `CellVector.jl` (outline), `CellMatrix.jl` (head).
- `DataFrameView.jl` (head), the other data frame files by outline; the pivot files by grep.
- The pages that hold a roster, the hand-made tables, the log views, `FileSystemToWidget.jl`, `ReflectionToWidget.jl`, `OutlinePaths.jl` by grep and short reads.
- Plans: the heads of `filter-sort-and-find-any-table.md` (lines 1–330 and the steps), `the-header-of-a-table-filters-and-sorts-its-arrangement.md`, `the-assistant-fills-a-live-table.md`, `catalog-all-documents.md`, `views-compose-as-content-composes.md`, and of the done plans `one-table-widget.md`, `a-view-document-keeps-the-state-of-one-view.md`, `the-explorer-shows-what-the-editor-holds.md`.

Not read: `Picking.jl`, `Finding.jl`, `ArrangementProgram.jl`, `ArrangementMenu.jl`, `FilterLanguage.jl`, `KeptListPrints.jl`, most of the pivot and the data frame printers, `Dashboard*.jl`, `OutlineRow.jl`, `DbCatalogToSyntax.jl`. No Julia was run.

## State

The area has three sound generic mechanisms. The arrangement is one way to filter, sort, group and find any collection: its parts are documents, and a dispatch puts them in front of the printer of a place. The roster is one way to show items with fields as a table, with a cost of what changed. The tree slice shows any document as a node through four generic functions. The lazy list (`ListNode`) with its three builders is used by every table that builds only the rows in view.

The main weakness is at the seams between these mechanisms and their users. A view that wants a table of its own collection can not ask for one in one line. It stores a roster and an arrangement in a field of its content document and repeats about 80 lines of wiring; seven documents do so. Many other views still draw their rows by hand, so they get no filter, no sort and no lazy rows. The table widget is one type with two full implementations, and features differ between them. Four projections print a tree, each with its own way to list children and to keep the open nodes. The filter of a tree is a mechanism of the explorer alone.

A second weakness is the model of a list and of a record. A list has two types with no shared protocol, so each view that can be lazy has a second code path. A row with named columns has three types and three ways to read a column. These two facts are the root of several of the findings below.

## Inventory

### A. Views that show many items

"Arrangement" means the filter, sort, group and find of the arrangement slice. "n.c." means not checked.

| View | Data source | Printer of a row or a cell | Builds only the rows in view | Filter, sort, find | Built on |
| --- | --- | --- | --- | --- | --- |
| Roster table | `CellVector{RosterRow}` that a `Roster` computes | `RosterRowsToWidget`, a cell by `make_roster_cell` | yes with a height or an edge, else every row ([RosterToGraphics.jl:185](../../../source/platform/roster/RosterToGraphics.jl#L185)) | arrangement, with header fields ([RosterToGraphics.jl:178](../../../source/platform/roster/RosterToGraphics.jl#L178)) | `WidgetTable` |
| `RecordTable` and six pages with a held roster (finding CO-1) | a `CellVector` in the page document | the same | the same | arrangement | `WidgetTable` |
| Group rows of an arrangement | `CellVector{ArrangementGroupRow}` | `ArrangementGroupRowsToWidget`, labels ([NaturalArrangement.jl:301](../../../source/platform/natural/NaturalArrangement.jl#L301)) | no | the later stages act on it; no header parts | `WidgetTable` |
| Data frame view | `DataFrameView` over a data frame | `DataFrameViewToWidget` | yes, rows and columns ([DataFrameView.jl:473](../../../source/adapter/dataframes/DataFrameView.jl#L473)) | its own: `DataFrameQuery`, `DataFrameFilter.jl`, `DataFrameSort.jl`, `DataFrameFind.jl` | `WidgetTable` |
| Pivot table | `PivotTable`, which reads the table interface | `PivotTableToWidget`, labels | yes, head fixed at row 1 ([PivotTableToWidget.jl:269](../../../source/domain/pivot/PivotTableToWidget.jl#L269)) | its own zones, order and first N | `WidgetTable` |
| Pivot part table | a `TablePart` | labels | yes, head fixed at row 1 ([PivotPartTableToWidget.jl:25](../../../source/domain/pivot/PivotPartTableToWidget.jl#L25)) | none | `WidgetTable` |
| `CellTable` view (result of a SQL query) | `CellTable`, row 1 holds the headers | primitive documents through the recursion | no ([CellTableToWidgetTable.jl:42](../../../source/platform/widget/CellTableToWidgetTable.jl#L42)) | none, read-only | `WidgetTable` |
| Page of a folder | `FileSystemDirectory.elements` | hand-made link and label | yes when `bounded`, head fixed at 1 ([FileSystemDirectoryToWidget.jl:126](../../../source/platform/filesystem/FileSystemDirectoryToWidget.jl#L126)) | none | `WidgetTable` |
| Help group | its children | labels ([HelpGroupToWidget.jl:88](../../../source/platform/help/HelpGroupToWidget.jl#L88)) | no | none | `WidgetTable` |
| Assistant list | `list.assistants` | hand-made buttons, badges, labels ([AssistantListToWidget.jl:113](../../../source/platform/assistant/AssistantListToWidget.jl#L113)) | no | none | `WidgetTable` |
| Matches of an explorer search | `search.result.matches` | link and label ([ExplorerSearchToWidget.jl:26](../../../source/platform/explorer/ExplorerSearchToWidget.jl#L26)) | no | none | `WidgetTable` |
| Frame statistics | the series of frames | its own cells | yes, its own anchor ([FrameStatisticsToWidget.jl:547](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L547)) | none; also a roster store `:frames` | `WidgetTable` |
| Lines of a task stream | an index of lines | labels | its own window: a slice from `top`, its own scroll bar ([TaskPagesToWidget.jl:398](../../../source/platform/task/TaskPagesToWidget.jl#L398)) | its own found line | `WidgetTable` of the slice |
| MCP log | `log.entries` | blocks made by hand ([McpLogToWidget.jl:61](../../../source/platform/mcplog/McpLogToWidget.jl#L61)) | no ([McpLogToWidget.jl:93](../../../source/platform/mcplog/McpLogToWidget.jl#L93)) | its own choice "all, tools, faults" ([McpLogToWidget.jl:42](../../../source/platform/mcplog/McpLogToWidget.jl#L42)); also a roster store `:mcp_log` | `VerticalLayout` by hand |
| Message log, fault log | `entries` | one syntax node for each entry, then the text domain | n.c. | none seen; also roster stores | syntax and text |
| Document tree | any document, through four generics | `_make_tree_node` ([DocumentTreeToWidgetTree.jl:78](../../../source/platform/tree/DocumentTreeToWidgetTree.jl#L78)) | yes | none | `WidgetTree` |
| Files tool | `WorkspaceExplorer` | `_fs_node` ([FileSystemToWidget.jl:57](../../../source/platform/filesystem/FileSystemToWidget.jl#L57)) | yes | none | `WidgetTree` |
| File chooser | `FileSystemChooser` | its own | n.c. | none | `WidgetTree` |
| Reflection tree | a shadow of `ReflectedNode` | `_tree_node` ([ReflectionToWidget.jl:85](../../../source/platform/reflection/ReflectionToWidget.jl#L85)) | bounded by the sync policy | none | `WidgetTree` |
| Explorer | a `DocumentTree`, or a second tree of matches | as the document tree | yes | its own `ExplorerFilter` ([ExplorerFilter.jl:130](../../../source/platform/explorer/ExplorerFilter.jl#L130)) | `WidgetTree` |
| Choice list | `find(query)`, a vector of `WidgetChoice` | `_make_choice_item` | yes, its own `top` ([WidgetChoiceList.jl:214](../../../source/platform/widget/WidgetChoiceList.jl#L214)) | its own typed query | rows by hand |
| `WidgetList` | strings | draws `string(item)` ([WidgetToGraphics.jl:12245](../../../source/platform/widget/WidgetToGraphics.jl#L12245)) | no | none | its own printer |
| Vector in a form | a vector field | every element in a `VerticalLayout` ([ObjectToWidget.jl:220](../../../source/platform/widget/ObjectToWidget.jl#L220)) | no | none | layout |
| Outline of records (research, workflow) | the records of a domain | `make_outline_row` cards with `OutlineSlot` maps | n.c. | none | cards by hand |

Result: of 24 kinds of view, 3 use the arrangement (the roster table, the pages that hold one, the group rows). The data frame view, the pivot, the explorer, the choice list, the MCP log and the stream lines each have their own filter or find. Thirteen views build a `WidgetTable`; five of them make the rows of a collection of records by hand.

### B. The two forms of `WidgetTable`

`WidgetTable` is the table widget. Its printer reads the type of the field `cells` and takes one of two code paths ([WidgetToGraphics.jl:13642](../../../source/platform/widget/WidgetToGraphics.jl#L13642)).

| Capability | Body is a vector (`WidgetToGraphics.jl`, about 1,300 lines) | Body is a list (`WidgetTableParts.jl`, 2,249 lines) |
| --- | --- | --- |
| builds only the rows in view | no | yes |
| a column as wide as its widest cell, whole extent known | yes | no: each column needs a width ([WidgetTableParts.jl:39](../../../source/platform/widget/WidgetTableParts.jl#L39)) |
| works with no offered height | yes | no ([WidgetTableParts.jl:98](../../../source/platform/widget/WidgetTableParts.jl#L98)) |
| press selects a row, a column, a cell, a header | yes, `_wt_mouse_select` ([WidgetToGraphics.jl:13942](../../../source/platform/widget/WidgetToGraphics.jl#L13942)) | yes, `_read_table_parts_press` ([WidgetTableParts.jl:1619](../../../source/platform/widget/WidgetTableParts.jl#L1619)) |
| keys | yes, `_wt_key_navigate` ([WidgetToGraphics.jl:14102](../../../source/platform/widget/WidgetToGraphics.jl#L14102)) | yes, `_read_table_parts_key` ([WidgetTableParts.jl:1843](../../../source/platform/widget/WidgetTableParts.jl#L1843)) |
| open cells: commit and drop | yes ([WidgetToGraphics.jl:13930](../../../source/platform/widget/WidgetToGraphics.jl#L13930)) | yes ([WidgetTableParts.jl:2211](../../../source/platform/widget/WidgetTableParts.jl#L2211)) |
| drag of the edge of a column | no | yes ([WidgetTableParts.jl:2196](../../../source/platform/widget/WidgetTableParts.jl#L2196)) |
| headers with levels | no | yes ([WidgetTableParts.jl:963](../../../source/platform/widget/WidgetTableParts.jl#L963)) |
| a corner | no: a corner forces the list form ([WidgetToGraphics.jl:13643](../../../source/platform/widget/WidgetToGraphics.jl#L13643)) | yes |
| writes `top_row` and `shown` | no | yes ([WidgetTableParts.jl:1718](../../../source/platform/widget/WidgetTableParts.jl#L1718)) |
| tooltip of a failed commit | no | yes ([WidgetTableParts.jl:2202](../../../source/platform/widget/WidgetTableParts.jl#L2202)) |

### C. Projections that print a tree

| Projection | Input | How it lists children | Where the open nodes are kept | Lines |
| --- | --- | --- | --- | --- |
| `DocumentTreeToWidgetTree` | `DocumentTree` of any document | `get_tree_children_steps` and three more generics | `DocumentTree.expanded`, places by identity ([TreeDocument.jl:47](../../../source/platform/tree/TreeDocument.jl#L47)) | 645 |
| `FileSystemToWidgetTree` | `WorkspaceExplorer` | reads `elements` of a folder itself | `WorkspaceExplorer.open` ([FileSystemToWidget.jl:129](../../../source/platform/filesystem/FileSystemToWidget.jl#L129)) | 374 |
| `FileSystemChooserToWidget` | `FileSystemChooser` | the same | `FileSystemChooser.open` ([FileSystemChooserToWidget.jl:41](../../../source/platform/filesystem/FileSystemChooserToWidget.jl#L41)) | 148 |
| `ReflectionToWidget` | a shadow of `ReflectedNode` | `reflect_child_count`, `reflect_child_pairs` | a marker in the shadow ([ReflectionToWidget.jl:61](../../../source/platform/reflection/ReflectionToWidget.jl#L61)) | 213 |

Each of the four turns its own open state into `WidgetTree.expanded`, a set of index paths, and turns the write of a chevron back.

### D. The collection types

| Type | Index | Count | Iteration | Lazy | Users in `source/` |
| --- | --- | --- | --- | --- | --- |
| plain `Vector` | from 1 | yes | values | no | arguments of constructors |
| `CellVector{T}` | from 1 | yes | values | one element at a time with `element =` | almost every slice |
| `ListNode` | from the node held: 1 is the head, 0 the node before ([ListNode.jl:184](../../../source/platform/collection/ListNode.jl#L184)) | none | nodes, from the left tail ([ListNode.jl:444](../../../source/platform/collection/ListNode.jl#L444)) | each link | 17 slices |
| `CellTable` | `[r, c]` | rows | rows | no | the ODBC adapter and `CellTableToWidgetTable` |
| `CellMatrix` | `[r, c]` | yes | values | no | none (finding CO-10) |

`ListDocument` is the abstract type of `CellVector` and `ListNode` ([CellVector.jl:30](../../../source/platform/collection/CellVector.jl#L30)). The two share no function with one meaning. The source has 119 branches `isa ListNode`; 28 are in `WidgetTableParts.jl` and 13 in `WidgetToGraphics.jl`.

### E. Implementations of "compute only the visible part"

1. `ListNode` under a `GridLayout` of a list: the table with a list body, and its users.
2. `WidgetTree`: rows placed by arithmetic, and a second form with a lazy list of rows ([WidgetToGraphics.jl:14893](../../../source/platform/widget/WidgetToGraphics.jl#L14893)).
3. `CellVector(@computation(keys); element)`: the count is known, an element computes at its first read.
4. `WidgetChoiceList`: an index list from its own `top`.
5. `TaskStreamLinesToWidget`: a slice of the rows and a scroll bar of its own.
6. The bounded sync of the reflection: a cap of elements with a tail marker.
7. The lines of a text (the text slice, not in this area).

### F. A row with named columns

| Model | Row | Read of a column | Readers |
| --- | --- | --- | --- |
| Table interface | a row number in a table | `get_table_value(table, row, "name")` ([TableInterface.jl:107](../../../source/platform/collection/TableInterface.jl#L107)) | the pivot only |
| Arrangement key | an item | `find_arrangement_key_value(item, key::Reference)` | filter, sort, group |
| Roster key | `RosterRow(item, within, columns, values)` | `compute_roster_value(row, "within.name")`, with facets ([RosterDocument.jl:90](../../../source/platform/roster/RosterDocument.jl#L90)) | the roster table |
| Group row | `ArrangementGroupRow(columns, values, members)` | by the name of a column ([Grouping.jl:108](../../../source/platform/arrangement/Grouping.jl#L108)) | stages after a group |
| Form field | `ObjectField(root, path)` | `get_object_field_value(field)` | `ObjectToWidget` |

## Findings

### CO-1 Seven content documents hold the filter, the sort and the head of their table

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** the rule "Content documents and view documents" ([architecture-rules.md:261](../../../documentation/rule/architecture-rules.md#L261)): a view document keeps "the head of a lazy list, the rows in view, a filter, a sort", one for each view. Also principle 7, one mechanism for every list. The finding touches the settled decision that the kernel has no notion of content or view; the proposal stays in the platform.
- **Today:** A `Roster` is the document that shows items as a table. An `ArrangementDocument` is the document that holds the filters and sorts of a place. Seven content documents make both in their constructor and keep them in a field `table`: `OpenFileList` ([OpenFileList.jl:84](../../../source/platform/fileformat/OpenFileList.jl#L84)), `TaskGroupList` ([TaskGroupList.jl:42](../../../source/platform/task/TaskGroupList.jl#L42)), `TaskGroupDocument` ([TaskGroupDocument.jl:250](../../../source/platform/task/TaskGroupDocument.jl#L250)), `BackgroundWorkLog` ([BackgroundWorkDocument.jl:57](../../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L57)), `RecordTable` ([RecordTable.jl:51](../../../source/platform/roster/RecordTable.jl#L51)), `GitRange` ([GitRange.jl:62](../../../source/domain/git/GitRange.jl#L62)) and `WorkflowList` ([WorkflowList.jl:50](../../../source/domain/workflow/WorkflowList.jl#L50)). Six readers in five files then call the two repair functions `keep_held_arrangement` and `retarget_held_row_open`; the seventh page, `WorkflowListToWidget`, has no `read_intent` of its own and calls neither (corrected by the check) ([TaskGroupToWidget.jl:1357](../../../source/platform/task/TaskGroupToWidget.jl#L1357), [TaskGroupToWidget.jl:1525](../../../source/platform/task/TaskGroupToWidget.jl#L1525), [BackgroundWorkLogToWidget.jl:87](../../../source/platform/backgroundwork/BackgroundWorkLogToWidget.jl#L87), [RecordTableToWidget.jl:76](../../../source/platform/roster/RecordTableToWidget.jl#L76), [OpenFileListToWidget.jl:77](../../../source/platform/fileformat/OpenFileListToWidget.jl#L77), [GitToWidget.jl:500](../../../source/domain/git/GitToWidget.jl#L500)). Four page projections are the same code, a count line above the table and the maps `table.<rest>` to `children[2].<rest>`: `RecordTableToWidget` (79 lines), `OpenFileListToWidget` (80), `BackgroundWorkLogToWidget` (97) and `WorkflowListToWidget` (70). A dependent repository has eight more lines that make such an arrangement or call the repair. The generic `make_document_view(document)`, which makes the view document of a page, exists ([DocumentView.jl:31](../../../source/platform/domain/DocumentView.jl#L31)) and the navigator keeps its answer for each visit ([NavigatorVisits.jl:264](../../../source/platform/navigator/NavigatorVisits.jl#L264)); none of the seven uses it. I found one reader that puts the first arrangement around content that nobody arranged: the reader of a tab ([PaneArrangement.jl:40](../../../source/platform/pane/PaneArrangement.jl#L40)). A page in a navigator has no such reader, which explains the field; this last step is my reading, no plan says it. (Corrected by the check: a plan does give a reason. Decision D1 of `plan/done/a-view-document-keeps-the-state-of-one-view.md` (the owner, 2026-10-18) keeps the selection path of a page in the content, so "a path to a field that only the view keeps" maps back to nothing ([navigator.md:77](../../../documentation/package/platform/navigator/navigator.md#L77), [NavigatorToWidget.jl:584](../../../source/platform/navigator/NavigatorToWidget.jl#L584)). A table whose rows, header fields and chips take a selection must therefore be a field of the content today. The view documents that exist keep only state that takes no selection, such as `anchor` and `shown`.)
- **Example:**
  ```julia
  # today: in the content document, and again in its page projection
  @document struct OpenFileList <: Document
      files::CellVector = CellVector(Any[])
      table::Any = nothing                    # a view, kept in the content
  end
  roster = Roster(CollectionItems(@reference(files)); columns = ["name", "folder", "state"])
  link_roster!(roster, list)
  list.table = ArrangementDocument(roster, ArrangementEntry[])
  # ... and in read_intent of OpenFileListToWidget:
  operation = keep_held_arrangement(answer.operation, getfield(list, :table)[], _OPEN_FILE_TABLE_STEP)
  operation = retarget_held_row_open(operation, list, _OPEN_FILE_TABLE_STEP)

  # after: the content declares its table, one generic view document holds the state
  @document struct OpenFileList <: Document
      files::CellVector = CellVector(Any[])
  end
  make_document_view(list::OpenFileList) =
      make_collection_view(list, @reference(files); columns = ["name", "folder", "state"])
  ```
- **Problem:** The filter, the sort and the head of the list are in a document that every page of that content shares, so two pages of the open files can not filter apart. This is the mix that the written rule names. The data document refers back to itself through the `link` of its roster. The general rule of the arrangement, "the last chip takes the wrapper away", does not fit a held table, so `keep_held_arrangement` undoes it. The row selects `table.document.rows[k].item` and not `files[k]`, so `retarget_held_row_open` and `find_held_item_path` repair the address of each open. The next page with a table must copy all of it.
- **Proposal:** One view document, here called `CollectionView(content, table)`, that `make_document_view` answers for a content document that declares the place and the columns of its table. It holds the roster, the arrangement and the head, and it names its content with `get_edited_field`, as `FileView` does. One projection draws the count line and the table and maps a row to the place of its item. The roster gets its link from the view.
- **What goes away:** The field `table` and its wiring in seven documents. Three of the four page projections (about 250 lines) and the table parts of `TaskGroupToWidget` and `GitToWidget`. The twelve repair calls. `keep_held_arrangement` ([Arranging.jl:107](../../../source/platform/arrangement/Arranging.jl#L107), about 35 lines). `find_held_item_path` and `retarget_held_row_open` become one map in one projection.
- **What stays:** The bar, the header fields, the link of the first column, the open of a row at the place of its item, the cells of a page (`make_roster_cell`), the marked row and `show_roster!`. A tab still puts the first arrangement around content that is no page.
- **Risk and open questions:** Where the view lives when a tab shows the content with no navigator. Code and the assistant call `sort_collection!(ledger, "number")` on the content today, through `get_arranged_collection_steps`; the verb must find the view of the content. `TaskGroupDocument.anchor` follows the task of the detail; that link must move to the view.
- **Related plans:** `plan/done/a-view-document-keeps-the-state-of-one-view.md` (done; it wrote the rule and `make_document_view`, and did not move these seven). `plan/pending/views-compose-as-content-composes.md` (later; the JSON pipeline, not these tables). `plan/pending/the-assistant-fills-a-live-table.md` (in progress; it added `RecordTable` in the held form).
- **Check:** weakened; value medium. The facts hold: I opened the seven documents and the six call sites (twelve repair calls), the four page projections have 79, 80, 97 and 70 lines, and no method of `make_document_view` exists for the seven (only `Url` and `FileDocument` have one). omnet-julia holds six more tables in the same form and calls the repair once. One count was wrong and one reason was missing; both are corrected above. The proposal does not hold as written. A view document that `make_document_view` makes can hold no part that takes a selection: by decision D1 of `a-view-document-keeps-the-state-of-one-view.md` the path of a page goes through the content, and a field that only the view keeps names nothing. So the rows, the columns, the header fields and the chips of a table in `CollectionView` could take no caret and no selection in a navigator page. The move needs D2 (paths through the view), which the owner left to the later plan `views-compose-as-content-composes.md`; that plan has no step for these tables. What the proposal would lose or change: a filter of a session page (tasks, open files, background work) stays today while the editor lives and is the same in every page of it; with a view for each visit a new visit starts with no filter. `sort_collection!(ledger, …)` on a content that no page shows has no view to write. What can be done now, with no move of state: one maker of a held table (roster, link, arrangement) and one page projection "count line above the table" with the two repairs inside. That removes the wiring of seven documents here and six in omnet-julia, three of the four page projections and the twelve calls, and it gives `WorkflowListToWidget` the repair that it lacks. `keep_held_arrangement` stays in either form, as one call.

### CO-2 A list has two types with no shared protocol, so each view that can be lazy is written twice

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** principle 7, one mechanism for every list; the settled decision that lazy lists have one generic solution and count from their head.
- **Today:** `CellVector` holds every element and counts from 1. `ListNode` is a link of a chain: it has no count, `head[i]` counts from the node held ([ListNode.jl:184](../../../source/platform/collection/ListNode.jl#L184)), and its iteration gives nodes from the far left end ([ListNode.jl:444](../../../source/platform/collection/ListNode.jl#L444)). A consumer can not be written once for both. So five fields of `WidgetTable` each accept two or three shapes ([WidgetDocument.jl:3222](../../../source/platform/widget/WidgetDocument.jl#L3222)), and the table has two printers, two IO maps and two readers; inventory B shows that the drag of a column edge, the header levels, the corner, `shown` and the tooltip of a failed commit work only with a list body. `WidgetTree` has two forms of its rows ([WidgetToGraphics.jl:14893](../../../source/platform/widget/WidgetToGraphics.jl#L14893)). `DocumentTreeToWidgetTree` keeps laid-out lists and mirrors of a lazy list side by side ([DocumentTreeToWidgetTree.jl:106](../../../source/platform/tree/DocumentTreeToWidgetTree.jl#L106)). Each owner of a table branches on the offered height to choose the form ([RosterToGraphics.jl:186](../../../source/platform/roster/RosterToGraphics.jl#L186), [FileSystemDirectoryToWidget.jl:129](../../../source/platform/filesystem/FileSystemDirectoryToWidget.jl#L129)).
- **Example:**
  ```julia
  # today: the form follows the type of the body, and the features follow the form
  WidgetTable(headers, rows)                                   # vector: no drag of a column edge, no levels
  WidgetTable(; column_headers, cells = make_index_list(n, 1, row_of), columns)   # list: needs a height

  # after: one protocol, one printer; what differs is a policy
  get_list_count(rows)          # an Int for a CellVector, nothing for an endless chain
  find_list_node(rows, k)       # the same call for both
  WidgetTable(; column_headers, cells = rows, columns)         # every feature, whatever holds the rows
  ```
- **Problem:** A feature added to the table is written twice or works in one form only; the done plan `a-table-selects-each-part-the-same-way.md` had to align the two readers by hand. A caller that wants a small table with levels or a column drag must build a list and get a height. A tree node with a lazy list beside another collection shows no children (a limit in `tree.md`).
- **Proposal:** A small protocol for "a list seen from a head, with or without a count": the head, the neighbour on each side, the node at a count, and the count or `nothing`. `CellVector` and `ListNode` both answer it. The table, the tree and the grid are written once against it. "As wide as the widest cell" and "whole extent" become a policy that needs a count, not a second printer.
- **What goes away:** The vector printer and reader of the table in `WidgetToGraphics.jl` (less than the about 1,300 lines of its table section, lines 13128 to 14421: the list form calls about 20 helpers of that section, such as `_wt_cell_ref`, `_wt_read_cell_event` and `_find_wt_lit_reference`, and those stay; corrected by the check) or the same amount of `WidgetTableParts.jl`; one of the two row forms of the tree; `WidgetTableRows` and `WidgetTableColumns` as count holders; the branch on the height in each owner; a large part of the 119 `isa ListNode` branches.
- **What stays:** Lazy rows and columns, a list that counts from its head, a table with no offered height that shows every row, columns as wide as their content when the count is known, every part path (`rows[r]`, `cells[r][c]`).
- **Risk and open questions:** `plan/done/one-table-widget.md` chose "one widget, two forms" on 2026-09-16 and argued that only the canvas of the content needs two forms; the list form has since grown its own readers. A table in a print with no window has no height; the one printer must still show all rows there. This reaches into the layout slice (`GridList.jl`, `GridColumnList.jl`, `LayoutList.jl`, 1,135 lines).
- **Related plans:** `plan/done/one-table-widget.md`, `plan/done/a-table-selects-each-part-the-same-way.md` (done). `plan/pending/filter-sort-and-find-any-table.md` step 5 (pending) builds on the list form.
- **Check:** confirmed-with-corrections; value high. I counted again: 119 branches `isa ListNode` in `source/`, 28 in `WidgetTableParts.jl` (2,249 lines) and 13 in `WidgetToGraphics.jl`; the three list files of the layout have 1,135 lines. `ListNode.jl` and `CellVector.jl` share no function: I read the list of the functions of `ListNode.jl`. The printer branches at [WidgetToGraphics.jl:13643](../../../source/platform/widget/WidgetToGraphics.jl#L13643), and the list form refuses a table with no offered height ([WidgetTableParts.jl:98](../../../source/platform/widget/WidgetTableParts.jl#L98)). The line count of what goes away was too high and is corrected above. Counter-evidence that I looked for: `plan/done/one-table-widget.md` gives a reason for two forms, but only for the canvas of the content and the child IO map (its pieces 4 and 5); it says that the rest has one implementation. The two readers came later, and `a-table-selects-each-part-the-same-way.md` lists "the two forms have separate readers, so a rule can drift" as a risk. So the stated reason does not cover the difference of today. No pending plan joins the forms. What the proposal must not lose: a table of a vector prints with no offered height and with columns as wide as their cells (a Markdown table, a print to a PDF); the list form can do neither today, and limit L4 of `pivot-table-next-steps.md` (no rows of a list in a PDF) must be solved first. The protocol itself is a design that nobody tried: the confidence stays medium, and the saving in `isa ListNode` branches is a guess.

### CO-3 Lists of records are still drawn by hand beside the roster

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** medium
- **Principle:** principle 8, reuse an existing view: a list of items with fields goes to the roster, a text goes to the text domain.
- **Today:** Five views build a `WidgetTable` from a collection of records by hand: the assistant list with 12 columns ([AssistantListToWidget.jl:144](../../../source/platform/assistant/AssistantListToWidget.jl#L144)), the matches of an explorer search ([ExplorerSearchToWidget.jl:26](../../../source/platform/explorer/ExplorerSearchToWidget.jl#L26)), the page of a folder ([FileSystemDirectoryToWidget.jl:126](../../../source/platform/filesystem/FileSystemDirectoryToWidget.jl#L126)), a help group ([HelpGroupToWidget.jl:88](../../../source/platform/help/HelpGroupToWidget.jl#L88)) and the frames of the statistics ([FrameStatisticsToWidget.jl:421](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L421)). The MCP log draws a block for every entry in a `VerticalLayout` and has its own choice of what shows ([McpLogToWidget.jl:93](../../../source/platform/mcplog/McpLogToWidget.jl#L93)). The lines of a task stream are a table of a slice with a scroll bar of its own ([TaskPagesToWidget.jl:398](../../../source/platform/task/TaskPagesToWidget.jl#L398)). Two of these collections are also offered as a roster store, `:frames` and `:mcp_log`, so the same records have two views.
- **Example:**
  ```julia
  # today (ExplorerSearchToWidget)
  rows = Any[_make_search_match_row(search, match) for match in matches]
  WidgetTable(Any["match", "place"], rows)

  # after: the page declares its table, as in CO-1
  make_collection_view(search, @reference(result.matches); columns = ["label", "place"])
  ```
- **Problem:** None of these views has the filter, the sort, the group or the find of the arrangement. Three of the five tables build every row, and so does the MCP log. Three cells of the assistant list read facets of the roster by hand (`compute_item_facet(a, Val(:plan))`, [AssistantListToWidget.jl:131](../../../source/platform/assistant/AssistantListToWidget.jl#L131)). Each new list of records must choose again between the two ways.
- **Proposal:** Each of the five tables becomes a roster of its collection; a cell that is a button or a badge comes from `make_roster_cell`, the hook that the task tables use. The MCP log keeps its block as the page of one entry and shows the entries as a roster. The lines of a stream go to the text domain, which has lazy lines.
- **What goes away:** The row builders and the eager tables of five views, the choice filter of the MCP log, the window and the scroll bar of the stream lines, the anchor code of the statistics table.
- **What stays:** Every column and every control in a cell; the link of a row; the pages.
- **Risk and open questions:** The roster follows a row by the identity of its item; a named tuple of a frame or a match must be one object for each row. A roster table gives each column an equal share unless `shares` is set. Whether a stream of a million lines is fast enough as a text was not measured.
- **Related plans:** `plan/pending/the-header-of-a-table-filters-and-sorts-its-arrangement.md` (in progress; decision D2 moved the table of a task group to the roster in this way). `plan/done/the-open-files-show-as-a-roster.md` (done).
- **Check:** weakened; value medium. The facts hold for the five tables and the two other views: I opened each cited line, the assistant list has 12 columns and reads three facets by hand, and `:frames` and `:mcp_log` are roster stores. The rule is the owner's ("a list with fields goes to the roster, no hand-made rows"), and no plan covers the assistant list, the search matches, the page of a folder or the help group. For these four the proposal holds, and `make_roster_cell` exists for a button or a badge in a cell. Three parts do not hold as written. (1) The frames table uses a header column, a corner and a fixed row height; the roster table has none of the three ([RosterToGraphics.jl:368](../../../source/platform/roster/RosterToGraphics.jl#L368) passes an empty header column and no corner), so the frame number would scroll away with the columns. The goal of `filter-sort-and-find-any-table.md` also names "the table of frame statistics" as a table that gets the arrangement in front of it, with no roster: that is another way, in a plan. (2) The MCP log shows the code and the answer of every call in line, one block after the other. A roster of the entries with the block as the page of one entry hides that text behind an open of a row, so a feature of today is lost. (3) The lines of a stream read the file through an index of line starts, so a stream of a million lines costs the lines in view ([task.md](../../../documentation/package/platform/task/task.md), "The page of a stream"). A text document holds its whole text, and the view has its own kept-lines field, marks by line, follow of the end and First error. The move to the text domain is not measured and may cost that property. The value is medium: four small tables get the filter and the sort, and the choice "roster or by hand" gets one answer.

### CO-4 Four projections print a tree, each with its own children and its own open nodes

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** principle 7; the design decision "One tree for every kind of document" in `tree.md`.
- **Today:** Inventory C. `DocumentTreeToWidgetTree` is the generic printer: a slice adds four methods and its documents are nodes; about 30 methods of `get_tree_children_steps` exist (the check counts 32 definitions with the defaults; the report said 27). The file system slice has those methods ([FileSystemTree.jl:27](../../../source/platform/filesystem/FileSystemTree.jl#L27)), and it also keeps `FileSystemToWidgetTree`, a printer of its own that the Files tool still uses ([Application.jl:195](../../../source/platform/application/Application.jl#L195), [WindowChrome.jl:234](../../../source/platform/shell/WindowChrome.jl#L234)), and a third for the file dialog. The reflection view has its own generics for children (`reflect_child_pairs`) and derives the open set from its shadow ([ReflectionToWidget.jl:141](../../../source/platform/reflection/ReflectionToWidget.jl#L141)).
- **Example:**
  ```julia
  # today: the same folders, two printers
  WorkspaceExplorer(workspace)                 # FileSystemToWidgetTree, open folders in .open
  DocumentTree(workspace; title = "Files")     # DocumentTreeToWidgetTree, open places in .expanded

  # after: one printer; a kind of node adds methods only
  TreeModule.get_tree_children_steps(::ReflectedNode) = ((FieldReferenceStep("children"),),)
  TreeModule.demand_tree_children(node::ReflectedNode) = request_sync!(node.children)
  ```
- **Problem:** What the document tree gives a node is written in `DocumentTreeToWidgetTree`: the decoration with its badges and its tooltip, the open of a page, the hold of the open and the shown documents, the mark of the current page ([DocumentTreeToWidgetTree.jl:78](../../../source/platform/tree/DocumentTreeToWidgetTree.jl#L78)). The file tree has its own icon and its own open code ([FileSystemToWidget.jl:49](../../../source/platform/filesystem/FileSystemToWidget.jl#L49)), so each such part must be written again there or stay behind. Each printer has its own maps between its paths and `roots[1].children[k]`.
- **Proposal:** The Files tool and the file dialog show a `DocumentTree` of the workspace; the dialog adds its name field and its choose gesture around it. The reflection view gives `ReflectedNode` the four generics: `has_tree_children` answers from the marker, and `demand_tree_children` asks for the sync.
- **What goes away:** `FileSystemToWidgetTree` (374 lines), the tree part of `FileSystemChooserToWidget` (148), most of `ReflectionToWidget` (213), the fields `WorkspaceExplorer.open` and `FileSystemChooser.open`, and three sets of path maps.
- **What stays:** The Files tool, the file dialog, the value viewer, a folder that reads when it opens, a reflection node that opens one level at a time.
- **Risk and open questions:** The reflection slice chose "the open state is the marker" so that the open set can not disagree with the shadow; with a document tree, a place can be open while its node is not synced yet, which `has_tree_children === nothing` must cover. The drag of a file from the Files tool has a test on the old printer. I found no plan that says why the Files tool keeps its own printer.
- **Related plans:** `plan/done/the-explorer-shows-what-the-editor-holds.md` (done; it named "the file tree does not use the four tree generics" as a fact to change, and gave the folders the generics). Other areas: file system, reflection.
- **Check:** weakened; value low. The facts hold: the four projections have 645, 374, 148 and 213 lines, the folders have the tree generics ([FileSystemTree.jl:27](../../../source/platform/filesystem/FileSystemTree.jl#L27)), and the Files tool still prints through `FileSystemToWidget` ([Application.jl:195](../../../source/platform/application/Application.jl#L195)). The reflection half is no finding, because the difference has a stated reason: `reflection.md` lists the design decision "The open state is the marker. A side table of open nodes can disagree with the shadow; a marker can not" (line 62, and lines 24 and 32). The proposal puts the open nodes of a reflected value into `DocumentTree.expanded`, which is that side table; the report names this only as a risk. So `ReflectionToWidget` (213 lines) stays. The file system half holds, with two notes. The ask of the owner in `the-explorer-shows-what-the-editor-holds.md` says "Special components for files, assistants and others stay", and its §5.10 says "The file tree keeps its own button, Files, as a special component": the tool must stay, and the proposal keeps it, but that plan left the printer on purpose, so the owner decides. A double click on a file in the Files tool answers `open_file(path)`, an `OpenFileOperation` by default, which opens a tab; the document tree answers `OpenPageOperation`. The wrapper of the Files tool must turn the one into the other, or the Files tool opens a page and no tab. What remains is one printer less for the Files tool and a part of the file dialog, about 400 lines.

### CO-5 Each owner of a lazy table converts the move of its head by hand

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** principle 6, decide locally; principle 7. The settled decision that a lazy list counts from its head stays.
- **Today:** When a scroll takes the top row more than 200 rows from the head, the table writes its own field `cells` with the node of that row and shifts its selection ([WidgetTableParts.jl:1725](../../../source/platform/widget/WidgetTableParts.jl#L1725)). The comment says "a projection that owns the rows turns the write of `cells` into an edit of its own". Three owners do: each recognises the write by its shape, finds the index with `find_list_index`, writes its own anchor and drops the shift of the selection ([RosterToGraphics.jl:651](../../../source/platform/roster/RosterToGraphics.jl#L651), [DataFrameViewToWidget.jl:734](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L734), [FrameStatisticsToWidget.jl:630](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L630)). Four documents keep an anchor of their own (`DataFrameView.anchor` and `column_anchor`, `Roster.anchor`, `FrameStatistics.anchor`, `TaskGroupDocument.anchor`), beside `top_row` and `scroll_position` of the table. The pivot, the pivot part table and the page of a folder build their list with the head fixed at 1 and convert nothing; the pivot plan records the result as limit L2.
- **Example:**
  ```julia
  # today, in each owner
  head = _find_written_cells(iomap.table, member)       # is this a write of the whole field `cells`?
  k = find_list_index(iomap.table.cells, head)          # walk the chain to find the index
  ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", old_head + k - 1))

  # after: the list knows its anchor, and the table names the move
  rows = make_anchored_list(count, view_anchor_cell, row_of)
  # the table answers MoveListHeadOperation(rows, k); its evaluation writes the anchor cell
  ```
- **Problem:** The protocol is a write that each owner must match by its shape, in a compound, and it is easy to miss: three of the six views with a list body do not handle it. `find_list_index` walks up to 10,000 links each way. The same view state lives twice, in the table and in the owner.
- **Proposal:** A list built from indices keeps its anchor in a cell that its owner gives. The table answers a typed operation for a move of the head, as it does for the width of a column (`SetTableColumnWidthOperation`), and the general evaluation writes that cell. An owner writes no reader for it.
- **What goes away:** `_find_roster_head_move`, `_find_written_cells`, `_make_head_write` in the roster, the same code in the data frame view and the statistics (roughly 150 lines in all; I did not count the data frame part), three uses of `find_list_index`, and limit L2 of the pivot.
- **What stays:** The head moves when the top row is far; a path counts from the head; an owner still decides what its anchor names (an index, or an item as in the roster).
- **Risk and open questions:** The roster keeps the anchor as an item, not an index; the anchored list must take a function for that. Step 5 of `filter-sort-and-find-any-table.md` says "the lazy rows from an anchor" and may be the place for this.
- **Related plans:** `plan/pending/filter-sort-and-find-any-table.md` step 5 (pending). `plan/pending/pivot-table-next-steps.md` L2 (pending).
- **Check:** confirmed-with-corrections; value medium. The facts hold: the table writes its own `cells` at the node of the top row ([WidgetTableParts.jl:1725](../../../source/platform/widget/WidgetTableParts.jl#L1725)), and the roster, the data frame view and the statistics each find that write by its shape and walk the list with `find_list_index` to get a count that the table had at hand (`k` in `_add_top_row`). That is a search for a fact that the producer knew. The four anchors exist, and limit L2 of the pivot plan says what happens when an owner does not follow the head. No step of a plan describes the change; step 5 of `filter-sort-and-find-any-table.md` is one line. One correction: the model that the proposal names, `SetTableColumnWidthOperation`, does not free the owner from a reader. The data frame view converts it by hand too (`_convert_column_width`, [DataFrameViewToWidget.jl:654](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L654)). So the typed operation that carries the count holds, and it removes the shape match and the three walks. The second half, "the list keeps the anchor cell of its owner, the general evaluation writes it, an owner writes no reader", does not hold as written: the output would then write a cell of the input outside the reader of the projection, which is the one way back (first principle 2), and the roster keeps an item and not an index as its anchor. The owner still maps the move in its reader, in one line. The saving is then smaller than the 150 lines of the report. The pivot still has to follow the move (L2); the change only makes the move a thing that it can see.

### CO-6 The filter of a tree is a second tree of copied rows

- **Kind:** partial-feature · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** principle 2, a general step works for every domain; `concepts.md`: "a filter … goes in front of any data".
- **Today:** A `DocumentTree` has no filter. The explorer has `ExplorerFilter`, words and kinds. While it is active, `_make_match_tree` walks the open places, builds a tree of `_ExplorerMatch` documents, each a copy of a row with its steps, and wraps it in a second `DocumentTree` ([ExplorerFilter.jl:40](../../../source/platform/explorer/ExplorerFilter.jl#L40), [ExplorerFilter.jl:130](../../../source/platform/explorer/ExplorerFilter.jl#L130)). `ExplorerToWidget` swaps the two trees and maps `tree.<rest>` or `matches.<rest>` by which one shows ([ExplorerToWidget.jl:125](../../../source/platform/explorer/ExplorerToWidget.jl#L125)); `_find_match_path` maps an address into the copy. The arrangement does not act on a tree.
- **Example:**
  ```julia
  # today: explorer only
  Explorer(content; filter = ExplorerFilter(; text = "smoke"))

  # after: any tree
  tree = DocumentTree(plan; title = "Steps")
  filter_collection!(tree, "label" => "smoke")      # a row stays with its ancestors
  ```
- **Problem:** A tree of work plan steps, of processes or of the work of an agent can not be filtered. The matches are other documents than the rows, so the selection, the open nodes and the mark of the current page are mapped a second time. The plan of the arrangement says "a tree shows each match with its ancestors", and no step builds it.
- **Proposal:** The filter is view state of the `DocumentTree`: a condition on a row, which the listing of the children of a node applies, with the rule "a row stays when a row below it that the tree read stays". The rows stay the same documents at the same paths. The condition is an `ArrangementFilter`, so the bar, the chips and the verbs of the arrangement serve it.
- **What goes away:** `_ExplorerMatch`, `_collect_matches`, `_make_match_tree`, `_find_match_path`, the field `Explorer.matches`, the swap of the two trees and the second set of maps (about 150 lines).
- **What stays:** The words and the kinds of the explorer filter, rows shown with their ancestors, no read of a disk by the filter.
- **Risk and open questions:** A lazy list of children has no count, so a filtered count of children needs the walk that the tree already did. The paths of the rows of the widget change when rows hide; `DocumentTreeToWidgetTree` counts children over all collections.
- **Related plans:** `plan/pending/filter-sort-and-find-any-table.md` §3 names the behaviour; no step covers it. `plan/done/the-explorer-shows-what-the-editor-holds.md` (done; "no tree can be filtered" was a fact to change).
- **Check:** weakened; value medium. The facts hold: `ExplorerFilter.jl` (143 lines) builds `_ExplorerMatch` copies and a second `DocumentTree`, `Explorer.matches` computes it ([ExplorerDocument.jl:118](../../../source/platform/explorer/ExplorerDocument.jl#L118)), and `ExplorerToWidget` maps `tree` or `matches` by which one shows. The rule "A tree shows each match with its ancestors" is in §3 of `filter-sort-and-find-any-table.md`, which the owner agreed to on 2026-10-07, and no step of that plan builds it. So the aim is the owner's, and the missing piece is a step of that plan more than a new finding. The second tree has a stated reason, which the report gives only as a risk: step 6a of `the-explorer-shows-what-the-editor-holds.md` says "a second tree, and not a filter inside `DocumentTreeToWidgetTree`, because a filter there changes the index path of every row, which the maps, the open places and the shown rows of the tree all read". The decision is marked "mine" there, so it is no decision of the owner, but the proposal must solve exactly that problem and does not say how: a row `children[k]` of the widget is then no longer child `k` of the document, in each map of the tree. Two more open points: a lazy list of children has no count and no filtered form, and "a row stays when a row below it stays" needs a walk of the read rows below each node, which is what `_collect_matches` does now. The explorer filter also has kinds and words on the label; a label is no key of an item today, so `"label" => "smoke"` needs a facet. The saving is less than 150 lines, because the words and the kinds stay.

### CO-7 A row with named columns has three types, and a column is read in three ways

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** principle 7; principle 2, a general step knows no domain.
- **Today:** Inventory F. The table interface reads a value by a row number and a column name; five kinds of value are tables (`is_table`), and the pivot is its one reader. The arrangement reads a value of an item by a `Reference` key. The roster reads a dotted key with facets and keeps `RosterRow`. A group makes `ArrangementGroupRow`. Each row type has its own table printer: `RosterRowsToWidget` (lazy, header fields, link), `ArrangementGroupRowsToWidget` (every row, labels only, [NaturalArrangement.jl:301](../../../source/platform/natural/NaturalArrangement.jl#L301)), `PivotPartTableToWidget` (lazy, read-only) and `CellTableToWidgetTable` (every row). The pivot and the group each compute `:count`, `:sum`, `:mean`, `:minimum`, `:maximum` ([Grouping.jl:98](../../../source/platform/arrangement/Grouping.jl#L98), [PivotCrossTable.jl:512](../../../source/domain/pivot/PivotCrossTable.jl#L512)).
- **Example:**
  ```julia
  # today
  is_table(roster)                                   # false: a pivot can not read a roster
  get_table_value(frame, 2, "price")                 # table interface
  find_arrangement_key_value(item, @reference(price)) # arrangement
  compute_roster_value(row, "within.name")           # roster

  # after: a collection of items with keys is a table
  is_table(roster.rows)                              # true, by one generic method
  get_table_value(table, r, name) = find_arrangement_key_value(table[r], make_key(name))
  ```
- **Problem:** A pivot of the tasks, of a record table or of a `CellTable` is not possible, though "pivot any table" is the aim. After a group, the table loses the lazy rows, the header fields and the link. A facet that a slice declares is visible to the roster only. A new aggregate is added in two places.
- **Proposal:** One record protocol: a collection of items, and a key that names a value of an item. The table interface gets one generic method set for any such collection, so a roster, a record table and a vector of documents are tables. A group row and a roster row are one type, "a row of named values with its item or its members", with one printer. The aggregates live once, in the arrangement, and the pivot calls them.
- **What goes away:** `ArrangementGroupRowsToWidget` (about 60 lines), one of the two aggregate tables, the separate key parsers of the roster and the arrangement.
- **What stays:** The fast path of a column as a vector (`find_table_column`), the native part of a data frame, facets, `within`, the missing-value rules of the pivot.
- **Risk and open questions:** The pivot treats `missing` and the arrangement treats `nothing`; the two rules must be joined with care. A generic `get_table_value` over items is slower than a column vector; the pivot must keep reading `find_table_column` first.
- **Related plans:** `plan/pending/filter-sort-and-find-any-table.md` step 5 (pending) gives the generic printer of a table, not the joined model. `plan/done/pivot-any-table.md` (done).
- **Check:** weakened; value low. Several facts hold: `is_table` has five kinds and a delegate, and only the pivot reads the interface; a roster and a `CellTable` are no table; the two aggregate tables exist. But "a column is read in three ways" is too strong. The arrangement key is already one generic with a method for each row type: `find_arrangement_key_value(item, key)` ([Picking.jl:175](../../../source/platform/arrangement/Picking.jl#L175)), `(row::RosterRow, key)` ([RosterDocument.jl:185](../../../source/platform/roster/RosterDocument.jl#L185)) and `(row::ArrangementGroupRow, key)` ([Grouping.jl:110](../../../source/platform/arrangement/Grouping.jl#L110)). `compute_roster_value` is what the roster method calls, not a third protocol. So there are two protocols: the table interface for rows and columns, and the arrangement key for items. They differ for a reason that the plans state: the arrangement names "a path inside one item" for any collection (§5 of `filter-sort-and-find-any-table.md`), and the table interface gives a column as a vector for speed (P5 and P9 of `pivot-any-table.md`, the owner). The same §5 already joins them from the table side (a stage gives a `TablePart` for a table), and step 5 of that plan covers the one printer of any table. What remains: a pivot of a roster needs the methods of the table interface for a roster, which is a missing row in a mechanism that exists and no new model; and one type for a roster row and a group row. The two aggregate tables are about 12 lines each and differ on purpose (`missing` against `nothing`, `:distinct_count` only in the pivot, an operator that a slice adds only in the arrangement). The proposal would lose nothing that I can name, but the joined model is larger than the need.

### CO-8 A live table is built with a constructor of 25 positional cells

- **Kind:** complicated-api · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** principle 1, every field is a cell and can be computed; principle 11.
- **Today:** The keyword constructor of `WidgetTable` takes plain vectors or a `ListNode` and wraps each in a cell ([WidgetDocument.jl:3327](../../../source/platform/widget/WidgetDocument.jl#L3327)). A projection whose headers, cells or columns are computed can not use it. Eight projections pass all 25 cells by position: the roster ([RosterToGraphics.jl:368](../../../source/platform/roster/RosterToGraphics.jl#L368)), the data frame view twice ([DataFrameViewToWidget.jl:158](../../../source/adapter/dataframes/DataFrameViewToWidget.jl#L158)), the statistics, the `CellTable` view ([CellTableToWidgetTable.jl:49](../../../source/platform/widget/CellTableToWidgetTable.jl#L49)), the pivot twice and Markdown. Four more sites build a table and then replace the computation of a field with `set_cell_computation!` ([FileSystemDirectoryToWidget.jl:134](../../../source/platform/filesystem/FileSystemDirectoryToWidget.jl#L134), [RosterToGraphics.jl:503](../../../source/platform/roster/RosterToGraphics.jl#L503)).
- **Example:**
  ```julia
  # today
  WidgetTable(Cell(Point2D(0, 0)), headers, CellVector(), Cell(nothing),
              Cell(@computation rows_of(head[])), Cell(:row_major), Cell(WidgetTableRows(nothing)),
              Cell(@computation WidgetTableColumns(length(headers))), Cell(1), Cell(policy), Cell(Content),
              Cell(:clip), Cell(true), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
              Cell(Point2D(0, 0)), Cell(1), Cell(nothing), Cell(nothing), Cell(:auto), Cell(:auto),
              Cell(nothing), Cell(nothing))

  # after: a keyword takes a value, a cell or a computation
  WidgetTable(; column_headers = headers, cells = @computation(rows_of(head[])), column_policy = policy)
  ```
- **Problem:** A new field of the table changes every call site; the done plan of `shown` notes "the ten positional calls of `WidgetTable` follow the new field". The comment above the roster call lists 24 field names so that a reader can count; the call passes 25 cells, and the comment misses `shown`, here and above the call of the statistics (added by the check: [RosterToGraphics.jl:362](../../../source/platform/roster/RosterToGraphics.jl#L362), [FrameStatisticsToWidget.jl:415](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L415)).
- **Proposal:** One rule for the keyword constructor of a document: each keyword takes a plain value, a `Cell` or a `Computation`, and a `CellVector` where a vector is expected. `WidgetTable` gets defaults for its fields, as `WidgetTree` has for three of its fields.
- **What goes away:** Eight positional calls, the four `set_cell_computation!` repairs, and the special constructor `WidgetTable(headers::CellVector, cells::CellVector)`.
- **What stays:** Every field, every default, and the short form `WidgetTable(headers, rows)` for plain values.
- **Risk and open questions:** The rule belongs to `@document` or to the widget slice; the first is a kernel change and needs the seal check. (Corrected by the check: no kernel change is needed. `@document` has the rule already: the constructor of all fields takes a value or a cell for each field, and the macro makes a keyword constructor for a document that declares a default ([DocumentMacro.jl:460](../../../source/kernel/document/DocumentMacro.jl#L460)). The macro leaves the signature `WidgetTable(; …)` to the table because the table writes its own keyword constructor, which checks and converts its arguments. So the change is in that one constructor of the widget slice.) The same pattern exists for `WidgetTree` and `WidgetScrollBar` (other area: widgets).
- **Related plans:** none found. (The check: `plan/done/document-macro-positional-defaults.md` gave `@document` the defaults and the keyword constructors.)
- **Check:** confirmed-with-corrections; value medium. I counted the fields of `WidgetTable` (25) and the positional calls outside `WidgetDocument.jl`: eight, in the roster, the data frame view (two), the `CellTable` view, Markdown, the pivot (two) and the statistics. The keyword constructor takes only `Vector` or `ListNode` for the headers and the cells ([WidgetDocument.jl:3327](../../../source/platform/widget/WidgetDocument.jl#L3327)). For the sites that replace the computation of a field of a table after they made it, my grep of `set_cell_computation!(getfield(<table>, :cells…))` finds three (the page of a folder, the roster, `TaskGroupToWidget.jl:270`); the report says four, and the fourth may have another form. Two facts are corrected above: the comment that lists the fields is out of date by one field, which shows the cost that the finding names, and the kernel needs no change. The proposal loses nothing: the checks of the keyword constructor can run on a plain value and pass a cell through. The owner's note that the count of positional arguments is advice does not speak against it; the finding is about a constructor that can not take a computed field.

### CO-9 The stores of a roster are a table of the process, beside the session documents

- **Kind:** special-case · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** the settled decision "no process-global registry"; principle 6.
- **Today:** `_ROSTER_SOURCES` is a `Dict` of the process ([RosterSource.jl:151](../../../source/platform/roster/RosterSource.jl#L151)). Six slices fill it in their `__init__` with `register_roster_source!(name, link -> source)`. Each of the six functions makes its source without a read of its argument `link`, and four of them read a session document of the editor of the evaluation at once, for example `link -> CollectionItems(get_session_message_log().entries)` ([MessageLogToSyntax.jl:102](../../../source/platform/log/MessageLogToSyntax.jl#L102), [FaultLogToSyntax.jl:99](../../../source/platform/fault/FaultLogToSyntax.jl#L99), [McpLogToWidget.jl:121](../../../source/platform/mcplog/McpLogToWidget.jl#L121)). The tree slice solved the same need with a method table and no registry (`is_session_explorer_entry_type`).
- **Example:**
  ```julia
  # today
  function __init__()
      register_roster_source!(:log, link -> CollectionItems(get_session_message_log().entries);
                              description = "the lines of the message log of the session")
  end

  # after: a method is the entry
  RosterModule.make_roster_store(::Val{:log}) = CollectionItems(get_session_message_log().entries)
  ```
- **Problem:** A second way to name "the collection of a session document", with its own list of names. A source reaches the session in two ways: through `link` (`TabDocuments`) or through the editor of the evaluation (the stores).
- **Proposal:** A method for each store name; `get_roster_source_names()` reads the method table, as `describe_roster_sources()` already reads the methods of `collect_roster_parts`. The description is the docstring of the method.
- **What goes away:** `_ROSTER_SOURCES`, `register_roster_source!`, six `__init__` calls.
- **What stays:** `StoreRecords(:log)`, the names, the list for the assistant, a file that keeps a roster of a store.
- **Risk and open questions:** A package that registers at run time, after load, has no method; I found no such caller. The natural renderer has the same pattern (`register_natural_graphics!`), which is another area.
- **Related plans:** none found.
- **Check:** weakened; value low. The facts hold: the `Dict` is at [RosterSource.jl:151](../../../source/platform/roster/RosterSource.jl#L151), six slices register in their `__init__` (`:log`, `:tasks`, `:frames`, `:faults`, `:workflows`, `:mcp_log`), none of the six reads `link`, and four read a session document at once. But the settled decision does not apply here. It is about state of one editor (session documents, open files, registries of what an editor holds). This table holds no state of an editor: it maps a name to a function, it is filled when the code loads, and it is the same for every editor, as a method table is. The rule PAR-FRAMEWORKS-SINK allows it by name: "A lower layer declares open generics (or a small registry)" ([architecture-invariants.md:1416](../../../documentation/rule/architecture-invariants.md#L1416)). The platform and the domains have 18 functions named `register_…!`; nine of them fill the tables of the natural renderer at load in the same way (the comment at the `Dict` says so), and I did not open the other eight. So a change of this one alone makes the code less uniform, not more. Two costs of the proposal: `describe_roster_sources()` would read a docstring at run time, which a trimmed build may not keep, and a second package that offers a store of the same name would overwrite a method of another package, which breaks precompilation, where the table only replaces an entry. What stays of the finding: the argument `link` of `make_source(link)` is read by no store, so the functions can take no argument.

### CO-10 `CellMatrix` has no user

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** principle 11.
- **Today:** `CellMatrix` is a rectangle of cells (172 lines). No file of `source/` outside the collection slice names it; one test does (`DocumentDuplicateTest.jl`). The two dependent repositories that I searched do not name it. It is a member of the union `CollectionDocument` ([CollectionDocument.jl:22](../../../source/platform/collection/CollectionDocument.jl#L22)), so each rule of that union must consider it. `CellTable` is the grid that the code uses, and it has two users.
- **Example:**
  ```julia
  # today
  const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}
  # after
  const CollectionDocument = Union{CellVector, CellTable, ListNode}
  ```
- **Problem:** A fourth collection shape that every generic rule must name and no view shows.
- **Proposal:** Remove `CellMatrix`, or keep it only when a spreadsheet view needs a fixed rectangle.
- **What goes away:** `CellMatrix.jl` and its cases.
- **What stays:** `CellTable` for a grid.
- **Risk and open questions:** A user outside the three repositories that I searched. The formula domain may want a matrix later.
- **Related plans:** none found. (The check: `plan/pending/strict-document-types.md` line 834 says that the union with its four members stays.)
- **Check:** confirmed-with-corrections; value low. The facts hold: `CellMatrix.jl` has 172 lines; in `source/` only the five files of the collection slice name the type; one test line does (`DocumentDuplicateTest.jl:109`); omnet-julia and inet-julia do not. Three additions. (1) The type is exported and `collection.md` documents it with an example (lines 14, 135, 152), two precompile workload lists name it, and the released copy of the platform holds it. So a removal takes a public, documented type away, which is a feature of the package for its users even with no view of it, and after a release it is a step of the minor version. The owner decides this; the report's second choice, "keep it", loses nothing. (2) The stated cost, "each rule of that union must consider it", does not show in the code: no file outside `CellMatrix.jl` has a method or a branch for `CellMatrix`, and the ten uses of `CollectionDocument` outside the slice name the union only. (3) The stronger fact is that the type has almost no test and no view, so nobody knows whether a path, a selection, a save and a copy work for it. That is a partly implemented feature, and the choice is "finish and test it" or "remove it".

## Covered by plans

- The data frame view has its own filter, sort, find and query: `plan/pending/filter-sort-and-find-any-table.md`, step 6.
- No generic printer shows any table (a `CellTable`, a vector of named tuples, a result of a query); `PivotPartTableToWidget` is one, in the pivot domain: the same plan, step 5.
- A collection that its parent prints inside its own print gets no arrangement: the same plan, step 7 and the gap of step 3c.
- The header parts (sort glyph, filter field, value list) shared by the data frame table and the roster table; the table of a task group as a roster: `plan/pending/the-header-of-a-table-filters-and-sorts-its-arrangement.md`, in progress.
- An insert or a delete in a collection does not move the selection and the stored paths after it: `plan/pending/an-insert-moves-the-paths-after-it.md`.
- The pivot does not follow the head of its list; a table of a list shows no rows in a PDF; a pivot of a database query: `plan/pending/pivot-table-next-steps.md`, L2, L4 and P5.
- The fold of a node is kept on about 40 content types: `plan/pending/views-compose-as-content-composes.md` (later) and `plan/pending/collapse-expand-syntax-nodes.md`.
- A table of records that the assistant fills: `plan/pending/the-assistant-fills-a-live-table.md`, in progress.
- Edits of a data frame: `plan/pending/view-and-edit-a-data-frame.md`.

## Examined and sound

- The builders of a lazy list (`make_index_list`, `make_mapped_list`, `set_lazy_link!`): one set, used by the table, the tree, the roster, the pivot and the data frame view.
- The arrangement as documents (`ArrangementEntry`, `ArrangementFilter`, `ArrangementSort`) and one dispatch (`make_arranged_dispatch`): saved, undone and edited as any document, and a place that nobody arranged costs nothing.
- `ArrangeCollectionOperation`: one operation that a header, a menu and a verb of the assistant all make; the nearest holder converts it.
- The cost model of the roster: one cell for each part, each item and each value, measured in `roster.md`.
- The four tree generics and the open places by identity in `DocumentTree`: a slice adds a node kind with methods only.
- The seams between the kernel and the collection slice: the kernel names no collection type.
- `TablePart` against a native part (`SubDataFrame`): one seam, `make_table_part`, with a generic default.
- The paths of a table by its field names (`rows[r]`, `columns[c]`, `cells[r][c]`): one vocabulary in both forms of the table.
- The source protocol of a roster (`collect_roster_parts`, `collect_roster_items`, `get_roster_item_inside`): parts give the cost of what changed; five slices add a source with methods only.
- The outline kit: builders over widgets that exist, no new widget; sampled only.
- The inspector slice and the `dbcatalog` domain: plain documents shown through the text and syntax domains; no list mechanism of their own; sampled only.
- `ObjectToWidget` against the roster: a form edits one object and a roster lists many; they differ in job. What they could share is named in CO-7.

## Check of the report

A second agent checked each finding against the code at commit 3a9b4fae4, the guides and the plans. It read files and ran grep; it ran no Julia. Each finding has a line **Check** with what was opened, what was corrected and what the proposal would lose.

| Id | Verdict | Value in the report | Value after the check | The main point of the check |
| --- | --- | --- | --- | --- |
| CO-1 | weakened | high | medium | The facts hold. A view document can hold no part that takes a selection today (decision D1 of `a-view-document-keeps-the-state-of-one-view.md`), so the move of the table to a view needs the later plan `views-compose-as-content-composes.md`. One maker and one page projection for a held table can be done now. |
| CO-2 | confirmed-with-corrections | high | high | The counts hold. The reason that `one-table-widget.md` gives for two forms covers only the canvas, not the two readers of today. The lines that go away are fewer than 1,300. A table with no offered height must keep working. |
| CO-3 | weakened | high | medium | Four tables hold (assistant list, search matches, page of a folder, help group). The frames table needs a header column and a corner that the roster has not, and a plan names it. The MCP log would lose its text in line. The stream lines as a text are not measured. |
| CO-4 | weakened | medium | low | The reflection half has a stated reason in `reflection.md` ("the open state is the marker"). The file system half holds; the plan of the explorer kept the Files tool as a special component on purpose. |
| CO-5 | confirmed-with-corrections | medium | medium | A typed operation that carries the count holds. "An owner writes no reader" does not: the owner still maps the move in its reader, as the data frame view does for the width of a column. |
| CO-6 | weakened | medium | medium | The aim is in §3 of `filter-sort-and-find-any-table.md` with no step. The second tree has a stated reason (the index path of every row changes), which the proposal does not solve. |
| CO-7 | weakened | medium | low | The roster row and the group row already answer one generic, `find_arrangement_key_value`. Two protocols remain, with a stated reason. A pivot of a roster needs methods of the table interface, not a new model. |
| CO-8 | confirmed-with-corrections | medium | medium | 25 fields and eight positional calls. `@document` has the rule already, so the change is in the keyword constructor of the table alone. The comment that lists the fields misses one. |
| CO-9 | weakened | low | low | The table holds no state of an editor, and PAR-FRAMEWORKS-SINK allows a small registry. What stays: the argument `link` that no store reads. |
| CO-10 | confirmed-with-corrections | low | low | No user and almost no test. The type is exported and documented, so its removal is a choice of the owner. The cost that the report names does not show in the code. |

One thing that the check saw and the report did not: `WorkflowListToWidget` is the only one of the seven pages of CO-1 with no `read_intent` of its own ([WorkflowListToWidget.jl](../../../source/domain/workflow/WorkflowListToWidget.jl), 70 lines), so it calls neither `keep_held_arrangement` nor `retarget_held_row_open`. I did not run it; by the code, the last chip that goes takes the arrangement out of `WorkflowList.table`. Whether the open of a row there also needs the second repair depends on its source `_OpenWorkflows`, which I did not follow.
