# The navigator selection goes into the row, and the navigator scrolls

**Status (2026-09-25): DONE** on the branch `navigator-selection`, in the
worktree `projectured-julia-navigator-selection`. Nothing is on `main`. One open
point: what the duplicate of a workspace selects (section 5).

## 1. The request and the rulings

> I think the blue mark should be displayed around structured stuff, e.g.
> widgets if the structured selection ends at the given widget, it should not be
> displayed if the selection goes deeper
>
> when the UI starts, the Files tab should not be selected, and if the user
> clicks on an item, it should be selected but the blue rectangle should not be
> displayed because it goes deeper, it's only when the user Alt+Clicks on the
> File explorer when the blue box should be displayed, because it gets selected
>
> also, there's no scrolling in the files box as far as I can tell

The user's rulings on the proposal, 2026-09-25:

| Question | Ruling |
| --- | --- |
| The navigator scrolls: a `WidgetScrollPane` around the tree | Yes. |
| How the row goes into the root path | Option A: a projection-introduced step (`ProjectionReferenceStep`) on the `WorkspaceFolder`. Not option B, a stored directory tree. |
| Where the selection starts when no file is open | On the root row of the navigator. |

## 2. What exists

| Fact | Where |
| --- | --- |
| The ring around a tab page shows while the document of the page has the selection `∅`, and only then. This rule is correct and does not change. | `source/widget/WidgetToGraphics.jl`, the ring of `WidgetTabbedPane` and `_is_whole_selected_page` |
| With no file open, the start selection is the content of the Files tab as a whole: `…PaneTab.content::Workspace`. | `example/projectured/Application.jl`, `_make_application_pane_tree` |
| A click on a row writes the row path into the `selection` of the computed `FileSystemDirectory`, and selects the `Workspace` as a whole. So the root path never goes past the `Workspace`, and the ring stays. This is a second, private selection. | `source/filesystem/WorkspaceToFileSystem.jl`, `read_intent(::WorkspaceToFileSystemDirectory, …)` |
| Measured on `main`: a click on a folder row answers `[directory.selection = .elements[2], select ::Workspace]`; `Down` answers the same with `.elements[2].elements[1]`; Alt+click answers `select ::Workspace`. `Ctrl+C` after a row click copies the whole `Workspace`. | probe, offscreen |
| The tree answers every left press with a row selection, an Alt+press too. | `_wtree_mouse_press` in `WidgetToGraphics.jl` |
| A container turns the answer to an Alt+press into a whole selection: it keeps a selection that names a document, and cuts a path at a projection-introduced step, which then names the node the projection printed it for. | `convert_to_whole_selection` and `_cut_introduced_place` in `source/focus/WholeSelection.jl` |
| A domain projection that must decide an Alt+press itself reads the gesture in its four-argument reader. | `read_intent(::ConversationConversationToWidgetComposite, recursion, change::Intent, iomap)` |
| `FileSystemToWidgetTree` prints a bare `WidgetTree`. The pane group puts nothing around the content of a tab, by design, so each content scrolls by itself. Measured: nothing answers a wheel event over the navigator, and the rows reach y=1194 in a window 1000 pixels high. | `source/filesystem/FileSystemToWidget.jl`, `source/pane/PaneToWidget.jl` |
| A scroll pane names its content with the step `content`. | `source/assistant/AssistantToWidget.jl` |
| `test_package_graph()` asserts that a package declares exactly the packages its source names. `ProjecturedFocus` depends only on `ProjecturedCollection`, and `ProjecturedWidget` and `ProjecturedPane` depend on it. | `documentation/rule/package-rules.md` |

## 3. Decisions

### D1. The navigator scrolls

`FileSystemToWidgetTree` prints `WidgetScrollPane(tree)`. The pane has no size
of its own, so it takes the extent that the tab page offers. The two reference
maps of the projection add and remove the `content` step. The printer wires the
selection of the tree from the file-system path directly, without the step.

Limit: a key move to a row below the edge does not scroll the row into view.
`WidgetScrollPane` has only `follow_end`. This is a separate change.

### D2. The row goes into the root path (option A)

A row of the navigator is a place that the projection introduces: the
`WorkspaceFolder` holds a name and a path, and the tree is computed from the
path. The root path carries the row as a `ProjectionReferenceStep` on the
folder:

    …PaneTab.content::Workspace.folders[1]::WorkspaceFolder.proj(<projection>, elements[2])

- `WorkspaceFolderToFileSystemDirectory` maps a file-system path back to that
  step, and the step forward to the path. The root of the directory is the
  folder itself, so the file-system path `∅` maps to the folder as a whole
  (`folders[1]`), and back.
- `WorkspaceToFileSystemDirectory` maps `folders[1].rest` forward through the
  folder, and a file-system path back to `folders[1]` and the folder's answer.
  The `Workspace` as a whole maps forward to nothing, so an Alt+click shows the
  ring and no row.
- The `selection` of the computed directory is a computed cell: the image of the
  folder's selection. No reader writes it, so the private selection is gone. A
  dormant selection maps to a dormant image, and the tree then shows no row.
- `read_intent(::WorkspaceToFileSystemDirectory, …)` maps a
  `ReplaceSelectionOperation` back through the reference map, and passes every
  other operation as it is.

A path that ends in a `ProjectionReferenceStep` names no document, so `Ctrl+C`
on a row other than the root row copies nothing. The root row copies the
`WorkspaceFolder`.

### D3. An Alt+click selects the navigator as a whole

