# The x of a tab is a button, and its menu closes others and copies on choice

**Status (2026-11-11): done.** The owner asked for this plan on 2026-11-11 and approved it on 2026-11-11.
The decisions D1 to D9 are proposals of the assistant, approved with the plan.
No question is open.

**Goal:** three changes to a tab of a group in the window:

- The menu of a tab has two more items: Close others and Close to the right.
- Duplicate in the menu makes the copy of the content only when a person chooses
  the item, not when the menu opens.
- The `x` of a tab is a toolbar button. It has the look of every toolbar button:
  flat at rest, the surface and the outline of a button while the pointer is on
  the `x`, and a darker surface while the left button is held down on it.

**Repository:** projectured-julia. No file that the plan changes is sealed:
[SEALING.md](../../SEALING.md) seals only files under `source/kernel/`, and the
plan changes none of them. Check each file against SEALING.md again before its
first edit.

**Branch:** `tab-button`, in the worktree `../projectured-julia-tab-button`.

## 1. The request

On 2026-11-11 the owner read the list "Not in this plan" of the plan of the tab
menu (`plan/done/a-tab-has-a-menu-and-shows-its-x-under-the-pointer.md`) and
answered:

- "The two closes are good ideas": Close others, and Close to the right.
- "the x highlight could be perhaps implemented switching to a toolbar item? It
  looks similar".
- "Yeah, duplicate should be delayed": the copy is made when a person chooses
  Duplicate.
- "Yes" to one plan for the three.

Then the owner read the first draft and asked: "Can't we control the padding on
the toolbar item?" and "The toolbar item background colour should match the
header", with the switch to a toolbar item only if both can be done. Both can be
done (D9). The owner then accepted, with "Yes", that the `x` of a tab that is not
selected is in the normal text color, a little darker than the lighter gray of
its name.

A key that opens the menu of the focused tab with no pointer stays out of this
plan.

## 2. What exists

**The strip.** `WidgetTabbedPane` draws its strip itself, in
[WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl). Each tab
is a canvas of its own, the header of the tab, and the header is the view of
`selector_element_pairs[i].selector`. The `x` is a plain icon that
`_push_tab_close_button!` draws, at the box that `_get_tab_button_box` gives.
`_get_tab_part` finds a point on the `x` by its position, and the reader answers
a left click there with `CloseTabOperation(w, i)`. The open tab always draws its
`x`. Another tab draws it in a canvas whose elements are a cell that reads
`_is_tab_header_under_pointer`, so a move redraws only that canvas. A middle
click on a tab of a `closable` pane is also `CloseTabOperation`. The badges of a
tab are documents too, but the strip draws them with the helpers of the badge
projection and reads no event on them.

**The toolbar button.** `WidgetToolbarItem` is a document. Its printer draws the
icon of its action and a hover layer: `_push_hover_layer!` shows the surface
while `get_mouse_target(item)` is not `nothing`, and a darker surface while
`item.pressed` is `true`. Its reader answers a left click with
`InvokeActionOperation(action)`, and a left down and up with a write of
`pressed`. That write is `ReplaceReferencedValueOperation(item, "pressed", …)`,
which names the item itself, so it reaches the item from any place. The theme
gives a toolbar button `toolbar_item_padding = Inset(4, 4, 4, 4)`.

**The pane.** `PaneTreeToWidget` in
[PaneToWidget.jl](../../source/platform/pane/PaneToWidget.jl) maps the strip of a
group both ways: `selector_element_pairs[i].selector` is `tabs[i].title` of the
`PaneGroup`, and the page is `tabs[i].content`. The mouse target of the tree is
the one true mouse target: a move writes it, and the forward map writes the mouse
target of the strip from it. The answer of the pane to `CloseTabOperation` is
`make_pane_close_tab_operation(tree, group, index)` in
[PaneSurgery.jl](../../source/platform/pane/PaneSurgery.jl). That builder moves
the focus only when the closed tab has it, and releases the closed tab with
`ReleaseDocumentOperation`. `make_delete_elements_operation(path, index; count)`
deletes a run of elements in one write.

**The menu.** [PaneTabMenu.jl](../../source/platform/pane/PaneTabMenu.jl) makes
the menu of a tab when the right click comes. `_find_pointed_tab_header` reads
the tree's mouse target, and needs it to go into `PaneTab.title`. Each item holds
an operation that the menu made at that time. So Duplicate calls
`make_pane_duplicate_tab_operation`, which copies the content with
`make_document_duplicate`, before the menu shows. The menu window sends the
operation of the chosen item through the readers with `read_rooted_operation`.
An operation that reports no reference goes through the readers as it is.

