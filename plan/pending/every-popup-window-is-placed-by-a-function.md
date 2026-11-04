# Every popup window is placed by a function

> **Status (2026-11-04):** pending, not approved. The owner answered Q1 to Q3 on
> 2026-11-04. It follows
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
reports a place of a window with a frame that is not the place that the backend
asked for, the backend writes that place into `x` and `y` and `nothing` into
`placement`. The screen then prints the window again without a placement. A
`:popup` or a `:tooltip` window has no frame, so the rule does not apply to it.

**D5: a popup names its part by a reference.** `OpenPopupOperation` holds
`source`, the reference of its part from the input of the reader that answers it,
in place of `x` and `y`. It gets `operation_reference` and `retarget_operation`,
so each reader above moves the reference as it does for every operation with a
reference; the tooltip and the right-click menu work this way now. Its
`map_operation_position` goes. `ScreenToScreen` makes from it an
`OpenWindowOperation` whose placement is below the part at `windows[i].content`
and the steps of `source`. A submenu and the list of a select answer it with the
gap that they have now.

**D6: a dialog stands at the center of a window.** The button of a `WidgetDialog`
answers `OpenPopupOperation` with the side `:center`, `style = :dialog`,
`modal = true` and the size of now, so the dialog opens at the center of the
window that holds the button. So `OpenPopupOperation` also holds `side`, `style`
and `modal`. A dialog that a callback opens has no part: the Open file dialog and
the "Filter by values" lists open with a placement at the center of the first
window of the screen, the main window.

**D7: the old code goes.** `map_operation_position(::OpenPopupOperation)`,
`find_part_place`, and the place code of the backend for a popup
(`_place_fitted_window!` and the call of `compute_window_place` from it) go. The
rule of `compute_window_place` and `_find_display_area` moves into the helper of
D2. The backend still centers a normal window with `x = -1`, as the main window.

## The steps

Each step is a commit, and the plan records what each step finds.

1. **The areas and the helper.** D1, D2, D3 and D4. Tests: `test_window_placement()`
   with new cases (a flip, a slide, two displays, no areas, a move by a person
   ends a placement) and `test_native_window()`, which checks the write of the
   areas.
2. **The tooltip and the right-click menu.** Both open with a placement: beside
   the point, else below the part. Tests: `test_tooltip()` and
   `test_context_menu_window()`, with a case at the edge of an area.
3. **The submenu and the list of a select.** D5. Tests: `test_widget_menu()`,
   `test_widget_select_dropdown()`, `test_widget_menu_keys()` and
   `test_window_shell()`.
4. **The dialogs.** D6. Tests: `test_file_dialog()`, the dialog test of the widget
   slice, and the value list tests of the data frame and the roster.
5. **The old code goes.** D7. The documents `popup-window.md`, `screen.md`,
   `tooltip.md` and `context-menu.md` describe one way of placement. The naming
   guard, the layering guards of the slices that changed, `test_native_window()`,
   and a check of the pixels with the offscreen renderer: a menu of the menu bar
   and a right-click menu near the bottom edge of an area flip above.

## Limits

- A dialog that a callback opens stands over the first window of the screen,
  also when a person works in another window. The screen does not record which
  window has the focus.
- The web backend writes no areas, so it keeps each place that a placement asks
  for.
- A popup that is taller than the area of its display slides to the top of the
  area, and the part below the area is cut. A popup does not get smaller to fit.
