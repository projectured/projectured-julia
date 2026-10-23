# Explorer

> **Kind:** design · **Status:** current · **Stands on:** [tree.md](../tree/tree.md), [navigator.md](../navigator/navigator.md), [domain.md](../domain/domain.md)

The explorer slice of `ProjecturedPlatform` shows what an editor holds in one tab: a tree of sections and entries on the left, and the page of the selected node in a navigator on the right. This document says how a section holds its entries, how a person adds, removes, moves and filters them, how a dashboard holds cards, and how the content of a window is kept for the next start.

## How it works

### A section holds entries

An `ExplorerSection(title, entries)` is a list of entries with a title. An entry is any document: a folder, the task list of the editor, a project, a dashboard, another section. A section links its entries and does not own them, so one document can be an entry of many sections, and a removal leaves the document as it is.

`find_navigator_address(::ExplorerSection, document)` asks each entry for the document and puts the place of the entry before the answer. So a document with a root of its own, such as a task group that a Run starts, opens at its full address in the explorer.

Each editor has one root section, `get_session_explorer_content(; editor)`: the section that an explorer in a tab of its window shows, else a new empty one. The application makes the first content with `make_editor_explorer_content(; editor, entries)` once the editor exists.

### An explorer is a tree beside a navigator

`Explorer(content; filter)` holds four documents:

| Field | Document | What it holds |
| --- | --- | --- |
| `tree` | `DocumentTree` of the section | the open places, the shown rows, the mark of the current page |
| `navigator` | `Navigator` over the section | the page, the visits, the address |
| `filter` | `ExplorerFilter` | the words and the kinds that a row keeps |
| `matches` | a `DocumentTree` of `_ExplorerMatch` rows, or `nothing` | the rows that the filter keeps, while it keeps rows out |

`ExplorerToWidget` draws a `WidgetSplitPane` of two sides. The left side holds a bar (the field of the filter, `+` and `▾`) above the tree, or above the tree of the matches while the filter keeps rows out. The right side holds the navigator. Each side is a `LayoutConstraint` with a share of the width, 1 for the left side and 3 for the navigator, so the navigator starts three times as wide. A drag of the divider sets the two widths. After it, the tree keeps its width when the explorer gets narrower or wider, such as by a drag of a divider of the window, and the navigator takes the change. The widths live in the split pane, so a new start of the editor starts at 1 : 3 again. The paths map so:

```
filter.text<rest>    elements[1].child.children[1].children[1].content<rest>
tree.<rest>          elements[1].child.children[2].children[1].<rest>    while no filter
matches.<rest>       elements[1].child.children[2].children[1].<rest>    while a filter
navigator.<rest>     elements[2].child.<rest>
```

The holder of the tree is a `VerticalLayout` whose one child is computed, so the other tree prints when the filter starts or ends. Each layout of the left side carries the part of the path of the split pane below it, so a key reaches the part that holds the caret.

### A press shows a page

The reader of the view reads the answers of the tree and of the tree of the matches:

| Gesture on a row | Effect |
| --- | --- |
| press | the selection stays in the tree, and the navigator visits the page of the document of the row |
| Ctrl+press | the page opens in a new tab, as a navigator rooted at the section |
| double press, Return | the keyboard goes into the page |
| right press | the menu of the row |

The tree marks the row of the page of the navigator (`DocumentTree.current`), also after a link on a page moves the navigator.

A visit of the navigator to a page below the root section, such as a link on a page or a match of a search, opens the nodes above that page in the tree (`make_tree_reveal_operation`, [tree.md](../tree/tree.md)).

### The keys of the explorer

`@gestures Explorer` holds the keys that work while the selection is on a row:

| Key | Effect |
| --- | --- |
| Insert, `+` | the menu of the kinds that a person adds, and "Other document" |
| Delete | the selected entry leaves its section, and the section is selected |
| F2 | the caret goes to the title of a section or a dashboard, on its page |
| Ctrl+Shift+Up, Ctrl+Shift+Down | the selected entry moves in its section |
| Ctrl+F | the caret goes to the field of the filter |
| Return (in the field of the filter) | a search for its text below the node of the page |
| "New section" | a command with no key: a new section after the selected entry |

