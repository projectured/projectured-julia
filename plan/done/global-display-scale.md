# Make the display scale truly global (logical pixels everywhere)

**Date:** 2026-06-14
**Status:** ✅ implemented 2026-06-14 (boundary approach). See "Implementation
notes" below for what shipped and where it diverged from this plan.

## Implementation notes (what shipped)

Chosen approach: **boundary** — one logical coordinate space everywhere, a
single `_DISPLAY_SCALE` (logical→device) applied at the SDL edge. (The
"uniform single-space / keep everything physical" alternative was rejected: the
boundary model is the correct, future-proof one.)

Changes:

- **`_FONT_SCALE` → `_DISPLAY_SCALE`** ([Font.jl](../../program/src/document/Font.jl)),
  reframed as the global logical→device factor; env var
  `PROJECTURED_FONT_SCALE` → `PROJECTURED_DISPLAY_SCALE`; detection functions
  `_detect_font_scale!`/`_update_font_scale!` → `_detect_display_scale!`/
  `_update_display_scale!`. `font_scaled_size` kept, now **backend-only** (glyph
  rasterization in `_get_font`).
- **Layout is fully logical:** removed `font_scaled_size` from
  [TextToGraphics.jl](../../program/src/projection/primitive/TextToGraphics.jl)
  (highlight/band heights → plain `font.size`),
  [Graphics.jl](../../program/src/document/Graphics.jl) hit-test,
  [GraphicsCaching.jl](../../program/src/projection/primitive/GraphicsCaching.jl)
  bounds. In
  [WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl),
  `_sc`/`_origin` were made **identity markers** (kept, not deleted — they
  document "this is a logical-pixel measurement" across ~100 call sites; far
  less churn than deleting, same runtime).
- **Measurement is logical** ([Sdl.jl](../../program/src/backend/Sdl.jl)
  `measure_text`): rasterize at device size, divide back by `_DISPLAY_SCALE`
  (option A). No caret drift in practice — advance and drawn-width both derive
  from the same divided value, so they stay consistent; round-trip tests pass at
  scale 2.
- **Backend scales once at the boundary:** `_render_window!` sets
  `RenderSetScale(ss * scale)`; the SSAA target is sized in device pixels
  (`_to_device(width) * ss`); `GraphicsText` dest rects are logical
  (`device ÷ scale`) so the device-size glyph texture lands 1:1.
- **Device↔logical at the edges:** `_to_device`/`_to_logical` helpers. Native
  window create/resize use device pixels; incoming mouse + resize events are
  converted back to logical.
- **Tests:** [ClickRoundtripTest.jl](../../test/src/editor/ClickRoundtripTest.jl)
  expectations switched to logical `font.size`.

Verification: full sweep (`test_printers/readers/selections/repls`,
`test_click_roundtrip`, `test_write_image`, `test_event_case`,
`test_mouse_clicks`, `test_cell`) — **zero regressions** (the two failures seen,
`object_to_widget` selection and `searching` mouse-click, reproduce identically
on the clean tree and are unrelated). The projected canvas geometry is now
**identical at scale 1, 2 and 3** (json_example: 396×624 at every scale),
proving the scale no longer leaks into layout.

Known follow-up (not blocking, single testable platform is X11/Xft here):
auto-HiDPI-density platforms (macOS Retina, native Wayland) where SDL itself
provides the extra pixels need the renderer-ratio detection path to *not* also
enlarge the window — the single-factor model currently assumes SDL window/mouse
coords are in device pixels (true on X11). Revisit when targeting those.

---

## Original plan

## Problem

`_FONT_SCALE` is named and documented as a *font* scale, but its actual job is
to make the editor's graphical output **independent of the OS's
(fractional) display scaling** — a `font_*_24` glyph and the box around it
should occupy the same physical size at 100%, 150%, or 200% OS scaling. That
is a property of the *whole* rendered frame: sizes, stroke widths, radii,
spacing, **and** positions, not just glyph rasterization.

Today it is applied **piecemeal**, in two different coordinate regimes:

