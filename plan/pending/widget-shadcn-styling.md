# shadcn/ui look & feel for the widget domain

Restyle the existing widgets to match [shadcn/ui](https://ui.shadcn.com), and
extend the widget set with the most useful shadcn components that are missing.
New widgets may be **printer-only** for now (a stub reader is fine).

**Primary goal: a consistent, beautiful set of widgets.** Consistency matters
more than preserving any current look — one theme drives every widget, and
per-instance colors are migrated away so the whole gallery reads as a single
coherent design system.

## Why

The current widgets render with ad-hoc per-instance colors set at each
construction site, square 1px borders, and placeholder glyphs (the checkbox is
literally the text `"[x]"` / `"[ ]"`). The result reads as a debug skin, not a
design system. shadcn/ui gives us a small, coherent token set (neutral zinc
palette, soft rounded corners, muted surfaces, a single accent/"primary", a
focus ring) that we can adopt wholesale, plus a well-known component vocabulary
to grow into.

## Where styling lives today (two layers)

1. **Construction time** — each widget document carries its own box-model
   fields (`margin/border/padding` + their colors, `content_fill_color`, …) in
   `program/src/document/Widget.jl`. Example builders in
   `example/src/document/Widget.jl` set these per instance.
2. **Render time** — `program/src/projection/primitive/WidgetToGraphics.jl`
   turns each widget into `GraphicsRect` + `GraphicsText` elements. A few colors
   are hardcoded in the projection structs/factory: `default_fg`, the scrollbar
   `track_color`/`thumb_color`, the tabbed-pane `selector_fg`, and the checkbox
   glyph. The single factory is
   `WidgetToGraphics(font; measure, default_fg)` (`WidgetToGraphics.jl:1628`),
   which builds the per-type dispatch table.

Two capabilities we already have and will lean on:

- `GraphicsRect` supports **per-corner radius** (`radius_tl/tr/br/bl`) and the
  SDL backend renders rounded corners (`Sdl.jl:_render_rect!`, scanline fill —
  **no anti-aliasing**, so curves are slightly stair-stepped).
- The box model is painted by `_push_box_rects!` (`WidgetToGraphics.jl:184`),
  which draws the border as **four square-cornered rectangles**. That is the
  main thing standing between us and shadcn's rounded 1px outline.

The backend is **not fixed** — we will extend it (see *Backend* below). Today's
renderer (`program/src/backend/Sdl.jl`) sits on SDL2 + SDL_ttf + SDL2_image:
text already renders anti-aliased (`TTF_RenderUTF8_Blended`), rects do not, and
`write_image` renders a canvas offscreen to a software renderer and saves a PNG
(`IMG_SavePNG`) — no window needed, which is our visual-diff channel.

## Design: a `WidgetTheme` token object

Introduce a theme/token struct that mirrors shadcn's CSS variables and thread it
through the projection factory instead of the loose `default_fg`.

```julia
struct WidgetTheme
    # surfaces
    background; foreground
    card; card_foreground
    popover; popover_foreground
    muted; muted_foreground
    # accents
    primary; primary_foreground
    secondary; secondary_foreground
    accent; accent_foreground
    destructive; destructive_foreground
    # lines / focus
    border; input; ring
    # geometry & type
    radius::Int            # base corner radius (shadcn default ≈ 6px)
    font::StyleFont; font_muted::StyleFont
    pad::Inset             # default control padding
end
```

- Provide two presets: `widget_theme_light()` (zinc-50 background, zinc-900
  foreground, zinc-900 primary — shadcn's default light look) and
  `widget_theme_dark()`. **The default theme is light** — `WidgetToGraphics`
  defaults to `widget_theme_light()`, all per-widget examples render light, and
  the dark editor chrome may opt into `widget_theme_dark()` explicitly.
- Colors are `StyleColor`s; add the needed constants to
  `program/src/document/Color.jl` (a `color_zinc_*` ramp) so tokens are named,
  not magic tuples.

**Threading.** `WidgetToGraphics(font; measure, theme=widget_theme_light())`
stores `theme` on every `*ToGraphicsCanvas` struct (replacing `default_fg`,
`track_color`, `thumb_color`, `selector_fg`). Each `projection_print` derives
its colors/radius from the theme.

**The theme is the single source of truth — consistency over per-instance
color.** The goal is a *coherent, beautiful set* of widgets, so the theme drives
the look and individual documents should **not** carry their own colors. Concretely:

- Every widget color/radius/spacing default comes from the theme; a widget that
  sets nothing is fully styled.
- A document field that *is* set still acts as an explicit override (the
  mechanism stays), but the shipped examples are **migrated to drop their
  hand-picked colors** so the whole gallery renders in one consistent palette.
  The existing dark-navy fills in the big gallery and the configuring-projection
  examples are replaced with theme tokens (or simply removed).
- Treat a stray per-instance color as a smell to clean up, not a feature to
  preserve — uniformity is the point.

**Rounded box helper.** Add `_push_rounded_box!(elems, w, cw, ch; radius, fill,
border, border_w)`. Once `GraphicsRect` gains `border_width`/`border_color` (see
*Backend*), this emits a **single** rounded rect with fill + outline; until then
it falls back to two stacked rounded rects (border rect, then fill rect inset by
`border_w`). Keep `_push_box_rects!` for the existing asymmetric/explicit cases.
Default control radius from `theme.radius`.

## Backend — extend the SDL renderer & graphics primitives

shadcn's polish (smooth corners, circles, soft shadows, subtle gradients,
hairline rules) is hard to fake with square-cornered fills. We can and should
push capability **down into the graphics layer** rather than emulating it with
stacks of rects in `WidgetToGraphics`. Everything here lives in
`program/src/document/Graphics.jl` (primitive structs) and
`program/src/backend/Sdl.jl` (rendering), and must respect the bidirectional
contract — every new primitive/field needs `@document` wiring, a `Base.show`,
hit-testing (`hit_element_at` / `_rect_hit`), a branch in
`_dispatch_render_elem!`, and walker/cache friendliness.

### Anti-aliasing

Rect/curve edges are aliased today. Two complementary routes:

- **Global SSAA (recommended first).** Render the canvas into an offscreen
  render-target texture at 2×–4×, then `SDL_RenderCopy` it down to display size
  with linear filtering (`SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1"/"2")`,
  `SDL_SetTextureScaleMode`). One change smooths *all* geometry (rounded rects,
  circles, lines) and the offscreen `write_image` path. Cost: 4×–16× fill.
- **Per-shape coverage AA.** Replace integer `_corner_inset` with fractional
  edge coverage (blend boundary pixels at partial alpha) for rounded rects and
  new curved primitives. Sharper than SSAA, more code; do this only where SSAA
  proves too costly.

Either way, enable alpha compositing globally:
`SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)` (required for rings,
shadows, translucent overlays, skeleton shimmer).

### New fields on existing primitives

- **`GraphicsRect`**: add `border_width` + `border_color` so one primitive
  expresses shadcn's "rounded fill + 1px outline" (retires the two-stacked-rects
  trick and the 4-rect border model for the common case); add optional
  `gradient_color` + `gradient_dir` for subtle fills/hover via vertex colors;
  optional `shadow` (offset, blur, color).
