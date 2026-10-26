# Help

> **Kind:** design · **Status:** current · **Stands on:** [domain.md](../domain/domain.md), [tree.md](../tree/tree.md), [navigator.md](../navigator/navigator.md), [widget.md](../widget/widget.md)

The help slice of `ProjecturedPlatform` holds what the Help menu of a window opens: the tree of every document type, the tree of every projection, and the page that says what the program is. This document says how a tree groups the types by package and by module, why a tree stores its groups and builds them at its acquire, and what the page of a group and of a type shows.

## How it works

### The documents

The help slice has five document types:

- **`DocumentTypeList`** is the tree of every document type that an empty tab can make.
- **`ProjectionList`** is the tree of every concrete projection: the views a window draws a document with, and the projections that combine other projections.
- **`HelpGroup(name, count, description, children)`** is a package or a module in a tree.
- **`HelpEntry(name, type, typed, description, text, supertypes, fields)`** is one type in a tree.
- **`AboutPage`** holds `name`, `summary`, `version` and `homepage`. It says what a program is.

A tree holds `children`, its groups, and `world`, the world counter at its last build. A new tree holds no group, and its constructor walks nothing.

### The shape of a tree

A tree has three levels at most:

```
Documents                  DocumentTypeList
├─ Kernel          1       a package with one module in this tree: its types
├─ Platform      113       a package with more modules: one group for each
│  ├─ Widget        34
│  │  ├─ WidgetLabel
│  │  └─ …
│  └─ …
├─ JSON            9
│  ├─ JsonArray
│  └─ …
└─ …
```

1. The tree holds one group for each package that defines a type of the tree. The kernel comes first, then the platform, then the other packages by name.
2. A package that has more than one module with a type of the tree holds one group for each such module, by name. Any other group holds the entries of its types.
3. The entries come in the order of the names, with no regard to case.

`parentmodule(T)` is the module of a type, and `Base.moduleroot` of that module is its package. Every type of the source is defined in a module at depth two, such as `ProjecturedPlatform.WidgetModule` or `ProjecturedJSON.JsonModule`. The name of a package group is the package name without `Projectured`: Kernel, Platform, JSON. The name of a module group is the module name without `Module`: Widget, FaultView, MessageLog. The loaded program holds these names, also in a binary. It holds no folder of a slice, such as `fault` or `log`.

The `description` of a group is the first paragraph of the docstring of the package, or of its one module when the package has none (`compute_docstring_summary(::Module)`). `count` is the count of the types below the group.

