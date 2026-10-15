# The wheel scrolls faster on a fast turn

> **Status (2026-10-15): pending.** The owner asked for it: "the scroll bar is
> too slow, perhaps it would make sense to have a speed range (min, max) and if
> scrolling is continuous than slowly speed up to max". The owner agreed to the
> four steps below and to a change of `MouseScroll` for the touchpad. Step 3
> changes `MouseScroll` with a new field and not with a new type of `dx` and
> `dy`. The owner agreed to that design and to the fix of the copies that drop
> `modifiers` ("yes and also with the fixes"). Step 1 is done.

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

- ⬜ `take_from_devices!` of the SDL backend merges a run of wheel events of the
  same window with the same modifiers into one `MouseScroll`. The event holds
  the sum of the turns, and the position and the time of the newest event.
- ⬜ The order of events stays. An event that is not a wheel event ends the run,
  as it ends a run of motion.
- ⬜ Test the merge, and test that a press after a turn comes after it.

### Step 3: a touchpad scrolls smoothly

Proposed, and waits for the word of the owner: `dx` and `dy` stay whole notches.
A new pair of fields holds the exact amount of the turn, in notches, as a
`Float64`. The readers of a whole notch (fact 5) do not change.

- ⬜ Add the pair to `MouseScroll`. The keyword constructor sets it from `dx` and
  `dy`, so the code of fact 8 does not change.
- ⬜ The SDL backend fills the pair from `preciseX` and `preciseY`. The web client
  sends the sign as now.
- ⬜ The eight copies of fact 6 use `shift_event_position` or
  `map_event_position`. They then keep the pair and the modifiers.
- ⬜ `_self_scroll` and the pan of `WidgetTransformPane` read the exact amount.
- ⬜ Check that omnet-julia and inet-julia precompile.

### Step 4: a fast run of notches speeds up

- ⬜ `WidgetScrollPane` and `WidgetTransformPane` keep the run of the wheel as
  view state: the time, the direction and the distance of the last notch. A
  write of it is a `ReplaceViewStateOperation` in the same operation as the
  scroll. The `.pred` writer leaves it out.
- ⬜ A notch that comes less than 80 ms after the last notch, in the same
  direction, multiplies the distance by 1.25. A gap from 80 ms to 150 ms keeps
  the distance. A longer gap, or a change of direction, puts the distance back to
  3 lines. A merged event of n notches counts as n notches.
- ⬜ The largest distance of a notch is the view less one line, so a notch never
  jumps past text that the person did not see.
- ⬜ Only a turn of whole notches speeds up. A turn with a fraction comes from a
  touchpad, and the system already speeds it up.
- ⬜ The growth is a field of the projection with a keyword. A growth of 1.0
  turns the speed-up off.
- ⬜ Test with events that carry their times. Tune the numbers in the live app.

## Decisions

- The speed-up applies where a pane scrolls, and not where a notch steps a value
  (fact 5).
- The state of a run lives in the pane that scrolls. No new event.