- **`GraphicsText`**: optional `max_width` + ellipsis (text-overflow truncation),
  `underline`, and a `background` highlight color (selection/▟hover rows).

### New primitives

- **`GraphicsLine`** (x1,y1→x2,y2, width, color, AA) — separators, slider/track
  rules, focus underlines, connectors.
- **`GraphicsCircle`** / **`GraphicsEllipse`** (center, radius, fill, optional
  border) — avatars, radio dots, switch knobs, slider thumbs with clean curves
  (a circle is currently a max-radius rect — fine, but a real primitive reads
  better and AAs cleanly).
- **Rounded-rect stroke / `GraphicsRoundedRect`** if border fields on
  `GraphicsRect` prove awkward.

### Rendering infrastructure (SDL2 ≥ 2.0.18)

- **`SDL_RenderGeometry`** for gradients and arbitrary filled shapes
  (triangulated) with per-vertex color — the clean path for gradients,
  triangles (chevrons/carets without glyphs), and AA'd polygons.
- **`SDL_RenderSetClipRect`** for rectangular clipping (scroll content, image
  cropping); rounded/circular clip (avatar images) needs render-target masking —
  mark as stretch.
- Avoid adding **SDL2_gfx** (`aacircleRGBA`, `roundedBoxRGBA`) unless the JLL is
  readily available; prefer `SDL_RenderGeometry` + SSAA to keep deps lean.

### Ripple to manage