The types of `DocumentTypeList` are `get_insertion_candidates(Document)`, and the types of `ProjectionList` are [`compute_concrete_subtypes(Projection)`](../domain/domain.md#completion-by-reflection). `HelpGroup` and `HelpEntry` answer `insertable` with `false`, so no empty tab makes one. With the packages of `ProjecturedAll` loaded on 2026-10-22, the Documents tree held 268 types in 21 packages, and the Projections tree about 520 types in 21 packages.

An entry stores what its page shows. `typed` holds the names that a person types into an empty tab to make the type, from `get_insertion_names` without the name of the type, joined by ", ". It is empty for a projection. `description` is `compute_docstring_summary(T)`, and `text` is the whole docstring, `find_docstring_text(T)`, or `""`.

The shape of the type is in two more fields. `supertypes` names the supertypes of `T`, nearest first, joined by " <: ", without the family type `A<Name>` that `@document` makes and without `Any`. `fields` holds a named tuple `(name, type, description)` for each field that a person can set:

- Every document holds `selection` and `mouse_target`, the view state that a save does not keep, so `fields` leaves them out. A field that `get_view_state_fields(T)` names has "View state, which a save does not keep." before its description.
- The type of a document field is the type that `@document` records (`find_declared_field_type`). A projection keeps each field in a cell, so the type of a projection field is the value type of that cell.
- The type shows as Julia prints it, with no module path, so an alias such as `ThemeText` keeps its name. A cell layout `AC<Name>{…}` shows as the document `<Name>`, such as `StyleFont`.
- The description is the docstring of the field on one line (`collect_field_docstrings(T)`), or `""`. The themes and the settings groups have a docstring on each field; most other types describe their fields in the docstring of the type.

### The build

`update_help_groups!(list)` builds the groups from the modules that are loaded now, and stores them in `list.children`. The acquire of a tree calls it when the world counter moved after the last build (`acquire_document!`). So the tree follows the loaded program: a package that loads, or a type that a session defines, shows after the next acquire.

A build keeps the objects of the build before it. A group keeps its object while its path of names stays, such as "Platform/Widget", and an entry keeps its object while its type stays. The build writes no field whose value stays, and no collection whose objects stay. So a second build writes nothing when the program did not change, and the open nodes of a tree and the address of a navigator stay.

`world` is view state of the build. `pred_arguments` answers an empty argument list for both trees, so a `.pred` file writes only the type name, and the acquire after a load builds the groups again. A saved navigator keeps its address as a path, such as `children[2]`, and its page comes back after that build.

### The nodes

A tree and a group are nodes of the tree slice: `get_tree_children_steps` names `children` for both. A tree answers `has_tree_children` with `true` and reads nothing, so the row of a tree shows its chevron before the first build. The label of a node is its title: "Documents", "Projections", the name of a group, or the name of a type.

The decoration gives an icon and a detail. A tree has `:circle_help`, a group `:layers`, a document type `:file` and a projection `:lambda`. The detail of a tree and of a group is the count of its types. The tooltip of a group and of an entry is its name over its description.

### The page of a tree and of a group

`HelpGroupToWidget` draws a tree or a group as a `GridLayout` of one column: a line, and under it a `WidgetTable` with one row for each child, which fills the rest of the height and scrolls there.

```
children[1]                the line
children[2].rows[k]        the row of the node children[k]
```

The line of a tree says how many types and packages the tree holds, such as "268 document types in 21 packages. Type one of the names in an empty tab to make a document of that type." The line of a group is its description, or "No description.".

The page builds the table with every row at once. A page holds at most about 60 rows, and the list of a page changes only at a build, so the table measures each cell. The name and the middle column take `Content`, so each is as wide as its widest cell, and the description takes `Fill`, the rest of the width, cut at its edge:

| Node | Columns |
| --- | --- |
| a tree, or a group of groups | name, types, description |
| a group of document types | name, names to type, description |
| a group of projections | name, description |

The maps lead the node `children[k]`, and any path inside it, to the row `k` of the table, and the row back to the node. So a press on a row selects its node, the selection of a node shows on its row, and Up and Down move from node to node. A double press on a row also answers `OpenPageOperation(nothing, children[k])`, so the nearest navigator opens the page of the node at its place in the tree, and Parent comes back to this page. A Ctrl+press opens the page in a new tab. Ctrl+Return and "Open as a page" read the selected node, so they open it at its place too.

### The page of a type

`HelpEntryToWidget` draws an entry as a column in a scroll pane of its own, because a navigator puts no scroll pane around a page:

1. the name of the type;
2. the module that defines it, such as `ProjecturedPlatform.HelpModule`;
3. the type with its supertypes, such as `AboutPage <: Document`;
4. for a document type, "Names to type in an empty tab:" and the typed names;
5. the whole docstring, one line of the page for each line of the text, or "No description.";
6. a table of the fields, with the columns field, type and description: the field and the type as wide as their widest cell, and the description in the rest of the width. A type with no field to set shows "No fields.".

The page is read only.

### The page about the program

`AboutPageToSyntax` prints the name of the page, its summary when it is not empty, a blank line, "Version " and the version when it is not empty, "Julia " and the Julia version that runs, and the home page when it is not empty. The Julia version comes from `VERSION` and not from a field, so it shows even when every field of the page is empty.

### The theme

`HelpTheme` holds the styles of the pages. `heading_text` draws the line over a table. `name_text`, `detail_text`, `description_text` and `muted_text` draw the page of a type, and `title_text` the name of the program on the about page, which reads `detail_text` and `description_text` too. A projection holds its styles and no theme. `make_help_group_projection(; theme, gap)`, `make_help_entry_projection(; theme, gap)` and `make_about_page_projection(; theme)` fill them with `get_help_style`, from a `HelpTheme` scaled or not, or the default values for `nothing`.

## How it fits

The help slice uses the collection, domain, layout, natural, projection, serialization, style, syntax, text, tooltip, tree and widget slices, and the kernel. The tool layer of the kernel gives `compute_docstring_summary`, `find_docstring_text` and `collect_field_docstrings`.

A tree and a group draw through `make_graphics_projection` of their type, chained to `GridLayoutToGraphicsCanvas`, and an entry draws chained to `VerticalLayoutToGraphicsCanvas`. The `__init__` of the slice registers `AboutPageToSyntax` for the page about the program with `register_natural_syntax!(:help, …)`.

The help slice loads before the navigator slice and does not name it. The shell opens a tree in a navigator. Help › Documents and Help › Projections open a tab with `Navigator(DocumentTypeList())` and `Navigator(ProjectionList())` through `_reach_tool!`, and a second use focuses the tab that is open. The tab of a navigator is called by its page. Help › About opens the page of the host's own program. [shell.md](../shell/shell.md) describes the menu.

The first content of the explorer of a window has a section "Help" with the two trees and the page about the program ([explorer.md](../explorer/explorer.md)). The trees open there as nodes, and a press on a node shows its page in the navigator beside the tree. The explorer slice has no code for them.

## Design decisions

- **Two trees, one for the document types and one for the projections.** The owner chose them on 2026-10-22, over one tree in which a module holds its document types and its projections. A document entry and a projection entry answer different questions: what a person types into an empty tab, and what draws a document. The labels "Documents" and "Projections" of the menu stay. The cost: the page of JSON under Documents shows none of the projections of JSON.
- **A tree stores its groups, and its acquire builds them.** The loaded modules are external mutable state, so a computation must not walk them (`PAR-PURE-THUNK`). A tree follows the model of a folder, which stores what it read, and whose acquire reads. The walk constructs a document of each candidate type to test it, so it runs on the task of the editor, and no background cell does it.
- **The constructor of a tree walks nothing.** `insertable(T)` calls `T()` while it walks the candidates that `get_insertion_candidates` enumerates, and `DocumentTypeList` is itself a candidate. A constructor that walked the candidates would call the enumeration that calls it.
- **The groups are packages and modules, by the names that the loaded program holds.** No table in the code says which package is a domain, a backend or an adapter, so the tree has no level of kinds.
- **The page builds its table eagerly, and the name and the middle column fit their content.** The owner chose it on 2026-10-22: "it's a finite and constant list". The option not chosen is a `Roster` of the children. A roster builds only the rows in view of a tab, so it measures no cell and gives each column an equal share of the width. It also needs the table in a field of each document, and it opens a row by its path through the table. The cost of the choice: a person can not filter or sort the table of a page.
- **The description is the raw text of the docstring, read through `Base.Docs.meta`.** It keeps the inline Markdown marks as they are written, and needs no dependency on the `Markdown` standard library.
- **`_get_typed_names` takes its type behind `@nospecialize`, so Julia compiles one method for it and not one for each type.** A closure that holds the type compiles once for each document type, and that costs about 10 seconds on the first build.
- **`AboutPage` is a document of the host program, and `about` is a function of the editor.** The default page names ProjecturEd. A host that runs its own program gives its own name, summary and home page.

The plan with the alternatives is [plan/done/the-help-shows-its-types-in-a-tree-of-packages-and-slices.md](../../../../plan/done/the-help-shows-its-types-in-a-tree-of-packages-and-slices.md).

## Usage

```julia
list = update_help_groups!(DocumentTypeList())     # the groups, with no editor
platform = only(group for group in list.children if group.name == "Platform")
open_pane!(Navigator(list))                         # a tab with the tree in a navigator

make_window_help_menu(; about = editor -> AboutPage(name = "My editor",
                                                     summary = "What it does.",
                                                     homepage = "https://example.org"))
```

- Tests: `test_help()` in `ProjecturedPlatformTest`, in [test/platform/help/](../../../../test/platform/help/), runs `test_help_tree()`, `test_help_pages()` and `test_about_page_to_syntax()`. The kernel tests the docstring functions in `test_docstring_summary()`, and `test_help_themes()` tests the theme. `test_window_shell()` tests the Help menu, and `test_explorer()` a tree in the explorer.

## Limits

- **The first build of a session can hold the window for 3 to 5 seconds.** The first `get_insertion_candidates(Document)` of a session walks every loaded module, on the task of the editor. An empty tab and the add menu of the explorer pay the same cost once.
- **A tree that no acquire built is empty.** A print with no editor, or a card that shows a tree that no tab holds, shows no group and no table. A script calls `update_help_groups!`.
- **The table of a page has no filter and no sort.** The filter of the explorer keeps the rows of the tree that it read.
- **Many projections have no docstring.** About 380 of the projections show "No description." on their page.
- **The page of a type shows the docstring as its raw Markdown,** one line of the page for each line of the text, with the marks as they are written.
- **No link joins a document type and the projections that draw it.**
- **The table of the fields shows no default value.** The keyword constructor of a type holds the defaults, and the code records none that the help can read.
