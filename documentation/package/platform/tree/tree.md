# Tree

> **Kind:** design · **Status:** current · **Stands on:** [cell.md](../../kernel/cell.md), [roster.md](../roster/roster.md), [widget.md](../widget/widget.md), [navigator.md](../navigator/navigator.md)

The tree slice of `ProjecturedPlatform` shows a document of any type, with the documents under it, as a tree. This document says how a document becomes a node, how a tree keeps its open nodes, how a double click or Return on a node opens a page, and how a slice adds its own kind of node.

## How it works

### The tree document

`DocumentTree(root; title)` holds a **root**, a **title** and the **open nodes**. It shows `root` as a tree, as a `Roster` shows the items of a source as a table. The default title is the text of the root node.

```julia
tree = DocumentTree(plan; title = "Steps")
show_document_tree!(plan; title = "Steps")        # the same, in a tab of the window
```

The open nodes are `expanded`, the open places: an `IdDict` whose keys are the documents of the open nodes below one place, each with the `IdDict` of the open places below it, and whose one key at the top is the root. A place is open by the identity of the documents on its path and not by its indices, so a node that comes or goes before another node does not change which nodes are open, and one document under two parents opens at each place on its own. Two siblings that are the same document under one parent are the same place, so they open together. The root is open at the start. `expanded` is view state: a write replaces the whole `IdDict` as view state, so the undo history records no open or closed node, and a file keeps the root and the title and no open node. `collect_open_tree_documents(tree)` gives the documents of the open nodes, each once. The `IdDict` is a dictionary, because a walk of the documents enters a dictionary by its values. A `Base.IdSet` keeps its keys in a field that the walk enters, and `search_documents` would find each open document a second time.

`current` is the path from the root of the node whose row has the mark of the current page, or `nothing`. It is a value, a cell, or a function of no argument, whose answer the tree follows. The row of that node draws a narrow bar at its left edge; a path that goes on into the document of a node marks that node. An explorer gives the address of the page of its navigator, so the mark follows the page also after a link inside the page.

### Four generics make a document a node

The slice names no kind of node. A slice that owns a kind adds methods to four generics, and each has a default, so any document is a leaf with a label. A fifth generic, `is_explorer_entry_type(type)`, is no part of the node: it says whether a person adds a document of `type` as an entry of an explorer. Its default is `false` (`TreeDefaults.jl`), and a slice that owns such a kind adds a method that answers `true` ([explorer.md](../explorer/explorer.md)).

| Generic | Answers | Default |
| --- | --- | --- |
| `get_tree_children_steps(document)` | the reference steps from the node to each collection of its children, in order, as a tuple of tuples | `()`: the node is a leaf |
| `format_tree_node_label(document)` | the text of the node, in one line: the node draws a line break as a space | the title of the document, else the name of its type that a person sees |
| `get_tree_node_icon(document)` | a Lucide glyph, as a `Symbol` | `nothing`: no icon |
| `has_tree_children(document)` | `true`, `false`, or `nothing` while that is not known | `true` when a collection of the children has an element: the default reads the children |

The children of a node are the elements of its collections, one collection after the other. So a node can have two kinds of children. The work of an agent has two: its subagents, then its background tasks. A process has one, the field `children`. A collection whose path reaches nothing gives no children.

```julia
@document struct Folder <: Document
    name::String
    children::CellVector
end

TreeModule.get_tree_children_steps(::Folder) = ((FieldReferenceStep("children"),),)
TreeModule.format_tree_node_label(folder::Folder) = folder.name
TreeModule.get_tree_node_icon(::Folder) = :folder
```

The functions run inside a computation, so they read cells, and a node follows what it reads.

The row of a node draws the decoration of its document (`get_document_decoration` of the domain slice). The icon, with its tint and corner marks, comes from `make_decoration_icon`. The counts follow the label as pills (`make_decoration_badges`), and the detail follows as dim text. The words of the conditions are the tooltip of the row, which shows when the pointer rests on it (`_read_wtree_row_dwell`).

A row draws a chevron only when `has_tree_children` answers `true`. A document whose children come from outside, such as a folder, answers from what it stores, so a closed row reads no children. `DocumentTreeToWidgetTree` gives each `WidgetTreeNode` the function `has_children = () -> has_tree_children(document) === true`. When a node gives `has_children`, the widget tree reads the chevron from it and reads no children while the row is closed. A node with no `has_children` reads its children for the chevron.

### The print

`DocumentTreeToWidgetTree` prints a `DocumentTree` as one `WidgetTree`, which scrolls itself in the slot that its parent gives it. Each node is two lazy lists: the entries of its children, and the widget nodes of its children. A list computes one element at its first read, so a node reads the collections of its document only when the tree draws the node or opens it.

