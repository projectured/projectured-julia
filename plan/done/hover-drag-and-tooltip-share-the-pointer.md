# Hover, drag and tooltip share the pointer

**Status (2026-09-22): DONE.** Landed on `main` in both repositories:
projectured-julia at `f698c294`, omnet-julia at `234d77e4`. Nothing is pushed.
The owner chose a deadline for the tooltip's delay, confirmed the other
decisions of §3 on the same day, and ruled that a hover must not land in the
undo history. One thing is left as the owner asked: a divider drag is still one
undo step for each move.

**Goal:** in both binaries, a button or a row lights up under the pointer, a
divider and a tab drag again, a tooltip opens only after the pointer rests on
something for a moment, and none of this pointer state lands in the undo
history.

**Repositories:** projectured-julia, and omnet-julia for the interface's entry.
The plan changes no sealed file: `event/MouseEvent.jl` and
`gesture/GestureRecognizer.jl` are sealed, and §3 keeps out of both.

## 1. What is wrong

The owner found it on 2026-09-22: nothing lights up under the pointer, a pane
cannot be dragged to another group, and a divider of a `WidgetSplitPane` cannot
be dragged. Measured in the application window at 1850 × 1150:

| Gesture | Tooltip off | Tooltip on (as both binaries run) |
| --- | --- | --- |
| a move over a tree row | a hover operation | nothing |
| a move over the toolbar's New tab, or the menu's File | passed through, no hover | nothing |
| a down on a divider, then a move with the button held | the split resizes | the move answers nothing |
| a down on the Assistant tab, then moves with the button held | no drag starts | no drag starts |

Five faults. The first four come from the one-interface plan:

1. **The tooltip probe takes every `MouseMove`.** On a move it sends a synthetic
   Alt+press inward and answers only its own tooltip operation; the real move
   never reaches the inner readers. So the hover tracker never synthesises
   `MouseEnter` or `MouseLeave`, and a divider drag never sees the pointer move.
   Moves with a button held are taken too: the backend never throttles those.
2. **The shell forwards `MouseDown` and `MouseUp` with window coordinates.**
   `WidgetShellToGraphicsCanvas` routes a press, a move, a scroll and a crossing
   to the band under the pointer, translated into that band's frame, but a down
   and an up fall to `_forward_to_children`, which ignores coordinates. In the
   content's frame a down on a tab lands one band height below the tab strip, so
   `DragTabOperation` is never made. A divider drag starts only because a
   divider spans the whole height. `_route_downup_to_children` exists for exactly
   this, and the other containers use it.
3. **The shell captures no drag.** Every routing helper hit-tests, so a drag
   whose pointer crosses the menu bar, the toolbar or the status line stops
   receiving moves, and its release is lost. Before the shell, the pane tree was
   the whole window and received everything.
4. **The hover tracker sits inside the shell**, around the pane tree only, so the
   menu bar and the toolbar never light up even with the tooltip off.
5. **A hover lands in the undo history.** A widget answers a crossing with
   `ReplaceReferencedValueOperation(widget, "hovered", true)`, a real write, and
   the history's default filter `is_undo_step` keeps every write that is not a
   bare selection move. A move over a tree row answered `RecordUndoOperation`, so
   Ctrl+Z would take back a hover. A button's `pressed` state and a tab drag's
   drop zone (`PaneTree.drag`) are written the same way. Fixing faults 1 and 4
   makes this one worse, because every button and row starts to hover again.

**How it passed.** The probe's suite drove the probe alone. No test sent a hover,
a divider drag or a tab drag through the whole fold, and none through the shell.

## 2. What the tooltip must do

The owner's rule: **a tooltip opens only after the pointer rests on something
for a while, not continuously.**

**A resting pointer sends nothing.** The SDL backend holds back idle motion and
sends the last position once, so no event arrives while the pointer rests. A
reader can not open a tooltip after a rest by itself. The older
`TooltipDecoratorProjection` checks its `delay_ms` with `time()` when an event
arrives, which is why it can not serve here.

