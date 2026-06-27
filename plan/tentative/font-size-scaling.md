# Increase / decrease font size for readability (Ctrl +/−/0 zoom)

**Date:** 2026-06-27
**Status:** 📝 proposed — not yet implemented

## Goal

Let the user make everything on screen bigger or smaller for readability with
the conventional shortcuts:

- **Ctrl + `=`** (and keypad `+`) — zoom in
- **Ctrl + `-`** (and keypad `-`) — zoom out
- **Ctrl + `0`** — reset to 100%

"Zoom" here means *uniform magnification of the whole editor* — glyphs, boxes,
spacing, carets, everything — exactly like a browser's Ctrl+/Ctrl−. It is a
single global readability knob, not a per-document or per-projection font
override.

## Why this is mostly a render-layer change

The repo already did the hard part. Per
[plan/done/global-display-scale.md](../done/global-display-scale.md), there is a
single global **logical→device** factor, `_DISPLAY_SCALE`
([Font.jl:89](../../package/domain/src/document/Font.jl#L89)), applied **only at
the SDL edge**:

- **All layout is in logical pixels** and never reads `_DISPLAY_SCALE`. The
  projected canvas geometry is provably *identical* at scale 1, 2, 3
  (json_example is 396×624 at every scale).
- **`measure_text`** ([ProjecturedSdl.jl:1511](../../package/sdl/src/ProjecturedSdl.jl#L1511))
  rasterizes glyphs at device size, then divides the measurement back by
  `_DISPLAY_SCALE` → returns the *same logical size* at any scale. So text
  intrinsic layout does not move when the scale changes.
- **Glyph crispness is automatic:** `_get_font`
  ([ProjecturedSdl.jl:617](../../package/sdl/src/ProjecturedSdl.jl#L617)) and
  the text-texture cache key on `font_scaled_size(size) = round(size *
  _DISPLAY_SCALE)` ([Font.jl:99](../../package/domain/src/document/Font.jl#L99)),
  i.e. on the **device** size. Bump the scale → new cache key → glyphs
  re-rasterize crisply at the larger size (no bitmap upscaling).
- **The renderer scales once** via `SDL_RenderSetScale(scale, scale)`
  ([ProjecturedSdl.jl:1401/1406](../../package/sdl/src/ProjecturedSdl.jl#L1401)).
- **Input converts back** through `_to_logical`/`_to_device`
  ([ProjecturedSdl.jl:507](../../package/sdl/src/ProjecturedSdl.jl#L507)), which
  also read `_DISPLAY_SCALE`, so mouse hit-testing stays correct at any scale.

So a font/zoom change requires **no relayout of content for size or crispness**
— only the viewport reflow and a repaint (see Wrinkle 1 below). The whole
feature is: *drive `_DISPLAY_SCALE` from a user zoom factor, on a keystroke.*

## Design

### 1. Split DPI scale from user zoom (domain — `Font.jl`)

Today `_DISPLAY_SCALE` *is* the detected DPI scale, written directly by the SDL
detection code. Introduce a clean factorization so zoom and DPI compose:

```julia
const _BASE_DISPLAY_SCALE = Ref(1.0)   # DPI scale, detected once at window open
const _USER_ZOOM          = Ref(1.0)   # user readability zoom, default 100%
const _DISPLAY_SCALE      = Ref(1.0)   # effective = base × zoom (what everyone reads)

_recompute_display_scale!() = (_DISPLAY_SCALE[] = _BASE_DISPLAY_SCALE[] * _USER_ZOOM[])

# Discrete, browser-like zoom steps, clamped.
const _ZOOM_STEPS = (0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)
function adjust_user_zoom!(delta::Int)   # +1 in, -1 out, 0 reset
    delta == 0 && (_USER_ZOOM[] = 1.0; _recompute_display_scale!(); return _USER_ZOOM[])
    i = argmin(abs.(collect(_ZOOM_STEPS) .- _USER_ZOOM[]))
    _USER_ZOOM[] = _ZOOM_STEPS[clamp(i + delta, 1, length(_ZOOM_STEPS))]
    _recompute_display_scale!()
    _USER_ZOOM[]
end
```

Everything downstream keeps reading `_DISPLAY_SCALE` unchanged — `font_scaled_size`,
`_get_font`, `_to_device`/`_to_logical`, `SDL_RenderSetScale` all Just Work.

**Redirect DPI detection** in
[ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl#L535-L602)
(`_detect_display_scale!` / `_update_display_scale!`, ~lines 535–602): write the
detected DPI into `_BASE_DISPLAY_SCALE[]` and call `_recompute_display_scale!()`,
and change the `_DISPLAY_SCALE[] == 1.0` "already detected?" guards to test
`_BASE_DISPLAY_SCALE[]`. `PROJECTURED_DISPLAY_SCALE` env override likewise sets
the base.

### 2. The operation (kernel struct, backend behavior)

Layering: `kernel` is the lowest layer; `domain` depends on `kernel`; `sdl`
depends on `domain`. The zoom refs live in domain and the repaint lives in the
backend, so — following the existing pattern where `evaluate_operation` methods
are spread across layers (e.g. ODBC, VersioningToAny define their own) — define
the **struct in kernel** with a no-op default, and the **real method in the SDL
backend**.

- **kernel** [`Operation.jl`](../../package/kernel/src/common/Operation.jl):
  ```julia
  struct AdjustZoomOperation <: Operation; delta::Int; end   # +1 in, -1 out, 0 reset
  ```
  The default `evaluate_operation(editor, op) = nothing` (line 21) already makes
  this a harmless no-op for the Console/PDF/web paths that don't implement it.
- **sdl** [`ProjecturedSdl.jl`](../../package/sdl/src/ProjecturedSdl.jl):
  ```julia
  function evaluate_operation(editor, op::AdjustZoomOperation)
      adjust_user_zoom!(op.delta)          # mutate scale (domain)
      _reflow_for_scale!(editor)           # Wrinkle 1
      _force_full_repaint!(editor)         # Wrinkle 2
      nothing
  end
  ```

### 3. The gesture (editor-global, with projection fallback)

Zoom should work no matter what is selected, so recognize it at the **editor
level** rather than per-projection — mirroring how `read!` already special-cases
the window-close `QuitEvent`
([Editor.jl:87](../../package/kernel/src/editor/Editor.jl#L87)).

The keys are already mapped by both backends — `:equals` (incl. keypad `+`) and
`:minus` (incl. keypad `-`):
[ProjecturedSdl.jl:362-365](../../package/sdl/src/ProjecturedSdl.jl#L362),
[ProjecturedWeb.jl:161](../../package/web/src/ProjecturedWeb.jl#L161). (Verify
the digit `0` mapping for reset; if absent, add `keysym 48 → :0` / keypad `0`,
or drop reset to a less conflict-prone gesture — see Decisions.)

**Recommended placement — global *fallback* in `read!`** so a projection that
explicitly claims these keys still wins (see the conflict below). In
[Editor.jl `read!`](../../package/kernel/src/editor/Editor.jl#L80), after the
pipeline is consulted and produced *no* operation, check the gesture:

```julia
op = change isa Change ? change.operation : change
if op isa Operation
    editor.operation = op; return true
elseif (z = _zoom_delta(env)) !== nothing      # Ctrl+= / Ctrl+- / Ctrl+0, unclaimed
    editor.operation = AdjustZoomOperation(z); return true
end
# else: swallow as today
```

where `_zoom_delta` returns `+1`/`-1`/`0`/`nothing` from a `KeyDown` with `ctrl`
and key `:equals`/`:minus`/`:0`. This keeps zoom editor-global yet yields to any
projection that binds the same keys.

### Keybinding conflict (must decide)

`Ctrl+=` and `Ctrl+-` are **already bound** by the clipboard-collection
projection for *add to / remove from collection*
([ClipboardToAny.jl:405-410](../../package/domain/src/projection/primitive/ClipboardToAny.jl#L405)).
The reader gives an active projection first crack at a gesture, so with the
*fallback* placement above, clipboard add/remove keeps working when a collection
is focused and zoom works everywhere else. That is the recommended resolution —
no breakage, minor surprise (zoom inert while editing a clipboard collection).

Alternatives if that surprise is unacceptable: (a) make zoom an *unconditional*
editor-global intercept (zoom always wins, clipboard add/remove via these keys is
lost), or (b) move zoom to a distinct chord (e.g. `Ctrl+Shift+=` / `Ctrl+Shift+-`).

## Wrinkles to handle

1. **Logical viewport reflow (`_reflow_for_scale!`).** The window's *device*
   size is fixed (the user's window doesn't change size on zoom), so its
   *logical* size = device ÷ `_DISPLAY_SCALE` **shrinks as you zoom in** — which
   is exactly "see less, bigger." Layout that fills/wraps/scrolls to the window
   must reflow to the new logical size. Recompute each native window's logical
   `width`/`height` from its retained device size and the new scale, and apply it
   through the existing resize path
   ([`ResizeWindowOperation`/`evaluate_operation`](../../package/kernel/src/common/Operation.jl#L389),
   which sets `target.width/height` on the `WindowDocument`). **Risk:** ensure the
   backend's window reconciliation does **not** react by resizing the *device*
   window (it must only relayout). Confirm against the window-create/resize code
   that uses `_to_device`.

2. **Force a full repaint (`_force_full_repaint!`).** Rendering is dirty-rect
   incremental ([`_render_window!`](../../package/sdl/src/ProjecturedSdl.jl#L1398)).
   On a zoom change *every* pixel moves, so invalidate the whole window
   (full dirty rect / reset damage history) for the next frame. The retained
   render target is device-sized (window-sized) and unaffected.

3. **Cache hygiene.** `_font_cache` and the text-texture cache key on the device
   size, so they self-populate fresh entries at the new scale — correct, but old
   entries linger. Optional: evict stale-scale entries on zoom to cap memory
   (not required for correctness).

4. **Headless / other backends.** `write_image` already drives scale explicitly
   via the offscreen renderer
   ([`_render_canvas_offscreen!`](../../package/sdl/src/ProjecturedSdl.jl#L1639),
   saving/restoring `_DISPLAY_SCALE`) — unaffected. The web backend keeps
   `_DISPLAY_SCALE = 1.0` ([web-backend plan](../done/web-backend.md#L111)); to
   support zoom there, add a parallel `evaluate_operation(::AdjustZoomOperation)`
   that drives its own zoom factor (or relies on the browser's native zoom — then
   web needs nothing).

## Files to touch

| File | Change |
|------|--------|
| [package/domain/src/document/Font.jl](../../package/domain/src/document/Font.jl) | `_BASE_DISPLAY_SCALE`, `_USER_ZOOM`, `_recompute_display_scale!`, `_ZOOM_STEPS`, `adjust_user_zoom!`; export them |
| [package/kernel/src/common/Operation.jl](../../package/kernel/src/common/Operation.jl) | `struct AdjustZoomOperation`; export |
| [package/kernel/src/editor/Editor.jl](../../package/kernel/src/editor/Editor.jl) | `_zoom_delta(env)` + fallback branch in `read!` |
| [package/sdl/src/ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl) | redirect DPI detection to `_BASE_DISPLAY_SCALE`; `evaluate_operation(::AdjustZoomOperation)`; `_reflow_for_scale!`; `_force_full_repaint!`; verify `:0` key |
| (optional) web/console backends | parallel `AdjustZoomOperation` handling or rely on native zoom |

## Testing

Per [CLAUDE.md](../../CLAUDE.md) / [testing.md](../../documentation/testing.md),
start narrow:

- **Unit (no SDL):** `adjust_user_zoom!` steps/clamps/reset correctly and
  `_recompute_display_scale!` composes base × zoom. `_zoom_delta` maps
  `KeyDown(:equals; ctrl)` → +1, `:minus` → −1, `:0` → 0, others → `nothing`.
- **Layout invariance:** assert projected canvas geometry is unchanged by zoom
  for a fixed logical viewport (same property the display-scale work verified:
  json_example identical at scale 1/2/3) — confirms zoom doesn't leak into
  layout.
- **Reader:** drive `read!` with a synthetic `Ctrl+=` envelope (no projection
  claiming it) and assert an `AdjustZoomOperation(+1)`; with a clipboard
  collection focused, assert the clipboard op still wins.
- **Render smoke:** `write_example_image` at a couple of zoom factors to eyeball
  crisp, larger glyphs and the shrunken logical viewport.
- After the targeted tests pass, a broad `test_printers`/`test_readers` sweep to
  confirm no regressions from the `_DISPLAY_SCALE` refactor.

## Decisions to confirm before implementing

1. **Conflict resolution** with clipboard `Ctrl+=`/`Ctrl+-`: recommended =
   global *fallback* (clipboard wins when active). Alternatives: zoom always
   wins, or move zoom to `Ctrl+Shift+=/−`.
2. **Reset gesture:** `Ctrl+0` (needs digit-key mapping verified/added) vs.
   another binding.
3. **Web backend:** implement an in-app zoom, or rely on the browser's own zoom
   and do nothing there.
