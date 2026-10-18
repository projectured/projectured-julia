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

`ExplorerToWidget` draws a grid of one row. The left column holds a bar (the field of the filter, `+` and `▾`) above the tree, or above the tree of the matches while the filter keeps rows out. The right column, three times as wide, holds the navigator. The paths map so:

```
filter.text<rest>    children[1].children[1].children[1].content<rest>
tree.<rest>          children[1].children[2].children[1].<rest>    while no filter
matches.<rest>       children[1].children[2].children[1].<rest>    while a filter
navigator.<rest>     children[2].<rest>
```

The holder of the tree is a `VerticalLayout` whose one child is computed, so the other tree prints when the filter starts or ends. Each layout of the bar carries the part of the path of the grid below it, so a key reaches the part that holds the caret.

### A press shows a page

The reader of the view reads the answers of the tree and of the tree of the matches:

| Gesture on a row | Effect |
| --- | --- |
| press | the selection stays in the tree, and the navigator visits the page of the document of the row |
| Ctrl+press | the page opens in a new tab, as a navigator rooted at the section |
| double press, Return | the keyboard goes into the page |
| right press | the menu of the row |

The tree marks the row of the page of the navigator (`DocumentTree.current`), also after a link on a page moves the navigator.

### The keys of the explorer

`@gestures Explorer` holds the keys that work while the selection is on a row:

| Key | Effect |
| --- | --- |
| Insert, `+` | the menu of the kinds that a person adds, and "Other document" |
| Delete | the selected entry leaves its section, and the section is selected |
| F2 | the caret goes to the title of a section or a dashboard, on its page |
| Ctrl+Shift+Up, Ctrl+Shift+Down | the selected entry moves in its section |
| Ctrl+F | the caret goes to the field of the filter |
| "New section" | a command with no key: a new section after the selected entry |

The tree moves its selection with Up and Down whatever the modifiers, so the two keys that move an entry are `override` rules, and the reader gives a key that the tree answered to the table of the explorer as a claimed key. Escape in the field of the filter empties the filter; the reader reads it, as the navigator reads Escape in its address.

### The kinds that a person adds

A kind is in the list of `+` when `is_explorer_entry_type(::Type)` of the tree slice answers `true` for it. The list is the insertion candidates of `Document` with that trait, each named by its first insertion alias:

| Kind | Alias | The document of a new entry |
| --- | --- | --- |
| `WorkspaceFolder` | folder | a folder with no place, whose page has a field for the place |
| `TaskGroupList` | tasks | the task list of the session |
| `AssistantList` | assistants | the assistant list of the session |
| `ExplorerSection` | section | an empty section, "New section" |
| `Dashboard` | dashboard | an empty dashboard, "New dashboard" |

"Other document" adds a `DocumentInsertion`, whose page takes the name of any document.

### The add of an entry

`AddExplorerEntryOperation(document; section, index, navigator, selection)` is in the widget slice, beside `OpenFileOperation`, so a menu of the navigator and a command of the pane name it. The editor evaluates it: the entry goes into its section, then the navigator visits its page, and its node is selected. The visit and the selection come after the insert, because neither the page nor the node exists before it. Its inverse removes the entry.

"Add to explorer" adds a document at the end of the root section: from the menu of a part on a page, from the menu of a row below an entry, and from the command "Add the tab to the explorer" of the pane tree.

### The menu of a row

A right press on a row opens one layer named by the row: Open in a new tab; Remove from explorer for an entry, or Add to explorer for a node below an entry; Rename for a section or a dashboard; New section and Add… for a section; Open as a list for a node with a lazy list or more than 50 children; then each command of the gesture table of the document that applies now, rerooted from the place of the document in the tree.

### The filter

The filter keeps a row when its label holds every word of the text, in any case, and its type is one of the kinds, or when a row below it stays. The tree of the matches walks the open places of the tree with `collect_read_tree_children`, so it reads the labels of the rows that the tree read, and no disk. Every row of the matches is open. `▾` lists the kinds of the read rows, with the icon `check` on the kinds that the filter keeps. An edit of the filter is view state, so an undo records none.

