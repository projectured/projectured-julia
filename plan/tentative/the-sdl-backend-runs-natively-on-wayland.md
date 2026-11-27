# The SDL backend runs natively on Wayland

The owner, 2026-11-27, after a test of the IDE on SDL 3 through sdl2-compat:
"almost works, but it appears glitchy in the first place, and yeah menu popups are
unusable (in the wrong place, disappearing, etc)", then "leave the wayland and SDL3
thing behind, SDL2 works okay for now", and on GIMP: its menus leave the window
on Wayland and appear at the right place. Not now: the owner left it for later.

## What is there now

- `SDL2_jll` 2.32.10 is built with no Wayland driver: its library holds the X11
  driver only, and the strings that name Wayland are the ones that detect XWayland
  (`X11_IsXWayland`). So each window of the editor is an X11 window, and on a
  Wayland desktop it runs under XWayland.
- The General registry (local copy of 2026-11-25) has no `SDL3_jll`,
  `SDL3_ttf_jll` or `SDL3_image_jll`, and `SimpleDirectMediaLayer` 0.5.0 binds
  SDL 2 only. [one-coherent-color-set.md](../done/one-coherent-color-set.md) S.1
  found the same on 2026-10-03. The backend calls 99 functions of SDL, SDL_ttf and
  SDL_image, nearly all of them in three files.

## The test of 2026-11-27

Fedora 45 ships `libSDL2-2.0.so.0` as sdl2-compat 2.32.74 over SDL 3.4.20. Called
from a bare Julia, it lists the drivers `wayland, x11, KMSDRM, offscreen, dummy,
evdev` and picks `wayland`.

How to run against it with no change to either repository: an environment whose
`Project.toml` names `SDL2_jll` in `[deps]`, with a `LocalPreferences.toml` that
sets `[SDL2_jll] libsdl2_path = "/usr/lib64/libSDL2-2.0.so.0"`, put on the load
path: `JULIA_LOAD_PATH="@:<that folder>:@stdlib" bin/omnet_ide …`. Julia merges
the preferences of each environment of the load path that names the package. The
builder rewrites `LocalPreferences.toml` of the app package at each start, so the
preference can not go there. Packages above `SDL2_jll` compile again, once on the
way in and once on the way back.

What the owner saw: a native Wayland window, sharp text, and two faults.

1. **Stale pixels.** A pane showed the new list on the left of a vertical cut and
   the cards of an older paint on its right. Not diagnosed. The first suspect is the
   age of the back buffer (`_back_buffer_age` in
   [SdlBackend.jl](../../source/backend/sdl/SdlBackend.jl)): it asks `libEGL.so.1`
   for the current surface and assumes that it is the one SDL draws with, which
   SDL 3 on Wayland may not hold. The test that separates it is a run with
   `PROJECTURED_PARTIAL_RENDER=0`; it was not run.
2. **Popups at the wrong place, and closing.** The SDL 2 API has no parent for a
   popup: a popup is a top-level window at a place on the screen. The backend
   computes that place as the place of its window and an offset, and a Wayland
   client does not know the place of its window (SDL answers 0, 0). So the
   compositor places the popup where it likes, and closes it when the focus moves.

## How GIMP does it

GTK opens a menu as an `xdg_popup` of its parent window, with an `xdg_positioner`:
a box in the frame of the parent to stand below, and what to do when the screen has
no room (flip, slide). The compositor knows the screen and places the popup, so the
menu leaves the window and stands at the right place, and the client never needs a
place on the screen.

SDL 3 has the same call: `SDL_CreatePopupWindow(parent, offset_x, offset_y, flags)`,
an offset in the frame of the parent, which on Wayland makes an `xdg_popup`.

## The idea

1. The backend runs on the SDL 3 API itself, not through sdl2-compat, which can
   not name a parent. It needs bindings: an `SDL3_jll` and its `ttf` and `image`
   kin in Yggdrasil, or bindings generated from the headers.
2. A popup opens with `SDL_CreatePopupWindow`, at an offset in the frame of the
   window that opens it. The screen layer has that offset already: an
   `OpenPopupOperation` carries the box in the frame of its opener, and only the
   last step, `_open_popup_window` in
   [ScreenToScreen.jl](../../source/platform/screen/ScreenToScreen.jl), adds the
   place of the window.
3. On Wayland the compositor flips and slides a popup at the edge of the screen in
   place of `compute_anchored_place`. Not checked: which constraint adjustments
   SDL 3 asks the compositor for.
4. The stale pixels of the test are found and fixed.

[architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
PAR-MANY-WINDOWS holds throughout: a popup stays a window of its own.

## Questions before it is a plan

- Whether an `SDL3_jll` exists by then, or the bindings are this project's to make.
- Whether a binary that ships SDL 3 still runs where the desktop has no Wayland,
  which SDL 3 handles by falling back to X11.
- Fault 1: the run with `PROJECTURED_PARTIAL_RENDER=0`.