**The loop gives time through a feed.** `compute_wait_timeout` sleeps until the
nearest feed deadline, `compute_wake_deadline(feed, editor)`, and forever when no
feed names one. So a waiting tooltip costs one wake, and an idle window costs
nothing.

## 3. Decisions

- **Every reader passes the pointer on.** The probe gives every event to its
  inner projection first, as the hover tracker does, and adds its own operation
  to what came back. A move only notes where the pointer is and when; it probes
  nothing.
- **The tooltip opens at a deadline.** A `TooltipFeed` in the tooltip slice names
  a deadline, the time of the last move plus the delay, while a move is pending
  and no tooltip is shown. When the deadline passes with no new move, the feed
  reads a `PointerRest(x, y)` gesture through the editor's own projection and
  posts the operation that comes back, with `post_operation!`. The probe answers
  `PointerRest`: it probes once at that point and opens the window, exactly as it
  does now. Every other reader declines a gesture it does not know.
- **`PointerRest` lives in the tooltip slice**, not in the kernel, because
  `event/MouseEvent.jl` is sealed. The feed reads the gesture through
  `read_intent` and does not reach into the recognizer, because
  `gesture/GestureRecognizer.jl` is sealed.
- **The tooltip closes** on a move of more than a few pixels, a press, a down, a
  key, a scroll, or the pointer leaving the window. No move probes, so it can not
  know whether the pointer is still on the same document; a move closes, and the
  next rest opens it again. Confirmed by the owner.
- **The delay is 500 ms by default**, a keyword of the fold and of the feed.
  Confirmed by the owner.
- **The entry makes the feed** with `make_tooltip_feed(; delay)` and hands it to
  both the fold and `run_window_editor(feeds = …)`, as it hands the fold its
  `pointer`. The fold's contract, `(document, projection)`, does not change.
- **The shell routes a down and an up like a press**, translated into the band's
  frame, with `_route_downup_to_children`.
- **The shell captures a drag.** The band that took a `MouseDown` gets every move
  with a button held and the next `MouseUp`, translated into its frame, wherever
  the pointer is. The shell keeps which band that is, per window, and not in a
  process-wide variable.
- **The hover tracker moves out, around the shell**, inside the probe. It leaves
  `_make_application_pane_projection`. `run_campaign_window` builds its projection
  with a tracker only when no `wrap` is given: the plain campaign binary has no
  fold and keeps its own, and the interface gets the fold's. Two trackers would
  each synthesise crossings. Confirmed by the owner.
- **Pointer state is view state, and the history does not record it.** A reader
  that writes view state — a widget's `hovered` or `pressed`, a pane tree's
  `drag` — marks the write with `ReplaceViewStateOperation`, a
  `WrappingOperation` around it, and `is_undo_step` drops what is marked. It
  lives in the kernel's operation layer, which is not sealed, because that is the
  one layer both the writers and the undo slice see: `ProjecturedUndo` depends on
  no widget and no pane package. Applying it applies the write inside, and
  rerooting and rewrapping work as for every wrapper. A divider's resize stays a
  step of the history, as the application's window history promises.

## 4. Steps

### Step 0 — baselines

**Done, 2026-09-22**, in the worktree `workspace/projectured-julia-pointer` on
branch `pointer`, cut from `main` at `8c934f40`.

- [x] `test_substrate()` **63337 pass, 3 fail, 2 error, 1 broken**: the five are
      the split-pane drag cases known on `main`. `test_shell()` **157**.
      `test_kernel()` **2017 pass, 3 fail, 3 error**: the Rule C cases and one
      reference case, known on `main`. `test_application()` **108**.
- [x] omnet-julia, measured on `main` earlier the same day:
      `test_ide_window_wrap()` 25, `test_ide_file_navigator()` 8,
      `test_select_and_paste()` 72 pass, 7 fail, 3 error (known, §4 of
      `the-shell-fills-its-window.md`).
- [x] What pointer gestures add to the application window's history today, with
      the tooltip off: **four moves over tree rows add four undo steps**, one per
      hover, and **a divider drag of three moves adds five**, the grab, each move
      and the release.

