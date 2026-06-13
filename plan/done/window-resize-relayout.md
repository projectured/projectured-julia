# Window Resize → Re-layout

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Summary

When the user drags a native window's edge to resize it, the editor should
update the **size of the corresponding `WindowDocument`**, and that single
write should flow — reactively, with **no re-projection** — into the printer
so the content re-lays-out to the new size.

The good news: **the re-layout half is already built.** The missing half is
the *plumbing from the OS resize event to the `WindowDocument`'s
`width`/`height` cells*. Today the SDL backend silently drops resize events,
so nothing downstream ever fires.

This plan adds four small pieces that close the loop:

1. a backend-agnostic `WindowResizeEvent(width, height)`;
2. backend code that surfaces `SDL_WINDOWEVENT_RESIZED` as that event
   (tagged with the originating window id), and updates its cached window
   size so the reconciler does not fight the OS;
3. a `ResizeWindowOperation` that writes the new size into a `WindowDocument`'s
   `width`/`height` cells;
4. a reader interception in **`WindowManagerProjection`** — the existing
   window-management projection — that turns the resize envelope into that
   operation. **`CopyingProjection` is not touched.**

Because those cells *are* the `available_width`/`available_height` cells the
printer threads down into the content, writing them invalidates only the
size-dependent layout cells. The next `print!` pulls the re-laid-out canvas —
`projection_print` never re-runs.

---

## Design principle: keep `CopyingProjection` generic

`CopyingProjection` is a generic structural copier — it walks any document's
struct fields and `CellVector`s and recurses. It must know **nothing** about
resizing, windows, or any other domain concept. Resize is a *window-management*
concern, and the codebase already has a projection whose entire job is window
management: **`WindowManagerProjection`**
([WindowManager.jl](../../program/src/projection/higherorder/WindowManager.jl)).
It already intercepts `OpenWindowOperation` and `CloseWindowOperation`, holds
the `ScreenDocument`'s window list on its iomap, and resolves windows by id.
Resize belongs there, next to open and close.

> The `WindowManagerProjection` docstring already frames its role this way:
> "intercept the changes this projection owns, delegate the rest" — and
> `ProjectionConfiguringProjection` calls out that it "mirrors
> `WindowManagerProjection`." Adding resize to it follows the established
> pattern; pushing it into `CopyingProjection` would not.

---

## What is already wired (do not rebuild)

The reactive resize machinery is in place; only the event source is missing.

- **`PrinterContext.available_width/height` are `Cell`s, on purpose.**
  [PrinterContext.jl](../../program/src/context/PrinterContext.jl) documents
  this explicitly: "using `Cell` (rather than a plain value) lets descendants
  read the allocation reactively so that a resize never forces re-projection."

- **`CopyingProjection` seeds the window's size cells as the available size.**
  When it descends into `WindowDocument.content` it does
  [Copying.jl](../../program/src/projection/generic/Copying.jl) ~L139:

  ```julia
  if input isa WindowDocument && nm == :content
      w_cell = getfield(input, :width)    # the raw Cell, not a snapshot
      h_cell = getfield(input, :height)
      child_ctx = with_available_size(child_ctx; width=w_cell, height=h_cell)
  end
  ```

  So `available_width === WindowDocument.width` (the same `Cell` object).
  (This is a *printer* concern — seeding layout extent from a window's size —
  not a reader concern, so it is acceptable here; it does not interpret
  events.)

- **Layout-aware projections already read those cells reactively.**
  `WordWrapping`, `WidgetToGraphics`, `LayoutToGraphics`, `WorkbenchToWidget`
  all wire adaptive cells over `ctx.available_width` / `ctx.available_height`
  (e.g. [WordWrapping.jl](../../program/src/projection/primitive/WordWrapping.jl) ~L88,
  [WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl) ~L944).

- **Input ↔ output cells are shared.** `CopyingProjection` copies non-document
  fields verbatim by pushing the *raw* `Cell` (`fv = getfield(input, nm)`),
  and `@document`'s auto-wrapping constructor keeps an existing `Cell`
  (`$a isa Cell ? $a : Cell($a)` in [common/Document.jl](../../program/src/common/Document.jl)).
  So the **output** `WindowDocument` shares the same `width`/`height` `Cell`
  as the **input** one. Writing the input cell therefore (a) drives the
  content re-layout via `available_width`, and (b) is immediately visible to
  the backend reconciler, which reads `w.width` / `w.height` off the output
  `ScreenDocument`.