A label reads only the cells of its own document. So a change of the text of one document computes its own node again, and the nodes under it keep their list. A document that is again on the path to its own node stays closed there, so a cycle of documents does not open without end.

A document whose one collection of children is a lazy list, a `ListNode`, has its entries and its widget nodes as two lists that mirror that list node for node (`make_mapped_list`). A node of them is made when a walk of the rows first reaches it, so a document with a million children makes only the entries of the rows in view, and the widget tree makes its rows as a lazy list too ([widget.md](../widget/widget.md)). The mirror is made again when the document gives a new list. `has_tree_children` is `true` by default for a lazy list of children, which has a node at its head.

A tree draws through `make_graphics_projection(DocumentTree)`, which chains the print to a widget renderer of its own, so a tree draws in the natural renderer and in the card of a pane.

`collect_tree_children(document; limit)` and `collect_read_tree_children(document)` are exported helpers. The first gives the first `limit` children of a document with the path of each, and walks a lazy list on from its head. The second gives only the nodes of a lazy list that a walk reached, so it reads no disk and no process. The page of a section and the filter of an explorer use them.

### The maps follow the steps

The path of a node in the widget is `roots[1].children[k]…`, where `k` counts the children of a parent over all its collections. The path of its document is the path of its parent, the steps of the collection, and the index in that collection. The reader maps both ways with no code for each kind of node.

For example, take a root with two documents in `parts` and one in `notes`. The third child of the root has the widget path `roots[1].children[3]` and the document path `root.notes[1]`. A child of a lazy list counts from the head of the list in both paths, and the maps read no link of the list that a walk did not read: a child that no walk reached maps no farther than its parent. A path outside the root has no image. The path of the tree itself is the widget, and a part that the view drew, such as a scroll bar, is named by an introduced path.

### The chevron writes the open nodes

A press on a chevron answers `ReplaceViewStateOperation(ReplaceReferencedValueOperation(widget, "expanded", paths))`. The reader of `DocumentTreeToWidgetTree` turns the answer into the same write of `expanded` of the `DocumentTree`, with the open places of those paths. The tree document holds no document that left the tree.

A `DocumentTree` holds the documents of its open nodes and of the rows that its view shows while a tab holds the tree. The acquire of the tree acquires each open document, and the release releases the same documents. The answer of the chevron contains a `ChangeHeldDocumentsOperation` in the same view-state write. It releases the documents of the nodes that close and acquires the documents of the nodes that open. So a document that opens, such as a folder, starts its read, and an undo records neither the open node nor the change of the hold. A tree that no tab holds holds nothing.

The widget writes the rows of its view as it writes its open nodes: beside each scroll and each toggle, `shown` of the widget gets the paths of the rows that the view shows after the answer. The reader turns that write into `shown` of the tree, the documents of those rows, and changes the holds once against the open and the shown documents together, so a node that closes while it is shown stays held. A document that comes into view starts what it needs, such as the read of the details of a run, and one that leaves the view is released. A tree whose view told it no row yet holds the first fifty children of each open lazy list of children at its acquire. A window that grows, or a list that changes by itself, writes no `shown`, so the rows that come into view that way are held at the next scroll or toggle ([plan/done/a-viewport-holds-the-rows-it-shows.md](../../../../plan/done/a-viewport-holds-the-rows-it-shows.md)).

### The keys

Up and Down move the selection by one row. With no modifier, Right opens a closed node and goes to the first child of an open one, Left closes an open node and goes to the parent of any other, Home and End go to the first and the last row, and Page Up and Page Down move by the rows that the view holds, less one. End does nothing in a tree whose rows are a lazy list, which can have no end.

### A node opens a page

Return while a node is selected, and a double click on a node, answer `OpenPageOperation(nothing, <path of the node>)`. A first press still selects the node, because only a press with the count two matches the binding. A node answers in the frame of the widget: the reader of the widget tree does not put the path of the node before the answer. So the binding of a node names its own path, `roots[1].children[k]…`, and `DocumentTreeToWidgetTree` maps it to the path of the document.

The nearest navigator around the tree takes the open, shows the document of the node as a page with the view of its type, and Back returns to the tree. With no navigator, the editor opens a new tab with a navigator ([navigator.md](../navigator/navigator.md)). `OpenPageOperation` is a type of the widget slice, so this slice does not name the navigator. A slice gives its kind of node a page view only where the page must look different from the node. The slices that use the tree do it for a system process, a plan step, the work of an agent and a task.

