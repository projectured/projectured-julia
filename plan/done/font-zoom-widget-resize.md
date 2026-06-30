# Font-zoom: widgets do not resize

**Date:** 2026-06-30
**Status:** ✅ implemented 2026-06-30
**Branch / worktree:** `font-zoom-widget-resize` (`../projectured-julia-font-zoom`)

## Symptom

Turning the **font-zoom** knob (`Ctrl+Alt+=` / `-` / `0`,
`AdjustFontZoomOperation`) enlarges the *glyphs* inside text widgets but the
widget **boxes do not grow to contain them** — text overflows / is clipped, and
nothing reflows. The uniform display-zoom knob (`Ctrl+=`, `AdjustZoomOperation`)
works fine.

## Root cause

The editor projects **once** and then re-renders reactively:

```julia
# package/kernel/src/editor/Editor.jl
function print!(editor::Editor)
    if editor.iomap === nothing
        editor.iomap = projection_print(editor.projection, editor.document)
    end
    write_to_devices(editor.backend, editor.devices, editor.iomap.output)
end
```

Font-zoom (`AdjustFontZoomOperation`) only writes the reactive `_FONT_ZOOM`
`Cell`. That invalidates layout cells **that read `font_logical_size` inside a
thunk** — which is exactly what `TextToGraphics` does (its canvas `w`/`h` are
`Cell`s, lines 367–378), so bare text reflows.

`WidgetToGraphics`, however, measures content **eagerly during
`projection_print`** and bakes the result into the canvas as **constant
`Int32`** via `_make_canvas` (~50 printers). Those values are not cells, so the
`_FONT_ZOOM` write never reaches them and the widget boxes stay frozen. The
glyphs still grow because the SDL backend rasterizes at
`font_device_size = font.size * _FONT_ZOOM * _DISPLAY_SCALE`.

This is the gap left by `plan/done/font-size-scaling.md`, which routed
`font_logical_size` through `Graphics.jl` / `TextToGraphics.jl` /
`GraphicsCaching.jl` / web — but **not** `WidgetToGraphics.jl`. Its stated intent
was: *"layout that sizes itself to text still grows; only hard-coded pixel
geometry stays fixed."* For widgets, neither half happens today.

## Approach — re-project on font-zoom (chosen)

Make `AdjustFontZoomOperation` drop `editor.iomap` so the next `print!`
re-runs `projection_print` with the new `_FONT_ZOOM`. Every widget printer then
re-measures via `p.measure` (which reads `font_logical_size`), so content boxes
grow to fit the larger text, while hard-coded paddings / positions
(`_sc` / `_origin`, identity markers) stay fixed — exactly the documented
font-zoom semantics. General (covers all ~50 widgets incl. flow containers),
small, and low-risk.

### Why re-projection is safe here

- **Window reconciliation is by id, not identity.** `write_to_devices`
  (ProjecturedSdl.jl:2314) reconciles `backend.windows` keyed by
  `WindowDocument.id` (a `Symbol`). A fresh output tree with the same ids reuses
  the native windows (`_update_window_geometry!`) and just re-renders content.
- **Transient widget state lives on the document, not the projection.** Scroll /
  pan position is `getfield(w, :scroll_position)` on the widget document; hover
  is the document's `hovered` field; selection is on the document. All survive a
  re-projection because each fresh print reads them back from the document.
- **SDL caches are content-keyed and bounded, so nothing leaks.**
  `_text_texture_cache` is keyed by (text, font, color) with a cap +
  `_clear_text_texture_cache!`; `_font_cache` by (file, size). Neither is keyed
  by canvas-object identity, so dropping the old tree frees nothing that the new
  tree won't reuse. `_force_full_repaint!` already bypasses the dirty-rect path
  (`first_paint = true`), so stale `objectid`s from the old tree don't matter.
- **Cost is a single full re-projection per keystroke** — font-zoom is a rare,
  user-initiated action, so this is acceptable (display-zoom deliberately avoids
  re-projection because it can fire during fast repeats and only needs a uniform
  render-scale change; font-zoom genuinely changes intrinsic content sizes that
  only re-measurement can capture).

## Changes

1. **`package/sdl/src/ProjecturedSdl.jl`** — in
   `evaluate_operation(editor, op::AdjustFontZoomOperation)`, set
   `editor.iomap = nothing` (before `_force_full_repaint!`) so the next `print!`
   re-projects. Update the explanatory comment block above it to describe
   re-projection (replacing the now-inaccurate "only text relayouts" note).

2. **Comments** — fix the stale claim in
   `package/example/src/document/Widget.jl` (lines ~173–175) that "the widget
   projection scales every widget's position by the font scale at render time"
   (`_origin` is identity); clarify that font-zoom re-measures content while
   authored positions stay logical/fixed.

## Out of scope (future work)

- Making each widget printer's canvas `w`/`h` reactive cells (the
  `TextToGraphics` pattern) to avoid re-projection entirely — a large, invasive
  refactor across ~50 printers + flow containers. Recorded as the alternative;
  not needed for correctness.
- Web backend: font-zoom there rides the browser zoom (ProjecturedWeb.jl:780);
  no `AdjustFontZoomOperation` handler exists. Unchanged.
- Scaling authored widget **positions/paddings** with font-zoom — intentionally
  left fixed per the font-size-scaling design.

## Verification (done)

- **`test_printer(widget_example)` → 6913/6913 pass.** No regression; the change
  is a no-op at the default zoom (`_FONT_ZOOM == 1.0`).
- **ProjecturedSdl precompiles clean** with the edit.
- **Premise check (SDL-free, scratch script):** re-running `projection_print`
  for the content-sized `WidgetLabel` example at `_FONT_ZOOM = 2.0` grows its
  geometry `(160,60) → (280,80)` — proportional to `font_logical_size`. This is
  exactly what `print!` re-runs once `editor.iomap` is dropped, so under SDL the
  widget boxes re-fit the larger text.
- Manual (SDL GUI) not run in this environment.

### Findings worth recording

- The two text measurers disagree on font-zoom: **`sdl_measure_text`** loads the
  font at `font_device_size` (includes `_FONT_ZOOM`) and divides back by
  `_DISPLAY_SCALE` only, so it *does* scale with font-zoom. **`pdf_measure_text`
  / `truetype_measure_text`** (the SDL-free default used by the test harness)
  measures at the raw `font.size` and **ignores `_FONT_ZOOM`**. So in the real
  GUI widgets grow; the pure-Julia layout (PDF export, tests) does not. Not
  changed here (export at a fixed size is the right default), but noted as a
  latent inconsistency.
- The gallery `widget_example` is a fixed-size `WidgetShell` (≈1024×768): its
  outer extent is pinned, so growth shows on the inner widgets, not the frame.
  The per-widget examples (`WidgetLabel`, …) are content-sized and show it
  directly.

## Progress

- [x] Worktree + plan
- [x] Implement re-projection in the SDL font-zoom handler + comment updates
- [x] Fix stale comment in example/Widget.jl
- [x] Targeted test run (`test_printer(widget_example)` 6913/6913; SDL precompiles; premise script PASS)
- [x] Move plan to `plan/done/`