Each new primitive/field touches: the `@document` struct + constructor +
`Base.show`; `_dispatch_render_elem!` in `Sdl.jl`; hit-testing in `Graphics.jl`;
the graphics walker / caching; and the printer-walk tests. Add each primitive
with a tiny graphics example so it renders in isolation (mirrors the per-widget
example pattern).

## Part A — restyle existing widgets, one at a time

**Work one widget per iteration**, driven by that widget's example. The
per-widget examples in `example/src/document/Widget.jl` (`widget_label`,
`widget_button`, …) are the unit of work and the unit of comparison:

1. Render the widget's example to a PNG **before** touching it
   (`write_image_example(widget_button_example, "out/widget_button.before.png")`).
2. Restyle just that one widget's `projection_print` in `WidgetToGraphics.jl`
   (and only its theme tokens / box treatment).
3. Re-render to `…after.png` and eyeball the pair.
4. If the existing example is too sparse to show the new styling (e.g. a button
   needs to demonstrate its `variant`s, an alert needs both states), **extend or
   add example(s)** — a `widget_button_variants` example, etc. — following the
   same `Example` const + `examples`-list pattern already in place.
5. Commit that single widget before moving to the next.

Run-of-show, in `WidgetToGraphics.jl`: switch each widget's hardcoded colors to
theme tokens and adopt rounded surfaces:

| Widget | shadcn treatment |
|---|---|
| `WidgetLabel` | `foreground` text; `muted_foreground` variant for hints |
| `WidgetText` (input) | `input` border, `background` fill, `radius`, `ring` when focused (selection present) |
| `WidgetButton` | `primary` fill + `primary_foreground` text, `radius`; add `variant` (default/secondary/outline/ghost/destructive) |
| `WidgetCheckbox` | **drawn**, not `[x]`: rounded square (radius ≈ 4), `input` border when off, `primary` fill + `primary_foreground` "✓" glyph when on |
| `WidgetTooltip` | `popover` fill, `border`, small `radius`, `popover_foreground` text |
| `WidgetMenu` / `WidgetMenuItem` | `popover` surface; hovered/selected item → `accent` row |
| `WidgetToolbar` | `background`/`muted` strip, `border` bottom rule |
| `WidgetTitlePane` → card-like | `card` surface, `border`, `radius`, title in `foreground`, body in `card_foreground` |
| `WidgetTabbedPane` | inactive tab `muted_foreground`, active tab `foreground` with `background` pill + bottom accent |
| `WidgetScrollPane` | `background` viewport, optional `border` + `radius` |
| `WidgetScrollBar` | `muted` track, `muted_foreground`/`border` thumb, rounded thumb (radius = thickness/2) |
| `WidgetSplitPane` | `border`-colored divider gutter |
| `WidgetShell` | `background` fill, `border` rules under menu/toolbar |

Checkmark/icon note: rotated strokes aren't supported by the backend, so icons
(`✓`, chevrons) are drawn as **font glyphs**, not geometry.

## Part B — new widgets (printer-only)

Each new widget needs: a `@document struct` in `program/src/document/Widget.jl`
(base box fields + `selection::Reference`), a `*ToGraphicsCanvas` projection in
`WidgetToGraphics.jl` with **`projection_print` only**, registration in the
`WidgetToGraphics` dispatch factory, module exports, and a minimal per-widget
example (document builder + `Example` const + entry in the `examples` list),
mirroring the per-widget structure already in place.

To stay green on the reader/repl sweeps, give each a no-op reader trio:
`projection_read(...) = nothing`, `map_reference_forward/backward(...) =
nothing`. (Interactivity is deliberately out of scope here.)

**Tier 1 — high value, easy with rects + rounded corners + glyphs**

- **WidgetBadge** — pill (`radius = h/2`) with `variant` (default/secondary/
  outline/destructive) + centered text.
- **WidgetSeparator** — 1px `border` line, `:horizontal` / `:vertical`.
- **WidgetCard** — rounded bordered container with optional header / description
  / content / footer stacked vertically (generalises `WidgetTitlePane`).
- **WidgetSwitch** — rounded track (`radius = h/2`) + knob circle; `primary`
  when on, `input` when off.
- **WidgetProgress** — rounded `muted` track + `primary` filled portion (`value
  ∈ [0,1]`).