The upshot: a single write to the input `WindowDocument.width` cell is the
*entire* re-layout trigger. The whole job of this plan is to perform that
write in response to an OS resize.

The downstream resize story is described in
[plan/done/projection-context.md](../done/projection-context.md) ("Resize flow
with the cell approach") and [plan/done/widget-layout.md](../done/widget-layout.md).

---

## What is missing (the gaps)

1. **The backend drops resize events.** `read_from_devices`
   ([Sdl.jl](../../program/src/backend/Sdl.jl) ~L1084) handles the
   `SDL_WINDOWEVENT` (`0x200`) group only for sub-event `14`
   (`SDL_WINDOWEVENT_CLOSE`); every other sub-event hits `continue` and is
   discarded. Resize is `SDL_WINDOWEVENT_RESIZED` (sub-event `5`).

2. **There is no resize event type.** There is `QuitEvent`
   ([device/Screen.jl](../../program/src/device/Screen.jl)) and
   `WindowCloseRequest` ([document/Screen.jl](../../program/src/document/Screen.jl)),
   but nothing for "this window became W×H".

3. **No reader turns a resize into a cell write, and no operation expresses
   the write.** `WindowManagerProjection` owns open/close but has no resize
   case; there is no `ResizeWindowOperation`.

4. **The default pipeline has no window-management layer.** The tooltip
   variant routes `ScreenDocument => WindowManagerProjection(inner =
   CopyingProjection())`, but the default `_multi_window_projection`
   ([Examples.jl](../../example/src/Examples.jl) ~L275) projects the
   `ScreenDocument` root with a bare `CopyingProjection`. There is nowhere for
   the manager's reader to run. Resize (like a future open/close in the
   non-tooltip case) needs the manager present.

---

## Design

### 1. `WindowResizeEvent` — backend-agnostic event

A per-window event, like `WindowCloseRequest`. Put it next to that type in
[document/Screen.jl](../../program/src/document/Screen.jl) and export it:

```julia
"""
    WindowResizeEvent(width, height)

Inner event carried by an `EventEnvelope` when the user resizes a window's
native frame (`SDL_WINDOWEVENT_RESIZED`). `width`/`height` are the new
pixel size of the window's content area. `WindowManagerProjection`'s reader
translates it into a `ResizeWindowOperation` on the matching window.
"""
struct WindowResizeEvent
    width::Int
    height::Int
end
```

It rides inside `EventEnvelope(window_id, WindowResizeEvent(w, h))`, exactly
like `WindowCloseRequest`.

### 2. Backend: surface `SDL_WINDOWEVENT_RESIZED`

In `read_from_devices`'s `SDL_WINDOWEVENT` branch, add a case for sub-event
`5`:

```julia
elseif t == 0x00000200  # SDL_WINDOWEVENT
    sub = evt.window.event
    wid = _lookup_window_id(backend, evt.window.windowID)
    if sub == UInt8(14)        # SDL_WINDOWEVENT_CLOSE
        return EventEnvelope(wid, WindowCloseRequest())
    elseif sub == UInt8(5)     # SDL_WINDOWEVENT_RESIZED
        nw = Int(evt.window.data1)
        nh = Int(evt.window.data2)
        # Mark the resource as already at this size so the reconciler's
        # `_update_window_geometry!` does not issue a redundant
        # SDL_SetWindowSize back at the OS (which would fight the drag).
        res = get(backend.windows, wid, nothing)
        if res !== nothing
            res.width = nw
            res.height = nh
        end
        return EventEnvelope(wid, WindowResizeEvent(nw, nh))
    end
    continue  # other window sub-events still ignored
end
```

Notes:

- **Use `RESIZED` (5), not `SIZE_CHANGED` (6).** `RESIZED` fires only for
  *external* size changes (user / window manager). `SIZE_CHANGED` (6) also
  fires for programmatic `SDL_SetWindowSize`, which the reconciler itself
  calls — listening to it would create a write→event→write feedback loop.
  Listening to `RESIZED` keeps the loop strictly one-directional:
  OS-drag → cell write → (no programmatic resize back, because the cached
  size now matches).
