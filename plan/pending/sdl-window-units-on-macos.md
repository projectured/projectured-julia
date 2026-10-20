# The SDL backend converts window units with the pixels of one unit

## The problem

A colleague ran the OMNeT++ IDE on a MacBook Pro M3 Max with a Retina screen
and an external 4K monitor (2026-10-20). Two faults showed:

1. Every font and every part of the window is twice as large as it must be.
2. While a code unit runs on its own thread, the whole picture shrinks into the
   top-left quarter of the window, and it jumps back when the unit ends.

## The cause

SDL counts the size and the place of a window, a resize event and a mouse
position in *window units*. On X11 and Windows a window unit is one device
pixel. On macOS, and with the Wayland driver, a window unit is one point, and
the renderer output has two device pixels for each point on a Retina screen.

The backend converts every window value with the device pixel ratio of its
`Display` (the density times the zoom), with `_to_device` and `_to_logical`.
That is right only where a window unit is one device pixel. On a Retina screen:

- The first window opens with 1000 points, before the density is known.
- The window probe finds the density 2: 2000 pixels of output over 1000 points.
- `_settle_native_windows!` reads the 1000 points and divides them by 2, so the
  document is laid out for 500 logical pixels.
- The frame draws a picture of 500 × 2 = 1000 pixels, and the copy to the window
  stretches it over 2000 pixels: everything shows twice as large. A click still
  hits its part, because the mouse position is divided by the same 2.
- A held frame copies the same picture 1:1 to the top left
  (`_present_held_window!`), so the picture fills one quarter of the window.

## The model

Two numbers, and each conversion uses the one that its unit needs:

- The **device pixel ratio**: device pixels in one logical pixel. It sizes the
  picture and the fonts. It does not change.
- The **pixels per window unit**: device pixels in one SDL window unit. Each
  window measures it when it opens, as the width of its renderer output over the
  width of the window: 1 on X11 and Windows, 2 on a Retina screen.

A value in SDL window units converts with the **window unit ratio**, the device
pixel ratio over the pixels per window unit. On a Retina screen at zoom 1 that is
2 / 2 = 1, so a point is a logical pixel. On X11 the pixels per window unit is 1,
so the conversions there do not change.

A conversion with no window — the bounds of the display, the global pointer and
the size of a new window — uses the pixels per window unit of the last window
that opened, and 1 before any window opened. On macOS the density is also not
known before the first window, so the ratio there is 1 / 1, which is correct.

## Steps

1. ~~The resources of a window hold its pixels per window unit~~ **Done.** A field
   of `SdlWindowResources`, measured in `_open_native_window!`; the probed value
   for the conversions with no window; and `_get_window_unit_ratio`, which gives
   the window unit ratio of a window, of a window id, or of no window. The
   creation of a window in `_open_native_window!` already converts with the ratio
   of no window, because that function is where the value is measured. The
   offscreen paint state and the two test constructions pass 1.
2. ~~Every SDL window value converts with the window unit ratio~~ **Done.**
   `_native_window_size`, `_update_window_geometry!`,
   `_adopt_native_position!`, the resize, button, motion and wheel events of
   `_poll_window_input`, `_queue_pointer_move!`,
   `_update_pointer_shape_at_pointer!`, `get_pointer_position`, the display
   bounds of `get_sdl_display_size` and the size of a glyph cursor. The picture,
   the fonts and the held frames keep the device pixel ratio. Each event of
   `_poll_window_input` converts with the ratio of its own window, so the one
   ratio at the top of that function is gone. Two conversions keep the density,
   because their values are device pixels: the monitor size from `xrandr`, and
   the size of the drawing target.
3. ~~Tests~~ **Done.** The new testset of
   [NativeWindowTest.jl](../../test/backend/sdl/backend/NativeWindowTest.jl)
   opens a window on X11 and gives it two pixels per window unit, as a window on
   a Retina screen measures, at density 2. The size of its document reaches SDL
   unchanged, the size of SDL reads back as the size of the document, and a press
   arrives at its own place. The same testset with one pixel per window unit
   checks the X11 case at density 2: twice the size, half the place. All of
   `test_device_config`, `test_dirty_rect`, `test_laid_out_canvas`,
   `test_input_coalescing`, `test_sdl_pointer_shape`, `test_native_window` and
   `test_sdl_held_frames` pass on X11 (21 testsets, 0 fail, 0 error). The macOS
   case itself can not run here: this machine has X11 at 96 DPI and no Wayland
   compositor.
4. Documentation. [sdl.md](../../documentation/package/backend/sdl/sdl.md)
   says the two numbers and the limit below.

## Limit

A window measures its pixels per window unit when it opens. A window that moves
to a screen with another number of pixels per point keeps the value of its first
screen until it opens again. The density of the process is one value too, so a
mixed setup draws at the density of the first window. This plan does not change
that; most external 4K monitors on macOS also run at two pixels per point.