### A dashboard

`Dashboard(title, cards)` holds `DashboardCard(title, content)` cards, which are the children of its node. `DashboardToWidget` draws the title in a field and the cards in a grid in a scroll pane. The grid has as many columns as cards of `card_width` fit in the exact width of the print, and each card fills its cell. The content of a card draws by the view of its own type, and the page maps `cards[k].content.<rest>` both ways, so a press, a caret and a key in a card reach its document. Insert on the page adds a card whose content is a `DocumentInsertion`.

### The file of the content

`get_explorer_content_file(folder)` is `projectured/explorer/<name>-<hash>.pred` in the state folder of the user, with a 32-bit FNV-1a hash of the absolute path. `save_explorer_content!(content, path; editor)` writes the section, each entry as its kind writes itself, and `load_explorer_content(path; editor)` reads it, or answers `nothing`. A session document writes a mark that a load gives back as the session document of the editor that loads it. A file of an explorer, as the window file writes it, keeps the section only.

## How it fits

The slice uses the collection, domain, focus, layout, navigator, pane, projection, serialization, style, tree and widget slices. The shell uses it for the button Explorer of the toolbar, and the application uses it for the first tab of the window. A kind of another slice joins the explorer through the generics of the tree slice and `is_explorer_entry_type`, with no code of this slice.

## Design decisions

- **An entry is a plain document.** A section links documents and wraps none, so a document shows the same in the explorer and in a tab. The owner chose it on 2026-10-17 ([the-explorer-shows-what-the-editor-holds.md](../../../../plan/pending/the-explorer-shows-what-the-editor-holds.md), Q0).
- **The matches are a second tree.** A filter inside the tree would change the index path of every row, which the maps, the open places and the shown rows of the tree read.
- **Insert opens a menu.** The completion of an insertion filters by the type of its place, and the trait of the kinds is no type, so a typed name could not show the list.
- **The add evaluates its visit after the insert.** A visit made before the insert finds no page.

## Limits

- **The field of the filter keeps its least width.** A text field takes the width of its text, and no text field fills its slot.
- **A dashboard keeps the count of columns of its print.** A change of the width after the print, such as a drag of a splitter, keeps the count until the page prints again. With no exact width at the print, the cards stand in one column.
- **The search below a node is not built.** It needs a way to read unread children for a search, which no kind gives.
- **The tree holds a removed document until its next toggle or scroll.**
- **A card has no key that removes it.**

## Layer structure

The slice is the folder [source/platform/explorer/](../../../../source/platform/explorer/), and `ExplorerModule` is its module.

```
explorer/ExplorerModule.jl        (ExplorerModule): the module, its exports and its include order
    ├─ ExplorerFilter.jl          : ExplorerFilter, the rows of the matches, the kinds of the read rows
    ├─ ExplorerDocument.jl        : ExplorerSection, Explorer, the root section of an editor, the kinds of +
    ├─ ExplorerToWidget.jl        : the view, its maps, and its reader
    ├─ ExplorerSectionToWidget.jl : the page of a section
    ├─ Dashboard.jl               : Dashboard, DashboardCard
    ├─ DashboardToWidget.jl       : the page of a dashboard
    ├─ ExplorerRowMenu.jl         : the menu of a row
    ├─ ExplorerEntryEdits.jl      : the add of an entry, the keys of the explorer
    └─ ExplorerContentFile.jl     : the file of the content in the state folder
```

## Tests

`test_explorer()` in `ProjecturedPlatformTest`, in `test/platform/explorer/ExplorerTest.jl`:

- a section is a node and lists its first children, and says where it holds a document;
- a press shows a page, Ctrl+press opens a tab, a double press puts the keyboard in the page;
- the folders of a workspace are nodes, and a file is one document for its page, its tab and the open files;
- the kinds of `+`, a folder with no place, Insert, Delete, the moves, F2, the menu of a row and the command of the pane;
- the filter, its kinds, and the tree of the matches;
- a dashboard with its cards, a key in a card, and Insert;
- the file of the content, read back as the session of the next editor.