The tree moves its selection with Up and Down whatever the modifiers, so the two keys that move an entry are `override` rules, and the reader gives a key that the tree answered to the table of the explorer as a claimed key. Escape in the field of the filter empties the filter; the reader reads it, as the navigator reads Escape in its address. Return in the field starts a search ([the search below a node](#the-search-below-a-node)).

### The kinds that a person adds

A kind is in the list of `+` when `is_explorer_entry_type(::Type)` of the tree slice answers `true` for it. The list is the insertion candidates of `Document` with that trait, each named by its first insertion alias:

| Kind | Alias | The document of a new entry |
| --- | --- | --- |
| `WorkspaceFolder` | folder | a folder with no place, whose page has a field for the place |
| `TaskGroupList` | tasks | the task list of the session |
| `AssistantList` | assistants | the assistant list of the session |
| `ExplorerSection` | section | an empty section, "New section" |
| `Dashboard` | dashboard | an empty dashboard, "New dashboard" |

A domain adds its own kinds the same way: the research domain a study, "New study",
and the workflow domain a workflow, "New workflow", each of which opens with one
quiet row where the first key makes the first item.

"Other document" adds a `DocumentInsertion`, whose page takes the name of any document.

### The add of an entry

`AddExplorerEntryOperation(document; section, index, navigator, selection)` is in the widget slice, beside `OpenFileOperation`, so a menu of the navigator and a command of the pane name it. The editor evaluates it: the entry goes into its section, then the navigator visits its page, and its node is selected. The visit and the selection come after the insert, because neither the page nor the node exists before it. Its inverse removes the entry.

"Add to explorer" adds a document at the end of the root section: from the menu of a part on a page, from the menu of a row below an entry, and from the command "Add the tab to the explorer" of the pane tree.

### The menu of a row

A right press on a row opens one layer named by the row: Open in a new tab; Remove from explorer for an entry, with Move the entry earlier and Move the entry later where the entry can move, or Add to explorer for a node below an entry; Rename for a section or a dashboard; New section and Add… for a section; Open as a list for a node with a lazy list or more than 50 children; then each command of the gesture table of the document that applies now, rerooted from the place of the document in the tree. One function, `_collect_row_commands(explorer, steps; selects)`, builds the items of the explorer, and the commands of a row for an assistant come from it too ([below](#what-an-assistant-calls)).

### The filter

The filter keeps a row when its label holds every word of the text, in any case, and its type is one of the kinds, or when a row below it stays. The tree of the matches walks the open places of the tree with `collect_read_tree_children`, so it reads the labels of the rows that the tree read, and no disk. Every row of the matches is open. `▾` lists the kinds of the read rows, with the icon `check` on the kinds that the filter keeps. An edit of the filter is view state, so an undo records none.

### The search below a node

Return in the field of the filter, with a text, answers `StartExplorerSearchOperation(explorer, text)`. The node is the node of the page of the navigator, or the root when the content of the navigator is not the root section.

The evaluation makes `ExplorerSearch(root, steps, text; depth = 10, limit = 100, identifier)`. The identifier is `S1`, `S2`, …: one more than the items of the list of the session whose identifier starts with `S`. The evaluation adds the search to the task list of the session and shows its page in the navigator. The caret stays in the field. The operation is no edit, so undo records none, and it answers `is_self_contained_operation`.

The matches are the nodes below the node whose label holds every word of the text, in any case. They lie at most `depth` levels down, there are at most `limit` of them, and they come in the order of the tree: a match, then the matches below it. The walk keeps an entry for each node it enters: a cell of its matches and a cell that calls `demand_tree_children`. A node waits while that cell is provisional. A node on the path to itself is not entered again. A lazy list of children gives its first `limit` nodes.

The result holds these values:

- the matches, each a document, its steps from the node, and the labels of the nodes above it;
- the count of waiting nodes;
- whether the limit or the depth stopped the walk;
- the time from the start to a final result.

`ExplorerSearchToWidget` draws the page. It shows the title ("Find "smoke" below Files"), the line, and a table of the matches with their places. The line reads, for example, "waiting for 3 nodes · 12 matches", "12 matches · 0.4 s", "stopped at 100 matches", "not below a depth of 10" or "stopped". A match is a link. A press opens its page here (`OpenPageOperation(root, address)`). Ctrl+press opens it in a new tab.

The search is a work item of the task list ([task.md](../task/task.md)). Its decoration reads its result, so its row in the Tasks pane, the node of the tasks in the tree, or its page keeps it going. While none shows, it waits. Stop keeps its matches and reads nothing more. Close leaves a closed row.

### A dashboard

`Dashboard(title, cards)` holds `DashboardCard(title, content)` cards, which are the children of its node. `DashboardToWidget` draws the title in a field and the cards in a grid in a scroll pane. The grid has as many columns as cards of `card_width` fit in the exact width of the slot, and each card fills its cell. On a page with an exact height, the grid takes its cards as a `ListNode` of rows, the list form of `GridLayout`, so it builds and draws only the rows that the page shows: a dashboard of 64 cards on a page of 500 pixels builds 8 of its 22 rows. The grid is the content of the scroll pane itself, because a pane scrolls a list only in its content. A page with no height has no screen to cut, so its grid takes the cards as a vector and draws them all. Card `k` is `children[r][c]` of a grid of rows and `children[k]` of a grid of a vector. The count is a cell that reads the cell of that width, so a drag of a splitter or a resize of the window lays the cards out again, and a width that keeps the count builds no grid. The content of a card draws by the view of its own type, and the page maps `cards[k].content.<rest>` both ways, so a press, a caret and a key in a card reach its document. Insert on the page adds a card whose content is a `DocumentInsertion`.

### The file of the content

`get_explorer_content_file(folder)` is `projectured/explorer/<name>-<hash>.pred` in the state folder of the user, with a 32-bit FNV-1a hash of the absolute path. `save_explorer_content!(content, path; editor)` writes the section, each entry as its kind writes itself, and `load_explorer_content(path; editor)` reads it, or answers `nothing`. A session document writes a mark that a load gives back as the session document of the editor that loads it. A file of an explorer, as the window file writes it, keeps the section only.

### What a row and a control say

Each row says what it holds when the pointer rests on it: the decoration of its document gives a function that makes a `TooltipNote` at that moment (see [tooltip.md](../tooltip/tooltip.md)). The filter field says what it keeps, its key (Ctrl+F) and what Return and Escape do; the kinds item says the kinds shown; the add item the kinds it offers; the items of the row menu say what they do, with the keys of Remove, the moves and Rename; the card of an entry on a section page says the note of the entry.

### What an assistant calls

An assistant works in the explorer with the verbs of its scope, and moves no selection of the person:

| Verb | What it does |
| --- | --- |
| `find_explorer_content()` | answers the root section as a part of the window, through the first tab that shows an explorer of it |
| `insert_elements!(content.entries, index, [document])` and `delete_elements!` | add and remove an entry, as an edit that undo takes back |
| `describe_commands(entry)` and `run_command!(entry, words)` | list and run the commands of the row of a node |
| `open_explorer_page!(part)` | shows the page of a node, or of a document that an entry holds, in the navigator, and opens the rows above it |
| `format_tree_node_label(entry)` | the label of a node as the tree shows it |

`Dashboard`, `DashboardCard` and `ExplorerSection` are in the scope too, so the assistant makes the documents that it adds.

The commands of a row come from `collect_part_commands(::Explorer, steps)`, the method of the explorer for the generic of the gesture help slice ([gesturehelp.md](../gesturehelp/gesturehelp.md)). They are the items of the menu of the row with `selects = false`: a removal is only the delete, and a move and a new section add with no visit and no selection. Rename and Add… are not commands for an assistant, because one puts the caret in a field and the other opens a menu for the person; the assistant renames with `replace_referenced_value!(entry, :title, text)` and adds with an insert. A path of the navigator does not follow an insert or a delete before it, so after a removal by an assistant the page of a later entry can show the entry after it.

## How it fits

The slice uses the collection, domain, focus, gesture help, layout, navigator, pane, projection, serialization, style, task, tooltip, tree and widget slices. It is included after the task slice. The shell uses it for the button Explorer of the toolbar, and the application uses it for the first tab of the window. A kind of another slice joins the explorer through the generics of the tree slice and `is_explorer_entry_type`, with no code of this slice.

## Design decisions

- **An entry is a plain document.** A section links documents and wraps none, so a document shows the same in the explorer and in a tab. The owner chose it on 2026-10-17 ([the-explorer-shows-what-the-editor-holds.md](../../../../plan/done/the-explorer-shows-what-the-editor-holds.md), Q0).
- **The matches are a second tree.** A filter inside the tree would change the index path of every row, which the maps, the open places and the shown rows of the tree read.
- **Insert opens a menu.** The completion of an insertion filters by the type of its place, and the trait of the kinds is no type, so a typed name could not show the list.
- **The add evaluates its visit after the insert.** A visit made before the insert finds no page.
- **A search is a computation and a work item.** It shares the reads of the tree, follows the stored state, and needs no task of its own. Its row and its page keep it going. The reasons are in [the-search-below-a-node-reads-the-folders-it-needs.md](../../../../plan/done/the-search-below-a-node-reads-the-folders-it-needs.md) (Q2 and Q4).

## Limits

- **The field of the filter keeps its least width.** A text field takes the width of its text, and no text field fills its slot.
- **A dashboard with no exact width has one column.** With no exact width at the print, as in an editor with no window size, the cards stand in one column.
- **A search does not watch the folders that it reads.** A later change on disk reaches its result only through a holder of the folder, such as an open node of the tree.
- **The tree holds a removed document until its next toggle or scroll.**
- **A card has no key that removes it.**

## Layer structure

The slice is the folder [source/platform/explorer/](../../../../source/platform/explorer/), and `ExplorerModule` is its module.

```
explorer/ExplorerModule.jl        (ExplorerModule): the module, its exports and its include order
    ├─ ExplorerFilter.jl          : ExplorerFilter, the rows of the matches, the kinds of the read rows
    ├─ ExplorerDocument.jl        : ExplorerSection, Explorer, the root section of an editor, the kinds of +, the verbs of an assistant
    ├─ ExplorerToWidget.jl        : the view, its maps, and its reader
    ├─ ExplorerSectionToWidget.jl : the page of a section
    ├─ ExplorerSearch.jl          : ExplorerSearch, StartExplorerSearchOperation, the walk of a search
    ├─ ExplorerSearchToWidget.jl  : the page of a search
    ├─ Dashboard.jl               : Dashboard, DashboardCard
    ├─ DashboardToWidget.jl       : the page of a dashboard
    ├─ ExplorerRowMenu.jl         : the menu of a row, and the commands of a row for a verb
    ├─ ExplorerEntryEdits.jl      : the add of an entry, the keys of the explorer
    └─ ExplorerContentFile.jl     : the file of the content in the state folder
```

## Tests

`test_explorer()` in `ProjecturedPlatformTest`, in `test/platform/explorer/ExplorerTest.jl`:

- a section is a node and lists its first children, and says where it holds a document;
- a press shows a page, Ctrl+press opens a tab, a double press puts the keyboard in the page;
- the folders of a workspace are nodes, and a file is one document for its page, its tab and the open files;
- the page of the open files is a table of the files, which a filter and Show all keep, and a press on the name of a file opens its page;
- the kinds of `+`, a folder with no place, Insert, Delete, the moves, F2, the menu of a row and the command of the pane;
- the filter, its kinds, and the tree of the matches;
- a dashboard with its cards, a key in a card, and Insert;
- Return in the filter searches below the node of the page and reads the folders that nobody opened;
- a search goes on while its page or its row shows, and waits while neither does;
- a search stops at its depth and at its limit, and a stop keeps its matches and reads nothing more;
- the file of the content, read back as the session of the next editor.
