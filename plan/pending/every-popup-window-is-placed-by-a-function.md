# Every popup window is placed by a function

> **Status (2026-11-04):** steps 1 to 5 done on the branch `popup-placement`, not
> landed; the recording of step 5 waits for the owner. The owner answered Q1 to Q3
> and approved the plan on 2026-11-04. It follows
> [ctrl-p-finds-a-file-by-its-name.md](../done/ctrl-p-finds-a-file-by-its-name.md),
> which made the placement function and gave the context menu window the place
> at the top of a part. The owner chose this order on 2026-11-03 (Q11 of that
> plan).

## The goal

Every popup window of the editor stands where a placement function puts it, and
no popup has its own code for its place. Then one way of placement exists, and
the old code goes away.

## What changes

The first plan moves the context menu window. The other popups place their
windows with their own code now
([popup-window.md](../../documentation/package/platform/screen/popup-window.md)):

| Popup | Its place now | Its placement |
| --- | --- | --- |
| Tooltip | `TooltipWindowProjection` adds `offset` to the point, else below the part | beside the point, else below the part |
| Right-click menu | `ContextMenuWindowProjection` opens it at the point, else below the part; only the place at the top of a part is a placement | beside the point, else below the part |
| Submenu of a menu item | `OpenPopupOperation` in the frame of the item, below it; each reader on the way up moves the position (`map_operation_position`) | below the item |
| List of a `WidgetSelect` | the same as a submenu | below the select |
| `WidgetDialog` | a fixed box, `x = 80, y = 60`, 480 × 320 | in the center of the window of the part |
| A `:floating` dialog: the Open file dialog, and the "Filter by values" list of a data frame and of a roster | `x = -1`: SDL centers it on the main display | in the center of the window that opens it |

Every submenu in the code is a menu of the menu bar (File, View, Help). No menu
opens a submenu inside it: such a submenu would replace its menu, because both
use the window id `:widget_popup`.

## Questions before it starts

The design of each step is open until the owner answers its questions, one at a
time, after the first plan lands. The first plan landed on 2026-11-04.

**Q1: what keeps a popup inside the screen?** Now the backend fits the size of a
popup to its content, then moves it inside the usable area of its display, and a
tooltip beside the pointer. Only the backend knows the areas of the displays. A
placed window skips that move, so a placed submenu at the right edge of a display
would open off the screen.

Answer (the owner, 2026-11-04): **A.** The backend writes the usable areas of the
displays into the screen document, as it writes the place and the size of each
window. The placement reads them and keeps its window inside, with one helper of
the screen slice, so the backend keeps no code that places a popup. The backend
writes the fitted size before it reads the place, so the place is correct in the
first frame. Not chosen: B, a placement that answers a wish and a rule for a lack
of room, which the backend applies as the last step, as Wayland does.

**Q2: when the first side of a popup has no room, where does it go?** A menu of
the menu bar opens below its item, the list of a select below the select, and a
right-click menu and a tooltip below and right of the pointer. The question named
a submenu right of its item; no such submenu exists, and the answer holds for the
menus of the menu bar. Now the backend only slides a
popup inside the screen, so it covers what opened it.

Answer (the owner, 2026-11-04): **A, flip, then slide.** The popup goes to the
opposite side first, and slides inside the screen only when that side has no room
either, as Qt, GTK and Windows do. Each placement gives the box that its popup
belongs to and its first side, and the one helper of the screen slice flips and
slides. The tooltip goes to the other side of the pointer and does not cover it, as
one case of the same rule. Not chosen: B, slide only.

**Q3: does a dialog stay at the place that its placement gives?** A placed window
follows its placement at each change, so a person can not move it. The dialogs
with a frame now open at the center of the main display, and a person can move
and resize them.

Answer (the owner, 2026-11-04): **A, the move of the person wins.** A dialog
opens at the center of the window that opens it. When a person moves or resizes
a placed window, its placement stops. Popups and tooltips have no frame, so the
rule does not apply to them. Not chosen: B, a dialog that always stays at the
center of its window.

## The design

The names below are proposals. The naming guard checks them in each step.