**What Step 0 adds to the plan.** One more write holds pointer state and is
marked in Step 5 with the others: a slider's `dragging`, the flag of a held
thumb. A divider holds its grab with two typed operations of its own,
`StartSplitterDragOperation` and `EndSplitterDragOperation`, which the pane layer
reads by type; they stay steps, and wrapping them would hide them from those
readers. So after Step 5 a divider drag still adds a step for the grab, one for
each move and one for the release. **A drag that becomes one step is not in this
plan**; the owner has the count.
Scroll positions (`scroll_position`, `tab_scroll`, `follow_end`) are view state
too, but no gesture of this plan writes them.

### Step 1 — the shell routes and captures the pointer

- [x] `MouseDown` and `MouseUp` route to the band under the pointer, translated.
- [x] A drag is captured by the band that took the down, until the up. The shell
      projection keeps the capture in a `Ref`, as the hover tracker keeps its
      state; one shell projection serves one window.
- [x] **A split pane now reads its drag before its own bounds check, while a drag
      is active.** Found by the test: the shell handed the held move to the
      content, and `_outside_widget` dropped it, because it landed past the split
      pane's edge. Before the shell a split pane at the root covered the window,
      so a drag never left it.
- [x] Tests in the substrate suite, `test_widget_shell_pointer()`: a down on a tab
      of a draggable pane inside a shell makes `DragTabOperation` for that tab; a
      held move over the status line still resizes a divider in the content; the
      up ends the drag. **`test_substrate()` is 63391** with the baseline's 3 fail,
      2 error and 1 broken: 5 new assertions, and the rest from the walkers that
      count one assertion per field, which meet the shell projection's new
      `capture` field. That remainder was not broken down further.

### Step 2 — the probe passes every event on

- [x] `TooltipProbeProjection` forwards every event inward first and adds its own
      operation. A move notes the position and the time, and closes an open
      tooltip after four pixels.
- [x] Tests: a move under the probe reaches a divider drag held inside it; a move
      alone opens nothing; a press closes an open tooltip; a move of two pixels
      keeps it and a move away closes it.
- Steps 2 and 3 are one commit: both live in the rewritten probe.

### Step 3 — the tooltip opens at a deadline

- [x] `PointerRest`, `TooltipRest`, `TooltipFeed` and `make_tooltip_feed(; delay =
      0.5, now, window)` in `source/tooltip/TooltipRest.jl`; the probe answers
      `PointerRest`. The fold takes the feed as `tooltip_feed` and refuses a
      tooltip without one, as it refuses one without a pointer.
- [x] The application makes the feed and passes it to the fold and, beside the
      tools' own feeds, to `run_window_editor`. **The interface follows once this
      lands**, because the fold now refuses its tooltip without a feed.
- [x] `test_tooltip_feed()`, with an injected clock, in a real editor over a
      `HeadlessBackend`: no deadline before a move; a deadline of the delay after
      one; a later move moves it; before it nothing opens; at it the feed posts
      and the inbox applies the opening; no deadline while one is shown; a move
      away closes it and the wait starts again. The application's toolbar case now
      asserts that a move alone opens nothing and a rest opens the tooltip.
- **`test_shell()` is 172** (157 before) and **`test_application()` 109** (108).

### Step 4 — the hover tracker covers the window

- [x] The fold puts the tracker around the shell, inside the probe, with no
      keyword: a window that shows a button must light it.
- [x] It leaves `_make_application_pane_projection`. The campaign window keeps its
      own only without a `wrap` — that half is omnet-julia's and follows.
- [x] **The tracker looks through a wrapper to find the widget it entered.** It
      took the target from a plain `ReplaceReferencedValueOperation`; outside the
      history every answer arrives inside `RecordUndoOperation`, and after Step 5
      inside the mark, so it saw no target at all.
- [x] Test through the whole fold, with a toolbar and the tooltip on: a move over
      a toolbar command lights it, a move over a button in the content lights the
      button and puts the command out, and a move to empty space puts the button
      out. The fold's own tests now find the tracker between the recorder and the
      content.

