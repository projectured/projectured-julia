# The explorer shows what the editor holds

> **Status (2026-10-18): IN PROGRESS.** Steps 1 to 9 but 6c and the projectured
> documents of step 11 landed on main at the owner's word ("yes", 2026-10-18).
> 6c is deferred (the owner: "defer"). The columns of a dashboard follow the
> width (8, option b, the owner's choice of 2026-10-18), on branch `explorer`.
> Step 10 (the omnet IDE, with the counts of rosters) and the omnet guides of
> step 11 landed on 2026-10-18 at the owner's word; the result folder below the
> project came with step 3 of plan C of the omnet UI session. Only 6c is open,
> deferred by the owner. **DESIGN DECIDED.** The owner
> decided Q0 to Q12 in §6 on 2026-10-17 and asked for the implementation the same
> day. The owner refines the structure of the tree later.

## 1. The ask

The owner, 2026-10-17: the explorer of projectured-julia and omnet-julia is a tree
of nodes, and the selected node shows a page on the right side, usually in a
navigator. Make it generic: "a generic means of exploring the state of the
editor". It is the central component of both binaries. It must:

- show many kinds of things: the file system, tasks, assistants, open files,
  formula computations, the workspace, projects, plots, graphs, graphics,
  markdown documents, other document kinds, simulations with their
  configurations and runs, simulation results, rosters with filters and sorts,
  "whatever the user can put there";
- give each kind its own page, with a navigator, an undo and a scroll where the
  kind needs them, and open a page as a tab of its own;
- take new kinds from each domain package when it loads;
- show the same object at many places;
- stay usable when a part is very large, also without end, in depth and in
  breadth;
- let the person add an item and remove an item, for example a folder, or a
  blank dashboard on which the assistant adds things;
- be easy to filter.

Special components for files, assistants and others stay.

## 2. Conclusion

The explorer is one document, `Explorer`, with three parts over one root:

- a **tree** (`DocumentTree`) on the left;
- a **navigator** (`Navigator`) on the right, which shows the page of the node
  that the person selects;
- a **filter** above the tree.

The root is an **explorer section**, `ExplorerSection(title, entries)`: a list of
entries that the person controls. An entry is any document. A section can hold
sections. The explorer links an entry and does not own it, so the same document
can be at many places, and a removal from the explorer never deletes the object.

Each editor has one explorer content, as it has one task list. Every explorer
tab of the editor shows it, with its own open nodes, page and filter.

A package adds what it knows by methods of generic functions, with no registry:
the node of a kind (the four tree generics that exist), the page of a kind (the
view of its type, which exists), the commands of a kind (its own gesture table,
which exists), and the kinds that a person can add (one new trait, §6 Q2).

The omnet explorer (`LegacySimulationExplorer`) is this design for one root. The
generic explorer lifts it into projectured-julia, and the omnet IDE then uses the
generic one.

## 3. What exists

### 3.1 The mechanism

| Part | What it does now | Where |
| --- | --- | --- |
| `DocumentTree(root; title)` | shows any document as a tree; four generics make a document a node: `get_tree_children_steps`, `format_tree_node_label`, `get_tree_node_icon`, `has_tree_children` | [tree.md](../../documentation/package/platform/tree/tree.md) |
| open nodes | `DocumentTree.expanded`, keyed by the identity of the document: view state, not in the undo | `source/platform/tree/TreeDocument.jl` |
| lazy children | a node reads its collections only when the tree draws it or opens it; a cycle stays closed | `DocumentTreeToWidgetTree.jl` |
| read on open | a document of outside state stores what it read and a read state; the acquire starts the read on a task; the release stops the watch | `source/platform/domain/DocumentRelease.jl`, `DocumentRead.jl` |
| `Navigator(content, address)` | a page of any document, with Back, Forward, Parent, an address bar and Open in a tab | [navigator.md](../../documentation/package/platform/navigator/navigator.md) |
| `OpenPageOperation` | a link: the nearest navigator takes it; `:new_tab` opens a tab with a navigator rooted at the content | `source/platform/widget/OpenPageOperation.jl` |
| `find_navigator_address(content, document)` | a domain says where its content holds a document | `NavigatorPageOpen.jl`; omnet answers it for the workspace |
| tree beside a navigator | press shows the page beside the tree, Ctrl+press opens a tab, Return or double press moves into the page | omnet `source/campaign/LegacySimulationExplorer*.jl` only |
| the commands of a part | a document answers its own gesture table; F1, the command palette and `describe_commands` read it | `source/platform/gesturehelp/PartCommands.jl` |
| document insertion | an empty slot takes a typed name with completion; the candidates come from the method table, so a package that loads adds its kinds; a session tool answers its session document | `source/platform/domain/Domain.jl` |
| session documents | each editor has its own task list, assistant list and logs (`get_session_document!`); a save writes a marker, and a load gives back the session document | `source/kernel/editor/Editor.jl`, `AssistantList.jl` |
| filter, sort, find | `ArrangementDocument` over any collection | `source/platform/arrangement/` |

Facts that the design must change:

- The file tree (`WorkspaceExplorer`, `FileSystemToWidgetTree`) does not use the
  four tree generics. It is a tree of its own.
- No tree can be filtered.
- A node is open by its document, so the same document opens at all its places
  at the same time.
- The widget tree takes only Up and Down. Right, Left, Home and End do nothing.
- A tree node has no menu.
- No document lists the kinds that a person can add to a list of things.

### 3.2 What a person can explore today

"Node" says that the kind has its own tree methods. "Page" says that a tab can
draw it. "Reach" says how a person finds it now.

| Kind | Document | Node | Page | Reach | This design |
| --- | --- | --- | --- | --- | --- |
| folders and files | `Workspace`, `FileSystemDirectory`, `FileSystemFile` | own tree only | Files tab | toolbar Explorer, Files tab | nodes; a folder page is a table of its entries |
| open files | `FileDocument` in tabs | no | file tab | the tabs | entry "Open files" |
| tasks | `TaskGroupList`, `TaskGroupDocument`, `TaskDocument` | yes | yes | omnet Tasks tab; projectured none | entry "Tasks" |
| assistants | `AssistantList`, `Assistant`, `AssistantWork`, `AgentWork` | work only | yes | toolbar | entry "Assistants"; an assistant shows its work below it |
| evaluator | `EvaluatorToplevel` | no | yes | toolbar | stays a tool; can be added |
| formulas | `FormulaEnvironment` | no | yes | examples only | node of its formulas; can be added |
| logs | `MessageLog`, `GestureLog`, `FaultLog`, `McpLog` | no | yes | toolbar; MCP log by name only | section "Editor" |
| statistics | `FrameStatistics`, `FrameTimeSeries` | no | yes | toolbar | section "Editor" |
| settings, appearance | `Settings`, `AppearanceDocument` | no | yes | toolbar, View menu | section "Editor" |
| selection | `SelectionInspector` | no | yes | toolbar | section "Editor" |
| document kinds, views | `DocumentTypeList`, `ProjectionList` | no | yes | Help menu | section "Editor" |
| system processes | `SystemProcessTree` | yes | yes | assistant verb only | section "Editor" |
| work plans | `WorkPlan` | yes | yes | example only | can be added |
| rosters, arranged views | `Roster`, `ArrangementDocument` | no | yes | assistant verbs | node of its items; can be added |
| domain documents | JSON, markdown, rst, Julia, SQL, chart, graph, pivot, data frame, … | default node | yes | file tabs | as files below folders; any part by "Add to explorer" |
| dashboards | none | | | | new kind (§6 Q4) |
| omnet project, INI file, configuration, run | `LegacySimulationProjectPage`, `LegacyIniFileEntry`, `LegacyConfigurationEntry`, `LegacyRunEntry` | yes | yes | omnet Explorer tab | entry for each project |
| omnet views | "Running now", "Not expected" (`ArrangementDocument`) | no | yes | omnet Explorer tab | section "Views" |
| omnet stores | fingerprint store, statistical baseline | address only | yes | project page | nodes below the project |
| omnet results | `LegacyResultFolder`, `LegacyResultFile` | no | yes | assistant verbs | node "Results" below the project (omnet plan C step 3) |
| a native simulation | module tree, inspector, log | no | yes, Qtenv window | not in the IDE | not in this plan |
| examples, the API, the evaluator names, the registries | | no | no | REPL, assistant | not in this plan |

Two kinds can not be explored at all: the reactive cells (their edges are weak
and nothing lists them) and the names of the evaluator (no page).

### 3.3 Decisions that this design keeps

- No preview tab. A press shows the page beside the tree, and the person makes
  it a tab (omnet D3, 2026-10-15).
- A tab is called by its page. Every navigator opens its page in a tab of its
  own (2026-10-15).
- The address is data in the navigator (2026-10-06).
- One shared listing of a folder, and each explorer keeps its own open nodes
  (plan A, M1).
- A view of outside state stores what it read; the acquire starts the read; no
  computation reads the disk (2026-10-16).
- A tool is never single (2026-09-18). A toolbar press reaches the open tool, or
  opens one (R1).
- Seams, not registries: a low package declares a generic function, and a
  package adds methods (C1, 2026-09-30).
- No document stores the editor. A session document belongs to its editor, and
  no document is shared by two editors.
- The shell names the tools, and the host gives what is its own (R3).
- A tree draws only the rows that its viewport reaches, and its children can be a
  lazy list with no end (T1, 2026-10-17, on main). What a viewport shows is a
  demand (V, 2026-10-17), a plan of its own.
- The explorer of omnet is one tab: the tree and a navigator side by side
  (2026-10-15).

## 4. What a professional explorer does

The reference tools: the Common Navigator of Eclipse, the tree views of VS Code,
the project view of JetBrains, the inspector and pager of Glamorous Toolkit, and
the sidebar of the Finder.

| | Requirement | Now |
| --- | --- | --- |
| R1 | A loaded package adds kinds of node, their pages, their commands and the kinds that a person can add. | nodes and pages: yes; commands in the tree, add list: no |
| R2 | A node reads its children when it opens, and no list is counted to its end. | yes: read on open, and lazy rows since 2026-10-17 |
| R3 | Each place of an object opens on its own, and a cycle ends. | cycle: yes; each place: no |
| R4 | A row has a label, an icon and its state. | label and icon; the state is in the label text (omnet); this design: §5.14 |
| R5 | The person adds, removes, orders and groups the roots. | no |
| R6 | A quick filter, a filter by kind, and a search below a node. | no |
| R7 | The page shows beside the tree, and opens in a tab. | omnet only |
| R8 | The tree marks the row of the page that shows. | no |
| R9 | Up, Down, Right, Left, Home, End, Page Up, Page Down. | Up and Down only |
| R10 | Each row has a menu. | no |
| R11 | The roots and what the person added come back at the next start. | only through a saved window file |
| R12 | A change shows with no refresh. | folders and tasks: yes |

This design meets R1 to R12. Drag and drop is not in this plan.

## 5. The design

### 5.1 The documents

One small case: the projectured binary, opened on the folder `/home/u/work`.

```julia
content = ExplorerSection("Explorer", [
    Workspace([WorkspaceFolder("work", "/home/u/work")]),           # "Files"
    open_files,                               # the open files of the editor (Q3)
    tasks,                                    # the task list of the editor
    assistants,                               # the assistant list of the editor
    ExplorerSection("Dashboards", []),
    ExplorerSection("Editor", [message_log, gesture_log, fault_log,
                               statistics, settings, appearance, selection]),
])

explorer = Explorer(content)
# Explorer(tree      = DocumentTree(content; title = "Explorer"),
#          navigator = Navigator(content),
#          filter    = ExplorerFilter(text = "", kinds = Set{Type}()))
```

- `content` is the explorer content of the editor. A second explorer tab, or a
  duplicate, shows the same content with its own tree, navigator and filter.
- `open_files`, `tasks`, `assistants` and the logs are the session documents of
  the editor. The same `tasks` is also what a Tasks tab shows. `open_files` holds
  one document for each file path that the editor has open, in a tab or on a
  page (Q3).
- The open nodes, the page and the filter are view state: the undo records none
  of them.
- An entry is a plain document, with no wrapper around it. Its row reads its
  label and icon from the tree generics of its kind. A section and a dashboard
  have a title of their own, which the person can rename.

### 5.2 What the person sees

```
┌ Explorer ─────────────────────────────┬────────────────────────────────────────────┐
│ [filter…                    ] [+] [▾] │ ← → ↑  Explorer › Tasks › #3 build      [⧉] │
│ ▾ Files                               │                                            │
│   ▸ work                              │   the page of the selected node            │
│ ▸ Open files · 3                      │                                            │
│ ▾ Tasks · 1 running                   │                                            │
│   ▸ #3 build · 2/4                    │                                            │
│   ▸ #2 smoke · 12/12                  │                                            │
│ ▸ Assistants · 1                      │                                            │
│ ▸ Dashboards                          │                                            │
│ ▸ Editor                              │                                            │
└───────────────────────────────────────┴────────────────────────────────────────────┘
```

- The left part is the filter bar and the tree. `+` adds an entry. `▾` is the
  menu of kinds for the filter.
- The right part is the navigator with its bar: Back, Forward, Parent, the
  address and Open in a tab.
- The row of the page that the navigator shows has a mark (R8), also after a
  link inside the page moves the navigator.
- The page of a section is an overview: one card for each entry, with its icon,
  its label, and its first children as links.

### 5.3 The gestures

| Gesture | Effect |
| --- | --- |
| press on a row | select the node; the navigator shows its page |
| Ctrl+press on a row | open the page in a new tab, as a navigator rooted at the content |
| double press, or Return | put the keyboard in the page |
| press on a chevron, Right, Left | open, close; Left on a closed row selects the parent; Right on an open row selects the first child |
| Up, Down, Home, End, Page Up, Page Down | move the selection in the tree |
| Ctrl+F | put the keyboard in the filter |
| Escape in the filter | clear the filter |
| Return in the filter | search below the selected node (§5.6) |
| Insert, or `+` | add an entry after the selected entry of a section |
| Delete | remove the selected entry from its section; a node that is not an entry of a section does not take it |
| F2 | rename a section or a dashboard |
| right press | the menu of the row (§5.8) |

The keys of the navigator (Ctrl+[, Ctrl+], Ctrl+Up, Ctrl+L) work in the page as
they work in every navigator.

### 5.4 A walk

The person opens the projectured window of §5.10, then does six things.

| Step | Gesture | `tree` open nodes | `navigator.address` | tabs | `content.entries` |
| --- | --- | --- | --- | --- | --- |
| 0 | the window opens | the root | empty: the overview | Explorer | 9 entries |
| 1 | press on "Tasks" | the root | `entries[3]` | Explorer | 9 |
| 2 | press on its chevron | the root, Tasks | `entries[3]` | Explorer | 9 |
| 3 | Ctrl+press on "#3 build" | same | `entries[3]` | Explorer, "#3 build" | 9 |
| 4 | type "smoke" in the filter | same; only "Tasks › #2 smoke" shows | `entries[3]` | same | 9 |
| 5 | Escape, then Delete on "Dashboards" | same | `entries[3]` | same | 8 |
| 6 | Insert, type "folder", Return | same | the new folder entry | same | 9 |

In step 3 the new tab is `Navigator(content, entries[3].groups[3])`, so its
address bar shows `Explorer › Tasks › #3 build` and Parent goes to the task list.
In step 6 the new entry is a folder with no path. Its page asks for the path,
with the completion of the Open dialog.

### 5.5 What a package adds

A package adds four things, each by a method of a generic function. Three of
them exist.

| What | How | Exists |
| --- | --- | --- |
| the node of a kind | `get_tree_children_steps`, `format_tree_node_label`, `get_tree_node_icon`, `has_tree_children` | yes |
| the page of a kind | the view of its type (`make_graphics_projection` or a natural row) | yes |
| the commands of a kind | its own gesture table, which F1 and the command palette read | yes |
| the kinds that a person can add | `is_explorer_entry_type(::Type)`, and its insertion name (`get_insertion_aliases`, `make_insertion_document`) | the trait is new (Q2, agreed) |

So a package that loads in the REPL gives its kinds to the `+` list at once, and
its documents show as nodes and pages wherever they are. No package adds an
entry by itself: the binary makes the first content, and the person changes it.

`find_navigator_address(::ExplorerSection, document)` asks each entry for the
document and puts the place of the entry before the answer. So an object with
its own root, such as a task group that a Run starts, opens at its full address
in the explorer, with its parent and its breadcrumb.

### 5.6 Many places, cycles and large parts

- **Many places.** Each place of a document opens on its own (Q1). A task that
  "Tasks" and "Views › Running now" both show can be open in one and closed in
  the other. An insert before a node does not change what is open, because a
  place is named by the documents on its path, not by indices.
- **Cycles.** A document that is again on the path to its own node stays closed
  there, as now.
- **Depth.** A node reads its children only when it opens. A document of outside
  state reads on its acquire, on a task.
- **Breadth.** The tree draws only the rows that its viewport reaches, and the
  children of a node can be a lazy list with no end, which the tree does not
  count. A far scroll moves the head of the list. This is on main since
  2026-10-17 (`plan/done/a-tree-draws-only-the-rows-it-shows.md`, the owner: "T1,
  lazy, that's the projectured default"), and the explorer uses it as it is. A
  kind with a long collection gives it as a lazy list. "Open as a list" in the
  menu of a row (§5.8) opens the collection as a page: a table with lazy rows,
  with the filter and the sort of the arrangement. That a viewport holds the
  documents of the rows that it shows is on main since 2026-10-17
  (`plan/done/a-viewport-holds-the-rows-it-shows.md`): the tree holds the
  documents of its open places and of its shown rows, and this plan adds
  nothing to it.

### 5.7 The filter

- **Quick filter.** The text of the filter keeps a row when its label holds every
  word, or when a row below it that the tree has read stays. The rows above a
  kept row show open. The filter reads only the cells of labels, so it starts
  no read of the disk and no process.
- **Kinds.** The menu `▾` lists the kinds of the read rows (folder, file, task,
  assistant, …). A person picks kinds, and only rows of those kinds and the rows
  above them stay.
- **Search below.** Return in the filter starts a task, "Find 'smoke' below
  Files". The task walks below the selected node with a limit of depth and of
  count, reads what is not read on its own task, and shows the matches as a list
  on its page in the navigator. A press on a match opens its node and shows its
  page. The task shows its progress and can stop, as every task does.

The filter is part of the explorer document, so a duplicate starts with the same
filter, and the person changes each one alone.

### 5.8 The menu of a row

1. Open in a new tab.
2. Add to explorer: for a node below an entry, it adds the document as a new
   entry of the root.
3. Remove from explorer: for an entry of a section.
4. Rename: for a section or a dashboard.
5. New section, and Add…: for a section.
6. Refresh: for a document of outside state. Open as a list: for a node with a
   long collection of children (§5.6).
7. Then the commands of the document itself, from its own gesture table, as F1
   lists them: Stop and Rerun for a task, Build and Clean for a project.

"Add to explorer" is also in the menu of a part on a page, after "Open as a page"
and "Open in a new tab", and in the menu of a tab. It adds the document to the
explorer content of the editor (`AddExplorerEntryOperation`, which the editor
evaluates, as it evaluates `OpenFileOperation`).

### 5.9 The page

- **Navigator.** Every page of the explorer is in its navigator. Back and Forward
  go through the visits, and Parent goes up to the node above.
- **View.** The page of a node is the view of its type. A kind with no view of
  its own gets the view on demand.
- **Scroll.** A view that can be tall scrolls where it is made. The navigator
  adds no scroll pane (Q3 of the navigator plan).
- **Undo.** An edit on a page is an edit of the window, and the undo of the window
  takes it back. One undo for each document across all its views is the subject
  of `plan/pending/a-history-records-every-edit-of-its-document.md`; the explorer
  uses its result and adds nothing.
- **Tab.** Ctrl+press, the menu, and Open in a tab on the bar open the page as a
  navigator tab rooted at the content. The tab keeps the breadcrumb and Parent.
- **A file.** The page of a file node shows the content of the file, and a person
  edits it there (Q3). It is the same document as a tab of the file: the editor
  keeps one document for each path, and the acquire of the page reads the file
  on a task when the editor does not hold it yet.

### 5.10 The first content of each binary

The binary names the first content, as the shell names the tools (R3). Every
tool of the toolbar and of the Help menu has a node (Q8). The owner refines the
structure of the tree later (2026-10-17); the content is data, so a change of it
is a change of the first content and of no code of the tree.

**projectured**, opened on a folder:

```
Explorer
├ Files              the folder of the window
├ Open files         the open files of the editor (Q3)
├ Tasks              the task list of the editor
├ Assistants         each assistant: its conversation, and its work below it
├ Evaluators         a section with one evaluator; `+` adds another
├ Dashboards         an empty section
├ Editor             what this editor does now
│  ├ Message log, Gesture log, Fault log, MCP calls
│  ├ Statistics, Frame times
│  └ Selection, System processes
├ Settings           the groups of the settings, Appearance
└ Help               Document kinds, Views, About
```

**omnet IDE**, opened on a project:

```
Explorer
├ Simulation projects
│  └ inet            Runner (Q7), INI files › configurations › runs, Results, Stores
├ Tasks              the task list of the editor
├ Views              Running now, Not expected
├ Files              the folder of the project
├ Open files
├ Assistants
├ Evaluators
├ Dashboards
├ Editor
├ Settings
└ Help
```

F1 and the command palette are popups over the selected part, not documents, so
they stay keys and have no node.

The window:

- In projectured, the Explorer is the first tab of the main group. The narrow
  Files group goes. The window shows the first file when files are given, and
  else the Explorer.
- In omnet, the tabs stay Explorer, Runner, Tasks, and the window opens on the
  Runner.
- The toolbar button Explorer reaches the explorer tab. The file tree keeps its
  own button, Files, as a special component.

### 5.11 The dashboard

A dashboard is a page on which the person and the assistant put things (Q4).

```julia
Dashboard("Queue study", [
    DashboardCard("Throughput", throughput_chart),       # a document the assistant made
    DashboardCard("Runs",       Roster(runs)),          # a list with its filter
    DashboardCard("Notes",      notes),                 # a markdown document
])
```

- A card holds any document: a document of its own, or the same document as at
  another place.
- The page draws the cards in a grid. The count of columns follows the width,
  each card fills its cell, and the height of a card comes from its content.
- The assistant adds a card with the insert of the collection `cards`, as the
  person does with Insert. The undo of the window takes it back.
- `+` in the explorer, "Dashboard", makes an empty dashboard.

### 5.12 The save

The content comes back at the next start (Q5): the editor writes it to the state
folder of the user, one file for each opened folder, when the window closes and
when the person saves the window. A save writes each entry as its
kind writes itself: a folder writes its path, a session list writes a marker that
the load gives back as the session list of the new editor, a dashboard writes its
cards. The open nodes, the page and the filter are view state; the save writes
none of them.

### 5.13 The assistant

The explorer content is a document, so the assistant reads it as any document.
It adds an entry or a card with the insert of the collection, and it opens a page
with `open_page!`. The assistant moves no selection of the person: it acts at a
part by its route. The editor API declares `Explorer`, `ExplorerSection`,
`Dashboard` and `DashboardCard`, and adds no verb of its own.

### 5.14 What a row says about its document

The owner, 2026-10-17: each node type has its label and icon; "to provide more
information we would support tinting icons and putting little badge icons [and]
counters on the icons as usual in IDEs. The point of this is not only what
should be displayed for each item but also where the state is stored. For
example, an unsaved file, a file modified on disk, a running task, a completed
one. Investigate every kind ... Make the whole look and feel consistent."

#### 5.14.1 The rule

- **One decoration for each document.** A document says one thing about itself,
  its decoration, and every place that names the document draws that same
  decoration: a row of the tree, a tab, an item of the address bar, the name
  column of a roster, and the title of a dashboard card. A tab and a row of the
  same document never disagree.
- **A decoration is never stored.** It is a computation over the cells of the
  document that owns the state, as a label is now. The state itself has one
  owner, and §5.14.4 names it for each kind.
- **A kind names its state; it never picks a look.** A kind answers conditions
  from one shared list (§5.14.3). One table gives each condition its tint and its
  mark. So an unsaved file and an unsaved fingerprint store look the same, and a
  failed task and a folder that can not be read have the same red.

Today the tab has the parts (`PaneTabTitle`: icon, `icon_role`, badges, tooltip,
each a cell that follows the state), but only three kinds fill them: the task
group, the task list and the navigator. The tree row has one color for every
icon and nothing after the label, so omnet puts its counts into the label text.
A file tab shows no unsaved mark.

#### 5.14.2 The parts and the look

```julia
DocumentDecoration(;
    icon       = :settings,                                # the kind; a work item shows its state here
    conditions = [DocumentCondition(:running),
                  DocumentCondition(:unexpected; count = 3),
                  DocumentCondition(:abstract)],           # from the list of §5.14.3, some with a count
    counts     = [DocumentCount("12 runs")],               # pills after the name, each with a role
    detail     = "omnetpp.ini",                            # dim text after the name
    tooltip    = nothing,                                  # more text; every condition in words comes first
)
```

The icon has four corners. Each corner has one meaning, the same in every kind,
so a person learns it once (the owner, 2026-10-17: "several kinds can have
multiple corner decorations on the icon such as counters or smaller icons
representing some information related to the item. This is common in IDEs."):

```
     the work that goes on now       what waits for an answer of the person
                        ⟳ ┌──────┐ 2
                          │ icon │
                        3 └──────┘ •
     what went wrong                 the document against its source
```

| Corner | It says | It shows |
| --- | --- | --- |
| top left | the work that goes on now | a glyph: running, pending |
| top right | what waits for an answer of the person | the count of the open requests |
| bottom left | what went wrong | a glyph for one problem, or the count of the problems |
| bottom right | the document against its source | a glyph: conflict, changed on disk, unsaved, read only, filtered |

A row draws the icon with its tint and up to four corner marks, then the name,
then the glyphs of the facts of its kind (§5.14.3), then the detail and the
counts. The tooltip of the row says every condition in words, also one that no
corner shows, and then the text of the kind.

| Place | What it draws |
| --- | --- |
| a row of the tree | everything |
| a tab | the icon with its tint and corners, the name, the counts |
| an item of the address bar | the icon with its tint and corners, the name |
| the name column of a roster | the icon with its tint and corners, the name |
| the title of a dashboard card | the icon with its tint and corners, the name, the counts |
| a text view, such as a terminal | the marks as characters after the name, and the conditions in words in the tooltip |

The label is the name only. The counts and the times that the labels of a task,
a group, an agent session and a configuration now hold move into the counts and
the detail.

#### 5.14.3 The conditions

| Condition | It means | Corner and mark | Tint (role) |
| --- | --- | --- | --- |
| `:failed` | it ended with an error, or it can not be read | bottom left: `x`, or the count of the failures | `error` |
| `:waiting` | the work stops until the person answers | top right: the count of the open requests | `warning` |
| `:unexpected` | it ended, but not as expected | bottom left: `!`, or the count | the role of its result code (FAIL `warning`, ERROR `error`) |
| `:running` | work goes on now: a task, a turn, a read, a build | top left: the loader glyph; none on a work item (rule 4) | `accent` |
| `:conflict` | it has unsaved edits, and the file on disk changed too | bottom right: `!` | `warning` |
| `:changed_on_disk` | the file on disk changed, and the editor did not load it | bottom right: `refresh` | `info` |
| `:done` | it ended as expected | none | `success`, for a work item only |
| `:unsaved` | it has edits that no save wrote | bottom right: `dot` | none |
| `:read_only` | it takes no edit | bottom right: `lock` | none |
| `:filtered` | a filter or a sort hides or orders its items | bottom right: `funnel` | none |
| `:pending` | not started | top left: a clock glyph; none on a work item | none; the icon is muted |
| `:stopped` | cancelled, skipped or closed | none | none; the icon is muted |

**A fact of a kind.** A package can add a condition of its own for a fact of its
kind, such as an abstract configuration. It declares the condition once: its
place, its glyph, its role and its words (Q10). A fact goes after the name, as a
small glyph with its words in the tooltip. It takes a corner only when it says
what that corner says. This plan adds one: `:abstract`, for an omnet
configuration.

The rules:

1. **One tint.** The tint is the role of the first condition of the table that
   holds and has a tint. A document with no such condition has no tint.
2. **One mark at each corner.** A corner shows the first condition of the table
   that holds and goes there, with its count when it has one. The other
   conditions of that corner are in the tooltip.
3. **A count at a corner counts what is there now** (Q11): the open requests of
   an assistant, the faults in the fault log until the person clears it, the files
   that a discovery could not read, the runs that failed.
4. **A work item shows its state as its icon**: a task, a task group, a step of a
   work plan, an agent session. The icons are the ones of the tab of a task group
   now: circle (pending), loader (running), check (done), x (failed or
   unexpected), stop (stopped). A running work item that knows its share done
   shows a ring of that share in place of the loader. So its top left corner
   stays empty. Every other kind shows its kind as its icon, and its state as the
   tint and the corners.
5. **Nothing spins.** A ring shows a share, and it changes only when the share
   changes. The loader is a still glyph. So a running node paints no frame of its
   own. The spinning ring of a task page stays as it is.
6. **No walk of children.** A node computes its decoration only from its own
   document and the documents that it holds. A parent that shows a sum of its
   children stores the sum, as a task group keeps its counts; else it shows no
   sum.
7. **Room for the corners.** A mark is about 45 % of the size of the icon, on a
   disc of the color behind the row, and it stands half outside the box of the
   icon, so the icon stays readable; the icon column grows to give the marks room.
   Step 3 checks this on an image at the scale 1 and 2 before the sizes are final.

#### 5.14.4 Each kind, and where its state is stored

projectured:

| Kind | Icon | Conditions, and the state they read | Counts and detail | New state |
| --- | --- | --- | --- | --- |
| section | a section glyph | none | none | none |
| folder (`FileSystemDirectory`, `WorkspaceFolder`) | `folder` | running while `state === :reading`; failed when `:failed`, with `failure` in the tooltip. The two child rows "reading" and "can not read" of the Files tab give way to this mark. | none | none |
| file in a folder (`FileSystemFile`) | by its extension (`_fs_icon`) | the conditions of its file document, while the row holds one | none | `FileSystemFile.document`: Q3 needs it anyway, because the page of a file shows the document from a cell of the row. The acquire of the page writes it. A file that the person opens in another way shows its conditions under "Open files" and on its tab, as in VS Code and JetBrains, which mark no unsaved file in the file tree. |
| open file (`FileDocument`, `FilePage`) | by its extension | unsaved: `has_unsaved_edits(content) === true`, which `UndoBuffer` answers; changed on disk: `page.band !== nothing`; conflict: both; read only: `!is_editable_file_type`; failed: the load or the parse of a change failed | detail: the folder of the file | `FilePage.failure`: today the failure of a parse goes to the fault log only |
| Open files | a files glyph | none | the count of unsaved files | none; the table is new by Q3 |
| Tasks (`TaskGroupList`) | `list` | running while a group runs | "N running" (`accent`), as its tab now | none |
| task group | its state (rule 4) | from `status` and `counts`, as its tab now | "finished/total"; "N CODE" for each unexpected code, with the role of the code; detail: the time | none |
| closed group | `minus` | stopped | detail: "closed" | none |
| task | its state (rule 4) | from its execution: status, result, and whether the result is the expected one | the result code, with its role; detail: "since 12:03" or the time it took | none. A fix: today the icon follows the status only, so a run that ends DONE where ERROR is expected shows a check; it becomes unexpected. |
| Assistants (`AssistantList`) | `chats` | running while one works | "N working" (`accent`); top right: the count of assistants that wait | none |
| assistant (`Assistant`) | `bot` | running: `status === :streaming`; waiting: an open permission, question or sign-in request in the last turn; failed: `status === :error` | the work state that the person sets, with its role as now; detail: the activity (`describe_assistant_activity`) | one public function that finds an open request of any of the three kinds; today a private one finds only a permission |
| agent session (`AgentWork`) | its state (rule 4) | running, waiting (`:requires_action`) | detail: the last tool, the tokens | none |
| evaluator (`EvaluatorToplevel`) | `terminal` | running: a form `is_running`; failed: the last form `is_error` | none | none |
| dashboard | a dashboard glyph | none | none | none |
| message log | a log glyph | none | the counts of warnings and errors in the log, with their roles | none: a count over at most 200 entries |
| fault log | `warning` | failed while it holds a fault, with the count of its lines at the bottom left (Q11) | none | none |
| MCP log | a log glyph | failed while `faults > 0` | "N faults" (`error`) | none |
| roster, arranged view | a table glyph | filtered while an arrangement has a filter or a sort | the count of the rows, and for an arrangement the count of the shown items, in the tint that the counted items share; no count for none | none |
| work plan, step | its state (rule 4) | as now | "3/7" | none |
| navigator | the decoration of its page, as its tab now | | | none |
| gesture log, statistics, frame times, selection, system processes, settings, appearance, the help pages | their glyph | none | none | none |

omnet:

| Kind | Icon | Conditions, and the state they read | Counts and detail | New state |
| --- | --- | --- | --- | --- |
| simulation project (`LegacySimulationProjectPage`) | a project glyph | running: the discovery is `:reading`, or its build group runs; failed: the discovery is `:failed`, or its last build failed | the count at the bottom left of the files that the discovery could not read (`discovery.problems`, which nothing shows now); "not built" (`warning`) when `facts.project_modes` is empty | `build_group`: the last build or clean group that the page started; today a running build is found only by a scan of the groups of the session |
| Runner | `play` | running while its last group runs | detail: the count of the match, as its footer says it now | `last_group`: the last group that the Runner started |
| INI file | `file_sliders` | failed: the discovery could not read it | none | `problem`: the update of the entries writes it from `discovery.problems` |
| configuration | `settings` | running at the top left while one of its runs runs; the count of its failed and unexpected runs at the bottom left; `:abstract` after the name | "N runs" (out of the label); "N CODE" for each unexpected code | `last_tasks`: the last task of each of its runs (Q12) |
| run | a run glyph | the conditions of its last task | the result code of its last task | none: it reads its task from `last_tasks` of its configuration (Q12) |
| fingerprint store | a store glyph | unsaved and changed on disk, as any file document | the count of its entries | none |
| statistical baseline | a store glyph | read only | the count of its files | none |
| result folder (plan C step 3) | a results glyph | running while it reads; failed | the count of its files | the read state of plan C |
| result file | `chart_line` | read only | none | none |
| Running now, Not expected | a table glyph | none | the count of its items, in the tint that they share: blue while all run, red for a failed task, when not 0 | none |

The new glyphs come from the Lucide font, one line each in `LUCIDE_ICON_GLYPHS`.

Not in this design: an unsaved mark for the settings and the appearance (nothing
records a saved state of them), a slow frame count (only the view of the
statistics computes it), and "new since you looked" (Q11).

#### 5.14.5 The widget

The icon becomes a value with its decoration (Q10):

```julia
WidgetIcon(:settings; role = :warning,
           top_left    = WidgetIconMark(:loader; role = :accent),
           bottom_left = WidgetIconMark(3; role = :warning))
```

- One printer draws it, at every place that draws an icon: a row of a tree, a
  tab, a toolbar button, a menu item, an item of the address bar. A corner mark
  (`WidgetIconMark`) is a glyph or a count, with a role, drawn as rule 7 of
  §5.14.3 says. A plain `Symbol` still names an icon with no decoration.
- `WidgetTreeNode` takes a `WidgetIcon` as its icon, and gets two fields after
  the label: `badges` (the counts, as `WidgetBadge` pills, which exist) and
  `detail`.
- One function makes the widget parts from a `DocumentDecoration`. The default
  of `make_pane_tab_title(document, name)` reads the decoration, so every tab
  gets the decoration of its content, and the method of the task group becomes
  its decoration.
- The Fault log button of the toolbar gets the count of its faults at the bottom
  left from the same value, which closes the limit "the fault button shows no mark for a fault that
  nobody read" of `shell.md`.

### 5.15 New names

So that nothing new comes in silently, this is the whole list:

| Name | What it is |
| --- | --- |
| slice `explorer` (`source/platform/explorer/`) | after `tree` and `navigator` |
| `Explorer(content)` | the document of an explorer tab: `tree`, `navigator`, `filter` |
| `ExplorerSection(title, entries)` | a list of entries that the person controls |
| `ExplorerFilter(text, kinds)` | the filter of one explorer |
| `get_session_explorer_content(; editor)` | the explorer content of the editor |
| the open files of the editor, a session document (its name is chosen in step 4) | one document for each open file path (Q3) |
| `AddExplorerEntryOperation(document)` | "Add to explorer", which the editor evaluates |
| `is_explorer_entry_type(::Type)` | the trait of the kinds that `+` lists (Q2) |
| the open places of `DocumentTree` | per place, not per document (Q1) |
| `Dashboard(title, cards)`, `DashboardCard(title, content)` | the dashboard (Q4) |
| `get_document_decoration(document)`, `DocumentDecoration`, `DocumentCount` | the decoration of a document, in the domain slice, below the tree and the pane (Q9); it takes in `get_tree_node_icon` |
| the list of conditions (§5.14.3) | one table of tint and mark for each condition |
| `DocumentCondition(name; count)` | one condition of a decoration, with a count when it has one |
| `get_condition_look(::Val{name})` | the place, the glyph, the role and the words of a condition; the platform answers the list of §5.14.3, and a package answers a fact of its kind (Q10) |
| `WidgetIcon(name; role, top_left, top_right, bottom_left, bottom_right)`, `WidgetIconMark(glyph or count; role)` | an icon with its tint and its four corner marks (Q10) |
| `WidgetTreeNode.badges`, `WidgetTreeNode.detail` | the counts and the detail of a row |
| `FileSystemFile.document`, `FilePage.failure` | the file document of a row (Q3), the failure of a file |
| omnet: `build_group` of the project page, `last_group` of the Runner, `problem` of an INI file, `last_tasks` of a configuration | the state that §5.14.4 needs (Q12) |

No new event, no new payload of a reader and no new reference step. The view of
the explorer reads the answers of its tree and its navigator, as the omnet view
does now.

## 6. Questions for the owner

Each question has the options and my recommendation. The recommendation is mine
and is not a decision.

**Q0. The model. Decided: (a), the owner, 2026-10-17.** (a) The explorer is one
document of a tree, a navigator and a filter over one content per editor, and an
entry is a link to any document; both binaries use it. (b) Each binary keeps an
explorer of its own, as omnet does now, and projectured gets a second one. The
reason for (a): the omnet view is already generic in all but its root type.

**Q1. The open nodes: by place or by document. Decided: by place, the owner,
2026-10-17.**

| | "Tasks › #3 build" | "Views › Running now › #3 build" |
| --- | --- | --- |
| by document (now): the person opens the first | open | open |
| by place: the person opens the first | open | closed |

By place, the tree names a place by the documents on its path, so an insert
before it changes nothing. The cost: the open set of a tree has more keys, and
the change is in the tree slice. The hold does not change: the tree holds each
open document once, also when it is open at two places. The reason for by place:
the same object at many places is a requirement of the ask, and every reference
tool opens one place at a time.

**Q2. The list of `+`. Decided: (a), the owner, 2026-10-17.** (a) A new trait,
`is_explorer_entry_type(::Type)`, default `false`, which a slice answers `true`
for its kinds: folder, task list, assistant list, project, dashboard, section.
The list is the insertion candidates for which the trait answers `true`. A typed
name of any other document still works and adds a scratch document. A package
that loads adds its kinds at once. (b) No filter: `+` lists every document that
Ctrl+T offers (`get_insertion_candidates(Document)`), with the parts of each
domain, such as a JSON string. (c) The binary names the list, as the shell names
the tools; a package that loads later can not add a kind. The reason for (a): it
is the only option that is short enough to use and open to packages that load
later. For step 5: `TaskGroupList` needs the session list as its insertion, as
`AssistantList` has, and a folder with no path shows a page that asks for it.

**Q3. The page of a file. Decided: (a), the owner, 2026-10-17.** (a) The page
shows the content of the file, editable, and it is the same document as the tab
of the file, so an edit on the page is an edit of the file. The read starts when
the page acquires the file. (b) The content, read only; an edit needs a tab.
(c) The facts of the file (size, time, kind) and an Open button. The reason for
(a): the page beside the tree is how a person looks into things, with no preview
tab (omnet D3), and a page that takes no edit is a preview under another name.
(a) needs a new model part: **the editor keeps one document for each file path**,
and an open of a file that is open reaches that document. Today each open of a
file makes a new tab with a new document (`evaluate_operation(editor,
::OpenFileOperation)` in `FileSystemDocument.jl`), so a file opened twice is two
documents in one editor; (a) removes that defect. The entry "Open files" lists
this table of the editor.

**Q4. The dashboard. Decided: (a), the owner, 2026-10-17.** (a) A new document,
`Dashboard(title, cards)` of `DashboardCard(title, content)`, which says what is
on it, and one view, which draws the cards in columns that follow the width.
(b) A markdown page with embedded documents, which exists: one column. (c) A
layout of widget cards (`FlowLayout` of `WidgetCard`), which exists: the data is
the view, and card widths come from their content. The reason for (a): data and
its view are separate, and (c) stores the view as the data; (b) gives only one
column. The view draws with the existing `WidgetCard` and a flow of cards. If
`FlowLayout` can not make the cards fill a line, step 8 brings that back to the
owner as a question and adds no layout feature on its own.

**Q5. Where the content is saved. Decided: (b), with the write at the close, the
owner, 2026-10-17.** (a) Only in the file of the window that
`save_user_interface` writes. (b) Automatically, in the state folder of the user
(`XDG_STATE_HOME`, or `~/.local/state`), at
`projectured/explorer/<name of the folder>-<short hash of its path>.pred`: one
file for each folder that a binary opens, and for omnet the project folder. The
editor writes it when the window closes, because the close releases the content
and the release exists, and also when the person saves the window. The first
open of a folder with no file gives the first content of the binary (§5.10).
(c) In the folder itself, in `.projectured/explorer.pred`. The reason for (b): a
person who adds a folder expects to see it at the next start, and (c) puts a file
in the project of the person. Not chosen: a write after each change, which needs
a way to start a write when the content changes; no such way exists, and it would
be a new mechanism.

**Q6. The omnet root. Decided: (a), the owner, 2026-10-17.** (a)
`LegacySimulationWorkspace` goes: the project page is an entry, the task list is
the session entry "Tasks", and the two views are a section "Views". A second
project is a second entry, which `+` "project" adds (Q2). The address code of the
workspace (`find_navigator_address(workspace, x)`) moves: the project page
answers for its INI files, configurations, runs and stores, the task list for its
groups and tasks, and the section asks each entry (§5.5). The overview page of
the workspace gives way to the page of a section. (b) The workspace stays as one
entry, "Simulations", with its projects, groups and views below it. The reason
for (a): the groups and the views are not parts of a simulation, a build or an
assistant also starts tasks, and (a) gives several projects with no new code
("several workspaces should be possible", catalog Q8).

**Q7. The place of the omnet Runner. Decided: (a), the owner, 2026-10-17.** The
owner, 2026-10-17: "the runner would
be an entry in the explorer, no?" The Runner (`LegacySimulationRunner`) holds the
project model (`project::LegacySimulationProject`), its selection and its
settings, so it belongs to one project. (a) The Runner is the first child of its
project node, "inet › Runner": the project page holds its runner, and the tree
lists it before the INI files. Each project has its own runner. (b) The Runner
is an entry of the root, after its project. With two projects, the root holds
two runners. In both, the Runner tab stays, shows the same document, and the
window opens on it. The reason for (a): the runner runs the simulations of one
project, and the runner holds the project model, not the project page, so a page
that holds its runner makes no cycle.

**Q8. The tools of the toolbar in the explorer. Decided: the proposal below, with
two changes, the owner, 2026-10-17:** "mostly right, inet should be under
simulation projects or something. There can be more than one evaluators. We can
later refine the explorer tree structure". So a project is in a section
"Simulation projects", and the evaluators are a section "Evaluators" with one
evaluator at first, to which `+` adds another. §5.10 holds the result. The ask,
the owner, 2026-10-17: "I would
even put all toolbar options there. For example, under editor or settings or
system. I don't know". The tools are Explorer, Assistant, Evaluator, Message log,
Gesture log, Fault log, Statistics, Frame times, Selection, Appearance, Settings,
Assistants and, with MCP, the MCP log; the Help menu has Documents, Projections
and About. F1 and the command palette are popups over the selected part, not
documents, so they stay keys. My proposal for the first content, before the two
changes:

```
Explorer
├ inet               (omnet) Runner, INI files › configurations › runs, Results, Stores
├ Files
├ Open files
├ Tasks
├ Assistants         each assistant: its conversation, and its work below it
├ Evaluator
├ Dashboards
├ Editor             what this editor does now
│  ├ Message log, Gesture log, Fault log, MCP calls
│  ├ Statistics, Frame times
│  └ Selection, System processes
├ Settings           the groups of the settings, Appearance
└ Help               Document kinds, Views, About
```

The toolbar stays as it is: a press reaches the open tool or opens one (R1).
The explorer and the toolbar then reach the same documents. Open for step 4: the
list of assistants is made from the tabs (the owner, 2026-10-09), so an
assistant that the explorer makes needs a place in that list.

**Q9. One decoration for every place. Decided: (a), the owner, 2026-10-17.** The
owner added: several kinds can have several corner marks on the icon, counts or
small glyphs, as in IDEs, and tooltips are fine; so §5.14.2 has four corners,
each with one meaning. (a) A new generic in the domain slice,
`get_document_decoration(document) -> DocumentDecoration`, which every place that
names a document draws: a row, a tab, an item of the address bar, the name
column of a roster, the title of a card. It takes in `get_tree_node_icon`, and the
default of `make_pane_tab_title` reads it. (b) The tab keeps
`make_pane_tab_title`, and the tree gets generics of its own for its tint, marks
and counts. A tab and a row of the same document can then disagree, and a kind
writes its state twice. The reason for (a): consistency is the ask, and (b) gives
two places to keep in step for each kind.

**Q10. The icon with its corners, and the look of a condition. Decided: (a), the
owner, 2026-10-17.** (a) A value,
`WidgetIcon(name; role, top_left, top_right, bottom_left, bottom_right)`, each
corner a `WidgetIconMark` (a glyph or a count, with a role), which every place
that draws an icon takes and one printer draws: a row, a tab, a toolbar button, a
menu item. The look of a condition is one generic, `get_condition_look(::Val{name})`:
its place, its glyph, its role and its words; the platform answers the list of
§5.14.3, and a package answers a fact of its own kind, such as `:abstract`.
(b) Fields of their own on each widget: `WidgetTreeNode` gets `icon_role` and four
corner fields, as `WidgetTabLabel` has `icon_role` now, and `Action` gets them for
a toolbar button; the look of a condition is a fixed table of the platform, and a
package can not add a fact. The reason for (a): one value drawn by one printer is
the same at every place, the Fault log button gets its count with no field of its
own, and a package that loads adds its facts as it adds its kinds (Q2).

**Q11. What a count at a corner counts. Decided: (a), the owner, 2026-10-17.**
(a) What is still there: the open
requests of an assistant, the faults in the fault log until the person clears it,
the files that a discovery could not read, the runs that failed. Nothing new is stored. (b) What is new since the
person looked: a new reply, a new fault, a new result. That needs a "seen" state
in each document, and a write of it when a page shows; a tab holds its content
also while it is hidden, so the hold of a tab can not be the write. The write
would be a new way to start an operation when a page shows, which is a new
mechanism. The reason for (a): it needs no new mechanism, and a count of what is
there now says what still needs the person; IDEs count problems so. The count
goes to zero when its cause goes: the request is answered, the run passes, the
log is cleared. Today no key and no menu item clears a log (`clear_fault_log!`
and `clear_message_log!` are functions only), so the fault log and the MCP log
get a command "Clear", which the menu of a row shows as a command of the
document (§5.8).

**Q12. omnet: where the outcome of a run is stored. Decided: (a), the owner,
2026-10-17.** Today the outcome of a run
is only in the tasks of the session; the explorer would need a search of every
task to mark a run. (a) The configuration entry stores the last task of each of
its runs (`last_tasks`, a run number to a task), which the start of a task writes:
the editor evaluates the start, and it finds the configuration by its key (INI
file, configuration, working directory), as the address code does now. A run row
reads its task from there, so its state is live, also while it runs. The
configuration row sums the states of those tasks; the configuration holds them,
so this is no walk of children (§5.14.3, rule 6). (b) Nothing is stored: the
outcomes stay in the tasks, under Tasks and the two views. (c) A copy of the
result code, which the end of a group writes with its `end_operation`: it is not
live while the group runs. The reason for (a): it is live, it writes once at the
start, and it copies nothing. The project page stores its `build_group` and the
Runner its `last_group` in the same way, at the start of the group. A limit of
(a) and (c): the outcome lasts for the session only; the tasks are session
documents, so a save keeps none, and after a restart the rows show no outcome.

## 7. Steps

Each step is one or more commits in a worktree, with a check of `SEALING.md`
before each edit of a kernel file. Mark each step done here.

1. [x] **The explorer document and its view** (projectured). `Explorer`,
   `ExplorerSection`, the view of the tree beside the navigator lifted from the
   omnet view, the overview page of a section, `find_navigator_address` of a
   section, the insertion name "explorer". The alias moves from
   `WorkspaceExplorer`, which keeps "files" and "file explorer". Test:
   `test_explorer()`, new.
   **Done 2026-10-17** on branch `explorer`. What the step found and decided:
   - The slice `explorer` loads after `navigator`; its edges are collection,
     domain, focus, layout, navigator, pane, projection, style, tree, widget.
   - The tree slice exports `collect_tree_children(document; limit)`: the first
     children of a node with their paths, a lazy list read from its head only.
     The page of a section uses it, and the filter and the menu can.
   - A double press: its first press already shows the page, so the visit of
     the second press is `nothing`. The explorer then writes the selection that a
     visit writes, `navigator.content.<address>`, so the keyboard goes into the
     page. The omnet view has the same gap; step 10 takes the fix with the view.
   - The page of a section: a `WidgetCard` for each entry, its name and its first
     five children as links (`WidgetButton` with `OpenPageOperation`, Ctrl for a
     new tab), in a scroll pane; a computation of the list of cards follows the
     entries. An empty section says "This section has no entry."
   - A duplicate of an explorer shares the section and has a new tree and
     navigator. `accepts_opened_file(::Explorer) = false`, as the Files tree.
   - `get_session_explorer_content` finds the section of an explorer in a tab
     of the window, else makes an empty one, as the task list does.
   - The umbrella `ToolViewTest.jl` asserted that "explorer" names `Workspace`;
     it now asserts "file explorer" names `WorkspaceExplorer`.
   - The exports of `TreeModule` follow the order of their definitions now, a
     guard violation that main has too.
2. [x] **The tree** (projectured). Open places (Q1), the mark of the current
   page, and the keys Right, Left, Home, End, Page Up, Page Down. The lazy rows
   are on main and do not change. Test: `test_document_tree()`.
   **Done 2026-10-17.** What the step found and decided:
   - `DocumentTree.expanded` is the open places: an `IdDict` from the document
     of each open node below a place to the `IdDict` of the places below it; the
     root is the one key at the top. `collect_open_tree_documents(tree)` gives
     the held documents, each once. A chevron write builds the places from the
     index paths and holds or releases a document only when it opens at its
     first place or closes at its last.
   - One limit of places by documents: two siblings that are the same document
     under one parent are one place, so they open together. The plan's case, one
     document under two parents, opens at each place on its own.
   - `DocumentTree.current` (a value, a cell or a function) is the path of the
     node of the current page; `WidgetTree.current` is its index path, and each
     row draws a bar of `current_width` (the theme's `stroke`) in
     `current_color` (the theme's `primary`) at its left edge. A path into the
     document of a node marks that node. The explorer passes the address of its
     navigator.
   - `WidgetTree` has the field `current` after `anchor` and `shown`: a
     positional call that passes the selection and the mouse target passes
     `anchor`, `shown` and `current` before them.
   - The keys take no modifier; Up and Down keep their old rule. End does
     nothing in a lazy list of rows. Page Up and Page Down move by the height of
     the view in rows, less one: the view that a pane offers
     (`WidgetTreeToGraphicsCanvasIoMap.view_height`), else the canvas of the
     tree. The view does not scroll to the
     new selection, as before (a limit of the file tree too).
   - `tree.md` describes places, the mark and the keys.
   - With the viewport plan on main, the tree holds the documents of its open
     places and of its shown rows (`tree.shown`). One write of view state
     replaces the places, the shown rows, or both, and one
     `ChangeHeldDocumentsOperation` holds the difference.
     `_collect_first_lazy_children` walks the places.
3. [x] **The decoration of a document** (projectured, §5.14). `DocumentDecoration`
   and `get_document_decoration` in the domain slice, the table of the
   conditions, `WidgetIcon` and its printer, `WidgetTreeNode.badges` and
   `detail`, the default of `make_pane_tab_title` that reads the decoration;
   `get_tree_node_icon` and the counts in the labels move into the decoration;
   the decorations of the projectured kinds of §5.14.4, with `FilePage.failure`,
   the public function for an open request of an assistant, and the fix of the
   icon of an unexpected task; the count of the Fault log button; the command
   "Clear" of the fault log and the MCP log (Q11);
   `DocumentCondition`, `WidgetIconMark` and `get_condition_look`; an image of
   rows with four corner marks at the scale 1 and 2 (rule 7). Test:
   `test_document_tree()`, `test_widget_icon()`, the task and pane suites.
   **Part 3a done 2026-10-17: the model and its drawing.** What it found and
   decided:
   - The domain slice holds `DocumentCondition(name; count, role)`,
     `DocumentCount(text; role)`, `DocumentDecoration(; icon, conditions, counts,
     detail, tooltip)`, `get_document_decoration` (its default answers the
     decoration of the document of `get_edited_field`), `ConditionLook(place,
     glyph, role, words)`, `get_condition_look(::Val{name})`,
     `DOCUMENT_CONDITIONS`, `find_decoration_tint`, `collect_decoration_marks`
     and `format_decoration_words`. Plain structs: a decoration is a computed
     value.
   - "Not started" takes the glyph `:hourglass`; the font has no plain clock.
     The glyphs `:lock`, `:funnel` (Lucide `filter`) and `:hourglass` are new.
   - The widget slice holds `WidgetIconMark` and `WidgetIcon` as widget
     documents, so a saved tab title can write them, and `WidgetDecoration.jl`:
     `make_decoration_icon` (a plain `Symbol` when there is no tint and no mark),
     `make_decoration_badges` (facts as small `WidgetIcon`s, then the pills) and
     `_push_decorated_icon!`, which the tree rows and the tab strip share. A mark
     is 45 % of the icon, a third outside its box, on a disc of the color behind
     the icon; a count is a pill of the surface of its role.
   - `WidgetTreeNode` has `badges` and `detail`; a row draws the facts, the
     detail and the pills after its label, and its measured width holds them.
     The tree printer has `badge`, `detail_text` and `mark_background`.
   - The default `make_pane_tab_title` reads the decoration of the content: icon,
     tint, pills and the conditions in words as the tooltip. A document with no
     decoration keeps a plain tab.
   - A kind with no icon in its decoration keeps `get_tree_node_icon`, which
     omnet still uses; step 10 moves omnet to decorations and takes the generic
     away.
   - Not in 3a: the tooltip of a row. A dwell on a row reaches no node now, and a
     binding of a node gets the widget node and not its document; 3b decides how
     a row shows its conditions in words.
   **Part 3b done 2026-10-17: the work items and the assistants.** What it found
   and decided:
   - `DocumentDecoration` has `work_item`: a task, a group, a closed group, a
     work plan step and an agent session say it. Their icon is their state, so
     their top left and bottom left corners, which say a state, stay empty, and
     only they take the green of `:done`.
   - The task group's tab title and its tree node read one decoration; its old
     `make_pane_tab_title` method is gone, and `make_task_group_tab_title` and
     `make_task_group_list_tab_title` give the default title. A stop is the
     condition `:stopped`: the tab icon has no warning tint now, the pill
     "cancelled" keeps its warning role.
   - A task's label is its name; its detail keeps the status word and the time
     ("running since 12:03", "1.2 s"), its result code is a pill, and a result
     that is not the expected one shows `x`.
   - The labels of a group, an agent session, a work plan and a step are their
     names; the rest is detail and pills. The work page of an agent joins the
     label and the detail in the text of a link, so the page reads as before.
   - `collect_open_assistant_requests(assistant)` is public: the permission,
     question and live sign-in requests of the last turn. An assistant waits
     while one is open; the list counts the assistants that work and wait.
   - The task, assistant and work plan slices use the domain module; the work
     plan slice has the edge `domain`.
   **Part 3c done 2026-10-17: the files, the logs, the tools and the pages.**
   What it found and decided:
   - `get_file_icon(path)` of the file format slice maps an extension to its
     glyph; the file tree and a file document use it. A file document says
     `:unsaved` (its history answers it) and `:read_only`, with its folder as its
     detail; a file page adds `:changed_on_disk`, or `:conflict` with unsaved
     edits, while its band shows.
   - Not done: `:failed` of a file whose change does not parse. The drain of the
     file changes throws the failure as a fault; a field of the page needs the
     drain to hand the failure to the page, a new seam between the watcher and
     the page, which is a question for the owner.
   - A folder reads (`:running`) and fails with the failure in its words; a log
     of messages counts its errors and warnings; the fault log fails with the
     count of its lines; the MCP log fails and counts its faults; a roster has
     its glyph and no count; an arrangement adds `:filtered`; a navigator says
     what its page says; an evaluator runs and fails; the other tools have their
     glyph. A roster first counted its rows, and that started the search of its
     source when its row drew; in the omnet explorer the search walked into the
     views that drew that row, and a cell read itself (found 2026-10-18, after the
     landing). A decoration reads fields that are there, and starts no search.
   - New glyphs: `:layers` (a section), `:folder_tree` (an explorer), `:files`,
     `:scroll_text`, `:plug`, `:table`, `:cpu`, `:circle_help`. The Message log
     button shows `:scroll_text`, as its decoration does.
   - The system process, settings management, appearance, roster and
     arrangement slices have the edge `domain`.
   - `get_tree_node_icon` now has methods only in omnet; step 10 moves them.
   **Part 3d done 2026-10-17: the tooltip of a row, the Clear commands, and the
   check of the marks.** What it found and decided:
   - A row has the tooltip of its node: `WidgetTreeNode.tooltip`, which the tree
     of documents fills with the conditions in words. A rest of the pointer on
     the row answers `OpenTooltipOperation`, titled by the label and rooted under
     the node, as the mark of a cell of a table answers.
   - The fault log has the command "Clear the fault log", and the MCP log "Clear
     the MCP log" (empty entries, no faults), as rows with no key of their own
     gesture tables: the command palette runs them, and the menu of a row will.
   - The check of rule 7, on images at the density 1 and 2 with no supersample:
     the first sizes hid the glyph and made a dot of one pixel. A mark is now 50 %
     of the icon and centered on the corner of its box; a count is a pill whose
     text is 60 % of the icon, at least 8 pixels; the unsaved mark is a filled
     disc, because the glyph of a dot is one or two pixels at that size. Four
     marks on one icon of 16 pixels still hide much of the glyph at the density
     1, as overlays do in IDEs; most rows have one or two.
   - Not done, a question for the owner: the count of the Fault log button. The
     shell builds the toolbar before the editor exists, and the fault log
     wrapper attaches the log of the editor later, so the button needs a link
     between two wrappers, which is a new mechanism.
   - Not done, a question for the owner: `:failed` of a file whose change does
     not parse (see part 3c).
4. [x] **The kinds of projectured become nodes.** The four generics for
   `Workspace`, `WorkspaceFolder`, `FileSystemDirectory`, `FileSystemFile`,
   `Roster`, `AssistantList` and `Assistant`; the page of a folder as a table of
   its entries; the open files of the editor, one document for each path, which
   the open of a file and the page of a file both reach (Q3); the page of a file;
   the first content of the application. Test: `test_explorer()`,
   `test_filesystem()`.
   **Part 4a done 2026-10-17: the nodes, the page of a folder, and the first
   content.** What it found and decided:
   - `Workspace` ("Files"), `WorkspaceFolder`, `FileSystemDirectory` and
     `FileSystemFile` are nodes (`FileSystemTree.jl`; the file system slice has
     the edge `tree`). A `WorkspaceFolder` holds its folder, so the open of its
     node reads the folder on its task. A root folder of a workspace shows a
     chevron until its own read finds it empty: no read of a parent says it.
   - A tree that a view makes is held by nothing and starts no read, so the page
     of a folder is no tree: it is a line with the path and the state of the
     read, and a table of the entries with their kind, lazy with an offered
     height (`FileSystemDirectoryToWidget`, for a folder and a workspace folder).
     Each name is a link to the page of its entry.
   - `AssistantList` has the assistants as children, and an assistant its
     subagents and background tasks.
   - `make_editor_explorer_content(; editor, entries, mcp_log)` of the
     application slice makes the first content of §5.10 from the documents of the
     session, once the editor exists; the host gives its own entries first. Step
     9 calls it. Its sections: Evaluators, Dashboards, Editor, Settings, Help.
   - Not in 4a: "Open files" and the page of a file, which need the document of
     each file path (part 4b).
   **Part 4b done 2026-10-17: one document for each file path.** What it found and
   decided:
   - The store of file changes is no table of the open files: an editor without
     the file change wrapper has none. So the open files are a session document
     of the file format slice, `OpenFileList` (`get_session_open_file_list`,
     `find_open_file_document`). The acquire of a file page or a file document,
     in the file change slice where the hold of a file lands, adds it, unless the
     page that shows it is listed; the release of its last holder takes it away.
     So the list is what the editor shows now. The file format slice has the
     edge `tree`; the glyph `:file_stack` is new.
   - An open of a file that the list holds reaches that document: the tab whose
     content it is takes the focus, or a tab opens on it. A second open opens no
     second tab.
   - `FileSystemFile` has the field `document`. Its acquire takes the open
     document of its path, or reads the file as an open does, in the evaluation
     of the operation that acquires, and holds it, so the page watches the file.
     Its release lets the page go and forgets a page with no unsaved edit. A save
     writes the path only.
   - The page of a file node (`FileSystemFileToWidget`) draws that document by its
     own row, so an edit on the page is an edit of the file.
   - The first content lists "Open files" after the entries of the host.
   - A limit: a page with unsaved edits that no tab and no page shows stays in its
     file node, out of the list, until the node shows it again.
5. [x] **Add and remove.** `+` and Insert with the list of Q2, Delete, F2, new
   section, the keys to move an entry, "Add to explorer" in the menu of a part
   and of a tab, and the save of Q5.
   - [x] **5a. The kinds** (2026-10-17). `is_explorer_entry_type(::Type)` is in
     the tree slice (`TreeInterface.jl`), because the slices of the kinds
     (filesystem, task, assistant) are below the explorer and above the tree; the
     default is `false`. The kinds: `WorkspaceFolder` (alias "folder"),
     `TaskGroupList` ("tasks", the session list, which a file now writes as a
     marker, as `AssistantList` does; the task slice has the edge
     `serialization`), `AssistantList` and `ExplorerSection` ("section", "New
     section"). The list of `+` is the insertion candidates for which the trait
     answers `true`, each named by its first alias (`_collect_entry_kinds`).
     A folder that a person adds has no place: its row says "New folder", it has
     no chevron and holds nothing. Its page asks for the place in a field that
     edits `pathname`; Return or Open writes the place into the folder and its
     folder document and holds that document, so the read starts. The Open
     dialog has no completion of a path, so the field has none.
   - [x] **5b. Add, remove and move** (2026-10-17). `AddExplorerEntryOperation(document;
     section, index, navigator, selection)` is in the widget slice, beside
     `OpenFileOperation`, so the menus of the navigator and the pane can name
     it; the explorer slice evaluates it. Its evaluation inserts the entry, then
     visits its page and selects its node, because a visit made before the insert
     finds no page (`make_navigator_open_operation` reads the page when it is
     made). Its inverse removes the entry; the page and the selection are view
     state. The keys of `@gestures Explorer` work while the selection is on a
     node of the tree:
     - Insert opens a menu of the kinds, sorted by name, and "Other document".
       Decision (mine): a menu, and not a typed name with completion as in the
       walk of §5.4. The completion of an insertion filters by the declared type
       of its place, and the trait of Q2 is no type, so a typed name could not
       show the list of Q2. The menu shows it. "Other document" adds a
       `DocumentInsertion`, whose page takes any name (Q2). A limit: after that
       name commits, the type in the address of the page no longer matches, so
       the navigator shows the section.
     - An entry comes after the selected entry, at the end of a selected section,
       or after the entry above a selected node that is no entry.
     - Delete removes the selected entry and selects its section with its page.
       A node below an entry, and the root section, take no Delete. A limit: the
       tree holds a removed document that was open or shown until its next
       toggle or scroll (bounded).
     - Ctrl+Shift+Up and Ctrl+Shift+Down move the entry, as they move a series
       in a chart. The tree moves its selection with Up and Down whatever the
       modifiers, so these two rules are `override`, and `ExplorerToWidget` gives
       a key that the tree answered to the table of the explorer as a claimed
       key, as the navigator does with its page. At an end of its section the
       entry and the selection stay.
     - "New section" is a command with no key.
     - The `+` button comes with the bar of the filter in step 6.
   - [x] **5c. Rename and "Add to explorer"** (2026-10-17).
     - The page of a section has a field of its title, which edits `title` as
       the field of the place of a folder edits its place. F2 on the node of a
       section visits its page and puts the caret at the end of the title. F2 on
       any other node is left to the pane, which renames the tab.
     - The menu of a part on a page has "Add to explorer" after the two opens,
       for a part that is a document and no widget. It adds the document at the
       end of the root section of the editor.
     - The tab: the header of a tab maps the pointer into the content of the tab
       (`tabs[i].content.selector`), and not to the tab or its title, so a menu of
       the header would read a path that names no part. Decision (mine): no menu
       of the header; the command "Add the tab to the explorer" of the pane tree,
       with no key, adds the document of the focused tab, through its history and
       not into a file. A fix of the map of the header is outside this plan; it
       is an open item for the owner.
   - [x] **5d. The save of Q5** (2026-10-17). `get_explorer_content_file(folder)`
     gives `projectured/explorer/<name>-<hash>.pred` in the state folder, with a
     32-bit FNV-1a hash of the absolute path, because `hash` changes between
     versions of Julia. `save_explorer_content!(content, path; editor)` writes
     the section, and a content that does not write leaves the file and warns.
     `load_explorer_content(path; editor)` gives the section, or `nothing` for no
     file or a file that does not read, with a warning.
     - A fact that moved the design: the close of a window releases nothing
       (`_close_screen_window!` only takes the window out), so the write at the
       close that Q5 names is a write after `run_editor!` returns in
       `run_application`. That call, and the load at the start, are step 9.
       A save of the window (`save_user_interface`) holds the content already,
       inside the explorer of a tab.
     - Each session document of the first content now writes a mark that a load
       gives back as the session document of the editor that loads it, as
       `AssistantList` does: the four logs (message, gesture, fault, MCP), the
       frame statistics and the frame times, the settings and the appearance
       (their values are in their TOML files). Before, a log wrote its capacity
       and a load made a new empty log that nothing fills. The process tree of
       the process of the editor writes that it shows that process, whose id
       changes; any other process tree writes its ids. The slices
       `systemprocess`, `settingsmanaging`, `appearance` and `explorer` have the
       edge `serialization`.
6. [ ] **The filter.** The quick filter, the kinds, and the search below a node as
   a task.
   - [x] **6a. The quick filter and `+`** (2026-10-17). `ExplorerFilter(; text,
     kinds)` is the field `filter` of `Explorer`, view state: the reader of the
     view marks each edit of it as view state, so an undo records none. While the
     filter keeps rows out, the field `matches` holds a second `DocumentTree`,
     of `_ExplorerMatch` rows, which shows in the place of the tree. Decision
     (mine): a second tree, and not a filter inside `DocumentTreeToWidgetTree`,
     because a filter there changes the index path of every row, which the maps,
     the open places and the shown rows of the tree all read. The matches walk
     the open places of the tree only, with `collect_read_tree_children` (new in
     the tree slice: every element, and of a lazy list only the nodes that a walk
     reached), so the filter reads no disk. Every row of the matches is open, the
     row of the page has the mark, and a press on a row visits the page of its
     document at its place in the section. The tree of the matches is made again
     at each change of the filter, of the open places or of a label that it read.
     The view is the bar (the field, `+`, `▾`) above a `VerticalLayout` whose one
     child is the tree or the matches, and each layout carries the part of the
     path of the grid below it, as the bar of the navigator does. Ctrl+F on a row
     puts the caret in the field; Escape there empties the filter and selects the
     node of the page in the tree. `+` opens the menu of Insert, at the end of the
     root when no node is selected. The keys of the entries work on the tree only.
     A file of an explorer keeps the section only (§5.12), and a duplicate copies
     the filter. A limit, seen in a picture of the window (2026-10-18): the field
     of the filter keeps its least width, because a text field takes the width of
     its text and no text field fills its slot; a `LayoutConstraint` with
     `width = Fill` gives the slot the width and not the field. That is a feature
     of the widget, outside this plan.
   - [x] **6b. The kinds** (2026-10-17). `▾` opens a menu: "Every kind" and each
     kind of the rows that the tree read, named as the list of `+` names a kind,
     with the icon `check` on what the filter keeps (a menu item has no check
     mark of its own). A choice adds the kind or takes it out, as view state.
   - [ ] **6c. The search below.** Deferred by the owner on 2026-10-18 ("defer"),
     so it is in §8 and not in this plan. The question was: a walk of
     documents must run on the editor task, because the cells belong to it, and
     the plan says that the search "reads what is not read on its own task". No
     kind says how to read its children now for a search, so that needs a new
     generic, which this plan does not name. The question: (a) a generic
     `read_tree_children_now(document)`, which a folder answers with a read of
     the disk on the task of the search, and the walk runs in steps on the
     editor task; (b) the search walks only what is in memory, and an unread
     folder is a row that says "not read"; (c) leave the search out of this plan.
     Recommendation (mine): (b) first, then (a) in a plan of its own.
7. [x] **The menu of a row.** The items of §5.8, and the commands of the document
   from its own gesture table.
   **Done 2026-10-17.** A right click on a row of the tree or of the matches opens
   one layer named by the row: Open in a new tab; Remove from explorer for an
   entry, or Add to explorer for a node below an entry; Rename, New section and
   Add… for a section; Open as a list for a node with a lazy list or more than 50
   children, which the navigator beside the tree visits; then, after a
   separator, each command of the gesture table of the document that applies now
   (a rule with a name and no pointer pattern), rerooted from the place of the
   document in the tree. The binding of the right click is spliced into
   `@gestures Explorer`, so it works wherever the selection is. Facts and
   decisions:
   - No refresh exists for a document of outside state, and a watched folder
     follows the disk, so the menu has no Refresh (no new mechanism).
   - Add… opens the menu of Insert as its operation, because a context menu
     window opens no submenu of its own.
8. [x] **The dashboard** (Q4). The document, its page, `+` "Dashboard", and the
   insert of a card by the assistant.
   **Done 2026-10-17**, in the explorer slice (`Dashboard.jl`,
   `DashboardToWidget.jl`). `Dashboard(title, cards)` of `DashboardCard(title,
   content)`; the cards are the children of its node; the icon is
   `layout_dashboard` (new glyph, and `panel_top` for a card), with the count of
   the cards. "Dashboard" is in the list of `+`. The page has a field of the
   title (F2 and Rename reach it, as for a section) and the cards in a grid in a
   scroll pane; the content of each card draws by the view of its own type, and
   the page maps `cards[k].content.<rest>` both ways, so a press, a caret and a
   key in a card reach its document. Insert on the page adds a card at the end
   whose content is a `DocumentInsertion`; an assistant adds one with an insert
   into `cards`, and an undo takes it back. Facts:
   - `FlowLayout` keeps the width of each child, so it can not make the cards
     fill a line. The page uses a `GridLayout` of equal weights, with as many
     columns as cards of `card_width` (a least width) fit in the exact width of
     the print: in pictures of 2026-10-18, three columns at 1100 pixels, two at
     640, and two in the page of the explorer. An editor with no size of its
     window, as the tests make, gives no exact width, and then one column. The
     owner chose on 2026-10-18, after an example, that the count follows the width
     while the page shows (option b): the count is a cell that reads the cell of
     the exact width of the print, and the grid is made again only when the count
     changes. In a live window of five cards, a resize from 1100 to 640 to 400
     pixels gives 2, 3 and 5 rows. No layout feature is new.
   - A card is not removed by a key on the page yet; the menu of its row in the
     explorer has no Remove either, because a card is no entry of a section.
9. [x] **The window of projectured.** The Explorer is the first tab of the main
   group, the narrow Files group goes, and the toolbar has Explorer and Files.
   Test: `test_application()`.
   **Done 2026-10-18.** `make_application_document` makes an Explorer whose
   section holds the folder of the window (a `Workspace`), and the main group
   holds it first and a tab for each file after it; the assistant is the other
   group (weights 0.68 and 0.32). The window opens on the first file, else on the
   root row of the tree of the Explorer. `start_application!` makes the first
   content once the editor exists (`make_editor_explorer_content` with the entries
   that the window brought). `run_application` then reads the content that the
   state folder keeps for the folder, and writes it after `run_editor!` returns;
   only `run_application` reads and writes the state folder, so a test that calls
   `start_application!` reads no file of the user. The toolbar: "Explorer"
   (`folder_tree`) reaches an `Explorer` tab, and "Files" (`folder`) reaches the
   file tree; the shell option `explorer` now makes the Explorer, and the new
   option `files` makes the file tree (the shell slice has the edge `explorer`).
   omnet passes `explorer = _make_project_explorer` for its file tree, so step 10
   must pass it as `files`. The tests of the Files pane (a lit row, the divider,
   a tab drag, a double press that opens a file, a scroll) keep their intent with
   a helper that puts the Files tool in a group at the left, as a person who moves
   it there has it. Results: `test_application` 381 pass, 2 broken, as on main
   (380 pass, 2 broken); the file watch window 16 pass; the tool views have only
   the failure that main has ("the file explorer opens by name, seeded").
10. [x] **The omnet IDE** (omnet-julia). The IDE and the campaign window make
   `Explorer` with the content of §5.10 (Q6); the project page holds its runner,
   the first child of the project node (Q7); `LegacySimulationExplorer` and
   `LegacySimulationWorkspace` go;
   the Tasks tab is a navigator over the content at "Tasks"; the result folder of
   plan C step 3 is a node below the project; the decorations and the new
   state of the omnet kinds of §5.14.4 (Q12). Test: `OmnetCampaignUiTest`,
   `OmnetIdeTest`.
   **Part 10a done 2026-10-18: the explorer of the window** (omnet `f3113b00` on
   branch `explorer-ide`, projectured `398146e38` on branch `explorer`). What it
   found and decided:
   - `make_campaign_explorer(project; tasks)` (`source/campaign/CampaignExplorer.jl`)
     makes the `Explorer` and the Tasks tab. The content is a section Simulation
     projects with the project page, the task list of the window, a section
     Views with the two rosters, and the folder of the project (a `Workspace`).
     The Tasks tab is a navigator over the content, at the address that the
     content answers for the task list.
   - `fill_campaign_explorer_content!(editor; tasks, mcp_log)` runs once the
     editor exists. It makes `tasks` the task list of the session
     (`get_session_document!`), because the session finds no list inside an entry
     of a section. Then it adds the tools of the editor
     (`make_editor_explorer_content`), which skips a session list that the
     entries hold already, so the list shows once.
   - The project page has the new field `runners`, and `build_campaign_session`
     puts the Runner of the window there. The page answers
     `find_navigator_address` for its Runner, INI files, configurations, runs and
     stores; the task list answers it for its groups, tasks and inner groups; a
     section asks each entry in turn.
   - `LegacySimulationWorkspace`, `LegacySimulationExplorer`, their projections
     and `count_workspace_view_items` go. The tests `CampaignExplorerContentTest.jl`
     and `CampaignExplorerTest.jl` take their place, and the omnet guides
     `user-interface-anatomy.md` and `interface-composition.md` follow.
   - Limit: the page of a project is one for each project in the process
     (`_PROJECT_PAGES`), so two windows over one project share it, and `runners`
     holds the Runner of the last window.
   - Limit: omnet does not save the content of its explorer yet (Q5), because the
     project page and the views have no file form.
   - Results: campaign window 378 pass, 1 fail (`PaneProgramTest.jl:227`, as on
     main). IDE 638 pass, 5 fail, 13 errors: select and paste 47/1/8, result
     verbs 1, study verbs 1/1, study by hand 30/1 and the Julia file tab 1 are
     the failures of main; the model cases wait for a baseline on main.
   **Part 10b done 2026-10-18: the decorations and the state of the omnet kinds
   (§5.14.4, Q12).** What it found and decided:
   - Four Lucide glyphs are new: `package` (a project), `circle_play` (a run),
     `database` (a store) and `circle_dashed` (the mark of an abstract
     configuration, a condition `:abstract` that omnet adds after the name).
   - The project page says that its discovery reads or failed, that its last
     build runs or failed (`build_group`, which `start_project_page_group!`
     writes), how many INI files the discovery could not read, and "not built".
     Its node holds its Runner, its INI files and its stores (`stores`, a
     computed collection of the fingerprint store and the baseline), so it always
     has a chevron. The decoration reads `facts`, a computed cell that reads the
     disk, as the page does; the cell keeps its value until a refresh or the end
     of a build.
   - An INI file that the discovery could not read has an entry with no
     configurations and its `problem`, which the update of the entries writes.
   - A configuration shows its name, "N runs" as its detail, running while a run
     runs, the count of its failed and unexpected runs, and "N CODE" for each
     unexpected code. A run shows the conditions and the result code of its last
     task. The state is `last_tasks` of the configuration entry (Q12 (a)):
     `record_run_tasks!` writes it at each start of a group of runs of a Runner
     (Run, `run_simulations!` and the test verbs), on the task that writes the
     documents. Not recorded: the run of a simulation card of a study, which
     starts in a file that loads before the page.
   - The Runner says that its last group runs (`last_group`, which Run writes)
     and, as its detail, the line under its form.
   - The fingerprint store says what any file says, with its count of entries;
     the baseline says read only and its count of files.
   - `get_tree_node_icon` goes from the tree slice: every kind names its icon in
     its decoration. It is an exported name, so the next release gives
     `ProjecturedPlatform` a minor step, which the generator of the release finds
     by itself (R36).
   - Two defects that the images of the IDE window found after the landing,
     fixed 2026-10-18 at the owner's "yes": (1) the page of a view showed "a Cell
     read itself while it computed", and the editor stayed busy. The search of its
     roster walks the groups of the task list, and a group that ran holds its
     scheduler, a Julia `Task`, whose closure reaches the editor and the printed
     window. The runtimes of a group and of an execution (`TaskGroupRuntime`,
     `TaskRuntime`) are opaque to the walk now (`is_walk_opaque`). (2) In the
     campaign window no tab held what it showed, so a run row read no details and
     the Runner held no page: the window builds its editor with `tabs = false`,
     and only the `tabs` wrapper and the start of the projectured application
     acquired a window tree. The start of the campaign window acquires its tree
     now.
   - The result folder below the project came with step 3 of plan C of the omnet
     UI session (omnet main `1c225d1f`, 2026-10-18; the node is `6b8c241d`): the
     project page holds one result folder for each working directory in
     `results`, the fourth children of its node, and a run holds its result
     files. The IDE window gives the page its folders when it opens
     (`add_project_results!`); the campaign window gives none, so its project has
     no node Results. That closes step 10. The page of a folder as a lazy table is
     step 3d of plan C, which is no part of this plan.
   - Done 2026-10-18 at the owner's "Do both", after a recommendation that changes
     projectured: the counts of rosters. The cycle of step 3c was the walk into the
     scheduler of a group, which the fix above removed; with it, a count in the
     real IDE window with running groups showed no cycle. A roster counts its rows
     again, an `ArrangementDocument` around a document that shows a collection of
     its own (`get_arranged_collection_steps`) counts the items that it shows, and
     the pill takes the tint that all the counted items share
     (`find_shared_decoration_tint`, new in the domain slice; a `RosterRow` says
     what its item says). No count for none. Not chosen: a keyword of the colour
     on `Roster`, which can disagree with the rows. So Not expected is red for a
     failed task and amber for an unexpected code, where §5.14.4 first said
     `warning` for both.
11. [x] **The documents.** Done for projectured (2026-10-18): `explorer.md` is new,
    and `tree.md`, `navigator.md`, `filesystem.md`, `shell.md`, `application.md`,
    `pane.md`, `task.md`, `assistant.md`, `roster.md` and the guides of the session
    documents follow the branch. Done for omnet with step 10:
    `user-interface-anatomy.md` and `interface-composition.md`.
    The list of the step: A new `documentation/package/platform/explorer/explorer.md`;
    `tree.md`, `navigator.md`, `filesystem.md`, `shell.md`, `application.md`;
    in omnet, `user-interface-anatomy.md` and `interface-composition.md`.

## 8. Not in this plan

The search below a node (step 6c, deferred by the owner on 2026-10-18): it needs
a way to read the unread children of a document for a search, which no kind gives.

Drag and drop of a row; a split beside the explorer from a row; the open nodes in
a save; a page for the names of the evaluator, the API, the examples and the
registries; the reactive cells; a native simulation in the explorer; the undo
history as a node; type to select a row.