**Undo.** The undo document evaluates an operation with
`evaluate_invertible_operation!`, which takes the inverse before the change. The
function is open: a package above the kernel can add a method for its own
operation that holds or makes other operations.

**Other places.** Only the pane makes a `closable` strip. The key Ctrl+Shift+D
duplicates the focused tab and copies at the key, which is the moment of the
choice, so the key does not change.

## 3. The behaviour

**The menu of a tab** has these items, in this order:

| Item | Keys | Greyed when |
| --- | --- | --- |
| Duplicate | Ctrl+Shift+D | the content has no duplicate |
| Rename | F2 | never |
| — | | |
| Split right | Ctrl+\ | never |
| Split down | Ctrl+Shift+\ | never |
| Maximize group, or Restore layout | Ctrl+M | the window has one group |
| — | | |
| Add to explorer | | never |
| — | | |
| Close | Ctrl+W | never |
| Close others | | the group has one tab |
| Close to the right | | the tab is the last tab of its group |

- Close others closes each other tab of the group of the tab. Close to the right
  closes each tab after it. One undo opens all of them again.
- If a tab that closes has the focus, the focus goes to the tab of the menu. If
  the group shows a tab that closes, it then shows the tab of the menu.
  Otherwise the focus and the shown tab of each group stay.
- Duplicate makes the copy when a person chooses it. A right click and then a
  choice of another item, or no choice, makes no copy. If the tab closed while
  the menu was open, Duplicate does nothing.

**The `x`** is a toolbar button at the right end of the header of each tab:

- The open tab always shows it. Another tab shows it only while the pointer is on
  the header of that tab or on its `x`, as now.
- While the pointer is on the `x` itself, the `x` shows the surface and the
  outline of a toolbar button. While the left button is held down on it, the
  surface is darker.
- A left click on the `x` closes the tab. A middle click on the `x` closes the
  tab, as a middle click anywhere on the tab does. A right click on the `x` opens
  the menu of the tab.
- The `x` says "Close" as its tooltip.
- The click area of the `x` is the box of the button. A press in the tab above
  or below the button opens the tab, and grabs it in a pane that drags tabs.
- Each tab keeps its width: the button has no padding, and the surface under
  the pointer fills the square of the icon.
- At rest, the button draws no background, so the header shows through. Under
  the pointer it draws the translucent hover layer of the theme and the outline
  of a toolbar button over the header.
- The `x` is in the normal text color. On a tab that is not selected, this is a
  little darker than the lighter gray of its name.

## 4. Decisions

- **D1. The two new items act on the tab of the menu, and they have no keys.**
  They close many tabs at once, so the menu, where a person sees the tab they act
  on, is a safe place for them. A key can be added later with one rule in the
  gesture table of the tree.
- **D2. Each new close is one builder in PaneSurgery.jl.**
  `make_pane_close_other_tabs_operation(tree, group, index)` and
  `make_pane_close_tabs_to_the_right_operation(tree, group, index)`. Each deletes
  its tabs with `make_delete_elements_operation(…; count)`, the run after the tab
  first and then the run before it, so the indices of the second write stay
  correct. Then it releases each closed tab, as Close does. Each answers
  `nothing` when there is no tab to close, and the menu greys the item. The group
  always keeps the tab of the menu, so no group goes and no split changes.
- **D3. The focus rule of D2 is the rule of Close.** The focus moves only when a
  tab that closes has it, and then to the tab of the menu, because that tab
  stays.
- **D4. Duplicate is an operation of the pane slice that makes its copy when it
  runs.** `DuplicatePaneTabOperation(tree, group, tab)` names the tab by the tab
  itself, not by its index, because a drag can move the tab while the menu is
  open. It has a method of `evaluate_invertible_operation!`: it finds the index
  of the tab at that time, calls `make_pane_duplicate_tab_operation`, runs that
  operation with `evaluate_invertible_operation!` and gives back its inverse. It
  also has a method of `evaluate_operation` for a caller with no undo. The menu
  greys the item with `has_document_duplicate`, which makes no copy. This is not
  a new mechanism: the explorer adds `AddExplorerEntryOperation` with its own
  evaluation in the same way, and `evaluate_invertible_operation!` is open for
  this use. An `Action` with a callback can not do this work, because the undo
  can not take a callback back.
- **D5. The `x` of a tab is a document of its page.** `WidgetTabPage` gets a
  field `close`, a `WidgetToolbarItem` with `Action("Close"; icon = :close)` and
  `padding = Inset(0, 0, 0, 0)`, which the constructor of the page makes. The strip draws it only when the pane
  is `closable`. The hover and the pressed state of a toolbar button read its own
  mouse target and its own `pressed`, so the button must be a document in the
  input of the strip. The page carries the button, so the button stays with its
  tab when a drag moves the tab, and `closable` can change at any time.
