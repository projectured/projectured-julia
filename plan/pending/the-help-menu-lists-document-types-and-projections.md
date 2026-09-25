# The Help menu lists the document types and the projections

> **Status (2026-09-25): in progress** on the branch `help-menu`, worktree
> `projectured-julia-help-menu`. A press on a menu name does
> not open the menu yet. That fault has its own plan,
> [a-press-on-a-menu-name-opens-its-menu.md](a-press-on-a-menu-name-opens-its-menu.md),
> which is deferred. Until it is done, a press on "Help" opens nothing, and the
> tests call the actions of the items.

The menu bar of the window gets a third menu, **Help**, after File and View. It
has three items:

- **Documents** opens a tab with every document type that a `DocumentInsertion`
  can make, in alphabetical order, each with a short description.
- **Projections** opens a tab with every projection, the views that a person can
  use and combine, in alphabetical order, each with a short description.
- **About** opens a tab that says what the program is, and its version.

A description is the first paragraph of the docstring of the type. The first
version is a plain list. A later plan can group, filter or search it.

## Decisions (owner, 2026-09-25)

- The menu click waits for the owner. It is not part of this plan.
- The Help documents go in a new slice, `ProjecturedHelp`.
- The lists are computed from the program that is loaded. The documents hold
  no entries.
- Help is the last menu, after the menus that a host adds with `extra`.
- Each menu of the bar has its own make function, and one function combines
  them. The owner gave `make_file_menu`, `make_view_menu`, `make_help_menu` and
  `make_main_menu` as examples, and asked for a better idea. The names below
  are the recommendation of the implementer.

## Facts found before the plan (2026-09-25)

- **The shared bar has two hosts.** `make_window_menu_bar()` is called by
  `_make_application_shell` in
  [Application.jl](../../example/projectured/Application.jl) and by
  `_make_ide_shell` in omnet-julia `source/ide/IdeWindow.jl`.
- **The document types come from reflection.**
  `get_insertion_candidates(Document)` in
  [Domain.jl](../../source/domain/Domain.jl) lists every insertable concrete
  type, memoized per world age. `get_insertion_root(DocumentInsertion)` is
  `Document`, so this is the list that an empty tab offers. With the whole
  umbrella loaded it has 167 types, and 150 of them have a docstring.
- **The projections have no list.** The private walker `_collect_concrete!` of
  `Domain.jl` finds 443 concrete subtypes of `Projection`, and 75 of them have a
  docstring.
- **A tool tab has one small pattern.** `MessageLog` is a document,
  `MessageLogToSyntax` is a read-only projection with no reader, and
  `register_natural_syntax!` adds its row, so the renderer of a tab draws it.
  `_reach_tool!(editor, type, make)` in
  [WindowChrome.jl](../../source/shell/WindowChrome.jl) focuses the tab that
  holds a `type`, or opens `make(editor)` in a new tab.
- **The name "catalog" is taken.** `test_catalog()` and
  [catalog-all-documents.md](catalog-all-documents.md) use it for the test
  catalog of example documents.
- **The toolbar tests fail on `main`.** Commit 94d4fc6d added the "Frame plot"
  button, and `test_window_shell()` (5 assertions) and `test_application()`
  (1 assertion) still expect the old list. This plan does not depend on them.

## Design

- **One make function for each menu.** Every function of the shell that makes
  a part of the chrome starts with `make_window_`: `make_window_toolbar`,
  `make_window_status_bar`, `make_window_command`. The menus follow it:
  - `make_window_file_menu()`, `make_window_view_menu()` and
    `make_window_help_menu(; about)` each return the `WidgetMenuItem` that the
    bar shows, with its dropdown as the `submenu`.
  - `make_window_menu_bar(; extra = [], about = ...)` combines them: File, View,
    the menus of `extra`, then Help. The name stays, because the widget that it
    makes fills the `menu_bar` field of `WidgetShell`, and no code says "main
    menu". Both hosts keep their call.
  - A host that wants another bar builds a `WidgetMenu` from the parts.
- **The slice `ProjecturedHelp`** (`source/help/`), with the test package
  `ProjecturedHelpTest`. `ProjecturedShell` depends on it. The expected
  dependencies are the ones of `ProjecturedGestureLog` without `Graphics`, and
  `test_package_graph()` checks them.
- **Two documents with no field: `DocumentTypeList` and `ProjectionList`.** The
  projection computes the lines from the program that is loaded. So the list
  shows a type that Revise defines later. A saved window has no data to save
  for the tab, and a load shows the list again. `insertable(T)` calls `T()`
  while it enumerates the candidates, and a constructor that does nothing can
  not call the enumeration again.
- **One projection, `HelpListToSyntax`**, for both documents: read-only, with no
  reader and no reference map, as `MessageLogToSyntax`. Each entry has two
  lines. The first line has the name of the type in bold and its module in a
  muted color. The second line has the description. For a document type, the
  first line also shows the name that a person types in an empty tab, from
  `get_insertion_names`. A type with no docstring shows "no description" in a
  muted color. The sort is by name, and it ignores the case.
- **A public walker, `compute_concrete_subtypes(root)`**, in `DomainModule`. It
  is the private `_collect_concrete!` walk, memoized per world age as
  `get_insertion_candidates` is. `get_insertion_candidates` calls it. The walker
  of `Domain.jl` exists so that the code does not need `InteractiveUtils`.
