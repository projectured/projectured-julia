# A tooltip or a popup stays where it opens

> **Status (2026-10-21): planned.** The owner asked for these three fixes on
> 2026-10-21, after an investigation the same day, and deferred a fourth fault
> (the black first tooltip on macOS). Built on the branch `tooltip-stays` in the
> worktree `projectured-julia-tooltip-stays`.

## The faults

1. **A tooltip of a part that a view makes closes at once, on every platform.**
   The tooltips of the assistant buttons at the bottom of the window (stop,
   picture, work) appear and disappear immediately. Toolbar tooltips stay.
2. **On macOS a menu or a dropdown closes as soon as it opens.** Predicted from
   the code and from the SDL logs of a tester on macOS; not yet seen there.
3. **A tooltip on a monitor above or left of the main one opens in the center of
   the main display.** A tester on macOS saw it with a monitor above the main
   one: the button at (869, −974), the tooltip at (885, 529).

## The causes

**Fault 1.** A view, such as `AssistantToWidgetSplitPane`, prints its input as
widgets that it makes itself. The answer to a dwell names the button as the path
of the document and then the widget steps:
`… .content .elements[2:3] .child .children[0:1]`. A move names the part at its
point with the backward map, and a view maps a point to an introduced reference:
`… .content proj(AssistantToWidgetSplitPane, ^(.elements[2:3] .child .children[0:1]))`.
Both name the same button. `_closes_tooltip` in `TooltipWindow.jl` compares them
as plain paths, so every move closes the tooltip. The backend sends a move to
the point of the pointer after each frame that changed a window, and the frame
that opens the tooltip is such a frame, so the tooltip closes at once. A probe
with the headless backend reproduced it: the tooltip of each assistant button
opened, and a move to the same point closed it.

**Fault 2.** SDL 2.32 on Cocoa makes each shown window the key window, which the
tooltip logs of the tester proved. When a popup becomes key, window 1 gets
`FOCUS_LOST`, and `WindowManagingProjection` closes every `:popup` when another
window loses the focus. A probe with the headless backend reproduced the second
half: a click on File opened its menu, and a `WindowDefocus` of the main window
closed it.

**Fault 3.** `WindowDocument` says `-1` means "the backend chooses", but the SDL
backend reads every negative place so: `_open_native_window!` gives SDL
`SDL_WINDOWPOS_CENTERED`, `_update_window_geometry!` never moves a window to a
negative place, `_place_fitted_window!` leaves such a window alone, and
`_keep_device_geometry_at_new_zoom!` does not scale its place. A monitor above or
left of the main one has negative coordinates. Also, `compute_window_place` keeps
a window inside the area of display 0 with its origin at (0, 0), so a tooltip on
a monitor to the right of the main one moves to the right edge of the main
display.

## The fixes

**Fix 1.** Before `_closes_tooltip` compares the part under a move with the
source of the tooltip, it replaces each introduced step of the move's path by the
widget path that it names. Both then name a part in the same form. A view that
maps a part of its input keeps its path, and a document part has no introduced
step, so nothing else changes.

**Fix 2.** `_can_take_key_focus` answers false for `:popup` too, so on macOS a
popup window carries the mark of `_refuse_key_focus!` and never becomes key. This
is the model the backend already has on X11: a popup never takes the focus, and
the keyboard stays in the window under it.

**Fix 3.**
- Only the place `(-1, -1)` means "the backend chooses". Every other place,
  negative or not, is a real place. A named constant and a predicate in
  `ScreenModule` say so, and the SDL backend uses them in the four places above.
- The SDL backend keeps the usable area of each display, in logical pixels, and
  reads them again when it reads the work area. `compute_window_place` keeps a
  window inside the area of the display that holds its point: the pointer for a
  tooltip, else the place of the window. A point on no display uses display 0.

**Decision: `(-1, -1)`, and not a value far off the screen.** The screen adds the
place of a window to the point of a popup or a tooltip (`ScreenToScreen.jl`), and
`show_document!` adds 40 to it. A window that the backend placed has its real
place there. A window of the headless backend keeps `(-1, -1)`, because that
backend adopts no native place. A value far off the screen would make those sums
far off too, and the web backend, which sends the place as it is, would need a
second meaning. With `(-1, -1)` no sum and no backend changes.

## Steps

The work is done in the worktree, on the branch. It lands on main only after the
owner approves.

1. ✅ Write this plan.
2. ⬜ **Fix 1, with tests.** A case in `ProjectionReferenceStepTest.jl` or a new
   tooltip case checks the comparison with an introduced reference, and a case in
   `ApplicationTest.jl` rests the pointer on an assistant button, moves to the
   same point, and finds the tooltip still open; a move to the next button closes
   it.
3. ⬜ **Fix 2, with its test.** `NativeWindowTest.jl` names `:popup` among the
   styles that never take the key focus.
4. ⬜ **Fix 3, with tests.** Cases for the predicate, for the place that SDL gets
   for a negative place and for `(-1, -1)`, and for `compute_window_place` with a
   display above, left of and right of the main one.
5. ⬜ **Run the narrow suites:** `test_native_window()`, then `test_sdl()`, the
   tooltip and screen cases of the platform, and `test_application()`.
6. ⬜ **Check on a Mac** with the script of the tester: a menu and a dropdown stay
   open, a click on an item acts, the item under the pointer lights, the arrow
   keys move in a dropdown, and a tooltip on the monitor above shows there. Check
   the assistant tooltip on Linux by hand.
7. ⬜ Write the results into this plan, and move it to `plan/done/`.

## Not in this plan

- The black first tooltip on macOS: deferred by the owner until a log from a Mac
  shows the paints and the presents of the tooltip window.
- The answer of a view naming its own part in the introduced form, which the plan
  "a view names the domain part under a point" covers.