- **D6. The strip prints the button through the recursion, and reads its
  answer.** The strip prints `page.close` as a child, as it prints the view of a
  name with the caret, and places its output at the right end of the header. An
  event on the button goes to the button first. The strip answers the
  `InvokeActionOperation` of the button of page `i` with `CloseTabOperation(w, i)`,
  so the pane answers a click on the `x` as it does now. An event that the button
  does not answer, such as a middle click, goes to the rules of the strip. A move
  on the button sets the mouse target of the strip to
  `selector_element_pairs[i].close`. `_get_tab_button_box`, `_get_tab_part` and
  `_push_tab_close_button!` go, and the width of the button in the geometry of the
  strip comes from the box of the button.
- **D7. In the tree, the `x` is a part that the pane projection introduced.** The
  tree has no place for a button, so the backward map of the pane gives the
  button of tab `i` as `tabs[i]` and a `ProjectionReferenceStep` whose output path
  is `.close`, and the forward map gives it back. This is the step that the kernel
  has for a part with no place in the input, so the plan adds no new kind of
  step. The routing of the mouse target of the group keeps such a path whole, as
  it keeps a path into a title.
- **D8. The `x` belongs to the header of its tab.** `_find_pointed_tab_header`
  takes a path into the button of a tab as the header of that tab, so a right
  click on the `x` opens the menu of the tab. `_is_tab_header_under_pointer` is
  true also while the pointer is on the button, so the `x` of a tab that is not
  open stays shown while the pointer moves onto it.
- **D9. The button has the look of a toolbar button, with no padding.** The
  padding of a toolbar button is a field of the document, so the button of a tab
  sets it to 0, and the tab keeps its width. The colors of a toolbar button
  already match the header: every part of its box is transparent at rest, and
  the hover layer is translucent, 6% of a neutral color in the light theme and
  12% in the dark theme. The icon takes the normal text color of a toolbar
  button. To give it the muted color of the name of a tab that is not selected,
  the strip would need a way to pass a theme color to a child, and none exists.
  The owner accepted the darker `x`. The look check of step 4 shows the result
  in the window.

## 5. Steps

1. [x] **Close others and Close to the right.** Add the two builders of D2 to
   PaneSurgery.jl and the two items to the menu of PaneTabMenu.jl. Add tests to
   `PaneReaderTest` through a right click on a tab: the two items, their greyed
   states, the tabs that stay, the focus of D3 and one undo. Run
   `test_pane_reader()` and `test_pane_surgery()`.
2. [x] **Duplicate on choice.** Add `DuplicatePaneTabOperation` of D4 to the pane
   slice, and make the Duplicate item hold it. Add tests: a content whose
   duplicate counts its calls gets no copy at the right click and one copy at the
   choice, and an undo closes the copy. Keep the greyed Duplicate of a content
   with no duplicate. Run `test_pane_reader()` and `test_pane_construct()`.
3. [x] **The `x` is a toolbar button.** Do D5 to D8. Change the tests of
   `WidgetTabStripTest`: the click on the button closes the tab, a press above
   the button does not, the button under the pointer draws the surface of a
   button and the darker surface while held, and the open tab and the tab under
   the pointer show their buttons. In `PaneReaderTest`, in an editor: the `x`
   lights under the pointer, a left click and a middle click on it close the
   tab, and a right click on it opens the menu of the tab. Run
   `test_widget_tab_strip()`, `test_pane_reader()`, `test_part_pointer_shape()`
   and `test_pane_drag()`.
4. [x] **Guides, list, and a look at the window.** Change widget.md and pane.md
   to §3. Record the precompile list of `ProjecturedPlatform` again. Take
   pictures of the real window: the pointer on the `x` of a tab that is not
   open, and the open menu of a tab. Run `test_platform()` once, in two halves.

## 6. Notes from the implementation

- The shared memory of the machine was full for a long time, so steps 1, 2 and
  3 were written before their tests ran, and steps 1 and 2 were committed then.
  The tests of the three steps ran in one job after that. The first run gave 677
  passes, 1 failure and 3 errors, all in the tests. The undo check of step 1 ran
  the inverse with its selection moves before the tabs came back, so it now runs
  the inverse with no selection moves and puts the selection back after, as the
  undo does. Three checks of step 3 read a full column under the `x`, or read
  the buttons from the top IO map; they now read the box of the button and find
  the strip IO map first. These fixes are in the commit of step 3. The second
  run gave 708 of 708 in `test_pane_reader`, `test_widget_tab_strip`,
  `test_part_pointer_shape`, `test_pane_surgery`, `test_pane_construct` and
  `test_pane_drag`.
