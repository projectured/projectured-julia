# Hover, drag and tooltip share the pointer

**Status (2026-09-22): PROPOSED.** Nothing is implemented. The owner chose a
deadline for the tooltip's delay; the other decisions in §3 are recommendations
until the owner confirms them.

**Goal:** in both binaries, a button or a row lights up under the pointer, a
divider and a tab drag again, and a tooltip opens only after the pointer rests
on something for a moment.

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

Four faults, all from the one-interface plan:

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
  next rest opens it again.
- **The delay is 500 ms by default**, a keyword of the fold and of the feed. It is
  the owner's to change.
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
  each synthesise crossings.

## 4. Steps

### Step 0 — baselines

- [ ] `test_shell()`, `test_application()`, `test_substrate()` (known: 3 fail,
      2 error, 1 broken, in the split-pane drag cases).
- [ ] omnet-julia: `test_ide_window_wrap()` 25, `test_ide_file_navigator()` 8,
      `test_select_and_paste()` 72 pass, 7 fail, 3 error (known, §4 of
      `the-shell-fills-its-window.md`).
- [ ] Measure whether a hover writes an undo entry: a move over a tree row
      answered `RecordUndoOperation`. If a hover lands in the history, write it
      down for the owner; this plan does not change the history.

### Step 1 — the shell routes and captures the pointer

- [ ] `MouseDown` and `MouseUp` route to the band under the pointer, translated.
- [ ] A drag is captured by the band that took the down, until the up.
- [ ] Tests in the substrate suite: a down on a tab of a draggable pane inside a
      shell makes `DragTabOperation`; a held move over the status line still
      reaches a divider drag in the content; the up ends it.

### Step 2 — the probe passes every event on

- [ ] `TooltipProbeProjection` forwards every event inward first and adds its own
      operation. A move notes the position and the time, and closes an open
      tooltip after a few pixels.
- [ ] Tests: a move under the probe reaches a divider drag and the hover tracker;
      a press, a key and a scroll close an open tooltip.

### Step 3 — the tooltip opens at a deadline

- [ ] `PointerRest`, `TooltipFeed`, `make_tooltip_feed(; delay = 0.5)`; the probe
      answers `PointerRest`.
- [ ] The application and the interface make the feed and pass it to the fold and
      to `run_window_editor`.
- [ ] Tests with an injected clock: no deadline before a move; a deadline of the
      delay after one; a new move moves the deadline; at the deadline the feed
      posts the opening; a move after it closes; no deadline while one is shown.

### Step 4 — the hover tracker covers the window

- [ ] The fold puts the tracker around the shell, inside the probe.
- [ ] It leaves `_make_application_pane_projection`; `run_campaign_window` keeps
      its own only without a `wrap`.
- [ ] Tests through the whole fold, with the tooltip on: a move over a toolbar
      button, the "+" of a tab group and a tree row each light it, and a move away
      puts it out.

### Step 5 — the windows, end to end

- [ ] `test_application()`: in the real window, with the tooltip on, a divider
      drags, a tab drags to another group, and a row lights up.
- [ ] omnet-julia: the same three in the interface's window, and the counts of
      Step 0 hold.

### Step 6 — close

- [ ] `documentation/package/shell/shell.md`: the order of the fold, the capture,
      and the tooltip's rest. `plan/pending/tooltip.md`: its Step 5, the show
      delay, is answered by the deadline.
- [ ] Move this plan to `plan/done/`.

## 5. Risks

| Risk | What is done about it |
| --- | --- |
| The toolbar plan of another session edits `WindowChrome.jl` and the toolbar now. | This plan edits the fold, the shell printer, the probe and the entries, not the bands. Rebase before each landing and run both suites. |
| A feed that reads the projection runs before `read!` in the frame. | It reads with the io map of the last print, as `read!` does, and posts its operation; the next frame applies it. |
| A captured drag whose up never comes, for example when the window loses the pointer. | The capture ends on the next down too, and on a leave of the window. |