- **WidgetSlider** — track line + filled segment + knob circle.
- **WidgetRadioGroup** / **WidgetRadio** — circle (`radius = h/2`) `input`
  border + filled `primary` inner dot when selected.
- **WidgetAvatar** — `muted` circle + centered initials (image-clipping isn't
  supported yet, so v1 is initials/solid).
- **WidgetAlert** — rounded bordered box, `variant` (default/destructive), bold
  title + `muted_foreground` description, optional leading icon glyph.
- **WidgetSkeleton** — `muted` rounded-rect placeholder.

**Tier 2 — nice to have**

- **WidgetToggle** / **WidgetToggleGroup** — pressed/unpressed buttons (`accent`
  when on).
- **WidgetSelect** — input-like box + trailing chevron glyph (closed state only;
  the dropdown is a reader concern).
- **WidgetTextarea** — multi-line `WidgetText` surface.
- **WidgetAccordion** — header rows (chevron) + expanded body.

## Part C — verify by rendering images

Use the existing image pipeline as the before/after diff tool (per the hint to
"see `write_image`"):

- `write_image_example(widget_button_example, "out/widget_button.png")` renders
  one widget to a PNG; `generate_screenshots()` does the whole `examples` list.
  Offscreen SDL rendering works in the test env (the suite prints a font scale),
  so this is our visual regression channel.
- Workflow per phase: snapshot the affected per-widget examples **before** the
  change, apply the restyle, re-render, and eyeball the pair. Optionally add a
  small `write_widget_gallery(dir)` helper that dumps every `widget_*` example
  to `dir/` for a one-shot contact sheet.
- The per-widget examples added in `example/src/document/Widget.jl` are the unit
  of comparison — each isolates one widget, which is exactly what makes the
  visual diff legible.

## Phasing

0. **Backend foundation** — SSAA (offscreen render target + linear downscale),
   global `SDL_BLENDMODE_BLEND`, and `GraphicsRect` `border_width`/`border_color`
   fields. This alone makes every later widget look crisp. Add a `GraphicsLine`
   and `GraphicsCircle` primitive when the first widget that needs them lands
   (separator / radio), each with a tiny graphics example.
1. **Theme scaffold** — `WidgetTheme`, `color_zinc_*` constants, light/dark
   presets, thread `theme` through `WidgetToGraphics` (replace `default_fg`
   et al.), add `_push_rounded_box!`. Land the `write_widget_gallery` harness.
2. **Restyle existing widgets** (Part A) — **one widget per commit**, each driven
   by its example with a before/after PNG, adding examples where a widget's
   styling isn't visible yet. Checkbox redraw and rounded borders come first.
3. **New widgets Tier 1** (Part B) — document struct + printer + example + image
   per widget, again one at a time.
4. **New widgets Tier 2**.
5. **Docs** — refresh `image/example/*` via `generate_screenshots()`, update the
   widget guide (`guide/document/widget.md`) and examples tour.

Gradients, shadows, ellipsis-truncation, and rounded clipping are **opt-in
later** — pull each forward only when a specific widget needs it.

## Risks / open questions

- **AA cost** — global SSAA is the simplest win but multiplies fill by 4×–16×.
  Validate `write_image` and live-window frame times at 2× before committing to
  4×; fall back to per-shape coverage AA on hot primitives if needed.
- **Backend ripple** — new primitives/fields must thread through `@document`,
  hit-testing, `_dispatch_render_elem!`, the walker, and caching. Land each
  primitive behind its own graphics example and printer-walk test first.
- **Migrating explicit colors (decided: consistency wins)** — existing examples
  (the big gallery, the configuring projection) set explicit dark-navy colors.
  These get **migrated to theme tokens / removed** so everything shares one
  palette; the override mechanism stays for genuine one-offs but the shipped set
  uses the theme throughout. Watch for examples that depended on a specific color
  for legibility (e.g. dark fill behind light text) and re-derive them from
  tokens.
- **Default theme (decided: light)** — the widget default is
  `widget_theme_light()`; the dark preset ships too and the editor chrome can opt
  in. Light examples mean any image background/clear color must also be the light
  `background` token so PNGs aren't light-on-light or light-on-black.
- **Printer-only readers** — new widgets must return `nothing` from the reader
  trio so `test_readers` / `test_repls` stay green; the editor-interaction tests
  already skip non-`widget_text` widget examples (we updated those skip-lists).