- **Step 1.** A group with no focus that shows a tab that closes keeps a dormant
  selection with the old index. `_make_kept_view_operation` finds no shown tab in
  the list after the close, so `_close_tabs_around` writes the dormant selection
  of the group to the tab of the menu itself.
- **Step 2.** The pane surgery declares no operation type, so
  `DuplicatePaneTabOperation` is in PaneTabMenu.jl. An operation that names no
  reference is dropped on its way up, so the operation carries `place`, the path
  of its tree, through `operation_reference` and `retarget_operation`, as
  `AddExplorerEntryOperation` carries its selection. When it runs, it puts the
  steps of `place` before the paths of the duplicate with `reroot_operation`, as
  the playback does. The undo document runs `evaluate_invertible_operation!`, so
  the operation has a method of it.
- **Step 2, a change of behaviour that follows D4.** `has_document_duplicate`
  answers from the kind of the content, and a copy can still fail on what the
  tree holds, such as a text field with a validator. The menu can not know that
  without the copy, so the item is enabled for such a content, and its choice
  logs the refusal and adds no tab, as Ctrl+Shift+D does. Before, the copy at the
  right click greyed the item.
- **Step 3.** The strip keeps the IO maps of the buttons in a new IO map type,
  `WidgetTabbedPaneToGraphicsCanvasIoMap`, with the fields of a
  `WidgetChildrenIoMap` and `close_iomaps`, as the card and the fact group have
  types of their own. It is in `_ChildEntriesIoMap`, its `get_child_iomaps` adds
  the buttons, and its `read_child_by_route` places each button where the strip
  draws it. The entries of `child_iomaps` stay one for each tab, because the
  reader finds a page by its index.
- **Step 3.** The geometry of the strip reads the width and the height of the
  canvas of each button, not `get_graphics_size`: that walks the elements, and
  the hover layer is one of them, so each move would lay out the strip again.
  The button gets a bounded size with no minimum, as a toolbar gives its items.
  `_get_tab_button_box`, `_get_tab_part` and `_push_tab_close_button!` stay with
  new bodies: the box comes from the size of the button, and the push places the
  output of the button.
- **Step 3.** In the pane the strip is the output of the group projection, so
  the walk of the mouse target does not reach the documents in it.
  `_make_tab_page` wires the paths of each button from the paths of the strip
  with `set_output_path_computations!`, as `FindBarViewToWidget` wires its
  children. A strip that is an input document gets the mouse target of its
  buttons from the walk.
- **Step 4.** Before the recording, 1806 of the 12464 recorded calls of
  `ProjecturedPlatform` did not resolve on the branch, and 1675 on main. The
  list of the kernel resolved in full, so a recording of the one package takes
  in no stale calls of a package below it. The first recording ran on main
  cfb077e2d, where the window workload stops at
  `WorkloadClick(DrawnText(r"lengths_1"))`, so its list missed the calls after
  that step. Main 3fd04ea4b fixes the workload, so the branch was rebased on it
  and the list recorded again. The new list has 10642 lines, the old one 10260:
  1889 calls are new, 161 of them name a changed type, and most of the others
  replace the stale calls of main. A load after it gives no warning of
  unresolved calls.
- **Step 4, the window.** Pictures of the application window, written with the
  SDL image writer from an editor that runs its frames with real events, show:
  the open tab alone shows its `x` at rest; the pointer on a tab that is not open
  shows its `x`; the pointer on that `x` shows the light surface tight around
  it; a held button shows the darker surface; a press that leaves the button
  before the release closes nothing; and the menu of a tab shows Close, Close
  others and Close to the right. The context menu opens only through
  `wrap_context_menu_window` in the tracking screen, as in the application.
  Duplicate is greyed for a text file, as on main: a text file has no duplicate.
- **Step 4, the suite.** `test_platform()` ran in two halves. Half 1: 220087
  passed, 4 failed; the 4 are static layering checks of files that the branch
  does not change. Half 2: 8047 passed, 2 failed, 1 error. The Save As check of
  the file dialog fails on main too. The error of `test_tooltip_note` comes from
  main 212901ac9, which reads `fact.second` of a `DocumentCondition`. The
  failure of `test_widget_round_trip` came from this plan: a page holds a close
  button, and a pane that is not closable draws none. The test now counts that
  button as a part that is not shown, as it counts the content of a tab that is
  not open, and passes 2 of 2.

## Not in this plan

A key that opens the menu of the focused tab with no pointer; keys for Close
others and Close to the right; Close all and Close saved.
