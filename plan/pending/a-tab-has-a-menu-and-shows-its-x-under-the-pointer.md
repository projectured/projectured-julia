# A tab has a menu and shows its x under the pointer

**Status (2026-11-10): in progress.** The owner gave the goal and answered Q1
(2026-11-10). The assistant proposed the decisions D4 to D7, and the owner
approved them with the plan on 2026-11-10. No question is open.

**Goal:** the tab strip shows less. A tab has one button, the `x`. The `x` shows
on the open tab of a group, and on another tab only while the pointer is on it.
A right-click on a tab opens a menu with the commands of the tab, Duplicate
among them. A middle click on a tab closes it.

**Repository:** projectured-julia. No file that the plan changes is sealed:
[SEALING.md](../../SEALING.md) seals only files under `source/kernel/`, and the
plan changes none of them. Check each file against SEALING.md again before its
first edit.

**Branch:** `tab-menu`, in the worktree `../projectured-julia-tab-menu`.

## 1. The request

> do tab panes in projectured-julia have a context menu?
>
> I think the visual clutter for + and x buttons should be reduces. Probaly we
> should move the clone button into the context menu of the tab pane available
> on the header. The other button should auto-hide and show on hover like in
> Visual Studio Code.

After the answer of the assistant:

> Agreed with recommendation, also support middle click

## 2. What exists

All lines are on `main` at `f78dab9dc`.