- `evt.window.data1` / `data2` carry the new width/height for window events.
  Verify the field path in the `SimpleDirectMediaLayer` wrapper while
  implementing (the existing code already reads `evt.window.event` and
  `evt.window.windowID`).
- Updating `res.width`/`res.height` here also keeps `_render_window!`'s
  viewport (`vw, vh`) and the canvas culling correct on the very next paint,
  since it renders with `res.width, res.height`
  ([Sdl.jl](../../program/src/backend/Sdl.jl) ~L754).
- The window is already created with `SDL_WINDOW_RESIZABLE` for `:normal`
  windows, so no change to creation flags is needed. (`:tooltip` windows are
  intentionally non-resizable — they simply never emit `RESIZED`.)

### 3. `ResizeWindowOperation` — the cell write

A small operation carrying the target `WindowDocument` directly, mirroring
`ToggleCollapseOperation` (which carries its target node). Self-contained
operations like this are evaluated by the editor and bubble up through every
reader layer unchanged.

In [common/Operation.jl](../../program/src/common/Operation.jl), beside the
other window operations:

```julia
"""
    ResizeWindowOperation(target, width, height)

Set the `width`/`height` cells of `target` (a `WindowDocument`) to a new
pixel size. Produced by `WindowManagerProjection` when the user resizes the
native window frame. Because those cells are the
`available_width`/`available_height` the printer threads into the window's
content, writing them re-lays-out the content reactively — no re-projection.
The output `WindowDocument` shares the same cells, so the backend reconciler
also sees the new size on the next frame.
"""
struct ResizeWindowOperation <: Operation
    target::Any
    width::Int
    height::Int
end

function evaluate_operation(editor, op::ResizeWindowOperation)
    op.target === nothing && return
    op.target.width = op.width
    op.target.height = op.height
end
```

Export it from `OperationModule`. The editor loop's `evaluate!` already calls
`evaluate_operation(editor, op)` generically
([Editor.jl](../../program/src/editor/Editor.jl) ~L102), so no editor change is
needed — and unlike open/close (which the manager *applies* during the read
because they need re-projection), resize is a plain cell write, so it goes
through the normal read → **evaluate** → print discipline and shows up in the
`[operation]` log.

### 4. `WindowManagerProjection` interprets the resize envelope

The manager's reader currently delegates to its inner projection first, then
inspects the bubbled-up operation for open/close. Add a resize case at the
**top**, keyed off the gesture, *before* delegating — so the inner
`CopyingProjection` never has to interpret the envelope:

```julia
function projection_read(p::WindowManagerProjection, recursion, change::Change, iomap::WindowManagerProjectionIoMap)
    env = change.gesture
    if env isa EventEnvelope && env.event isa WindowResizeEvent
        win = _find_window(iomap.input, env.window_id)
        win === nothing && return Change(change.gesture, nothing)
        return Change(change.gesture,
                      ResizeWindowOperation(win, env.event.width, env.event.height))
    end

    inner = projection_read(p.inner, recursion, change, iomap.inner_iomap)
    op = inner.operation
    # ...existing OpenWindowOperation / CloseWindowOperation handling...
end

# Find the WindowDocument with the given id on the manager's input screen.
function _find_window(screen, id::Symbol)
    screen isa ScreenDocument || return nothing
    for w in screen.windows
        w isa WindowDocument && w.id === id && return w
    end
    nothing
end
```

`iomap.input` is the input `ScreenDocument` (the manager stores it), and
`env.window_id` is a stable input-domain identifier, so the manager resolves
the target window with **no coordinate mapping and no help from
`CopyingProjection`**. The returned `ResizeWindowOperation` carries the *input*
`WindowDocument`, whose cells are the `available_*` source; the editor
evaluates it; the shared cells take care of both the content re-layout and the
output side the reconciler reads.

New imports for `WindowManager.jl`: `EventEnvelope`, `WindowResizeEvent` (from
`ScreenDocumentModule`), `ResizeWindowOperation` (from `OperationModule`). The
module already imports `ScreenDocument`/`WindowDocument`.

> **Alternative considered (rejected):** apply the resize directly inside the
> manager's reader and return a nothing-change, exactly like `_apply_open!` /
> `_apply_close!`. Open/close *must* mutate in the reader because they
> re-project new window content for the output side; resize needs no
> re-projection (shared cells), so emitting a normal operation evaluated by
> the editor is cleaner and keeps the cell write in `evaluate!`.