### The verb

`show_document_tree!(root; title, editor)` shows a tree in a tab of the window of `editor`, and answers the tree in its window as a `ReferencedDocument`, as `show_roster!` does. It runs through `run_on_editor_task!`, so any task can call it, and with no `title` it reads the label of the root there. A `DocumentTree` in place of a root shows with its own title. The verb is declared to the assistant, and its system text names it.

## How it fits

The slice uses the collection, domain, graphics, natural, projection, roster, screen, serialization, style and widget slices of the platform. It uses the domain slice to hold the documents of its open nodes: the acquire of a tree holds them, and a chevron changes what it holds (`ChangeHeldDocumentsOperation`). It uses the roster slice for the facet `type` of a document, which the default label reads. It loads after `roster` and before `systemprocess` and `workplan`.

These slices add kinds of node:

| Slice | Node | Children |
| --- | --- | --- |
| [systemprocess.md](../systemprocess/systemprocess.md) | `SystemProcessTree`, `SystemProcess` | the roots; the children of a process |
| [workplan.md](../workplan/workplan.md) | `WorkPlan`, `WorkPlanStep` | the steps; the steps under a step |
| [task.md](../task/task.md) | `TaskGroupList`, `TaskGroupDocument`, `TaskDocument`, `ClosedTaskGroup` | the groups; the tasks of a group; the tasks of the inner group of a task that is a group, else none |
| [assistant.md](../assistant/assistant.md) | `AssistantList`, `Assistant`, `AgentWork`, `AssistantWork` | the assistants; the subagents, then the background tasks |
| [filesystem.md](../filesystem/filesystem.md) | `Workspace`, `WorkspaceFolder`, `FileSystemDirectory`, `FileSystemFile` | the folders; the entries of the folder document; the entries of a folder; none |
| [explorer.md](../explorer/explorer.md) | `ExplorerSection`, `Dashboard`, `DashboardCard` | the entries; the cards; none |

## Design decisions

- **One tree for every kind of document.** The file tree of the Explorer shows one kind of node. The tree slice shows any kind, and a slice adds only the four generics. The options and the steps are in [the-assistant-shows-the-work-of-its-agent.md](../../../../plan/done/the-assistant-shows-the-work-of-its-agent.md).
- **A place is open by the documents on its path.** An open node that a path of indices names would name another node after an insert, and an open node that only its document names would open at every place of the document. The owner chose places on 2026-10-17 ([the-explorer-shows-what-the-editor-holds.md](../../../../plan/pending/the-explorer-shows-what-the-editor-holds.md), Q1).
- **Each node reads its own cells.** A change of one document draws its own label again, and no other label.
- **A double click opens a page and adds no event.** The answer is the operation that every link already makes, so a tree needs no reader above the navigator.

## Limits

- **No columns.** A node is one line of text with an icon. A table of the same items is a `Roster`.
- **A node under a closed node leaves `expanded` at the next write.** The open paths of the widget list the open nodes that a walk reaches through open nodes only. A node that opens again shows its children closed.
- **A label is text.** A row has no button and no editable part. It has badges, which are the counts of the decoration. A press on a node selects or opens its document.
- **A file keeps no open node.** A tree read from a file has its root open.
- **A lazy list of children is the only collection of its node.** It has no count, so a lazy list beside another collection gives no children.
- **An open child of a lazy list opens only after a walk reached it.** The open nodes are found among the entries that a walk made, so a child that no row showed stays closed.

## Layer structure

The slice is the folder [source/platform/tree/](../../../../source/platform/tree/), and `TreeModule` is its module.

```
tree/TreeModule.jl                (TreeModule): the module, its exports and its include order
    ├─ TreeInterface.jl           : the generics, with no body
    ├─ TreeDefaults.jl            : their fallback behaviours
    ├─ TreeDocument.jl            : DocumentTree
    ├─ DocumentTreeToWidgetTree.jl: the print, the reader, the maps, the open nodes, the open of a page
    └─ TreeProgram.jl             : show_document_tree!
```

## Tests

`test_document_tree()` in `ProjecturedPlatformTest`, in `test/platform/tree/TreeTest.jl`:

- the nodes of plain documents with one or two collections of children;
- the maps of a path both ways;
- an open node stays open when a node comes before it;
- a node whose children are a lazy list of a million makes the entries that the rows reach, maps its paths both ways from the head, and holds a child that a chevron opens;
- a change of one document computes its own node again and no other;
- the verb shows a tree in a tab;
- in a real `Editor`, a double click on a node and on a row of a roster opens a page in a navigator, and Back returns.
