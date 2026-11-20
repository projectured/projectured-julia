# A tab moves along its strip and between windows

> **Status (2026-11-20): in progress, step 1.** The owner asked for this plan on
> 2026-11-20 and answered the questions D1 to D8 the same day. P1 to P12 were proposed
> by the assistant and approved with the plan on 2026-11-20 ("yes, approved, start the
> implementation"). The work is on the branch `tab-windows` in the worktree
> `projectured-julia-tab-windows`.

## 1. The purpose

The owner, 2026-11-20: "in tab groups, I can't reorder tabs by dragging. also, it
would be nice to be able to move a tab into a separate window and back a tab from
another window into a group. what gestures should we use? what feedback? how
should we implement this?"

## 2. What exists

- **The drag of a tab.** A press on a tab and a move of 5 px start the drag
  (`_read_tab_press` in [PaneToWidget.jl](../../source/platform/pane/PaneToWidget.jl)).
  The tree keeps the drag in its view state field `PaneTree.drag`, as
  `(group, index, target, zone, origin, started)`. The drag tracker
  (`DragTrackingState`, around all windows) then sends `DragMove`, `DragEnd` and
  `DragCancel` to the tree by its path.
- **The drop zones.** `get_pane_drop_zone` in
  [PaneGeometry.jl](../../source/platform/pane/PaneGeometry.jl) answers the group under
  the pointer and one zone: `:strip` (a band of 32 px across the top), `:center`,
  or an edge band (`:left`, `:right`, `:above`, `:below`, 20 % of the group). The
  layout of the tree gives each group a rectangle in the unit square, so the tree
  knows no place of a single tab.
- **The feedback.** One `WidgetHighlight` over the panes (`_drop_indicator`) shows a
  gray rectangle: the whole group for the strip and the middle, half of the group
  for an edge band. The pointer is a closed hand over a group and a crossed circle
  elsewhere.
- **Why a reorder fails.** `_drop_operation` answers `nothing` when the target group
  is the source group (`source === target && return nothing`), and it puts a tab
  that goes into another group at the end. But `make_pane_move_tab_operation` in
  [PaneSurgery.jl](../../source/platform/pane/PaneSurgery.jl) already does a reorder
  inside one group, with a target index.
- **A drag outside the window.** SDL 2.32 keeps the moves and the release for the
  window of the press while the button is held, also outside its edge. Today a
  release outside does nothing.
- **Windows.** `ScreenDocument.windows` holds the windows. The backend writes the
  place and the size of each window into its `WindowDocument` (X11). Only the first
  window holds a tab tree. The screen draws the content of the first window with the
  full projection of the editor, and the content of a later window, such as a
  tooltip or a menu, with the rows of `opened_window_projections`
  ([WindowScene.jl](../../source/platform/screen/WindowScene.jl)).
- **The layers of the first window.** `build_editor` runs the wrappers once, at the
  start. Three wrappers of the layer `:container` put a document around the tabs, so
  in the application the content of the first window is
  `ClipboardSlice(WidgetShell(UndoBuffer(PaneTree(…))))`. The other wrappers of that
  layer (focus cycling, F1 help, the command palette, the gesture log) change only
  the projection. The editor keeps no argument of a wrapper after the start.
- **The keys of the menus.** A key of the menu bar or of the toolbar, such as Ctrl+O,
  fires only through the `WidgetShell` of the window that holds the focus
  (`read_gesture` of `WidgetShellToGraphicsCanvas` in
  [WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl)).
- **The global drag.** `find_drop_zone(document, dragged, point)` is a kernel generic,
  and `StartDragOperation(path, dragged)` carries the dragged thing. The guide
  [dragtracking.md](../../documentation/package/platform/dragtracking/dragtracking.md)
  says: "Each global drag is a drag of the part that keeps it", and "a drag that
  must land in a document other than the one that keeps it … has no such search yet".
- **The clipboard.** A `ClipboardSlice` holds its `content` and `slice`, a reference
  into that content. It wraps the first window only, so a copy in one window can not
  reach another window.

## 3. Decisions

D1 to D9 are the owner's, 2026-11-20. P1 to P12 were proposed by the assistant and
approved with the plan on 2026-11-20.

- **D1. A reorder shows a line** (owner). While you drag a tab over a strip, a short
  vertical line between two tabs shows where the tab goes. The tabs do not move until
  the release. A drop on the strip of any group, its own or another, puts the tab at
  the line. A drop in the middle of another group still puts it at the end.
  Rejected: the tabs slide aside while you drag, as in a web browser.
- **D2. A release anywhere outside makes a new window** (owner). A release outside
  every window of the editor opens a new window at the pointer, with the tab in it.
  The menu of a tab gets the item "Move to new window", which does the same.
  Rejected: a minimum distance from the edge of the window; the menu item only.
- **D3. A label follows the pointer outside** (owner). Outside every window, a small
  frameless window, made as a tooltip is made, shows the icon and the name of the tab
  next to the pointer. It goes away when the pointer comes back over a window. The
  pointer stays a closed hand. Rejected: the pointer only; a gray frame of the size of
  the new window.
- **D4. The new window is a full window** (owner). It has its own menu bar, toolbar
  and status bar around its own tabs, every key works in it, and a tool button opens
  the tool in that window. You can split it and drag tabs in and out of it. Rejected:
  tabs only; tabs only with the keys of the menus.
- **D5. The close of a window closes its tabs** (owner). The close of the last window
  quits the editor. Ctrl+Q and File → Exit quit the editor from any window. Rejected:
  the tabs move to a window that stays open; the first window stays the main window.
- **D6. Two new gestures** (owner, a new mechanism). The drag tracker sends them by
  position to the window under the pointer:
  - `DragOver(x, y, dragged)`: a drag that carries a thing is at this point.
    `DragOver(-1, -1, dragged)` says that the pointer left, as a pointer move to
    `(-1, -1)` does today.
  - `DragDrop(x, y, dragged)`: the release is at this point.

  A tab tree keeps where a tab would land in its own view state, draws the line or
  the rectangle from it, and answers `DragDrop` with the move of the tab. A drop in
  the tab's own window uses the same two gestures, so one piece of code does every
  drop of a tab. The tree that started the drag still gets `DragMove` and `DragEnd`.
  This replaces the rule of the guide "Each global drag is a drag of the part that
  keeps it". Rejected: no drag between windows, and a menu item "Move to window ▸".
- **D7. A new function for each wrapper that adds a layer** (owner, a new mechanism).
  Each wrapper that puts a document around the tabs of a window gets a second method:
  put my layer around the content of a new window. The start of the editor and each
  new window call the same methods, in the same order, so a host that turns a
  wrapper off gets the same result in every window. Each window has its own undo
  history: Ctrl+Z in a window undoes only the edits of that window. Rejected: one
  function that builds the layers by hand; a copy of the layers of the window that the
  tab comes from.
- **D8. One clipboard for all windows** (owner): "the clipboard should be shared so I
  can copy-paste between windows".
- **D9. No Ctrl+/ toggle** (owner, 2026-11-20, option C). The toggle of the clipboard
  replaced the content of the window with the stored copy. Around the screen it would
  replace the whole screen, so the shared clipboard offers no toggle, as the omnet IDE
  offers none today. Rejected: the stored copy in place of the content of the window
  where you press Ctrl+/, which needs a new path from the clipboard into the drawing
  of one window; a tab that shows the stored copy, a later plan if the toggle is
  missed.

- **P1. The place of the line** (proposed by the assistant). The places on a strip are
  before the first tab, between two tabs, and after the last tab. The pointer chooses
  the place whose gap is nearest. The line is 2 px wide and as high as the strip. The
  indicator widget that draws the gray rectangle now also draws the line, so a move
  of the line prints nothing again. A drop at the place of the tab itself changes
  nothing. Rejected: the line at a fixed width per tab, because the tabs have the
  width of their names.
- **P2. The tab strip gives the places** (proposed by the assistant). The tree reads
  the places of the tabs from the strip that the widget of the group printed, which
  the IO map of the group holds, and not from the unit square of the layout. Rejected:
  a computed width per tab in the pane package, which would repeat the measure of the
  widget.
- **P3. `DragMove` and `DragEnd` say when the pointer is outside** (proposed by the
  assistant, a part of D6). Each gets a field `outside`, `true` when the pointer is
  outside every window of the editor. The tree that started the drag shows the label
  of D3 from `DragMove`, and opens the new window of D2 from `DragEnd`. A release over
  a window that does not take the drop, such as its toolbar, does nothing. Rejected:
  the tracker opens the label itself, because only the tree knows the icon and the
  name of the tab.
- **P4. The window under the pointer** (proposed by the assistant). The tracker
  finds it from the place and the size of each window, which the backend writes. A
  popup, a tooltip and the label of D3 do not count. When two windows of the editor
  overlap at the pointer, the first of them in `ScreenDocument.windows` gets the
  gesture.
- **P5. The tracker clears what it showed** (proposed by the assistant). When the
  pointer goes from one window to another, the window that it left gets
  `DragOver(-1, -1, dragged)`. A `DragCancel` and a release also send it to the window
  that got the last `DragOver`, so no line or rectangle stays.
- **P6. The place, the size and the title of a new window** (proposed by the
  assistant). The upper left corner of the window is at the pointer. Its size is the
  size of the pane that the tab came from, at least 400 × 300 px. Its title is the
  name of the tab that it shows.
- **P7. The only tab of a window does not go out** (proposed by the assistant). A
  release outside with the only tab of a window does nothing, because the result would
  be the same window at another place. The item "Move to new window" is off for that
  tab.
- **P8. A window closes when its last tab leaves** (proposed by the assistant). When a
  drop moves the last tab of a window into another window, that window closes. This
  holds for the first window too.
- **P9. A move between windows is in no undo history** (proposed by the assistant).
  The open of a window and the move of a tab from one window to another are not edits
  of one window, so no undo history records them. A move inside one window stays in
  the history of that window, as today. Rejected: the history of the target window
  records the move, because its undo would put the tab back in a window that can be
  closed.
- **P10. The editor keeps the layers of a window** (proposed by the assistant, a part of
  D7). The new method is
  `wrap_window_content(::Val{keyword}, argument, content, arguments) -> content`; its
  default answers `content` as it is. The undo wrapper and the shell wrapper add a
  method, and their `wrap_editor!` call it for the first window. The editor keeps the
  wrappers of the layer `:container` that are on, with their arguments, in the order
  of the layers, so a new window gets the same layers. They are kept with the editor,
  not in a global. The status bar of a new window follows the tabs of that window.
- **P11. The clipboard wraps the screen** (proposed by the assistant, for D8). The
  `ClipboardSlice` goes around the `ScreenDocument`, inside the trackers, in the layer
  `:window`, as the tooltip window and the context menu do. A slice is then a
  reference from the screen, so a copy in window 1 pastes in window 2. The walk of the
  objects (Alt and the arrows), which the clipboard wrapper adds now, stays in the
  layer `:container`, so it walks inside one window. Rejected: a clipboard in each
  window with one store that all of them read, because each would read the state of
  another.
- **P12. Every tab window draws with the full projection** (proposed by the assistant,
  a part of D4). The window scene adds a row by the type of the content of the first
  window to the rows of the later windows, so a window whose content has that type
  draws as the first window. The dispatch by type exists. Rejected: a new field on
  `WindowDocument` that names its projection.

## 4. Steps

Each step ends with its narrowest test file and a commit. Before a step lands, the
suites of the packages that it touches run against the baseline of main.

- [x] 1. **The reorder and the line, in one window, with the two gestures** (D1, D6, P1,
  P2, P4, P5). (Done 2026-11-20.) A drop on a strip answers the place of P1, read from the printed strip
  (P2), and the drop calls `make_pane_move_tab_operation` with that index, also for the
  own group. The strip draws the line, and the indicator the rectangle elsewhere. The
  two gestures carry the drop: `DragOver` and `DragDrop` in the gesture layer of the
  kernel, which the drag tracker sends by position to the window under the pointer
  (`find_screen_window_at`), and which the tab tree reads for every drop of a tab. Test
  in `test/platform/projection/PaneDragTest.jl`: drag `a` of `a b c d` between `c` and
  `d` gives `b c a d`; a drop on the strip of another group lands at the line; a cancel
  changes nothing; the line is drawn in the gap between `c` and `d` (assert the place).

  Found in the work (2026-11-20):
  - **Why the gestures came into step 1.** The strip of a group is drawn in the second
    stage of the tabs projection, and the tab tree in the first, so only the strip knows
    where its tabs are. The strip can report a place only for a gesture that comes to it
    by position, and containers give a gesture to the child at its point only for the
    gestures in their lists (`_positioned_event` of the widgets, `_is_point_gesture` of
    the layouts). `DragMove` goes by the path of the part whose drag is on and is in no
    list. So the reorder needs `DragOver` and `DragDrop`, which are in both lists now.
  - **The strip draws the line** (changes P1). The indicator over the panes can not draw
    it, because it is in the first stage and knows no place of a tab. The strip has a
    view state field `drop_place` (`WidgetTabbedPane`), which the group computes from
    the drop state of the tree, and it draws a line 2 px wide in the primary color of
    the theme. The strip reports the place with `DropTabOperation(widget, place)`, a
    fourth report beside `CloseTabOperation`, `OpenTabOperation` and `DragTabOperation`.
  - **Two states on the tree.** `PaneTree.drag` holds the held tab,
    `(group, index, origin, started)`, and the new view state field `PaneTree.drop`
    holds where a carried tab would land, `(target, zone, place, dragged)`. A tree can
    hold a `drop` for a tab of another tree, which steps 2 and 5 need. The thing that
    the drag carries is `(tree, group, index)`.
  - **The leave comes from the moves** (changes P5). A `DragOver` at `(-1, -1)` lies
    outside every part, so a container drops it before it reaches the tree; and when the
    pointer goes from the tabs to the toolbar of the same window, no `DragOver` reaches
    the tree at all. The moves already have the rule: a container gives a move to
    `(-1, -1)` to the part that the pointer left, and the screen does so for the window
    that the pointer left. So during a drag that carries a thing, the tracker gives each
    move to the window under the pointer, at the point in that window, and a tree with a
    drop state clears it, with the crossed circle, when a move comes where it has no
    group. The parts under the pointer in another window light during the drag too. The
    `DragOver` at `(-1, -1)` stays for the end of a drag and for a change of window: it
    goes as a key goes, so it reaches the tree, which the shell offers each gesture
    that has no point.
  - **The window under the pointer.** The drag tracker sits below the screen package, so
    the screen gives it the function `find_screen_window_at` when it builds it
    (`make_drag_tracking_projection(projection; find_window)`), and no new generic is
    needed.
  - **An unchanged landing is an answer.** When the place did not change, the tree
    answered nothing, and the chain then read the gesture again in the first stage,
    with no place from the strip (`_read_chain_from` in `Chaining.jl`). The tree now
    answers `DoNothingOperation()` when the landing stays.
  - **The start shows the landing.** The move that starts a drag that carries a thing
    also sends `DragOver`, so the mark shows from the first move of the drag.
  - **Tests.** `test_pane_drag` 291 of 291, `test_pane_construct` 63, `test_drag_pointer_shape`
    39, `test_drag_tracking` 60, `test_pane_reader` 155, `test_widget_tab_strip` 74,
    `test_split_pane_drag` 43 and 5 broken, as on main. The wider drag suites (the shell,
    the widgets, chart, graph, math, sequence chart, data frames, the application) show
    only failures that the index of main knows: Save As (`FileDialogTest.jl:138`), the
    depth of the math walk (`MathToGraphicsTest.jl:346`), two vertex drags
    (`GraphVertexDragTest.jl:166`, `:328`) and the usage text of the agent bar
    (`ApplicationTest.jl:1050`). The application test of a tab drop drove the drop with
    `DragMove` and `DragEnd` and now sends `DragOver` and `DragDrop`, as the tracker
    does; `test_dragging` errors 4 times in a stub that is no IO map, in code this branch
    does not change. A run in a check worktree at `f2decb134` and one on a clean worktree
    of main `18817ba15` gave the same: `test_dragging` 10 passes and the same 4 errors on
    both, `test_application` 421 passes on the branch and 420 on main, with the one
    failure at `ApplicationTest.jl:1050` and 2 broken on both.
- [x] 2. **The gestures across windows** (D6, P3, P4, P5). (Done 2026-11-20.) The field
  `outside` on `DragMove` and `DragEnd`, and two windows of the editor. The guide of the
  drag tracker gets the new rule. Test in `test/platform/shell/DragTrackingTest.jl`, with
  two windows at known places on a headless backend: the window under the pointer gets
  `DragOver`, the window that the pointer left gets the leave, and a release outside
  gives `outside = true`.

  Found in the work (2026-11-20):
  - The code of the field `outside` and of the send to the window under the pointer came
    with step 1, because the reorder needed the same gestures. Step 2 added the tests of
    two windows (`_dt_two_window_editor`: `W` at `(0, 0)` and `V` at `(500, 0)`, each 400
    by 300): the window under a point of the screen, the mark in `V` while every move
    comes in `W`, the leave when the pointer goes back or into the gap between the
    windows, and Escape.
  - `test_drag_tracking` 92 of 92 at `f2decb134`. Its last test said that a release in
    another window moves no tab; step 5 changes it to the moves of step 5.
- [ ] 3. **The layers of a new window** (D4, D7, D8, P10, P11, P12).
  `wrap_window_content` with the methods of the undo wrapper and the shell wrapper; the
  editor keeps the layers; the clipboard around the screen; the row of P12. A function
  of the pane package opens a window with a given tab and the layers. Test: open a
  second window by code with one tab; Ctrl+O and Ctrl+P fire in it; Ctrl+Z in it undoes
  only its own edit; a copy in window 1 pastes in window 2. The omnet IDE suites run,
  because the IDE window passes options to the clipboard wrapper.
- [ ] 4. **A tab goes out** (D2, D3, P6, P7). A release with `outside = true` opens the
  window of step 3 with the tab, at the place of P6. While the pointer is outside, the
  label of D3 follows it. The item "Move to new window" in the menu of a tab. Test: a
  drag of `b` from `a b c` to 200 px outside gives a second window with `b` at the
  pointer and leaves `a c`; the label is shown while outside and is gone after the
  release; the only tab of a window does not go out.
- [ ] 5. **A tab goes back, and the close of a window** (D5, P8, P9). A drop into the
  strip or a pane of another window moves the tab there, and an empty window closes. The
  close button of a tab window closes its tabs, and the close of the last tab window
  quits. A save of the layout (`save_user_interface`) keeps every window, and a load
  gives them back. Test: drag `b` from window 2, its only tab, between `a` and `c` of
  window 1 gives `a b c` and one window; the close of window 2 with `b d` releases `b`
  and `d`; no undo history holds a move between windows.
- [ ] 6. **The guides and the live check.** The guides of the pane, the drag tracker,
  the screen and the shell describe the new rules. A live check on SDL with two real
  windows: a reorder, a tab out to a new window, a tab back, a copy and paste between
  the windows, with a picture of each state. Then the owner tries it.

## 5. Not in this plan

- A file dragged from the explorer into an editor. The gestures of D6 can serve it later.
- The reorder of a list by the dragging slice (`DraggingState`) keeps its own drag.
- A Wayland session without X11, where SDL gives no place of a window, so the window
  under the pointer can not be found.
- The order of overlapping windows on the screen.
- `get_window_tree()` answers the tree of the first window, as today.