1. **Text** — `measure(text, font)` (= `sdl_measure_text` →
   [`measure_text`](../program/src/backend/Sdl.jl#L786)) rasterizes the font at
   `font_scaled_size(font.size)` and returns **physical** pixel widths. So every
   `SegCoord.x/.y` and every emitted `GraphicsText.x/.y` in
   [TextToGraphics.jl](../program/src/projection/primitive/TextToGraphics.jl)
   accumulates in **already-scaled (physical)** space. Line height is
   `font_scaled_size(...)` too.
2. **Widgets** — authored `position`/insets/radii are **logical** pixels and
   are scaled at render time, by hand, via
   [`_sc` / `_origin`](../program/src/projection/primitive/WidgetToGraphics.jl#L246-L256).

Everything else — `GraphicsRect.w/h`, stroke widths, viewport boxes, raw
`GraphicsLine`/`GraphicsCircle` coordinates — is **not** scaled at all. The
result is the half-scaled feel: fonts and a few widget paddings track DPI;
arbitrary geometry does not. The naming (`_FONT_SCALE`, `font_scaled_size`,
`_sc`) actively hides that this is meant to be one global knob.

## The irony: the clean mechanism already exists

The backend already does exactly the "scale once at the boundary" trick — but
only for **supersampling** (`res.ss`), not for the DPI scale:

```
# _render_window!  (Sdl.jl:756-768)
SDL_RenderSetScale(res.renderer, ss, ss)   # draw everything in logical coords
_render_canvas!(...)                        # no manual *ss multiplies anywhere
SDL_RenderSetScale(res.renderer, 1, 1)
SDL_RenderCopy(...)                         # downsample for AA
```

`ss` magnifies *all* geometry uniformly with zero per-element multiplies. The
DPI scale should ride the **same** mechanism. `ss` is net-neutral on size
(render N×, downsample N×, pure anti-aliasing); the DPI scale is a real
magnification — they compose as a single `RenderSetScale(ss * dpi_scale)` on
vector geometry.

## Target architecture

**Invariant: all layout/geometry stays in logical pixels until a single
conversion at the SDL boundary.**

- All projection output (`GraphicsText/Rect/Line/Circle/Viewport`, all
  `SegCoord`s, all widget geometry) is in **logical** pixels. No
  `font_scaled_size` / `_sc` / `_origin` anywhere in the projection layer.
- The backend applies the DPI scale exactly once, composed with supersampling,
  via `SDL_RenderSetScale`.

**The one genuine exception — glyph rasterization.** A glyph is a bitmap; if it
is rasterized at logical size and magnified by `RenderSetScale`, you get a
blurry upscaled bitmap (the `ss` downsample does *not* rescue it — that only
cancels the supersample factor). So glyphs must still be **rasterized at the
physical size** `size * dpi_scale * ss`, and then drawn into a **logical**
destination rect. With `RenderSetScale = ss * dpi_scale`, a logical dest of
`phys/(ss·dpi)` maps to `phys` device pixels and the physical-size texture
lands 1:1 → crisp. So:

- **Fonts:** rasterize at physical size (today's `font_scaled_size`, extended
  to include `ss`); position + size the dest rect in **logical** coords.
- **Everything else:** logical coords, scaled once at the boundary.

## The load-bearing change: text measurement is logical

This is the crux and the riskiest part. `measure(text, font)` must return
**logical** widths so `SegCoord`/`GraphicsText` positions accumulate in logical
space. But the rasterized font is at physical size, so `TTF_SizeUTF8` reports
physical widths. Two options:

- **(A) Measure at physical, divide back:** `logical_w = round(phys_w /
  dpi_scale)`. Simple, but rounding per-segment can drift the cursor/advance vs.
  the crisp physical glyph run.
- **(B) Keep a logical-size font handle for measurement only**, rasterize a
  physical-size handle for drawing. Cleaner advances, doubles the font cache.

Recommend **(A)** first (least churn; the drift is sub-pixel and the dest rect
is physical-exact anyway), and only move to (B) if cursor/caret alignment in
long lines proves visibly off in `test_repl`/click round-trip.

Either way `measure` must stop baking scale into the numbers that layout sees.

## Step-by-step

1. **Rename + reframe the scale.**
   `_FONT_SCALE → _DISPLAY_SCALE` in
   [Font.jl](../program/src/document/Font.jl); keep `font_scaled_size`/
   `_FONT_SCALE` as thin deprecated aliases for one transition so nothing
   breaks mid-refactor. Compose with `ss` at the call site, not in the name.

2. **Backend: scale at the boundary.**
   In `_render_window!`/`_render_canvas!`
   ([Sdl.jl](../program/src/backend/Sdl.jl#L754)), set
   `RenderSetScale(renderer, ss * dpi, ss * dpi)` for the whole frame (replacing
   the `ss`-only call). Confirm the SSAA target sizing
   (`_ensure_ss_target!`) and the final `RenderCopy` downsample still use `ss`
   only (the dpi part is *not* downsampled away).

3. **Backend: glyph drawing.**
   `_get_font`/`measure_text`/`_render_element!(::GraphicsText)`
   ([Sdl.jl:440-468](../program/src/backend/Sdl.jl#L440-L468)) rasterize at
   `size * dpi * ss` (physical) but place the dest rect using **logical**
   `elem.x/elem.y` and **logical** width = the physical texture size divided by
   `ss*dpi`. Verify 1:1 mapping (crisp text) on a hi-dpi run.

4. **Text layer → logical.**
   Make `measure` return logical widths (option A above). Drop every
   `font_scaled_size` in
   [TextToGraphics.jl](../program/src/projection/primitive/TextToGraphics.jl)
   (lines ~860, 911-912: highlight height, band height) and replace with the
   plain logical `font.size`. `SegCoord`/cursor/caret math then lives entirely
   in logical space. Re-check `_seg_cursor_x`, `_char_position_at_x`, and the
   click hit-test bands (`_seg_band_height`).

5. **Widget layer → drop manual scaling.**
   Delete `_sc`/`_origin` from
   [WidgetToGraphics.jl](../program/src/projection/primitive/WidgetToGraphics.jl#L246-L256);
   emit authored positions/insets/radii/spacing directly as logical. (Note: the
   "scale at render not construction-time, because precompile runs at scale 1.0"
   hazard the current comment warns about **disappears** — construction-time
   logical values are now correct by definition.)

6. **Other graphics consumers.**
   - `Graphics.jl:425`, `GraphicsCaching.jl:71/151` use `font_scaled_size` for
     bounds/keys — switch to logical `font.size`. Make sure the
     [GraphicsCaching](../program/src/projection/primitive/GraphicsCaching.jl)
     cache key no longer mixes scaled values (cache becomes scale-independent,
     which is correct and desirable).
   - `write_image` ([Sdl.jl:874](../program/src/backend/Sdl.jl#L874)) already
     supersamples its software renderer with `RenderSetScale(S)`; it should use
     `dpi = 1.0` (images are authored at logical size — we do **not** want
     screenshots to inherit the developer's monitor DPI). Confirm `write_image`
     ignores `_DISPLAY_SCALE` entirely.

7. **Tests that hard-code the scaled geometry.**
   [ClickRoundtripTest.jl](../test/src/editor/ClickRoundtripTest.jl#L130) uses
   `font_scaled_size` to recompute expected y-bands. With layout now logical,
   these become plain `font.size`. Update and run `test_selection` +
   click-roundtrip with `PROJECTURED_FONT_SCALE=2` to prove geometry is
   scale-invariant.

## Risks / things to watch

- **Double-scaling regressions.** Any spot still calling `font_scaled_size`
  while the renderer also scales will be 2× too big. The deprecated-alias step
  is there to grep them out one at a time; the refactor isn't done until
  `font_scaled_size` has **zero** call sites in the projection layer.
- **Caret/cursor drift** from logical measurement rounding (the option A/B
  question) — verify in `test_repl(text_example)` and the click round-trip.
- **Click hit-testing space.** Mouse events arrive in window-logical pixels;
  with layout now logical too, the event coordinates and `SegCoord`s finally
  live in the **same** space (today the backend has to reconcile physical
  layout vs. logical events). Confirm `_char_position_at_x` no longer needs any
  scale fixup.
- **`ss` vs. `dpi` separation.** Keep them distinct in code even though they
  multiply together at the boundary: `ss` sizes the offscreen target and is
  downsampled away; `dpi` is not. Conflating them breaks AA or magnification.

## Verification

- `PROJECTURED_FONT_SCALE=1` and `=2` runs of the same example produce
  geometrically identical layouts (one just larger) — same wrapping, same
  relative positions, crisp text at both.
- `test_selection` / click round-trip pass at scale 1 and 2 unchanged.
- `write_image` output is byte-stable regardless of the host's detected DPI.

## Smallest tests to drive this

- Text math: `test_repl(text_example)`, `test_selection(text_example)`.
- Click bands: the editor click round-trip test.
- Widgets: `test_printer` on a widget example + a manual hi-dpi screenshot.
- Don't reach for `test_all` until the targeted ones pass at both scales.
