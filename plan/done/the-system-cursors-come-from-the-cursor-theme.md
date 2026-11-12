# The system cursors come from the cursor theme

## Problem

On a screen at 200%, the SDL backend shows the arrow, the text bar and the
pointing hand much smaller than the cursors of other applications, and the
open and the closed hand much larger.

Cause, found on this machine (GNOME, XWayland, `Xcursor.theme: Yaru`,
`Xcursor.size: 48`, `Xft.dpi: 192`):

- SDL asks the Xcursor library for a themed cursor (`XcursorLibraryLoadCursor`),
  and then falls back to `XCreateFontCursor`, which also asks the Xcursor
  library first.
- The Xcursor library of `Xorg_libXcursor_jll` searches only
  `~/.local/share/icons:~/.icons:/workspace/destdir/share/icons:/workspace/destdir/share/pixmaps`.
  `/workspace/destdir` is the prefix of the build machine. The themes of the
  system are in `/usr/share/icons`, so the library finds no theme.
- So the X server shows its built-in cursors of the core cursor font, which
  are small and do not follow the scale of the screen.
- The open and the closed hand are glyphs of the Lucide font that the backend
  draws at 22 logical pixels × density × zoom, so they follow the scale.

A probe of the library with `XcursorLibraryLoadImage(name, "Yaru", 48)` finds
no `default`, `pointer`, `text` or `left_ptr` cursor; with
`XCURSOR_PATH=/usr/share/icons`, it finds each one at 48×48.

## Design

The SDL backend sets `XCURSOR_PATH` in `__init__`, the same way it sets
`XLOCALEDIR` for the locale data of Xlib:

- A value that the user set wins.
- Only where `Xorg_libX11_jll` is available, so a system with no X11 is not
  touched.
- The value is the search path that a system build of libXcursor has, with the
  XDG data folders: `$XDG_DATA_HOME/icons`, `~/.icons`, `<each of
  $XDG_DATA_DIRS>/icons`, `/usr/share/pixmaps`. The defaults of the XDG base
  directory specification apply when a variable is not set or is empty.
- The library reads the variable once, at its first search, so the variable
  must be set before SDL makes the first cursor. `__init__` runs before any
  SDL call.

### The glyph hands

With the themed cursors, the visible size at `Xcursor.size: 48` is: Yaru
`default` 28×42, `pointer` 38×39, `grab` 38×40, `grabbing` 35×32. The Lucide
open hand at 22 × 2 = 44 pixels is 41×41, and 45×45 with its outline of 2
pixels on each side: about 15% larger than the hand of the theme. It also grew
with the zoom of the editor at the time when the backend first showed it, while
the cursors of the system do not follow the zoom.

Decision (mine, approved by the owner in the conversation only as "make it
smaller if it is still too large"): `_GLYPH_CURSOR_SIZE` is 19, and the glyph
follows only the density of the display, not the zoom. At 19 × 2 = 38 pixels the
open hand is 36×35 and 40×39 with its outline, which is the size of Yaru
`grab`. A size from the cursor size of the system (`XCURSOR_SIZE`,
`Xcursor.size`) is the more exact model, but it needs a read of X resources or
a call into libXcursor, so it is not part of this fix.

## Steps

1. [x] Set `XCURSOR_PATH` in `__init__` of the SDL backend, and test the value
   and that the library in the process reads it. Done: `_set_x11_cursor_path!`
   next to `_set_x11_locale_directory!`, and a test set in
   `test_sdl_pointer_shape`. With the offscreen driver the test passes 21 of 21:
   17 assertions before, and 4 new ones, which include the check that
   `XcursorLibraryPath()` of the library in the process equals
   `ENV["XCURSOR_PATH"]`.
2. [x] Check the cursors in the live editor, and compare the size of the glyph
   hands with the themed cursors. Done:
   - A script on the real display (`DISPLAY=:0`, no window) loads
     `ProjecturedSDL` and asks the library of the process with
     `XcursorLibraryLoadCursor` for `default`, `text`, `pointer`, `ew-resize`,
     `not-allowed` and `wait`, which are the names that SDL asks for. Each one is
     a themed cursor of Yaru. Before the fix, a probe of the same library found
     none of them.
   - The size of the themed cursors follows the X resources, which GNOME
     changes with the monitor: `Xcursor.size: 48` and `Xft.dpi: 192` with the
     monitor at 200% on, `Xcursor.size: 24` and `Xft.dpi: 96` when the X server
     has no monitor. The backend sets no size.
   - The glyph hands get the decision under "The glyph hands": 19 logical
     pixels, at the density only. `test_sdl_pointer_shape` passes 21 of 21 with
     that change too.
