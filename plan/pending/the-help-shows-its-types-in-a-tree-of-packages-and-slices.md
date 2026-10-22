# The help shows its types in a tree of packages and slices

Status: IN PROGRESS, 2026-10-22. The owner answered Q1 (two trees) and asked for
the implementation. Branch `help-tree`, worktree
`/home/projectured/workspace/projectured-julia-help-tree`, off main `ec6fc6a66`.

## The ask

The owner, 2026-10-22: "I would like to organize the documents and projections
in the help by the domains and platform slices in a navigable tree using the
navigator. let's design this"

## What there is now

- The Help menu has Documents, Projections and About
  ([WindowChrome.jl:127](../../source/platform/shell/WindowChrome.jl#L127)).
  The owner named the three labels on 2026-09-25
  ([the-help-menu-lists-document-types-and-projections.md](../done/the-help-menu-lists-document-types-and-projections.md)).
  Each item opens a tab with a scroll pane around the document.
- `DocumentTypeList` and `ProjectionList` hold no field
  ([HelpDocument.jl](../../source/platform/help/HelpDocument.jl)).
  `HelpListToSyntax` computes one flat list, in the order of the names, when it
  prints. No entry is a link.
- The explorer of a window has the section "Help" with the same three documents
  ([ApplicationExplorer.jl:50](../../source/platform/application/ApplicationExplorer.jl#L50)).
  A list has no tree children, so its row is a leaf, and its page in the
  navigator is the flat list.

Facts measured on 2026-10-22, with `ProjecturedAll` loaded:

| | Document types | Projections |
|---|---|---|
| All | 268 | 519 |
| Platform | 113, in 33 slices | 219, in 42 slices |
| The largest slice, widget | 34 | 51 |
| Kernel | 1, in `DocumentModule` | 0 |
| JSON, Julia, RST | 9, 17, 15 | 7, 60, 54 |
| No docstring | 15 | 378 |

- Every type is defined in a module at depth 2, `<Package>.<Slice>Module`: for
  example `ProjecturedPlatform.WidgetModule` and `ProjecturedJSON.JsonModule`.
  Each domain package has one module.
- Each of the 67 modules has a docstring.
- No table in the code says which package is a domain, a backend or an adapter.
  `@domain` marks 10 of the 20 domains, and the text slice of the platform.
- [help.md](../../documentation/package/platform/help/help.md) gives 170 and 445
  for the two counts, and names a test package `ProjecturedHelpTest` that does
  not exist. The tests are in [test/platform/help/](../../test/platform/help/).

## The model

Two trees, Documents and Projections, each with the shape below. The owner
chose them in Q1.

### The tree

```
Documents                  the root, DocumentTypeList
├─ Kernel          1       a package with one module in this tree: its types
├─ Platform      113       a package with more modules: one node for each
│  ├─ Application    1
│  ├─ Widget        34
│  │  ├─ WidgetLabel
│  │  └─ …
│  └─ …
├─ Book            2
├─ JSON            9
│  ├─ JsonArray
│  └─ …
└─ …
```

1. The root holds one node for each package that defines a type of the list.
   Kernel comes first, then Platform, then the other packages in the order of
   the names.
2. A package node holds one node for each of its modules that defines a type of
   the list, when there is more than one such module. Else the package node
   holds the types.
3. A module node holds the types of the module.
4. The types come in the order of the names, with no regard to case, as in the
   list now.

The title of a package node is the package name without `Projectured`: Kernel,
Platform, JSON, SequenceChart. The title of a module node is the module name
without `Module`: Widget, FaultView, MessageLog. A binary knows these names. It
does not know the folder of a slice, such as `fault` or `log`.

### The documents

- **`HelpGroup(name, count, description, children, table)`** is a package or a
  module. `description` is the first paragraph of the docstring of the package,
  or of its one module when the package has none. `children` is a `CellVector`
  of `HelpGroup`s or of `HelpEntry`s.
- **`HelpEntry(name, type, typed, description, text)`** is one type. `typed` is
  the names to type, joined by ", ", and `text` the whole docstring, which the
  build stores, so the page reads no docstring when it prints.
- **The two roots keep their names and get the fields `children` and `world`.**
  The constructor walks nothing. So the candidate walk still constructs a
  `DocumentTypeList` at no cost (reason 3 of help.md), and `pred_arguments`
  stays empty (reason 2).
- **The groups are stored, and the acquire of a root builds them**
  (`update_help_groups!`). Decision made in step 2: the design had a
  `CellVector` whose computation walked the loaded modules at its first read.
  `PAR-PURE-THUNK` forbids that, because the loaded modules are external
  mutable state. The model is the one of a folder: a document stores what was
  read, and its acquire reads (owner, 2026-10-16). The walk is a reflection of
  the loaded program and must run on the task of the editor, so no background
  cell does it.
- **The root follows the loaded program at its acquire** (reason 1). `world` is
  the world counter at the last build. When the counter moved, the acquire
  builds the groups again. A group keeps its object while its path of names
  stays, such as "Platform/Widget", and an entry while its type stays. A
  collection whose objects stay is not written. So the open nodes of a tree and
  the address of a navigator stay.
- The field names are the column names of the tables of the pages, because the
  header of a roster column shows its key.
- `HelpGroup` and `HelpEntry` are no insertion candidates: an empty tab does not
  make one.

### The nodes

| Generic | `DocumentTypeList`, `ProjectionList` | `HelpGroup` | `HelpEntry` |
|---|---|---|---|
| `get_tree_children_steps` | `children` | `children` | none: a leaf |
| `format_tree_node_label` | the title: "Documents", "Projections" | the title | the name |
| `has_tree_children` | `true`, with no read | `true` | the default |

The root answers `has_tree_children` with no read, so the explorer draws the row
"Documents" with no walk. The decoration of a node gives an icon of the icon set
now, and the count of the types below the node as its detail: `:layers` for a
group, `:file` for a document type, `:lambda` for a projection.

### The pages

- **The page of a root or a group** shows the title, the summary, and a table of
  the children. For a root, the summary is the heading of the list now: "268
  document types. Type one of the names in an empty tab to make a document of
  that type." The table is a `Roster` of `CollectionItems` of `groups` or
  `entries`, in an `ArrangementDocument`, as `BackgroundWorkLog` holds its table
  ([BackgroundWorkDocument.jl:55](../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L55)).
  The columns:
  - a group: name, count, summary;
  - a document type: name, typed names, summary;
  - a projection: name, summary.

  A double click on a row opens the page of its node in the nearest navigator.
  The roster answers this already. The arrangement gives a filter and a sort.
  The page is a `make_graphics_projection` method, as the page of the log is.
- **The page of an entry** shows the name, the package and the module, the names
  to type for a document type, and then the whole docstring as its raw text, or
  "no description". The page has a scroll pane of its own, because a navigator
  puts none around a page.
- `HelpListToSyntax` goes. The page of a root takes its place.

### Where the tree shows

- **The explorer.** The section "Help" holds the two roots now. Their nodes open
  in the tree, and a press shows the page in the navigator beside the tree. The
  explorer slice gets no code.
- **The Help menu.** Documents and Projections open a tab with a `Navigator`
  around the root, in place of the scroll pane. The tab has Back, Forward,
  Parent, and an address such as `Documents › Platform › Widget › WidgetLabel`.
  The arrow before a name of the address lists the siblings of that node. A
  second use of the item reaches the tab that is open, as now. omnet-julia uses
  the same menu, so its IDE gets the same tabs.

### The layers

- The help slice gets the edges `collection`, `tree`, `roster`, `arrangement`,
  `layout` and `widget` in
  [PlatformSuite.jl:103](../../test/platform/PlatformSuite.jl#L103). These
  slices load before the help slice. The help slice does not use the navigator,
  which loads after it. The shell makes the navigator.
- The tool layer of the kernel gets the summary of a module, as
  `compute_docstring_summary(::Module)`, and a function that gives the whole raw
  text of a docstring.

## Q1 (answered): two trees, or one tree for both

The owner, 2026-10-22: "nobody cares about the saved explorer file yet / make it
two trees".

- **Option A, two trees: chosen.** Documents and Projections, each with the
  shape above. The labels of 2026-09-25, the menu, the explorer section and the
  omnet-julia menu stay. A document entry and a projection entry answer
  different questions: what a person types in an empty tab, and what draws a
  document. The cost: the page of JSON under Documents shows its 9 document
  types and none of its 7 projections.
- **Option B, one tree: not chosen.** One root holds the packages. A module node
  holds its document types, then its projections, as two collections of
  children. The page of JSON shows both tables. The menu gets one item in place
  of two. The load of a saved explorer file is no reason for or against an
  option: the owner said that nobody depends on it yet.

## Steps

1. [x] **The docstring of a module, and the whole text.** Done:
   `compute_docstring_summary(::Module)` and `find_docstring_text`, which
   answers `nothing` for no docstring and keeps the indent of a signature.
   `test_docstring_summary()` passes, 17 of 17. Add the two functions
   to the tool layer of the kernel. Test: new cases in
   `test_docstring_summary()`. The summary of `HelpModule` is its first
   paragraph. The whole text of a type with two paragraphs holds both.
2. [x] **The groups and the entries.** Done, in
   [HelpTree.jl](../../source/platform/help/HelpTree.jl). `test_help()`
   passes, 62 of 62. `test_platform_layering()` fails one check on two files of
   main (`filechange/FileChangeModule.jl` from `ec6fc6a66`, and
   `shell/ShellModule.jl` from `550163da1`: a symbol list on a `using`), which
   this branch does not touch. The Help module holds four document types:
   `HelpTheme` is one too. Add `HelpGroup`, `HelpEntry`, the field
   `groups` of the roots, the build, the identity across a build, the build at
   the acquire, the tree generics and the decorations. Test: a new testset in
   [test/platform/help/](../../test/platform/help/).
   - The groups of Platform and of JSON have the shape of the tree above.
   - A `DocumentTree` of a `DocumentTypeList` maps the path
     `groups[2].groups[k].entries[j]` both ways.
   - A second build keeps the objects of the groups and the entries.
   - `DocumentTypeList()` walks nothing, and a save writes its type name only.
3. [ ] **The pages.** Add the page of a root and a group, and the page of an
   entry. Remove `HelpListToSyntax`. Test:
   - The page of Platform under Documents has 33 rows.
   - In a `Navigator`, a double click on the row Widget opens its page, and Back
     returns.
   - The page of an entry shows the whole docstring, and it scrolls.
4. [ ] **The menu opens a navigator.** Change the two items of the Help menu.
   Test: the help cases of `test_window_shell()`, and in `test_explorer()` a
   press on Documents › JSON that shows its page.
5. [ ] **The guides and a live check.** Update help.md (the tree, the pages, the
   counts, the place of the tests), the table of the slices that add nodes in
   [tree.md](../../documentation/package/platform/tree/tree.md), and the Help
   menu in shell.md. In a live window, open Help › Documents, go to Platform ›
   Widget › WidgetLabel, then Back and Parent, and take a picture. Run
   `Pkg.precompile` and the help tests of omnet-julia. Move this plan to
   `plan/done/`.

## Not in this plan

- A level of kinds, such as Domains, Backends and Adapters. It needs a fact that
  each package declares, and no table gives it now.
- A link from a document type to the projections that draw it, and back.
- A button on the page of a document type that opens a new tab with one.
- Docstrings for the 378 projections that have none.
- A walk off the loop. The first open of a root walks the loaded modules on the
  loop, for 3 to 5 seconds, as the list does now.

## Open items

- The titles of the nodes: the names that a binary knows (Widget, FaultView,
  MessageLog), not the folders of the slices (widget, fault, log).
- The names `HelpGroup` and `HelpEntry`, to check against
  [naming-rules.md](../../documentation/rule/naming-rules.md).