### 5. Put the manager in the default pipeline

The default `_multi_window_projection`
([Examples.jl](../../example/src/Examples.jl) ~L275) must route the
`ScreenDocument` *root* through `WindowManagerProjection` so the reader above
has somewhere to run. The pipeline dispatches by **reference path**; the root
is `EmptyReferencePath`. Insert a root case ahead of the existing prefix match:

```julia
return RecursiveProjection(ReferenceDispatchingProjection(ref -> begin
    for i in 1:n
        reference_equal(ref, targets[i]) && return NestingProjection(...)
    end
    # The ScreenDocument root is the window-management seam.
    ref isa EmptyReferencePath &&
        return WindowManagerProjection(inner = CopyingProjection())
    for t in targets
        is_prefix_of(ref, t) && return CopyingProjection()
    end
    return PreservingProjection()
end))
```

`ReferenceDispatchingProjection` re-dispatches on the stored reference for the
reader too ([ReferenceDispatching.jl](../../program/src/projection/higherorder/ReferenceDispatching.jl) ~L84),
so the root reader resolves to the same `WindowManagerProjection`. Its printer
is a passthrough (projects `inner` and recurses normally), so the rest of the
spine — the `windows` `CellVector`, each `WindowDocument`, each `content` —
dispatches exactly as today. `WindowManagerProjection` is stateless apart from
its `inner`, so a fresh instance per dispatch is fine (same as the bare
`CopyingProjection()` returned today). The tooltip variant already wraps the
screen this way, so it needs no change.

### Why this never re-projects

```
OS drag → SDL_WINDOWEVENT_RESIZED
        → EventEnvelope(:id, WindowResizeEvent(w,h))              [backend]
        → ResizeWindowOperation(window, w, h)                     [WindowManagerProjection]
        → window.width / window.height cells := w, h              [evaluate]
        → invalidates available_width/height consumers            [reactive]
        → content canvas geometry recomputed lazily on read       [next print!]
```

`print!` only calls `projection_print` when `editor.iomap === nothing`
([Editor.jl](../../program/src/editor/Editor.jl) ~L112). The resize operation
does **not** null the iomap, so `print!` just re-runs
`write_to_devices(backend, devices, iomap.output)`; the reconciler reads
`w.content`, which pulls the reactively re-laid-out canvas. No projection
re-runs — matching the "one root-cell write → re-flow" story in
[plan/done/widget-layout.md](../done/widget-layout.md).

---

## Files to change

| File | Change |
|------|--------|
| [program/src/document/Screen.jl](../../program/src/document/Screen.jl) | Add + export `WindowResizeEvent`. |
| [program/src/backend/Sdl.jl](../../program/src/backend/Sdl.jl) | Import `WindowResizeEvent`; handle `SDL_WINDOWEVENT_RESIZED` in `read_from_devices`; update `res.width/height`. |
| [program/src/common/Operation.jl](../../program/src/common/Operation.jl) | Add + export `ResizeWindowOperation` and its `evaluate_operation`. |
| [program/src/projection/higherorder/WindowManager.jl](../../program/src/projection/higherorder/WindowManager.jl) | Import the new event/op; intercept `WindowResizeEvent` in the reader; add `_find_window`. |
| [example/src/Examples.jl](../../example/src/Examples.jl) | Route the `ScreenDocument` root through `WindowManagerProjection` in `_multi_window_projection`. |
| [program/src/Projectured.jl](../../program/src/Projectured.jl) | `using`/`export` wiring for the new exports as needed. |

**Explicitly not touched:** `CopyingProjection`
([Copying.jl](../../program/src/projection/generic/Copying.jl)), the
`PrinterContext`, the `Editor` loop, and every layout projection — the
downstream is already reactive, and the generic copier stays generic.

---

## Implementation steps

1. **`WindowResizeEvent`** — define and export it in `document/Screen.jl`.
2. **Operation** — add `ResizeWindowOperation` + `evaluate_operation` to
   `common/Operation.jl`; export it.
3. **Manager reader** — import the new types into `WindowManager.jl`; add the
   resize interception + `_find_window`.
4. **Default pipeline** — wrap the `ScreenDocument` root in
   `WindowManagerProjection` in `_multi_window_projection` (import
   `EmptyReferencePath` / `WindowManagerProjection` as needed; the tooltip
   variant already has both).