With D2 alone, an Alt+click on a row answers the introduced step, and the
container cuts it to the `WorkspaceFolder`. No widget draws a ring for the
folder, because the folder draws as the whole view. So the four-argument reader
of `WorkspaceToFileSystemDirectory` answers an Alt+press
(`is_whole_selection_press`) with the `Workspace` as a whole, as the conversation
decides its own Alt+press. The ring then shows around the page.

`ProjecturedFileSystem` gets `ProjecturedFocus` as a declared dependency.

### D4. The selection starts on the root row

With no file open, `_make_application_pane_tree` puts the selection on
`tabs[1].content.folders[1]`: the root row. The first key reaches the tree, and
no ring shows.

## 4. Steps

- [x] **Step 1.** D1: the scroll pane around the tree, and its reference maps.
  Test: a wheel over the navigator scrolls it, and a click and Enter still open
  a file.

  Done. What the work showed:
  - A container widget prints its content through the `recursion` argument, so
    the renderer at the end of a chain must be `RecursiveProjection(WidgetToGraphics(…))`,
    as the header of `WidgetToGraphics.jl` says. The three navigator chains used a
    bare `WidgetToGraphics`, which was enough for a leaf `WidgetTree`: the natural
    row in `FileSystemToSyntax.jl`, the widget example, and the row in
    `Application.jl`. All three are wrapped now. Inside the application the bare
    renderer borrowed the recursion of the outer renderer.
  - In this code a wheel event with a positive `dy` scrolls up.
  - A scroll of any `WidgetScrollPane` was a plain `ReplaceReferencedValueOperation`,
    so the window history recorded it and `Ctrl+Z` took it back. The owner ruled
    (2026-09-25): "a scroll should not go into the undo history". Every write of a
    scroll in the widget layer is now `_write_view_state`, which a history skips:
    `scroll_position` and `follow_end` of the scroll pane, `tab_scroll` of the tab
    strip, and every write of `transform` in the transform pane, the keys that zoom
    it too, because the field is view state. The wheel zoom of the two charts
    writes the chart's `view`, a field of the chart document that keys and drags
    change as well, so it is not changed here.
  - Baseline on `main`: `test_application` fails one assertion at the toolbar
    (commit `94d4fc6d` added "Frame plot" and did not update the test), and the
    position navigation of `filesystem_widget` and `navigator` fails 3313 and 328
    times. The branch changes none of these counts.
- [x] **Step 2.** D2 and D3: the row in the root path, the computed directory
  selection, the Alt+press, and the dependency. Test: a click on a row puts the
  row in the root path and no ring shows; `Down` moves it; Enter opens the file;
  Alt+click selects the `Workspace` and the ring shows.

  Done. What the work showed:
  - `DatabaseInstanceToDbCatalog` does the same thing for a catalog row: its
    backward map wraps the path as `proj(p, …)` on the instance, and the output's
    `selection` is computed from the instance's. The folder needs no reference map
    of its own: the defaults of `Projection` wrap and unwrap the step, and keep
    `∅` as `∅`.
  - `set_cell_computation!` runs on the first read, so the output computation sets
    the directory's selection computation and still depends on the pathname
    alone. A selection that moves does not read the disk again.
  - Measured: the start path ends at `….content.folders[1]`; a click on `beta`
    ends at `….folders[1]` and the step `‹.elements[2]›`; `Down` gives
    `‹.elements[2].elements[1]›`; Alt+click ends at `….content`, and the folder
    then holds no selection, because the editor's writer (`replace_selection!`)
    clears the branch the selection leaves.
  - A written image now shows the selected row. Before, `write_image` printed a
    new directory and lost the private selection on it.
  - The status bar printed the step in its long form. It now asks for the compact
    form, as a short line should, and reads `::WorkspaceFolder‹.elements[2]›`.
  - `FileSystemModule` uses `FocusModule`, `IntentModule` and `SelectionModule`.
    `test_package_graph()` passes with `ProjecturedFocus` declared.
- [x] **Step 3.** D4: the start selection. Test: the start path ends at
  `folders[1]`, and no ring shows.

  Done. The root row is lit at the start, and the page draws no ring.

  Tests after Steps 2 and 3: `test_application` 311 of 312 (the toolbar failure
  of `main`), `test_filesystem` 36 of 36 with the new
  `test_workspace_to_filesystem`, `test_package_graph` 661 of 661, the file
  dialogs 11 of 11, `test_shell` 175 of 180 (the same five toolbar failures as
  `main`), the two examples at the counts of `main`, and the naming guard.
- [x] **Step 4.** The guides: `documentation/package/filesystem/filesystem.md`
  and the dependency table in `documentation/rule/package-rules.md`.

  Done. `filesystem.md` has a section on the selection of a row, the scroll
  pane, the recursive renderer, the new dependency, a design decision and two
  limits. `package-rules.md` lists only the packages of the substrate, so it has
  no row to change.

## 5. Open points after the rebase onto `main` (2026-09-25)

`main` gave the `Workspace` a duplicate (`2000d04d`). Its comment in
`source/filesystem/Workspace.jl` says that a duplicate opens with no row
selected, because the selected row belongs to the view. With this plan the row
is in the workspace's selection, and `make_document_duplicate` takes the
selection as it is now, as for every duplicate. Measured: after a click on a row
and `duplicate_pane!`, the focus is on the copy, the root path ends at the same
row in the copy, the original holds no selection, and no live selection is off
the root path. So the comment is now wrong. Two ways, for the owner to choose:

- keep the new behavior, which is the rule of every duplicate, and correct the
  comment; or
- give the `Workspace` a duplicate that drops the selection, and keep the
  comment.