**D1: the screen holds the areas of the displays (Q1).** `ScreenDocument` gets
the field `display_areas::Vector{NTuple{4,Int}}`: the usable area of each display,
`(x, y, width, height)`, the main display first, in the coordinates of the place
of a window, which are logical pixels at the zoom of the display. The SDL backend
writes the field when it reads the areas: at the start, at a change of the
displays and at a change of the zoom. It writes only a value that changed. The
output screen shares the cell of its input, as the fields of a window do, so a
placement reads `context.screen.display_areas`. A backend that writes no areas
leaves the vector empty, and then the helper of D2 keeps the place that the
placement asks for.

**D2: one helper flips and slides (Q2).** A function of the screen slice,
`compute_anchored_place(context, anchor; side, gap) -> (x, y)`, puts the window
of `context` on `side` of `anchor`, a box in screen coordinates; a point is a box
of no size. `side` is `:below`, with the left edges aligned, or `:center`. It uses
the area of the display that holds the anchor, or the first area. On the axis of
`side`, a window that crosses the edge of the area goes to the opposite side of
the anchor, and slides inside the area when that side has no room either. On the
other axis it slides inside the area. A `:center` place only slides. The rule of
the backend that keeps a tooltip off the pointer is this rule with the point as
the anchor: the window is on one side of the point, so it never holds it.

**D3: the size of the window.** The helper reads the size of the window of the
context. The backend fits the size to the content before it reads the place, and
the size cell of an output window is the cell of its input, so the read of the
place in the same frame computes it again with the fitted size. A placement must
not make its bounds from the size of its window, because the size comes from the
bounds.

**D4: the move of a person ends the placement (Q3).** When the window manager
reports a place of a placed window with a frame that is not the place that the
backend asked for, the backend replaces its placement with
`make_fixed_placement(x, y; minimum_size, maximum_size)`, a placement that answers
that place with the bounds of the window. When a person resizes such a window,
`WindowManagingProjection` answers the resize together with the same write, at the
place where the window stands. A `:popup` or a `:tooltip` window has no frame
(`has_window_frame`), so the rule does not apply to it.

*Found in step 1:* the plan first wrote `nothing` into `placement` and the place
into `x` and `y`. That does not work: the `x` and `y` of a placed window are
computed cells of the screen projection, which the window manager replaces only
for an operation, and the backend gives no operation. A write of a fixed
placement uses the computation that exists, needs no new event, and gives a
person the same result.

**D5: a popup stands at the box of its part in its window.** `OpenPopupOperation`
keeps `x` and `y`, now the top left corner of the box of its part in the frame of
the reader that answers it, and each reader above moves them into its own frame
with `map_operation_position`, as now. It also holds `anchor_size`, the size of
that box, and `gap`. `ScreenToScreen` makes from it an
`OpenWindowOperation` whose placement finds the window that answered it on the
screen of the context, adds the place of that window to the box, and calls
`compute_anchored_place`. So the popup follows its window when the window moves.
A submenu and the list of a select answer it with the box of their control and
the gap that they have now.

*Found before step 3:* the plan first gave `OpenPopupOperation` a reference of its
part, in place of `x` and `y`, which each reader above would map. That drops the
popup of a part that a view made: the kernel drops an operation whose reference has
no place in the input of a projection (`has_introduced_step`), and omnet-julia
makes a `WidgetSelect` in a view (`LegacyTestRunnerToWidget.jl`). The operation is
self-contained on purpose, so it passes up through every view, and the box in the
frame of the window keeps that.

**D6: a dialog stands at the center of a window.** A dialog at the automatic place
takes the placement at the center of the window that opens it, and the button of a
`WidgetDialog` opens its dialog at the automatic place. A dialog that a callback
opens has no window: the Open file dialog and the "Filter by values" lists stand
at the center of the first window of the screen, the main window. Step 4 records
how.

**D7: the old code goes.** `find_part_place` and the place code of the backend for
a popup (`_place_fitted_window!` and `compute_window_place`) go. The rule of
`compute_window_place` and `_find_display_area` is in the helper of D2.
`map_operation_position(::OpenPopupOperation)` stays: it moves the box of a popup
as it moves every point of an operation. The backend still centers a normal window
with `x = -1`, as the main window.