- **No menu on a tab header.** A right-click on a header goes out from the part
  under the pointer ([PaneToWidget.jl:692](../../source/platform/pane/PaneToWidget.jl#L692)),
  and the mouse target of the tree names the `PaneTab`. The only right-click
  rule of a `PaneTab` is the menu of the first filter and sort
  ([PaneArrangement.jl:9](../../source/platform/pane/PaneArrangement.jl#L9)). It
  answers only inside the content, so on the header it gives nothing.
- **Two buttons in one column.** The pane tree makes its strip with
  `closable`, `new_tab`, `draggable` and `duplicable`
  ([PaneToWidget.jl:391](../../source/platform/pane/PaneToWidget.jl#L391)). A
  tab whose content has a duplicate gets a `+` above its `x`, each in one half of
  the strip height ([WidgetToGraphics.jl:5448](../../source/platform/widget/WidgetToGraphics.jl#L5448)).
  The press of the `+` answers `DuplicateTabOperation`
  ([WidgetToGraphics.jl:5969](../../source/platform/widget/WidgetToGraphics.jl#L5969)),
  and the pane tree reads it ([PaneToWidget.jl:613](../../source/platform/pane/PaneToWidget.jl#L613)).
- **The width of the column is already the same on every tab.** The strip
  measures the column of a tab once, as one line times `icon_size`
  ([WidgetToGraphics.jl:5382](../../source/platform/widget/WidgetToGraphics.jl#L5382)).
- **The mouse target of the strip names the header.** A move over a header
  writes `selector_element_pairs[i].selector` as the mouse target of the pane
  ([WidgetToGraphics.jl:6079](../../source/platform/widget/WidgetToGraphics.jl#L6079)).
- **A light under the pointer is cheap.** `_push_hover_layer!` gives the layer
  cells of its own that read the mouse target, so a move redraws the layer and
  not the strip ([WidgetToGraphics.jl:346](../../source/platform/widget/WidgetToGraphics.jl#L346)).
- **A middle click reaches the strip.** The SDL backend gives `:middle`
  ([SdlBackend.jl:601](../../source/backend/sdl/SdlBackend.jl#L601)). The strip
  does not look at the button of a click, so a middle click on a tab now selects
  the tab.
- **The commands of a tab exist, for the focused tab.** `@gestures PaneTree`
  ([PaneGestures.jl:187](../../source/platform/pane/PaneGestures.jl#L187)) has
  Ctrl+T, Ctrl+W, Ctrl+Shift+D, Ctrl+\, Ctrl+Shift+\, Ctrl+M, F2 and "Add the tab
  to the explorer". Each one calls a function of the pane tree with a group and
  an index: `make_pane_close_tab_operation`, `make_pane_duplicate_tab_operation`,
  `make_pane_split_operation`, `make_pane_maximize_operation`,
  `make_pane_restore_operation`, `make_pane_title_caret_operation`, and
  `AddExplorerEntryOperation`.
- **A menu item shows its keys.** `WidgetMenuItem` has `keys`, drawn at its
  right edge ([WidgetDocument.jl:843](../../source/platform/widget/WidgetDocument.jl#L843)).
- **The users of the removed names.** Only projectured-julia uses `duplicable`
  and `DuplicateTabOperation`: the strip, the pane tree, `WidgetTabStripTest`,
  `PaneReaderTest`, and the guides widget.md, pane.md, filesystem.md and
  conversation.md. omnet-julia and inet-julia use neither. `Projectured.jl` is
  made by the release generator, so the plan does not change it.
- **Release.** `DuplicateTabOperation` is exported from `WidgetModule`. The
  release generator finds a removed export and gives `ProjecturedPlatform` the
  next minor version by itself (step B7 of
  [release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md)).
- **Precompile list.** 41 of the 10349 lines of
  `package/ProjecturedPlatform/precompile/workload.txt` name `WidgetTabPage`
  with seven type parameters. Without `duplicable` it has six, so these lines
  stop to resolve. That is less than the 10 % limit of
  [compile-ahead.md](../../documentation/design/compile-ahead.md), so the build
  does not stop, but the list must be recorded again.

## 3. The behaviour

```
pointer not on "notes":   [ json-example x ] [ notes    ] [+]
pointer on "notes":       [ json-example x ] [ notes  x ] [+]
right-click on "notes":   a menu for "notes"; the open tab stays "json-example"
middle click on "notes":  "notes" closes
```

The menu of a tab, top to bottom:

| Item | Keys shown | Does |
| --- | --- | --- |
| Duplicate | Ctrl+Shift+D | Copies the tab. Greyed when the content has no duplicate. |
| Rename | F2 | Puts the caret in the name of the tab. |
| — | | |
| Split right | Ctrl+\ | Splits the group of the tab. The new pane is on the right. |
| Split down | Ctrl+Shift+\ | Splits the group of the tab. The new pane is below. |
| Maximize group | Ctrl+M | Maximizes the group of the tab. "Restore layout" when a group is maximized. Greyed when the window has one group. |
| — | | |
| Add to explorer | | Adds the document of the tab to the explorer. |
| — | | |
| Close | Ctrl+W | Closes the tab. |

## 4. Decisions

- **D1. Duplicate leaves the tab and goes into the menu of the tab.** The owner,
  in the request. The widget loses the `+` of a tab: the field `duplicable` of
  `WidgetTabbedPane` and of `WidgetTabPage`, the four-element tuple form of a tab
  entry, the part `:duplicate`, and `DuplicateTabOperation`. The column of a tab
  holds one `x` at the full height of the label.
- **D2. The `x` shows on the open tab, and on another tab only under the
  pointer.** The owner, Q1 (2026-11-10), which chose the way of VS Code. The open
  tab of each group shows its `x`, also in a group that has no focus.
- **D3. A middle click on a tab closes it.** The owner (2026-11-10). On a
  `closable` strip the widget answers `CloseTabOperation`, the same answer as a
  press of the `x`, and the pane tree decides what it means. A middle click on
  the new-tab button, on an empty part of the strip, or on a strip that is not
  `closable` does nothing. A middle click in the page goes to the page, as now.
- **D4. The space of the `x` stays.** Proposed by the assistant, approved with the plan (2026-11-10). A hidden `x`
  keeps its place, so a tab has the same width with and without it, and no tab
  moves under the pointer. Rejected: a tab that grows when its `x` shows. The
  tabs to its right then move away from the pointer.
- **D5. The `x` hides by a cell, not by a new print of the strip.** Proposed by
  the assistant, approved with the plan (2026-11-10). The `x` of each tab sits in a small canvas whose visibility is
  a cell. The cell reads the mouse target and the selection of the pane, as the
  layer of `_push_hover_layer!` does, so a move of the pointer redraws only that
  canvas. Rejected: the strip reads the mouse target in its element list. Then
  each move over the strip builds the whole strip again.
- **D6. The menu belongs to the pane tree and acts on the tab under the
  pointer.** Proposed by the assistant, approved with the plan (2026-11-10). A right-click rule in the gesture table
  of `PaneTree` applies only when the mouse target of the tree names a tab and
  goes no deeper than its header. Its items call the functions of §2 with the
  group and the index of that tab, not of the focused tab. The right-click does
  not select the tab, as now. The keys in the menu are the keys of the same
  command for the focused tab, as in VS Code. Rejected: the rule on `PaneTab`. A
  tab does not know its group or the focus of the tree, and Close and Split need
  both. Rejected: a menu in `WidgetTabbedPane`. The widget does not know what a
  split or the explorer is.
- **D7. The items are the commands that exist.** Proposed by the assistant, part of the recommendation that the owner agreed
  to, and approved with the plan (2026-11-10). "Split right" does what
  Ctrl+\ does: the new pane gets a new empty tab. Rejected: a split that moves or
  copies the tab into the new pane. That is a new command, and the request did
  not ask for one.

- **D8. The header of a tab maps back to the title of the tab.** Proposed by the
  assistant during step 3 (2026-11-10). Before, a point on a header and a point of
  the page that the content does not claim both gave the tab, so the tree could
  not tell the header from the page, and the menu of D6 would open in the page
  too. Now the backward map of `PaneGroupToWidgetTabbedPane` gives any part of
  the header as `tabs[i].title`, and its forward map gives any part of the
  title as the header, as it already gave a caret in the name. The forward map is
  also what puts the mouse target on the strip in the editor, so without it the
  `x` of D2 stays hidden there (the first run of the editor test showed it). A
  selection of the whole tab still maps to its page. The menu applies when the
  mouse target of the tree goes into the title. Rejected: the menu asks the widget which part is under the
  pointer. The tree holds no widget, and a projection must not read another's
  state.

## 5. Steps

1. [x] **One `x` per tab.** Done 2026-11-10. Remove `duplicable`, `:duplicate`, the tuple form
   with four elements and `DuplicateTabOperation` from the widget, and the
   reader of `DuplicateTabOperation` and `duplicable = true` from the pane tree
   (D1). Draw the `x` at the full height of the label. Change
   `WidgetTabStripTest` and `PaneReaderTest`. Test: `test_widget_tab_strip()`
   and the pane reader test.
2. [x] **The `x` under the pointer, and the middle click.** Done 2026-11-10, in
   one commit with step 1, with the maps of the pane view of D8, which the `x` in
   the editor needs. Put the `x` in its
   canvas with the visibility cell (D2, D4, D5). Answer a middle click on a tab
   with `CloseTabOperation` (D3). Add tests to `WidgetTabStripTest`: the `x` of
   a tab that is not open draws nothing, and it draws after the mouse target
   names its header; the `x` of the open tab always draws; the width of each tab
   stays the same; a middle click on a tab closes it, and a middle click on the
   new-tab button gives nothing.
3. [ ] **The menu of a tab.** Add the rule of D6 with the items of §3 (D7). Add
   tests to `PaneGestureTest`: a right-click on the header of a tab that is not
   focused opens the menu, Duplicate is greyed for a content with no duplicate,
   and each item acts on that tab and not on the focused tab. A right-click in
   the content still opens the menu of the filter and sort.
4. [ ] **Guides, list, and a look at the window.** Change widget.md, pane.md,
   filesystem.md and conversation.md to the strip of §3. Record the precompile
   list of `ProjecturedPlatform` again. Take a screenshot of the real window
   with two groups, the pointer on a tab that is not open, and the open menu of
   a tab. Run `test_platform()` once.

## 6. Notes from the implementation

- Steps 1 and 2 change the same lines of the strip, the drawing of the close
  button, so they are one commit.
- The menu reads the keys of its items with `find_bound_keys` of the tooltip
  slice, which the explorer and the navigator use for the same work. So the
  pane slice uses the tooltip slice now, and `PLATFORM_SLICE_EDGES` of
  [PlatformSuite.jl](../../test/platform/PlatformSuite.jl) has the new edge
  `pane → tooltip`. The widget slice already uses the tooltip slice.
- The tests of the menu are in `PaneReaderTest`, not in `PaneGestureTest`:
  `PaneReaderTest` drives the whole chain from a pixel, and the menu needs a real
  move of the pointer and a real right click.
- The items make their operations when the menu opens, as the items of the menu
  of a row of the explorer do. So Duplicate makes its copy of the content at the
  right click, and the copy is lost when no one chooses the item. A copy that is
  made only at the choice needs a new kind of operation.

## Not in this plan

A key that opens the menu of the focused tab with no pointer; Close others and
Close to the right; a light under the pointer on the `x` itself; a Duplicate
item that copies only when it is chosen.
