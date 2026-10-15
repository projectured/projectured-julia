# The wheel scrolls faster on a fast turn

> **Status (2026-10-15): pending.** The owner asked for it: "the scroll bar is
> too slow, perhaps it would make sense to have a speed range (min, max) and if
> scrolling is continuous than slowly speed up to max". The owner agreed to the
> four steps below and to a change of `MouseScroll` for the touchpad. Step 3
> changes `MouseScroll` with a new field and not with a new type of `dx` and
> `dy`. The owner agreed to that design and to the fix of the copies that drop
> `modifiers` ("yes and also with the fixes"). Steps 1 to 4 are done. The
> check in the live app and the precompile of omnet-julia are open.

## The goal

One notch of the wheel moves the view by 3 lines. A fast run of notches moves it
more at each notch, up to one view less one line. A touchpad scrolls smoothly.

## The facts (2026-10-15)

1. `_self_scroll` of `WidgetScrollPane` (`WidgetToGraphics.jl`) moves the view
   by `dy` times the height of "M", one line for each notch. The pan of
   `WidgetTransformPane` does the same. Windows, the browsers and VS Code move 3
   lines for each notch.
2. The SDL backend merges a run of motion events (`take_from_devices!`). It does
   not merge wheel events, so each notch gets a frame of its own.
3. The SDL backend reads `evt.wheel.x` and `evt.wheel.y`, which are whole
   numbers. SDL adds the fractions of a touchpad into these whole numbers. The
   backend does not read `preciseX` and `preciseY`, which hold the fractions. So
   a touchpad scrolls in steps of whole lines.
4. `MouseScroll` (`source/kernel/event/MouseEvent.jl`, not sealed) holds
   `dx::Int`, `dy::Int`, `x`, `y`, `modifiers` and `time`.
5. Some readers step a value by a notch: the spin box, the zoom of the transform
   pane, the chart, the sequence chart and the task pages. They need whole
   notches. A fraction makes them step too often or never.
6. Eight places copy a `MouseScroll` field by field when they move it into a
   child: `LayoutList.jl:296`, `LayoutToGraphics.jl:322` and `:1952`,
   `WidgetTableParts.jl:263`, `WidgetToGraphics.jl:1440`, `:3232`, `:4277` and
   `:10138`. Six of them drop `modifiers`. `shift_event_position` and
   `map_event_position` (`EventPosition.jl`) keep every field.
7. The web client sends only the sign of a turn (`asset/web/client.js`).
8. omnet-julia (`source/tool/record_precompile.jl`) and inet-julia
   (`source/tool/repl/record/driver.jl`) make a `MouseScroll` with the keyword
   constructor `MouseScroll(dx, dy, x, y; time)`.

## Steps

### Step 1: a notch moves 3 lines

- ✅ `_self_scroll` and the pan of `WidgetTransformPane` move the view by 3 lines
  for each notch. The count is a field of each projection with a keyword,
  `lines_per_notch`.
- ✅ The spin box, the zoom, the tab strip, the chart, the sequence chart and the
  task pages do not change.
- ✅ Update the tests that assert the distance of a notch, and the docstrings and
  `widget.md`. 16 assertions in 4 files changed. Each test that scrolls three
  hundred rows now starts two lines higher, so its turn ends where a turn of
  one line ended before and the intent of the test stays. A line of
  `FixedMeasure(8, 12, 4, 0)` is 16 pixels: the ascent and the descent. 17 test
  functions that send wheel events pass.

### Step 2: the backend merges a run of wheel events

- ✅ `take_from_devices!` of the SDL backend merges a run of wheel events of the
  same window with the same modifiers into one `MouseScroll`. The event holds
  the sum of the turns, and the position and the time of the newest event
  (`_take_wheel_run!`, `_merge_wheel_events`).
- ✅ The order of events stays. An event that is not a wheel event ends the run,
  as it ends a run of motion. A motion sample that ends a run waits in
  `pending_motion`, and any other event in `pending_inputs`. Nothing merges
  while an older input, a held motion or the update of a frame waits.
- ✅ Test the merge, and test that a press after a turn comes after it
  (`InputCoalescingTest.jl`, 63 of 63).

### Step 3: a touchpad scrolls smoothly

The owner agreed to this design: `dx` and `dy` stay whole notches.
A new pair of fields holds the exact amount of the turn, in notches, as a
`Float64`. The readers of a whole notch (fact 5) do not change.

- ✅ Add the pair to `MouseScroll`: `precise_dx` and `precise_dy`, after `time`,
  so a destructure of the first fields does not change. The keyword
  constructors and the six-argument constructor set it from `dx` and `dy`, so
  the code of fact 8 does not change. `MouseEvent.jl` was not sealed (⬜).
- ✅ The SDL backend fills the pair from `preciseX` and `preciseY`, and takes the
  whole notch where SDL gives no fraction. The merge of step 2 adds the pair
  up too. The web client sends the sign as now.
