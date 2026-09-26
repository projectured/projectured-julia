# Every window tracks the pointer, and says when the pointer leaves it

> **Status (2026-09-26): in progress** on the branch `window-leave`, worktree
> `projectured-julia-window-leave`. The owner chose the correct design for the
> leave of a window, allowed the unsealing of the kernel files it needs, named the
> event `WindowLeave`, and chose (B). A fact found after the choice reopens (B):
> see "Decisions".

Follows [a-popup-shows-every-item-on-a-popover-and-a-help-page-scrolls.md](../done/a-popup-shows-every-item-on-a-popover-and-a-help-page-scrolls.md).
The owner found that a row of a popup menu does not light under the pointer.

## The faults (found 2026-09-26)

- **H1. No window but the first tracks the pointer.** An item lights when its
  `hovered` state is set, and only a `MouseEnter` or a `MouseLeave` sets it. A
  backend reports no crossing, only `MouseMove`; `WidgetHoverTrackingProjection`
  makes the crossings from the motion. `make_window_wrap` puts it around the
  content of the first window only. A probe through the window scene of the
  application showed it: a move over "File" in the first window answers a hover
  write; a move over "Documents" in the popup answers nothing, and the item stays
  unlit; a `MouseEnter` at "Documents" answers a hover write and lights it. So
  the menu and its items work, and only the tracker is missing.
- **H2. The SDL backend reads a gained focus as a lost one.** `_poll_window_input`
  turns window event 12 into `WindowDefocus`, under a comment that says
  `SDL_WINDOWEVENT_FOCUS_LOST`. In SDL2, 12 is `SDL_WINDOWEVENT_FOCUS_GAINED`, and
  13 is `FOCUS_LOST`, which the backend ignores. So a window reports a loss of
  focus when it gains the focus. This was the real cause of F7 in the plan
  before: the `:floating` popup closed because it gained the focus. Today a
  popup closes when the first window gains the focus, and it stays open when the
  person switches to another program, which was the purpose of the rule.
- **H3. No event says that the pointer left a window.** The backend ignores
  `SDL_WINDOWEVENT_LEAVE` (11), and the web client sends nothing when the pointer
  leaves a canvas. A tracker sees the pointer leave a widget only when a move
  lands on another widget of the same window, so a row or a button that the
  pointer leaves by going out of the window stays lit.

## The design

- **H3: a device event for the pointer that leaves a window.** Every windowing
  layer reports it as an event of its own: X11 `LeaveNotify`, SDL
  `SDL_WINDOWEVENT_LEAVE`, Windows `WM_MOUSELEAVE`, macOS `mouseExited:`, Qt
  `QEvent::Leave`, GTK `leave-notify-event`, the DOM `mouseleave`. The kernel
  makes `MouseEnter` and `MouseLeave` synthetic ("an event source does not report
  it"), so a backend must not send those, and a pointer move to a point outside
  the window would lie to every reader of `MouseMove`: a drag would jump, the
  rest timer of a tooltip would start again, and a point outside is a real value
  during a drag with a button held. The new event goes beside `WindowDefocus` in
  `WindowEvent.jl`, with the time of its input:
  - the SDL backend reports it from event 11;
  - the web client sends `leave` from `mouseleave` on the canvas of a window,
    and the web backend reports it;
  - the hover tracker answers it with a `MouseLeave` to the widget it entered
    last, and forgets that widget; every other reader ignores it, as they ignore
    `WindowResize`;
  - a drag that leaves the window goes on: the leave clears the hover, and the
    reader of the drag does not read it.
- **H2:** event 13 becomes `WindowDefocus`, and 12 becomes nothing.
- **H1:** every window tracks the pointer. See "Decisions to make" for where.

## Decisions

- **The owner, 2026-09-26:** the event is `WindowLeave`; the window route tracks
  the pointer (B).
- **Found after the choice:** `WidgetHoverTrackingProjection` is also a standalone
  hover tracker, used with no window scene: in the gallery, two pane examples,
  the widget projection example, and the tests of the button and of the
  gestures; in omnet-julia in the presentation example, Qtenv, the campaign
  window, the build program and a demo. (B) as written, with the widget tracker
  reduced to the wrap-around of Tab, takes the hover from all of them. The choice
  goes back to the owner before step 3. Steps 0 to 2 do not depend on it.

## The choices as they were put

1. **The name of the event.** My proposal is `WindowLeave`: it sits in the family
   `WindowClose`, `WindowResize`, `WindowDefocus`, and it says what SDL and X11
   say. The alternative is `PointerLeave`, which names what leaves. It must pass
   the naming law either way.
2. **Where a window tracks the pointer.** The hover half of
   `WidgetHoverTrackingProjection` reads only kernel types (`MouseEnter`,
   `MouseLeave`, `WrappingOperation`, `ReplaceReferencedValueOperation`); only its
   other half, the wrap-around of Tab, needs the widgets.
   - **(A) A tracker around each opened window, given by the caller.**
     `make_window_scene_projection` and `make_editor` take a new keyword that
     wraps the content of every opened window, and the shell passes the widget
     tracker. The tracker keeps its state in its IO map, so one projection serves
     every window. Small, but each caller that wants hover in its popups passes
     the keyword: the application (two places), the video of the application,
     the rehearsal tool, the IDE of omnet-julia, and their tests.
   - **(B) The window route tracks the pointer of every window.** A projection of
     the screen package, inside the window manager and around `ScreenToScreen`,
     keeps for each window id the widget the pointer entered last. It turns a
     `MouseMove` of a window into the crossings of that window, and the new leave
     event of a window into a leave of its last widget. Every window of every host
     tracks the pointer, with no keyword, and the leave event arrives where the
     tracking is. The widget tracker keeps only the wrap-around of Tab, under a
     name that says so, and the first window stops tracking twice.
   - **My recommendation is (B).** It is where a window system tracks crossings,
     one window at a time, and it needs no caller to remember a keyword. It is
     more work: a new projection in the screen package, the split of the widget
     tracker, and a rename that reaches its callers and documents.

## Steps (for the recommended choices)

- [ ] 0. Unseal `event/WindowEvent.jl` and `event/EventModule.jl` in
  `SEALING.md`, in a commit that names the owner's permission.
- [ ] 1. **H2.** Event 13 becomes `WindowDefocus`, 12 nothing. Test: an SDL
  window event 13 pushed into the queue reads as `WindowDefocus`, and 12 reads as
  nothing.
- [ ] 2. **H3, the event.** The new event in `WindowEvent.jl`, exported and named
  in the list of window events of `EventModule.jl`. The SDL backend reports it
  from event 11; the web client and the web backend report it from `mouseleave`.
  Tests: the SDL event 11 reads as the new event; the web backend reads a
  `leave` message as it.
- [ ] 3. **H1 and H3, the tracking.** The tracking of the chosen place: a move
  over a row of the popup lights it, a move to the next row moves the light, and
  the leave of the window unlights it; the first window keeps its hover and its
  wrap-around of Tab.
- [ ] 4. The documents: `devices-and-backends.md` (the window events),
  `screen.md`, `widget.md`, `sdl.md`, `web.md`.
- [ ] 5. A live check on the display. Pushed SDL events do not move the real
  pointer; with the owner's word, the XTest library moves it, and the script
  clicks only where the window under the pointer is the application's.
- [ ] 6. The audit of `WindowEvent.jl` and `EventModule.jl` against
  `architecture-invariants.md`, reported to the owner, and the seal again with the
  owner's word. The verification against `main`, and the move of this plan to
  `plan/done/`.