## The steps

Each step is a commit, and the plan records what each step finds.

1. ✅ **The areas and the helper.** D1, D2, D3 and D4. Tests: `test_window_placement()`
   with new cases (a flip, a slide, two displays, no areas, a move by a person
   ends a placement) and `test_native_window()`, which checks the write of the
   areas.
   *Done 2026-11-04:* `test_window_placement` 41, `test_window_fit` 15,
   `test_context_menu_window` 69, `test_window_wrappers` 74 and every set of
   `test_native_window` pass, with the new sets "a frame writes the areas of the
   displays into the screen" (3) and "a person moves a placed window with a frame,
   and it stays there" (5). `find_display_area` moved from the backend to the
   screen slice in this step, and `compute_window_place` of the backend uses it.
   The new field gives `ScreenDocument` one more type parameter, so 8 recorded
   calls of ProjecturedSDL no longer resolve. With the 78 that were stale before,
   86 of 838 pass the limit of 10%, and the precompile of ProjecturedSDL warns.
   Step 5 records the lists again.
2. ✅ **The tooltip and the right-click menu.** Both open with a placement: beside
   the point, else below the part. Tests: `test_tooltip()` and
   `test_context_menu_window()`, with a case at the edge of an area.
   *Done 2026-11-04:* `test_context_menu_window` 71, `test_tooltip_window` 58,
   `test_tooltip`, `test_tooltip_note` 44, `test_tracking_screen`,
   `test_widget_context_menu` 20, `test_window_wrappers` 74 and
   `test_window_placement` 41 pass. The new sets: "a menu with no room below the
   pointer opens above it" and "a tooltip with no room below the point goes above
   it". The reference of a part from the screen is `find_screen_reference` of the
   screen slice, which both wrappers use. `show_window_layers` keeps the placement
   of a window that F2 opens again. The tests read the place of a placed window
   from the output screen, because the input window holds only the place where it
   stands while its placement answers none.
3. ✅ **The submenu and the list of a select.** D5. Tests: `test_widget_menu()`,
   `test_widget_select_dropdown()`, `test_widget_menu_keys()` and
   `test_window_shell()`.
   *Done 2026-11-04:* `test_widget_menu` 44, `test_widget_select_dropdown` 38,
   `test_widget_menu_keys` 36, `test_widget_popup_example` 19, `test_widget_action`
   46, `test_window_placement` 41, `test_window_shell` 149, `test_window_wrappers`
   74 and `test_context_menu_window` 71 pass. The new set: "the list of a select
   stands below the select, follows its window, and goes above it with no room
   below". `map_operation_position` moves both corners of the box, so a box in a
   zoomed pane has the size that it is drawn at; the gap stays in the pixels of the
   window. `find_window_box` gives the box of a printed window, so a popup of a
   placed window follows the place that the placement of that window computes.
4. ✅ **The dialogs.** D6. Tests: `test_file_dialog()`, the dialog test of the widget
   slice, and the value list tests of the data frame and the roster.
   *Done 2026-11-04:* `test_window_placement` 46, `test_widget_popup_example` 23,
   `test_widget_dialog` 18, `test_widget_action` 46, `test_file_dialog` 22,
   `test_window_wrappers` 74, `test_roster_header` 41, `test_widget_column_header`
   48 and `test_data_frame_filter` 81 pass. The new sets: "a dialog with no place
   of its own stands at the center of the main window" and "the dialog of a button
   stands at the center of its window".
   *Found in this step:* `OpenPopupOperation` needs no `style` and no `modal`. Every
   dialog opens with `OpenWindowOperation`, and the dialogs with a frame use the
   automatic place `(-1, -1)`. So one rule places them: a window of the style
   `:floating` or `:dialog` at the automatic place with no placement takes
   `make_window_center_placement`. `ScreenToScreen` gives it the window whose
   content opened it, and the window manager gives it the first window of the
   screen when no window opened it, as for a callback. The button of a
   `WidgetDialog` opens at the automatic place in place of `(80, 60)`. A normal
   window at the automatic place, as the main window, stays the backend's to
   place.
