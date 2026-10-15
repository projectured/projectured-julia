# The pointer shows the hourglass while the editor is busy

Status: closed on 2026-10-15 by
[the-editor-always-answers-the-person.md](the-editor-always-answers-the-person.md),
which took it in. It was deferred by the owner on 2026-10-02 ("defer this
change"), as step 7 of
[the-pointer-shows-what-a-press-does.md](the-pointer-shows-what-a-press-does.md).
What that plan built in its place:

- A long frame of code, a code unit, no longer runs on the thread of the loop.
  The loop runs held frames meanwhile, and a held frame shows the hourglass over
  each window of the editor and gives the pointer back its shape after the unit
  (`prepare_held_frames!`, `run_held_frame!` and `end_held_frames!` of the SDL
  backend). After 0.5 s a busy bar names the unit and offers a stop. So option A
  of §4, a watcher on a second thread with its own X connection, is not needed,
  and the hourglass works on every system that SDL runs on.
- The web backend shows the busy bar of a unit (`client.js`), which answers §5.
- A frame that is slow for another reason, such as an operation or a print, shows
  no hourglass. The loop writes it in the log with its slowest stage
  (`SLOW_FRAME_SECONDS`, 1 s), because such a frame is a fault to find, not a wait
  to show.

## 1. The goal

While the loop of the editor is in a frame that takes longer than a threshold,
such as half a second, the pointer is the hourglass over every window, and after
the frame it takes the shape at the pointer again (§4.3 of the plan above).

## 2. What is there

- `:hourglass` is one of `POINTER_SHAPES`. SDL maps it to
  `SDL_SYSTEM_CURSOR_WAIT`, the web backend to the CSS cursor `wait`, and the video
  backend draws its picture.
- Nothing says that a frame is long. The busy shape is a state of the editor and
  not of a part, so it has no region.

## 3. The problem

The editor runs each frame on the main thread, and SDL lets only that thread
change the cursor. During a long frame that thread runs Julia code, not SDL, so it
can not show the hourglass. The web backend has the same problem: its send task
runs on the same thread, so no message leaves during the frame.

## 4. The options for SDL

- **A. A watcher on a second thread, with its own X connection.** At the first
  read of a frame the backend notes the time. After the threshold, the watcher sets
  the hourglass on each SDL window with Xlib (`XDefineCursor`) through a connection
  of its own, so it shares no state with SDL; `Xorg_libX11_jll` is a dependency of
  the SDL backend already. At the end of the frame, the main thread sets the shape
  at the pointer again through SDL. X11 only, and only with two Julia threads or
  more. About 100 lines.
- **B. A watcher that calls `SDL_SetCursor` from the second thread.** Simpler, but
  SDL does not promise that it is safe: macOS forbids it, and on X11 it competes
  with the state of SDL.
- **C. Only between the reads of a frame.** The backend sets the hourglass at a
  read inside a frame that has run longer than the threshold. One thread, and
  safe, but a frame that is one long operation or one long print, the usual long
  frame (a compile), shows none.
- **D. No hourglass.**

The recommendation of the writer was A, because it covers the long frames that
matter on X11 and touches no state of SDL from the second thread.

## 5. The web backend

It needs its own way to send the hourglass during a long frame, for example a
watcher that sends on the WebSocket, or a client that shows `wait` when an input
it sent has no answer within the threshold. To decide after §4.
