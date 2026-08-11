# The document takes the window size the window system granted

## The problem

A windowed editor lays its whole document out twice at start.

`run_example` has no `width`/`height`, so it takes the display size from
`get_display_size`. The SDL backend answers with `SDL_GetDisplayUsableBounds`,
which is the work area — on this desktop 1853×1168 of a 1920×1200 screen.
`_build_window_scene` writes that size into the `WindowDocument`. The first
frame projects and paints the document at 1853×1168, and only then does
`write_to_devices` open the native window.

The window manager cannot fit a client area of 1168 px plus a 37 px title bar
into a work area of 1168 px. It grants 1853×1131 and sends
`SDL_WINDOWEVENT_RESIZED`. The backend turns that into a `WindowResize`, the
window-managing projection turns it into a `ResizeWindowOperation`, and every
cell that depends on the available height computes a second time. The content
moves under the reader's eyes.

Measured on the omnetpp-julia demo catalog, one frame at a time:

```
asked for 1853x1168
frame 1 (project + open window + paint): 986.0 ms
frame 2: 321.3 ms  operation=ResizeWindowOperation  window=1853x1131
frame 3:   9.5 ms  operation=-                      window=1853x1131
```

The same run, asked for the height the manager grants:

```
asked for 1853x1131
frame 1 (project + open window + paint): 964.5 ms
frame 2:  12.0 ms  operation=-  window=1853x1131
```

So the second layout costs 321 ms and it is the only extra one. A bare SDL
window shows the same clamp with no ProjecturEd code in the way, at any
position, so this is the manager and not the backend:

```
usable bounds: 67,32 1853x1168
asked 1853x1168 at (100,100) -> got 1853x1131 at (67,69) resize events: [(1853, 1131)]
asked 1853x1131 at (100,100) -> got 1853x1131 at (67,69) resize events: []
```

## The decision

The window system owns the window size. The document follows it.

Open the native windows **before** the first projection, read back the geometry
the window system granted, and correct the document to it. Then the first
layout is the only layout, whatever the manager, the decoration, or the
requested size.

Two alternatives were rejected:

- Subtract the decoration from the default size. `SDL_GetWindowBordersSize`
  needs an open window, so this only moves the guess, and a guess is still
  wrong on the next manager.
- Choose a smaller default size. This hides the fault at one size and keeps it
  at every other.

## The design

A new generic on the backend contract:

    open_native_windows!(backend, document)

It opens the native window of every window `document` names, then corrects the
document to the geometry the window system granted. A backend with no windows
of its own answers with the no-op default, so nothing else changes.

The document is what the backend corrects, because the kernel cannot walk a
`ScreenDocument` — that document lives in the visual package, above the kernel.
The SDL backend already reconciles native windows against it, so the knowledge
stays where it already is.

`run_editor!(backend, projection, document)` calls it once, after
`configure_devices!` and before the first frame. Writing the size there is free:
no cell has been read yet, so nothing invalidates.

The size is corrected on the **input** document. `ScreenToScreen` projects the
output from it, so the output carries the granted size from its first print.

## The steps

- [x] 1. Declare `open_native_windows!` in `backend/BackendInterface.jl`, give
  it the no-op default in `backend/BackendDefaults.jl`, and export it from
  `backend/BackendModule.jl`. **These three files are sealed. The user gave
  explicit permission for this change on 2026-08-11.**
- [x] 2. Call it from the `run_editor!` bootstrap in `editor/Editor.jl`.
- [x] 3. Answer it in `ProjecturedSdl`: open each window, settle its size, and
  write the granted size back into the `WindowDocument`.
- [x] 4. Drain the window events the opening produced, so the editor does not
  read a resize for a size the document already has.
- [x] 5. Check it on a real window: one layout, no `ResizeWindowOperation`.
  `test_native_window` in `package/sdl/test/backend/NativeWindowTest.jl` holds
  the invariant, and `probe_editor.jl` showed the operation is gone.

## What was found while implementing

- The size a manager grants arrives after the window exists. `SDL_CreateWindow`
  returns before the manager has answered, so the size read straight after it is
  still the size that was asked for. SDL learns the real one when it pumps the
  event queue. `_settle_native_windows!` pumps until the size holds still for
  20 ms, and gives up after 250 ms.
- On this desktop the manager answers in **0.4 ms**, so the settle costs the
  20 ms quiet period and nothing more. Opening the window and its renderer costs
  293 ms, which is not new: it happened inside the first frame before.
- `SDL_PollEvent` is the only way to see the window events and it consumes them.
  Every event that is not a size change of a window just opened is pushed back
  with `SDL_PushEvent`, so a key pressed while the editor starts is not lost.
- The `SdlWindowResources` size needs correcting as well as the document.
  Otherwise the first `write_to_devices` sees a difference between them and
  calls `SDL_SetWindowSize`, which asks the manager for the size it refused.
- The window and its renderer now exist before the first projection, so
  `_update_display_scale!` runs before anything is measured. On a display whose
  scale only the open window can report, the first layout used to use the wrong
  font scale.

## Result

The omnetpp-julia demo catalog, driven one frame at a time, asking for the whole
work area of 1853×1168:

| | before | after |
| --- | --- | --- |
| open the windows | inside frame 1 | 934 ms |
| frame 1 | 1838 ms | 1154 ms |
| frame 2 | 441 ms, `ResizeWindowOperation` | 1.6 ms, no operation |
| until the window holds still | 2279 ms | 2088 ms |
| the document at frame 1 | 1853×1168, wrong | 1853×1131, what the window has |

The second layout is gone, which is what the plan is for. The total is 191 ms
shorter, which is less than the 441 ms the resize frame cost, because the window
and its renderer now open before frame 1 instead of inside it.

Most of the 934 ms is compiled once and never again: a bare process spends
308 ms opening the window and its renderer, and 155 ms in the settle, of which
the wait for the manager is 0.4 ms and the quiet period 20 ms. The rest is the
first call of the new path. `OmnetppRepl` compiles ahead of time from a
recording, and no recording covers this path yet, so re-recording the workload
would take that cost out of the first window.