5. **Backend event** — import `WindowResizeEvent` into `Sdl.jl`; add the
   `RESIZED` case to `read_from_devices`; update `res.width`/`res.height` when
   surfacing it.
6. **Top-level wiring** — re-export from `Projectured.jl` as needed.
7. **Manual check** — `run_example("json")` (or any word-wrap / widget
   example), drag the window narrower/wider, confirm the content re-wraps /
   re-flows without a flash of re-projection and without the window snapping
   back.

A natural ordering is 1–4 first (all unit-testable without a live window),
then the backend (5) and a manual SDL check (7).

---

## Testing

The reader path is unit-testable without a live window, since
`projection_read` takes a constructed `EventEnvelope`:

- **Manager reader → operation.** Build the default screen + projection used by
  `run_example` (or a minimal `ScreenDocument([WindowDocument(...)])` projected
  through `WindowManagerProjection(inner = CopyingProjection())`),
  `projection_print` it, then feed
  `Change(EventEnvelope(:main, WindowResizeEvent(800, 600)), nothing)` to
  `projection_read` and assert the returned `Change.operation` is a
  `ResizeWindowOperation` targeting the `:main` window with
  `width==800, height==600`. Feed an envelope with an unknown id and assert a
  nothing-change.

- **Operation → cells.** Evaluate the operation (against a minimal `editor`
  stub, or call `evaluate_operation` directly) and assert the
  `WindowDocument.width`/`height` cells changed.

- **Cell sharing (the load-bearing invariant).** Assert that after the write,
  the *output* `WindowDocument` (from the printed iomap) reports the new
  `width`/`height` too — i.e. input and output share the cell. If this ever
  regresses, the reconciler would stop seeing resizes and the operation would
  need to update both sides explicitly.

- **Reactive re-layout, no re-projection.** For word-wrapping content, force
  the content canvas height once, apply the resize operation with a smaller
  width, force again, and assert the canvas height grew (more wrapping) with
  **no** new `projection_print` call. This mirrors the reactivity assertion in
  [test/src/projection/TextToGraphicsTest.jl](../../test/src/projection/TextToGraphicsTest.jl).

- **Pipeline regression.** A quick `test_printer` / `test_repl` on an existing
  multi-window example to confirm wrapping the root in `WindowManagerProjection`
  changed nothing about normal printing/reading.

Use the narrowest runner per [CLAUDE.md](../../CLAUDE.md); a live SDL drag can
only be checked by hand.

---

## Edge cases & open questions

- **Resize before first paint.** `read!` skips envelopes while
  `editor.iomap === nothing` ([Editor.jl](../../program/src/editor/Editor.jl)
  ~L81), so a resize arriving before the first `print!` is dropped. Harmless:
  the initial size is whatever the `WindowDocument` already specified.
- **Event coalescing.** A drag emits many `RESIZED` events. Each becomes one
  operation/eval/print. The reactive layer only recomputes size-dependent
  cells, so this is cheap, but if profiling shows churn the backend could
  collapse consecutive `RESIZED` for the same window into the latest before
  returning (keep the simple one-event-per-poll form for v1).
- **`0` / auto-size semantics.** `WindowDocument.width/height == 0` means
  "auto-size" at creation. `RESIZED` always reports concrete pixels, so after
  the first user resize the size is concrete — no special handling needed.
- **Multi-window.** Each `RESIZED` is tagged with its `window_id`; the manager
  resolves it from its window list, so resizing one window of several updates
  only that window's cells.
- **`SIZE_CHANGED` vs `RESIZED` portability.** If some platform/WM delivers
  only `SIZE_CHANGED` (6) for user resizes, revisit: listen to `6` but guard
  against the feedback loop by comparing the reported size to `res.width/height`
  and returning `nothing` when they already match (the programmatic-resize
  case).
- **Position changes (`MOVED`, sub-event 4).** Out of scope here, but the same
  mechanism (`WindowMoveEvent` → `MoveWindowOperation` → write `x`/`y` cells,
  owned by `WindowManagerProjection`) is the obvious follow-up if window
  position should also round-trip into the document.
- **Pre-existing wart, not addressed here.** `CopyingProjection`'s reader
  already special-cases `ScreenDocument`/`WindowDocument` envelope *routing*.
  This plan deliberately does not add to that; whether that routing should
  itself migrate to the window-management layer is a separate cleanup.