5. **The old code goes.** D7. The documents `popup-window.md`, `screen.md`,
   `tooltip.md` and `context-menu.md` describe one way of placement. The naming
   guard, the layering guards of the slices that changed, `test_native_window()`,
   and a check of the pixels with the offscreen renderer: a menu of the menu bar
   and a right-click menu near the bottom edge of an area flip above. The recorded
   calls of each package whose list names a changed type are recorded again
   (`record_package_calls!`), so no precompile warns about stale calls.
   ✅ *Done 2026-11-04, except the recording:* `test_window_placement` 55,
   `test_native_window` (with "a place that SDL gives back rounded is no move of a
   person" 3 and the zoom step in "a person moves a placed window" 8),
   `test_widget_menu` 44, `test_widget_select_dropdown` 38,
   `test_widget_popup_example` 23, `test_window_wrappers` 74,
   `test_context_menu_window` 71, `test_widget_dialog` 18, `test_file_dialog` 22
   and `test_tooltip_window` 58 pass.
   - `find_part_place` and `PartPlace.jl` went; `_find_part_box` is in
     `WindowPlacement.jl`, and two tests read it as their oracle. The backend lost
     `_place_fitted_window!`, `compute_window_place` and `_POINTER_GAP`. The cases of
     the monitors above, left and right moved from the SDL test to
     `test_window_placement`.
   - The documentation writer updated `sdl.md`, `reference.md`, `graphics.md`,
     `popup-window.md`, `screen.md`, `tooltip.md`, `context-menu.md` and
     `widget.md`.
   - The naming guard passes. `test_sdl_layering` passes 7 of 7.
     `test_platform_layering` fails 1 of 7, with the four errors that main has
     (filechange once, roster twice, shell once) and none of this plan.
   - The pixel check: with the bottom edge of the area 100 pixels below the top
     of the main window, the File menu (206 × 142) opens above the menu bar, at
     y = 158 for a window at y = 300; a right-click menu (70 × 70) at the point
     (120, 110) with the edge at y = 140 opens above the point, at (120, 40).
   - A review of the whole diff found three faults, all fixed with a test each.
     (1) At a new zoom the backend scaled the place of a window with no placement,
     but not a fixed placement, so a dialog that a person moved jumped, maybe off
     the display: `make_fixed_placement` now answers a `FixedPlacement`, which the
     zoom step scales. (2) Below the zoom 1 a window unit is larger than a logical
     pixel, so a place came back from SDL 1 pixel off and looked like a move of a
     person: `_adopt_native_position!` compares the device place that it sent.
     (3) A popup with the id of the window that opened it, as a submenu in a menu
     of the same id, would read the place of its own window in a cycle: it takes
     the place of now. The review also removed what no caller used:
     `OpenPopupOperation.side` (its `:center` case named the whole window, not the
     box) and the bounds keywords of `compute_anchored_place`.
   - *The recording is not done.* `record_package_calls!("ProjecturedSDL")` ends the
     warning, but it made the list grow from 794 to 1752 lines: of the 1130 new
     calls only 188 name a type that this plan changed, and the rest are general
     calls of the cells and the walks of documents. So the lists of the packages
     below ProjecturedSDL are stale for other reasons, and a recording of one
     package takes their calls in. That list is not kept. The fix is
     `record_repository_calls!()`, which records each package after the packages
     that it depends on; it is a long run of its own, for the owner to decide. Until
     then the precompile of ProjecturedSDL warns: 87 of its 838 calls do not
     resolve, 9 of them from this plan, against 78 before it.

## Limits

- A dialog that a callback opens stands over the first window of the screen,
  also when a person works in another window. The screen does not record which
  window has the focus.
- The web backend writes no areas, so it keeps each place that a placement asks
  for.
- A popup that is taller than the area of its display slides to the top of the
  area, and the part below the area is cut. A popup does not get smaller to fit.
- A window manager of X11 that moves a dialog with a frame when it first shows
  it, as some do, ends its placement at once: the dialog then stays where it
  opened, and does not follow the window that opened it.
- An open tooltip or right-click menu keeps the point of the old zoom at a new
  zoom, so it moves; it stays inside the area of its display.