- ✅ The copies of fact 6 use `shift_event_position`. They then keep the pair
  and the modifiers. The implementation found ten copies, not eight: the tabbed
  pane and the content of a scroll pane copied the event too. Seven of the ten
  dropped `modifiers`, so by the code a child of such a container got the wheel
  with no Ctrl. A new test shows that Ctrl and the wheel zoom a transform pane
  in a composite; the test was not run before the fix.
- ✅ `_self_scroll` and the pan of `WidgetTransformPane` read the exact amount.
- ⬜ Check that omnet-julia and inet-julia precompile. A static scan found only
  the keyword constructor `MouseScroll(dx, dy, x, y; time)` in both, which
  keeps working. The precompile itself waits for the landing, because a scratch
  environment over two repositories needs 16 GB.
- ✅ 18 test functions pass: 1022 of 1022.

### Step 4: a fast run of notches speeds up

- ✅ `WidgetScrollPane` and `WidgetTransformPane` keep the run of the wheel as
  view state, `wheel_run`: the time, the direction and the distance of the last
  notch. A write of it is a `ReplaceViewStateOperation` in the same operation as
  the scroll, after it. The `.pred` writer leaves it out. The panes that the
  table and the list make by position get a cell of their own for it; a list
  keeps it across notches (`WidgetRowsScrollTest.jl`).
- ✅ The answer of a pane to the wheel is now a compound of the scroll and the
  run. The table read the scroll as one write (`_find_written_offset`), so it
  now finds it inside a compound, and keeps the other writes beside a move of
  its head, in one flat compound, so a reader that looks for the selection at
  the top level still finds it.
- ✅ A notch that comes less than 80 ms after the last notch, in the same
  direction, multiplies the distance by 1.25. A gap from 80 ms to 150 ms keeps
  the distance. A longer gap, or a change of direction, puts the distance back to
  3 lines. A merged event of n notches counts as n notches.
- ✅ The largest distance of a notch is the view less one line, so a notch never
  jumps past text that the person did not see.
- ✅ Only a turn of whole notches speeds up. A turn with a fraction comes from a
  touchpad, and the system already speeds it up.
- ✅ The growth is a field of the projection with a keyword, `wheel_growth`. A
  growth of 1.0 turns the speed-up off.
- ✅ Test with events that carry their times (`ScrollPaneBarTest.jl`). The older
  tests that send several notches at the time 0.0 made a fast run, so their
  helpers now send each notch a second after the last. 17 test functions pass:
  1012 of 1012.
- ⬜ Tune the numbers in the live app. The live check (see the plan of the
  scroll bar) confirms the numbers in a real window: one notch scrolls 69
  pixels, three lines of 23, and three notches 50 ms apart scroll 263 pixels,
  69 + 86 + 108. Whether 80 ms, 150 ms and 1.25 feel right needs a real wheel
  in the hand of the owner.

## The review (2026-10-15)

A reviewer agent read the whole diff of the branch. Its findings, and what
became of each:

1. ✅ Ctrl and the wheel zoomed one step for a merged turn of many notches, by
   the sign of `dy`. `_zoom_op` now takes a count of steps, and the wheel
   zooms a step for each notch; a turn with no whole notch, from a touchpad,
   zooms nothing (before the branch it zoomed in).
2. ✅ A notch was never shorter than three lines, so in a view less than four
   lines tall it passed lines that never showed. Now the largest notch is the
   view less one line and at least one line, and a notch is never more.
3. ✅ The pan of a transform pane read `w.size`. It now reads the canvas that
   it drew, as the scroll pane does. The case of the finding, a pane with no
   size, can not happen: the constructor refuses a size of `nothing`.
4. ✅ A merged turn grew at each later notch, so a slow frame sped up a slow
   wheel. Now the notches of a merged turn share the time since the last
   notch, so their pace decides; a merged turn that starts a run does not grow.
5. ⬜ Open, for the owner: the video scripts `tool/video/record_data_frame.jl`,
   `record_appearance.jl`, `record_lazy_primes.jl`, `check_assistant_undo.jl`
   and `record_assistant_window.jl` send wheel events at the time 0.0 or ten
   notches in one event. A take recorded again scrolls further than before.
6. ✅ `pred_arguments(::WidgetTransformPane)` now writes the content first, as
   the constructor takes it, as the scroll pane does. A save of a transform
   pane still fails at `transform`, which is no document, as before.
7. ⬜ Open: the recorded precompile statements name `WidgetScrollPane` and
   `WidgetTransformPane` with the old count of type parameters, in
   `package/*/precompile/*.txt` and in omnet-julia and inet-julia. They are
   skipped until the next recording; this costs compile time and changes no
   result.
8. ✅ The table took the scroll of any document as its own, also of a pane in a
   cell. `_find_written_offset` now takes only the scroll of the pane of the
   cells.

The reviewer found no fault in the order of the SDL merge, in the readers of
the compound answer, in the positional constructors, or in the `.pred` of a
scroll pane. One caveat it did not check: a bar that stops being drawn during
its show keeps the clock read until the bar computes again or is collected,
as a progress ring does.

## Decisions

- The speed-up applies where a pane scrolls, and not where a notch steps a value
  (fact 5).
- The state of a run lives in the pane that scrolls. No new event.