- **The description comes from the raw text of the docstring**, read from
  `Base.Docs.meta` of the module of the type. The function skips the signature
  block and returns the first paragraph as one line. The first version keeps
  the inline Markdown marks as they are written. The raw text needs no
  dependency on the `Markdown` standard library.
- **About is a document of the host: `AboutPage`** with the fields `name`,
  `summary`, `version` and `homepage`, and the projection `AboutPageToSyntax`.
  It also shows the Julia version. `make_window_help_menu` and
  `make_window_menu_bar` take a keyword `about`, a function of the editor that
  makes the page, as `make_window_toolbar` takes `assistant`. The default page
  names ProjecturEd. The omnet-julia IDE gives its own page.
- **The labels are "Documents", "Projections" and "About"**, as the owner named
  them. Each item calls `_reach_tool!`, so a second use focuses the tab that is
  already open.

## Steps

- [x] 1. **One make function for each menu.** `make_window_file_menu` and
  `make_window_view_menu`, and `make_window_menu_bar` combines them. The bar
  looks and acts as before. Test: `test_window_shell()` has the same counts as
  `main`, and a new case checks that the bar holds the two menus in order.
- [x] 2. **`compute_concrete_subtypes(root)`** in `DomainModule`, with a test,
  and `get_insertion_candidates` calls it. The narrowest test of `Domain.jl`
  and the naming guard pass.
- [x] 3. **The package `ProjecturedHelp`** and `ProjecturedHelpTest` with
  `test_help()` and `test_help_layering()`. Add the package to the re-export
  loop of `Projectured` and to `environment/all/Project.toml`. Run the naming
  guard first, then `test_package_graph()`.
- [x] 4. **The description of a type**, with tests: a type with a docstring, a
  type with none, a docstring that starts with a signature block, and a
  docstring that has only a signature.
- [x] 5. **`DocumentTypeList`, `ProjectionList` and `HelpListToSyntax`**, with
  the two rows of `register_natural_syntax!`, `get_document_title` and
  `get_insertion_aliases`. The tests read the drawn text: the order is
  alphabetical, every insertion candidate is there, and the description of
  `MessageLog` and of `ChainingProjection` is the first paragraph of its
  docstring. Measure the first print of `ProjectionList`, because it reads
  about 600 docstrings.
- [x] 6. **`AboutPage` and `AboutPageToSyntax`**, with a test of the drawn text.

  Steps 3 to 6 are one commit: `HelpModule.jl` includes every fragment, so the
  package does not compile with a part of them. `test_help()`: 41 pass.
  `test_package_graph()`: 668 pass. The package needs `ReferenceModule`,
  because `@document` expands to code that names `Reference`, and it does not
  need `ProjecturedCollection`, because the printers build plain vectors.

  The measurement, with the packages of the application loaded: 170 document
  types and 445 projections. The first `get_insertion_candidates(Document)` of a
  session takes 3 to 5 s, and an empty tab pays the same cost. After it, the
  first `compute_help_entries` of the document types took 10.4 s, and all but
  0.2 s of it was compilation: a closure that held the type compiled once for
  each of the 170 types. `_get_typed_names` does not specialize on the type
  now, and the entries are sorted through `sortperm` of plain strings. The
  first computation now takes 0.22 s, the next 0.01 s, and the projection list
  0.06 s.
- [x] 7. **`make_window_help_menu(; about)`**, the last menu of
  `make_window_menu_bar`. `ProjecturedShell` depends on `ProjecturedHelp`.
  Tests in `WindowShellTest.jl`: the bar has File, View and Help in that order,
  with the menus of `extra` before Help, and each Help item opens its tab once.
  A test in `ApplicationTest.jl`: the action of "Documents" opens a tab that
  draws the name `JsonString`. The same test with a real press on "Help" waits
  for [a-press-on-a-menu-name-opens-its-menu.md](a-press-on-a-menu-name-opens-its-menu.md).

  Done. The application test looks for the heading and for `AboutPage`, the
  first entry, and not for `JsonString`: the tab shows the start of the list
  without a scroll. `test_window_shell()`: 98 pass and the 5 known failures of
  "Frame plot". `test_application()`: the new case passes, and the 1 known
  failure of "Frame plot" stays. An offscreen image of the window shows "File",
  "View" and "Help" on the bar and the three tabs. A description longer than
  the tab runs past its right edge, because the tab does not wrap a line.
- [ ] 8. **omnet-julia.** Each environment that has a `[sources]` line for
  `ProjecturedShell` gets one for `ProjecturedHelp`. `_make_ide_shell` gives an
  `AboutPage` for the IDE. Run `Pkg.precompile()` and the IDE tests.
- [ ] 9. **The documents.** A design document
  `documentation/package/help/help.md`, a row in the index of
  [documentation/README.md](../../documentation/README.md), a row in the table
  of [package-rules.md](../../documentation/rule/package-rules.md), the test
  functions in [testing-guide.md](../../documentation/guide/testing-guide.md),
  and the docstrings of the menu functions.
- [ ] 10. **Verification** against a baseline of `main`, and the move of this
  plan to `plan/done/`.

## Out of scope

- The press on a menu name: see
  [a-press-on-a-menu-name-opens-its-menu.md](a-press-on-a-menu-name-opens-its-menu.md).
- A press on an entry that opens a new tab with that type.
- Groups of projections (primitive, higher-order, by slice), a filter, and a
  search.
- Docstrings for the 368 projections that have none.
- A Help item for the gesture help (F1). A menu command can not reach the help
  wrapper now, and that needs its own decision.
- The toolbar tests that do not list "Frame plot".
