# A tooltip opens beside the pointer at any density

> **Status (2026-10-09): in progress.** The owner reported the fault and asked for
> the fix on 2026-10-09. Branch `tooltip-place`, worktree
> `projectured-julia-tooltip-place`. Not on main and not pushed.

## The fault

On the owner's display, which has the density 2 (`Xft.dpi: 192`, 5120×2880), a
tooltip of the toolbar often opens and closes at once. Sometimes it stays.

The tooltip window opens under the pointer. X11 then sends a leave to the main
window, and `TooltipWindowProjection` closes the tooltip on `WindowLeave`
(`_closes_tooltip`). A move of the pointer in the tooltip window closes it too.

## The cause

Above the backend, every coordinate is in logical pixels. The SDL backend gives
and takes three values in device pixels:

- the position of a window: `SDL_CreateWindow`, `SDL_SetWindowPosition` and
  `SDL_GetWindowPosition` (`_adopt_native_position!`) use `w.x` and `w.y` with no
  conversion;
- the pointer: `get_pointer_position` returns `SDL_GetGlobalMouseState` with no
  conversion;
- the work area: `Display.width` and `Display.height` are the device size over
  the density, so they are in pixels at the zoom 1, not at the ratio.

The screen adds the window position (device) to the dwell point (logical), and
the tooltip adds its offset (logical). The window gets a device size of the
logical size times the ratio. At the ratio 2, a pointer at the logical point
`(100, 40)` of a window is at the device point `(wx+200, wy+80)`, and a 150×32
tooltip opens at `(wx+116, wy+60)` with the device size 300×64: it covers the
pointer. `compute_window_place` finds the overlap and moves the tooltip left, but
with the logical width, so the tooltip still covers the pointer. A tooltip in the
right half of the screen moves to the middle, because the work area is compared
with a device `x`. A popup opens above and to the left of the pointer.

At the density 1 and the zoom 1 all three units are the same, so the fault does
not show there.

## The fix

The SDL backend converts at its boundary, so that the `x` and the `y` of a
`WindowDocument` and the pointer are logical, as the size of a window already is.
The ratio is `get_device_pixel_ratio(backend.display)`, the density times the
zoom.

1. ✅ Write this plan.
2. ⬜ Convert in the SDL backend, and test it:
   - `_open_native_window!`: the position to device pixels;
   - `_update_window_geometry!`: the position for `SDL_SetWindowPosition` to
     device pixels;
   - `_adopt_native_position!`: the result of `SDL_GetWindowPosition` to logical
     pixels, at the ratio of this frame;
   - `get_pointer_position`: to logical pixels;
   - `_place_fitted_window!`: the work area at the ratio, that is the size of the
     `Display` over the zoom;
   - `_keep_device_size_at_new_zoom!`: scale the position by the old zoom over
     the new one too, as it scales the size, so a window does not move at a new
     zoom.
   - Docstrings: the `x` and `y` of `WindowDocument`, and `get_pointer_position`
     in `BackendInterface.jl`, say "logical pixels of the screen".
   - Tests: `test_native_window` and `test_device_config` read the native
     position in the new unit; a new test checks the round trip of a position at
     a ratio that is not 1.
3. ⬜ A live check at the density 2: a dwell on a button of the toolbar opens a
   tooltip whose native rectangle does not hold the point of the dwell.
4. ⬜ The owner hovers the toolbar with the real pointer.

## Decisions

- **The unit of a window position is the logical pixel of the screen.** The
  `Display` docstring and the comment of `_to_device` already say that documents
  and events are in logical pixels and that only the native side is in device
  pixels. The web backend works in CSS pixels, which are logical. So the SDL
  backend is the one place that breaks the rule, and the fix goes there, not in
  the screen or the tooltip.
- **`Display.width` keeps its meaning** (pixels at the zoom 1). `get_display_size`
  gives the same value, and `WindowScene` sizes a main window with it, so the
  placement code converts it, and the field stays.
