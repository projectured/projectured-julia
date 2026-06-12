# shadcn/ui look & feel for the widget domain

Restyle the existing widgets to match [shadcn/ui](https://ui.shadcn.com), and
extend the widget set with the most useful shadcn components that are missing.
New widgets may be **printer-only** for now (a stub reader is fine).

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
  `widget_theme_dark()`. Pick **light** as the default to match shadcn out of
  the box; the dark editor chrome can opt into the dark preset.
- Colors are `StyleColor`s; add the needed constants to
  `program/src/document/Color.jl` (a `color_zinc_*` ramp) so tokens are named,
  not magic tuples.

**Threading.** `WidgetToGraphics(font; measure, theme=widget_theme_light())`
stores `theme` on every `*ToGraphicsCanvas` struct (replacing `default_fg`,
`track_color`, `thumb_color`, `selector_fg`). Each `projection_print` derives
its colors/radius from the theme.

**Precedence (compatibility).** A widget's explicit document field wins when set;
`nothing` falls back to the theme. This keeps the existing gallery and the
configuring-projection examples working while unstyled widgets pick up the theme
automatically. The per-widget examples we just added mostly omit colors, so they
will inherit the theme cleanly.

**Rounded box helper.** Add `_push_rounded_box!(elems, w, cw, ch; radius, fill,
border, border_w)` that paints shadcn's outline as two stacked rounded rects:
the border-color rect, then a fill-color rect inset by `border_w`. Use it when a
uniform border + radius is in play; keep `_push_box_rects!` for the existing
asymmetric/explicit cases. Default control radius from `theme.radius`.

## Part A — restyle existing widgets

Per widget, in `WidgetToGraphics.jl`, switch hardcoded colors to theme tokens
and adopt rounded surfaces:

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

0. **Theme scaffold** — `WidgetTheme`, `color_zinc_*` constants, light/dark
   presets, thread `theme` through `WidgetToGraphics` (replace `default_fg`
   et al.), add `_push_rounded_box!`. No deliberate visual change beyond what
   tokens imply. Land the `write_widget_gallery` harness.
1. **Restyle existing widgets** (Part A), one widget per commit, each with a
   before/after PNG. Checkbox redraw and rounded borders are the biggest items.
2. **New widgets Tier 1** (Part B) — document struct + printer + example + image
   per widget.
3. **New widgets Tier 2**.
4. **Docs** — refresh `image/example/*` via `generate_screenshots()`, update the
   widget guide (`guide/document/widget.md`) and examples tour.

## Risks / open questions

- **No anti-aliasing** in the rect backend → rounded corners are slightly
  jagged. Acceptable for v1; a later supersample pass in `Sdl.jl` could smooth
  them.
- **Rounded border ring** isn't native (border = 4 square rects today). The
  two-rounded-rects trick covers uniform borders; asymmetric borders stay
  square. Confirm that's acceptable.
- **Override precedence** — existing examples (the big gallery, the configuring
  projection) set explicit dark-navy colors that will clash with a light theme.
  Decide whether to (a) leave explicit colors winning (gallery keeps its look),
  or (b) migrate those examples to tokens too. Recommended: (a) for
  compatibility, migrate the gallery opportunistically.
- **Default theme** — shadcn defaults to light, but the editor chrome is dark.
  Ship both presets; default the widget examples to light.
- **Printer-only readers** — new widgets must return `nothing` from the reader
  trio so `test_readers` / `test_repls` stay green; the editor-interaction tests
  already skip non-`widget_text` widget examples (we updated those skip-lists).
```
