# Readability scaling: independent font-zoom and full-zoom knobs

**Date:** 2026-06-27 (revised)
**Status:** 📝 proposed — not yet implemented

## Goal

Two **separately controllable** readability knobs, each with its own shortcuts:

1. **Font-only zoom** — make *text* bigger/smaller while fixed graphics, images,
   paddings and explicit spacing stay put. The "font scaling for readability"
   knob. (Layout that *sizes itself to text* still grows; only hard-coded pixel
   geometry stays fixed.)
2. **Full uniform zoom** — magnify *everything* proportionally (glyphs, boxes,
   spacing, images, carets), like a browser's Ctrl+/Ctrl−.

The two compose: a user can run, say, full-zoom 125% **and** font-zoom 150% at
once. Each has its own state, shortcuts, and reset.

## Background: the existing scale boundary

Per [plan/done/global-display-scale.md](../done/global-display-scale.md), there
is already a single global **logical→device** factor, `_DISPLAY_SCALE`
([Font.jl:89](../../package/domain/src/document/Font.jl#L89)), applied **only at
the SDL edge**:

- All layout is in **logical pixels** and never reads `_DISPLAY_SCALE`; projected
  canvas geometry is identical at scale 1/2/3 *for a fixed logical viewport*.
- `measure_text` ([ProjecturedSdl.jl:1511](../../package/sdl/src/ProjecturedSdl.jl#L1511))
  rasterizes glyphs at device size then divides back by `_DISPLAY_SCALE` →
  returns logical size.
- `_get_font` ([ProjecturedSdl.jl:617](../../package/sdl/src/ProjecturedSdl.jl#L617))
  and the text-texture cache key on `font_scaled_size(size) = round(size *
  _DISPLAY_SCALE)` ([Font.jl:99](../../package/domain/src/document/Font.jl#L99)) —
  i.e. on the **device** size — so a larger size re-rasterizes crisply.
- The renderer scales once via `SDL_RenderSetScale`
  ([ProjecturedSdl.jl:1401](../../package/sdl/src/ProjecturedSdl.jl#L1401)); input
  converts back via `_to_logical` ([ProjecturedSdl.jl:507](../../package/sdl/src/ProjecturedSdl.jl#L507)).

The two knobs hook this boundary at different points (see the size pipeline
below), which is exactly *why* one is font-only and the other is uniform.

## The size pipeline (where each knob lives)

A glyph's size flows: `font.size` (authored, in the document/projection) →
**logical** size (what layout measures and positions in) → **device** size (what
the GPU rasterizes). The two knobs insert at the two arrows:

```
font.size ──×_FONT_ZOOM──► logical size ──×_DISPLAY_SCALE──► device size
            (font-only)                    (= base_dpi × _USER_ZOOM; full zoom)
```

- **`_FONT_ZOOM`** multiplies the *logical* text size, so layout reflows around
  bigger text **but non-text geometry (read directly in pixels, not via a font)
  is untouched** → font-only.
- **`_USER_ZOOM`** feeds `_DISPLAY_SCALE`, which is read *only at the device
  edge* and applied uniformly to all geometry → full zoom.

Define in [Font.jl](../../package/domain/src/document/Font.jl):

```julia
const _FONT_ZOOM          = Ref(1.0)   # font-only readability zoom
const _BASE_DISPLAY_SCALE = Ref(1.0)   # DPI scale, detected once at window open
const _USER_ZOOM          = Ref(1.0)   # full uniform zoom
const _DISPLAY_SCALE      = Ref(1.0)   # effective = base × user_zoom (read everywhere as today)

_recompute_display_scale!() = (_DISPLAY_SCALE[] = _BASE_DISPLAY_SCALE[] * _USER_ZOOM[])

# Logical text size after font-zoom — what LAYOUT must use in place of raw font.size.
font_logical_size(font::StyleFont) = max(1, round(Int, font.size * _FONT_ZOOM[]))

const _ZOOM_STEPS = (0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)
_stepped(cur, delta) = delta == 0 ? 1.0 :
    _ZOOM_STEPS[clamp(argmin(abs.(collect(_ZOOM_STEPS) .- cur)) + delta, 1, length(_ZOOM_STEPS))]

adjust_font_zoom!(delta::Int) = (_FONT_ZOOM[] = _stepped(_FONT_ZOOM[], delta))
adjust_user_zoom!(delta::Int) = (_USER_ZOOM[] = _stepped(_USER_ZOOM[], delta); _recompute_display_scale!(); _USER_ZOOM[])
```

`font_scaled_size(size::Integer)` stays as-is (device = `round(logical *
_DISPLAY_SCALE)`); callers feed it `font_logical_size(font)` instead of raw
`font.size`. The combined device size is then `round(round(font.size *
_FONT_ZOOM) * _DISPLAY_SCALE)`. (If double-rounding ever matters for crispness,
add `font_device_size(font) = max(1, round(Int, font.size * _FONT_ZOOM[] *
_DISPLAY_SCALE[]))` and use it at the rasterization sites.)

## Implementation by knob

### A. Full uniform zoom (`_USER_ZOOM`) — small, contained

This is the original plan and barely touches anything beyond the backend:

- **`Font.jl`:** the `_BASE_DISPLAY_SCALE` / `_USER_ZOOM` / `_recompute_…` split
  above.
- **SDL DPI detection** ([ProjecturedSdl.jl:535-602](../../package/sdl/src/ProjecturedSdl.jl#L535)):
  write the detected DPI into `_BASE_DISPLAY_SCALE[]` + call
  `_recompute_display_scale!()`; change the `_DISPLAY_SCALE[] == 1.0`
  "already detected?" guards to test `_BASE_DISPLAY_SCALE[]`;
  `PROJECTURED_DISPLAY_SCALE` env override sets the base.
- Glyph crispness, render scale, and mouse mapping all already read
  `_DISPLAY_SCALE` → no change. Just needs **viewport reflow + repaint**
  (Wrinkles 1–2).

### B. Font-only zoom (`_FONT_ZOOM`) — more invasive (touches layout)

Font-only must make text *logically* bigger, so every place that reads a font's
size **for measurement, line/caret height, or rasterization** must route through
`font_logical_size(font)` instead of raw `font.size`. Audit and update:

- **Layout heights/metrics** in
  [TextToGraphics.jl](../../package/domain/src/projection/primitive/TextToGraphics.jl):
  the `font.size` / `sc.font.size` / `elem.font.size` reads used for segment,
  highlight and band heights (~lines 654, 770, 820) → `font_logical_size(...)`.
- **Per-line metrics** for `TextNewline` / `TextSpacing` and any baseline/gap
  derived from font size ([Text.jl](../../package/domain/src/document/Text.jl)
  consumers) → `font_logical_size(...)`.
- **Measurement** [`measure_text`](../../package/sdl/src/ProjecturedSdl.jl#L1511)
  and its empty-string fast path (`return (0, font.size)`) → use
  `font_logical_size(font)`; the device rasterization goes through
  `_get_font` which is updated next, and the result is divided by
  `_DISPLAY_SCALE` to stay logical.
- **Rasterization keys** [`_get_font`](../../package/sdl/src/ProjecturedSdl.jl#L617)
  and the text-texture key ([line 636](../../package/sdl/src/ProjecturedSdl.jl#L636)):
  `font_scaled_size(font_logical_size(font))` so font-zoom participates in the
  cache key and re-rasterizes crisply.

**Caret/selection geometry must follow text.** Anything that draws a caret or
selection band whose height comes from the font has to use the same
`font_logical_size`, or carets will desync from glyphs. This is the main
correctness risk and what makes font-only the heavier change.

**Invalidation.** `_FONT_ZOOM` is a plain global ref; the reactive layout cells
won't know it changed. On a font-zoom change, force a **full reprint** by
clearing the cached iomap (`editor.iomap = nothing`, then `print!` recomputes) +
repaint. *Alternative (cleaner, incremental):* make `_FONT_ZOOM` a reactive
`Cell` so `font_logical_size` reads register a dependency and only the affected
layout invalidates — preferred if the extra wiring is acceptable. Full uniform
zoom does **not** need a relayout for size (geometry is scale-invariant in
logical space) — only for the viewport change (Wrinkle 1).

## Operations and gestures

Two operations, mirroring each other. Struct in **kernel** (no-op default
`evaluate_operation`, so non-SDL backends ignore them), real methods in the
backend — the existing cross-layer `evaluate_operation` pattern.

- **kernel** [`Operation.jl`](../../package/kernel/src/common/Operation.jl):
  ```julia
  struct AdjustZoomOperation     <: Operation; delta::Int; end   # full zoom
  struct AdjustFontZoomOperation <: Operation; delta::Int; end   # font-only
  ```
- **sdl** [`ProjecturedSdl.jl`](../../package/sdl/src/ProjecturedSdl.jl):
  ```julia
  function evaluate_operation(editor, op::AdjustZoomOperation)
      adjust_user_zoom!(op.delta); _reflow_for_scale!(editor); _force_full_repaint!(editor)
  end
  function evaluate_operation(editor, op::AdjustFontZoomOperation)
      adjust_font_zoom!(op.delta); editor.iomap = nothing; _force_full_repaint!(editor)
  end
  ```

**Gestures — editor-global fallback in [`read!`](../../package/kernel/src/editor/Editor.jl#L80)**
(after the projection pipeline returns no op, like the existing `QuitEvent`
special-case), so they work regardless of selection yet yield to any projection
that explicitly binds the keys (resolves the clipboard conflict below):

| Action | Recommended binding |
|--------|--------------------|
| Full zoom in / out / reset | `Ctrl+=` · `Ctrl+-` · `Ctrl+0` |
| Font zoom in / out / reset | `Ctrl+Shift+=` · `Ctrl+Shift+-` · `Ctrl+Shift+0` |

`:equals` (incl. keypad `+`) and `:minus` (incl. keypad `-`) are already mapped
in both backends ([ProjecturedSdl.jl:362](../../package/sdl/src/ProjecturedSdl.jl#L362),
[ProjecturedWeb.jl:161](../../package/web/src/ProjecturedWeb.jl#L161)); `Modifiers`
carries `shift` independently of the keysym, so the `Ctrl+Shift` variants come
for free. Verify the `0` keysym is mapped for the resets (add `48 → :0` / keypad
`0` if not). A single `_zoom_gesture(env)` helper returns
`(:full|:font, +1|-1|0)` or `nothing`.

**Conflict:** `Ctrl+=`/`Ctrl+-` are bound by the clipboard-collection projection
for add/remove ([ClipboardToAny.jl:405](../../package/domain/src/projection/primitive/ClipboardToAny.jl#L405)).
The *fallback* placement means clipboard keeps those keys when a collection is
focused and zoom works everywhere else. (Decision: which knob gets bare `Ctrl`
vs `Ctrl+Shift` — recommended bare `Ctrl` = full zoom for browser muscle memory;
trivially swappable.)

## Wrinkles (shared)

1. **Viewport reflow (`_reflow_for_scale!`, full-zoom only).** The window's
   *device* size is fixed, so its *logical* size = device ÷ `_DISPLAY_SCALE`
   shrinks as you zoom in → fill/wrap/scroll layout must reflow. Recompute each
   window's logical `width`/`height` from its device size and apply via the
   existing resize path ([`ResizeWindowOperation`](../../package/kernel/src/common/Operation.jl#L389)).
   **Risk:** the backend must not react by resizing the *device* window — only
   relayout.
2. **Force full repaint (`_force_full_repaint!`).** Rendering is dirty-rect
   ([`_render_window!`](../../package/sdl/src/ProjecturedSdl.jl#L1398)); on either
   zoom change everything moves, so invalidate the whole window for the next
   frame. Retained render target is device/window-sized → unaffected.
3. **Cache hygiene.** `_font_cache` / text-texture cache key on the device size
   (now including both factors) → self-populate fresh entries; old ones linger.
   Optional eviction to cap memory.
4. **Other backends.** `write_image`'s offscreen renderer drives scale itself
   ([line 1639](../../package/sdl/src/ProjecturedSdl.jl#L1639)) — unaffected;
   could honor `_FONT_ZOOM` for headless previews. Web stays `_DISPLAY_SCALE=1.0`
   ([web-backend plan](../done/web-backend.md#L111)) — give it parallel handlers
   or rely on the browser's own (full) zoom; font-zoom there reuses the same
   `font_logical_size` path.

## Files to touch

| File | Full zoom | Font zoom |
|------|-----------|-----------|
| [domain/.../Font.jl](../../package/domain/src/document/Font.jl) | `_BASE_DISPLAY_SCALE`,`_USER_ZOOM`,`_recompute…`,`adjust_user_zoom!` | `_FONT_ZOOM`,`font_logical_size`,`adjust_font_zoom!`; `_ZOOM_STEPS`,`_stepped` shared; exports |
| [kernel/.../Operation.jl](../../package/kernel/src/common/Operation.jl) | `AdjustZoomOperation` | `AdjustFontZoomOperation` |
| [kernel/.../Editor.jl](../../package/kernel/src/editor/Editor.jl) | `_zoom_gesture` + fallback branch in `read!` (both) | — |
| [sdl/.../ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl) | DPI→`_BASE_…`; `evaluate_operation`; `_reflow_for_scale!`; `_force_full_repaint!`; verify `:0` | route `_get_font`/texture-key/`measure_text` through `font_logical_size`; `evaluate_operation` |
| [domain/.../TextToGraphics.jl](../../package/domain/src/projection/primitive/TextToGraphics.jl) | — | layout/caret/band heights → `font_logical_size` |
| (optional) web/console backends | parallel handlers / native zoom | reuse `font_logical_size` |

## Testing

Per [CLAUDE.md](../../CLAUDE.md) — start narrow, never `test_all` first:

- **Unit (no SDL):** `adjust_font_zoom!`/`adjust_user_zoom!` step/clamp/reset and
  compose independently; `font_logical_size` scales with `_FONT_ZOOM` only;
  `_recompute_display_scale!` = base × user_zoom; `_zoom_gesture` maps each
  Ctrl / Ctrl+Shift combo correctly.
- **Font-only layout grows, chrome doesn't:** project a doc mixing text and a
  fixed-size graphic; assert text bounding boxes scale with `_FONT_ZOOM` while
  the fixed graphic's bounds are unchanged. Caret/selection band height tracks
  the scaled text.
- **Full-zoom layout invariance:** with a fixed logical viewport, canvas geometry
  is unchanged by `_USER_ZOOM` (the scale-1/2/3 property) — confirms it never
  leaks into layout.
- **Reader:** synthetic `Ctrl+=` → `AdjustZoomOperation(+1)`, `Ctrl+Shift+=` →
  `AdjustFontZoomOperation(+1)`; with a clipboard collection focused, clipboard
  op still wins.
- **Render smoke:** `write_example_image` at a few `(_FONT_ZOOM, _USER_ZOOM)`
  combinations.
- Broad `test_printers`/`test_readers` sweep last, to catch regressions from the
  `font.size` → `font_logical_size` audit.

## Decisions to confirm

1. **Binding assignment:** bare `Ctrl` = full zoom, `Ctrl+Shift` = font-only
   (recommended) — or swap.
2. **Clipboard conflict:** fallback (clipboard wins when active; recommended) vs.
   unconditional zoom vs. an entirely different chord.
3. **Reset key:** `Ctrl+0` / `Ctrl+Shift+0` (verify/add `:0` mapping) vs. another.
4. **Font-zoom invalidation:** brute-force full reprint (simpler) vs. make
   `_FONT_ZOOM` a reactive `Cell` for precise incremental invalidation
   (cleaner).
5. **Web backend:** in-app zoom handlers vs. rely on the browser's native zoom.
