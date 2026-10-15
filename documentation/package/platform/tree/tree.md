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

The open nodes are `expanded`, an `IdDict` whose keys are the documents of the open nodes. A node is open by the identity of its document and not by its index, so a node that comes or goes before another node does not change which nodes are open. The root is open at the start. `expanded` is view state: a write replaces the whole `IdDict` as view state, so the undo history records no open or closed node, and a file keeps the root and the title and no open node. The `IdDict` is a dictionary, because a walk of the documents enters a dictionary by its values. A `Base.IdSet` keeps its keys in a field that the walk enters, and `search_documents` would find each open document a second time.

### Three generics make a document a node

The slice names no kind of node. A slice that owns a kind adds methods to three generics, and each has a default, so any document is a leaf with a label.

| Generic | Answers | Default |
| --- | --- | --- |
| `get_tree_children_steps(document)` | the reference steps from the node to each collection of its children, in order, as a tuple of tuples | `()`: the node is a leaf |
| `format_tree_node_label(document)` | the text of the node, in one line: the node draws a line break as a space | the title of the document, else the name of its type that a person sees |
| `get_tree_node_icon(document)` | a Lucide glyph, as a `Symbol` | `nothing`: no icon |

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

The three functions run inside a computation, so they read cells, and a node follows what it reads.

### The print

`DocumentTreeToWidgetTree` prints a `DocumentTree` as one `WidgetTree`, which scrolls itself in the slot that its parent gives it. Each node is two lazy lists: the entries of its children, and the widget nodes of its children. A list computes one element at its first read, so a node reads the collections of its document only when the tree draws the node or opens it.

A label reads only the cells of its own document. So a change of the text of one document computes its own node again, and the nodes under it keep their list. A document that is again on the path to its own node stays closed there, so a cycle of documents does not open without end.

A tree draws through `make_graphics_projection(DocumentTree)`, which chains the print to a widget renderer of its own, so a tree draws in the natural renderer and in the card of a pane.

### The maps follow the steps

The path of a node in the widget is `roots[1].children[k]…`, where `k` counts the children of a parent over all its collections. The path of its document is the path of its parent, the steps of the collection, and the index in that collection. The reader maps both ways with no code for each kind of node.

For example, take a root with two documents in `parts` and one in `notes`. The third child of the root has the widget path `roots[1].children[3]` and the document path `root.notes[1]`. A path outside the root has no image. The path of the tree itself is the widget, and a part that the view drew, such as a scroll bar, is named by an introduced path.

### The chevron writes the open nodes

A press on a chevron answers `ReplaceViewStateOperation(ReplaceReferencedValueOperation(widget, "expanded", paths))`. The reader of `DocumentTreeToWidgetTree` turns the answer into the same write of `expanded` of the `DocumentTree`, with the documents at those paths. The tree document holds no document that left the tree.

### A node opens a page

Return while a node is selected, and a double click on a node, answer `OpenPageOperation(nothing, <path of the node>)`. A first press still selects the node, because only a press with the count two matches the binding. A node answers in the frame of the widget: the reader of the widget tree does not put the path of the node before the answer. So the binding of a node names its own path, `roots[1].children[k]…`, and `DocumentTreeToWidgetTree` maps it to the path of the document.

The nearest navigator around the tree takes the open, shows the document of the node as a page with the view of its type, and Back returns to the tree. With no navigator, the editor opens a new tab with a navigator ([navigator.md](../navigator/navigator.md)). `OpenPageOperation` is a type of the widget slice, so this slice does not name the navigator. A slice gives its kind of node a page view only where the page must look different from the node. The slices that use the tree do it for a system process, a plan step, the work of an agent and a task.

### The verb

`show_document_tree!(root; title, editor)` shows a tree in a tab of the window of `editor`, and answers the tree in its window as a `ReferencedDocument`, as `show_roster!` does. A `DocumentTree` in place of a root shows with its own title. The verb is declared to the assistant, and its system text names it.

## How it fits

The slice uses the collection, graphics, natural, projection, roster, screen, serialization, style and widget slices of the platform. It uses the roster slice for the facet `type` of a document, which the default label reads. It loads after `roster` and before `systemprocess` and `workplan`.

These slices add kinds of node:

| Slice | Node | Children |
| --- | --- | --- |
| [systemprocess.md](../systemprocess/systemprocess.md) | `SystemProcessTree`, `SystemProcess` | the roots; the children of a process |
| [workplan.md](../workplan/workplan.md) | `WorkPlan`, `WorkPlanStep` | the steps; the steps under a step |
| [task.md](../task/task.md) | `TaskDocument` | none; a task is a leaf |
| [assistant.md](../assistant/assistant.md) | `AgentWork`, `AssistantWork` | the subagents, then the background tasks |

## Design decisions

- **One tree for every kind of document.** The file tree of the Explorer shows one kind of node. The tree slice shows any kind, and a slice adds only the three generics. The options and the steps are in [the-assistant-shows-the-work-of-its-agent.md](../../../../plan/pending/the-assistant-shows-the-work-of-its-agent.md).
- **A node is open by the identity of its document.** An open node that a path of indices names would name another node after an insert.
- **Each node reads its own cells.** A change of one document draws its own label again, and no other label.
- **A double click opens a page and adds no event.** The answer is the operation that every link already makes, so a tree needs no reader above the navigator.

## Limits

- **No columns.** A node is one line of text with an icon. A table of the same items is a `Roster`.
- **A node under a closed node leaves `expanded` at the next write.** The open paths of the widget list the open nodes that a walk reaches through open nodes only. A node that opens again shows its children closed.
- **A label is text.** A node has no button, no badge and no editable part. A press on a node selects or opens its document.
- **A file keeps no open node.** A tree read from a file has its root open.

## Layer structure

The slice is the folder [source/platform/tree/](../../../../source/platform/tree/), and `TreeModule` is its module.

```
tree/TreeModule.jl                (TreeModule): the module, its exports and its include order
    ├─ TreeInterface.jl           : the three generics, with no body
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
- a change of one document computes its own node again and no other;
- the verb shows a tree in a tab;
- in a real `Editor`, a double click on a node and on a row of a roster opens a page in a navigator, and Back returns.
