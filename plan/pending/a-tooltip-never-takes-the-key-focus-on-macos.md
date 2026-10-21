# A tooltip never takes the key focus on macOS

> **Status (2026-10-21): step 2 done, on the branch `tooltip-never-key` in the
> worktree `projectured-julia-tooltip-never-key`, not on main.** The owner asked
> for this plan on 2026-10-21, after a test on macOS confirmed the cause, and
> asked for the implementation the same day. Step 3 needs a Mac.

## The fault

On macOS a click on the IDE window is lost after a tooltip opened. The tooltip
itself shows for only 15 to 60 ms, so a person sees at most a flicker.

A tester on macOS posted pointer moves and clicks with `CGEventPost` and read the
SDL event log (`SDL_EVENT_LOGGING=1`):

| Click-through | Monitor | Click after a tooltip | Click before a tooltip |
|---|---|---|---|
| off | main | 9 of 9 lost | 8 of 8 arrived |
| on | main | 4 of 4 arrived | 3 of 3 arrived |
| off | second | 4 of 4 arrived | not tested |

Every lost click shows the same order of events:

1. Window 1, the IDE window, gets `FOCUS_LOST` and `LEAVE`, and the tooltip
   window gets `FOCUS_GAINED` and `SHOWN`.
2. The tooltip window gets `HIDDEN` and `FOCUS_LOST` 15 to 60 ms later.
3. Window 1 gets no `FOCUS_GAINED`, so no window of the IDE has the key focus.
4. At the click, window 1 gets `ENTER` and `FOCUS_GAINED`, and no
   `SDL_MOUSEBUTTONDOWN` comes.

On the second monitor window 1 gets `FOCUS_GAINED` about 20 ms after the tooltip
hides, so the clicks arrive. There the tooltip opens and hides again about every
0.6 s while the pointer rests on the button.

## The cause

SDL 2.32.10 on Cocoa makes every window that it shows the key window:

- `Cocoa_ShowWindow` always calls `makeKeyAndOrderFront:`. The Cocoa code does
  not read `SDL_WINDOW_TOOLTIP`, `SDL_WINDOW_POPUP_MENU` or
  `SDL_HINT_WINDOW_NO_ACTIVATION_WHEN_SHOWN`.
- `SDLWindow` answers `YES` to `canBecomeKeyWindow` and `canBecomeMainWindow`,
  also for a borderless tooltip.
- `acceptsFirstMouse:` answers `NO` unless `SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH` is
  set. AppKit uses a click on a window that is not key only to make it key, and
  SDL never gets that click.
- `windowDidResignKey:` takes the mouse focus from window 1. That sends
  `SDL_WINDOWEVENT_LEAVE`, although the pointer did not move.

Our own code then closes the tooltip at once. `_closes_tooltip` in
`TooltipWindow.jl` closes it on any `WindowLeave`, and the backend destroys the
window in the next frame. SDL closes the `NSWindow`, and AppKit chooses the next
key window by its own rules. On the main monitor it chose none. On the second
monitor it chose window 1. SDL then sent a move at the pointer, and the
`WindowLeave` had reset `DwellRecognition`, so the move started a new dwell: that
is the loop of 0.6 s. Why AppKit chooses differently on the two monitors is not
known, and the fix does not depend on it.

On X11 the fault does not show. SDL makes a tooltip window override-redirect,
the window manager gives it no focus, and a click on a window that is not
focused still arrives.

## The fix

On macOS the `NSWindow` of a `:tooltip` window answers `NO` to
`canBecomeKeyWindow` and `canBecomeMainWindow`. The window then never takes the
key focus. `SDL_ShowWindow` stays as it is: `makeKeyAndOrderFront:` on a window
that can not become key only orders it to the front. This is the expected
behaviour of AppKit, and step 3 checks it. So window 1 keeps the key
focus, SDL sends no `LEAVE`, the tooltip stays until the pointer leaves its part,
and the next click arrives.

A tooltip takes no input of its own. Its keys, F2 and Shift+F2, come through the
window under it, and a press anywhere closes it. So a tooltip window loses
nothing when it can not become key.

The mechanism is the Objective-C runtime, through `ccall`, as
`_macos_drop_activation_policy_to_accessory!` in `SdlBackend.jl` already uses it:

- **The `NSWindow`.** `SDL_GetWindowWMInfo` fills an `SDL_SysWMinfo`. The binding
  has no type for it, so the backend passes a buffer of 72 bytes with the version
  of the linked SDL in its first 3 bytes. On Cocoa the subsystem at byte 4 is
  `SDL_SYSWM_COCOA` (4), and the `NSWindow` pointer is at byte 8
  (`_find_native_window_handle`).
- **The answer.** Once a process, `class_replaceMethod` puts one `@cfunction`,
  `_answer_key_window_question`, in place of `canBecomeKeyWindow` and
  `canBecomeMainWindow` on the class `SDLWindow`. It answers `NO` for a marked
  window, and for any other window it calls the method of SDL that it replaced
  (`_install_key_window_answer!`).
- **The mark.** `objc_setAssociatedObject` puts a mark on the `NSWindow`, with
  the address of a selector as its key and its value, and with
  `OBJC_ASSOCIATION_ASSIGN` (`_refuse_key_focus!`). The mark goes away with the
  window.

`_open_native_window!` calls `_refuse_key_focus!` after `SDL_CreateWindow` when
`_can_take_key_focus(style)` is false, which is for `:tooltip` only. Off Cocoa
the subsystem is not `SDL_SYSWM_COCOA`, so nothing happens. The reconciler opens
a tooltip hidden and shows it later in `_show_painted_window!`, so the mark is
there before AppKit shows the window.

**Decision in step 2: no subclass on the window.** The plan first put a subclass
on each tooltip window with `object_setClass`. SDL observes the `visible` key of
each window (`SDL_cocoawindow.m:525`), and for that observation AppKit already
gave each window a class of its own. A second change of the class removes that
class, and SDL loses its events for a window that shows or hides. A replaced
method on `SDLWindow` and a mark on the window leave the class of the window as
it is.

**Decision in step 2: the record of the replaced methods belongs to a process.**
`_REPLACED_KEY_WINDOW_METHODS` is filled at run time. A precompile workload that
opens a tooltip on macOS would put a filled record into the package image, and
the next process would then replace nothing. `__init__` empties it, as it resets
the probes of the machine.

## Steps

The work is done in a worktree, on a branch. It lands on main only after step 3
passes and the owner approves.

1. ✅ Write this plan.
2. ✅ **Make the tooltip window of macOS one that can not become key.** The
   Objective-C helpers stand beside `_macos_drop_activation_policy_to_accessory!`,
   and `_open_native_window!` calls them. On Linux, a case in
   `NativeWindowTest.jl` checks the rule that names the styles that never take
   the key focus, and that a tooltip window opens there as before.
   `test_native_window()` and then `test_sdl()` must pass.
   **Result:** the new case passes 8 of 8. On X11 it also proves the offsets of
   `SDL_SysWMinfo`: the subsystem is X11 and the first handle is set.
   `test_native_window()` passes. `test_sdl()` passes 1014, and
   `test_tree_render` fails 2 and errors 1 at `TreeRenderTest.jl:43-55`; main at
   c092f2aff, the base of the branch, fails there in the same way, so the fault
   comes from main.
3. ⬜ **Check on a Mac** with the script of the tester, click-through off:
   - on the main monitor, 5 of 5 clicks after a tooltip arrive;
   - when the tooltip opens, window 1 gets no `FOCUS_LOST` and no `LEAVE`;
   - the tooltip stays while the pointer rests on the button, and closes when the
     pointer leaves it;
   - a key typed while the tooltip shows reaches the IDE window;
   - on the second monitor the tooltip does not open again every 0.6 s.
4. ⬜ Write the results of step 3 into this plan, and move it to `plan/done/`.

## Not in this plan

- Popups (menus and dropdowns) take the key focus on macOS through the same
  path, so a menu can close as soon as it opens; check this with one click
  first, because a popup takes clicks and hover, which a window that can not
  become key may not get.
- `SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH`: the tester confirmed it as a workaround,
  but it leaves the flicker, the lost keys and the loop, and it changes the first
  click after a switch from another application.
- SDL3, which has non-focusable and popup windows on Cocoa.