### Step 5 — pointer state stays out of the history

- [x] `ReplaceViewStateOperation` in `source/kernel/operation/Operations.jl`, with
      the rewrapping every wrapper has and a description that is the write's own;
      `is_undo_step` drops it, and a compound of nothing but marked writes.
- [x] `_write_view_state` in the widget slice marks all sixteen writes of
      `hovered`, `pressed` and a slider's `dragging`; the pane slice marks its
      `drag`. A history comment in `WidgetDocument.jl` gave way to the helper's
      docstring.
- [x] `test_undo_buffer()`: a marked write is no step, a compound of marked writes
      is none, and a compound with one real write is one. **`test_undo()` is 91.**
      The window-level check is in Step 6. Fourteen substrate cases asserted the
      old form of a hover or a press; they now assert the mark and the write in
      it, through one helper, and the table's and the tree's readers look through
      the mark, with one direct assertion of the mark each.
- **`test_kernel()` is 2017 pass, 3 fail, 3 error**, its baseline exactly.
- **A layering guard found a fault of Step 3**: the tooltip slice imported
  `post_operation!`, and an import list states what a file extends. It uses
  `EditorModule` now.

### Step 6 — the windows, end to end

- [x] `test_application()`: in the real window, with the tooltip on, a row of
      the navigator lights up and the window's history does not grow, the divider
      between the navigator and the files moves its weights, and the open file's
      tab drags into the navigator's group. **`test_application()` is 115.**
      **The case keeps one print**, as the editor keeps it: a divider holds its
      drag on the widget a print made, and a case that printed before every event
      lost the drag on the second print. The real editor prints once and keeps
      its io map live.
- **`test_substrate()` is 63393** with the baseline's 3 fail, 2 error and 1 broken,
  and **`test_shell()` 177**.
- [x] omnet-julia, after the projectured half landed: a new case in
      `test_ide_window_wrap()`, with the tooltip on, lights the runner's Run
      button and drags the divider between the runner and the conversation. A
      tab drag has no case of its own there; the interface draws through the
      same fold and shell as the application, whose case drags a tab.
      `test_ide_window_wrap()` **32**: 29 on `main` after its toolbar commit,
      and 3 new. `test_ide_file_navigator()` **8** and `test_ide_closure()`
      **26**, as before. `test_select_and_paste()` **81 pass, 4 fail, 1 error**,
      against 72, 7 and 3 before: every failure left was in the baseline, at
      lines 304, 310, 314, 317 and 434, where the focus does not reach through
      the shell. The ones that went away are the "two Run texts" cases, which
      the toolbar commit removed.
      `run_campaign_window` keeps its own tracker only without a `wrap`:
      `build_campaign_projection(; hover = true)`. `run_omnet_ide` makes the
      feed only when it has a backend, because only a backend has a pointer.

### Step 7 — close

- [x] `documentation/package/shell/shell.md`: the order of the fold, the capture,
      and the tooltip's rest. `plan/pending/tooltip.md`: its Step 5, the show
      delay, is answered by the deadline. The guides of the tooltip, the widget,
      the pane, the inspector and the undo slice lose the fault as a limit and
      name the view state; the shell's one limit left is the divider drag, one
      undo step per move.
- [x] Move this plan to `plan/done/`.

## 5. Risks

| Risk | What is done about it |
| --- | --- |
| The toolbar plan of another session edits `WindowChrome.jl` and the toolbar now. | This plan edits the fold, the shell printer, the probe and the entries, not the bands. Rebase before each landing and run both suites. |
| A feed that reads the projection runs before `read!` in the frame. | It reads with the io map of the last print, as `read!` does, and posts its operation; the next frame applies it. |
| A captured drag whose up never comes, for example when the window loses the pointer. | The capture ends on the next down too, and on a leave of the window. |
| A new operation type in the kernel touches the layer every slice stands on. | It is one wrapper, beside the other wrappers of `Operations.jl`, and the layer is not sealed. The kernel suite runs with Step 5, and its known failures (5 Rule C, 1 MEvalBranch) are the baseline. |
