# Stage 5 — Icons (named, theme-aware, pluggable backings)

> **Status: ✅ DONE** (all sub-steps, including the tab/tree-node follow-up).
> Detailed plan for **Stage 5** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Icons"). Fills the
> `Action.icon` slot left as a hook by **Stage 4**
> ([widget-actions-shortcuts.md](widget-actions-shortcuts.md)).
>
> **Implemented & tested** (commits `5260fe1`, `56bef16`, `0a311f7`;
> `WidgetIconTest` 17 assertions): ✅ 1 registry (`register_icon!` + `_push_icon!`)
> + built-in vector set + `glyph_icon`/`image_icon` pluggable backings; ✅ 2 `icon`
> slot on `WidgetButton`/`WidgetMenuItem` (+ toolbar) taking `command.icon` then
> the widget's own, tinted to the foreground and muted when disabled; ✅ 3
> `WidgetToolButton`; ✅ 4 `WidgetTabbedPane` 3-tuple tab icons + registry-aware
> `WidgetTreeNode` icons (Symbol → vector, String → glyph); ✅ 5 gallery icons
> (menu / toolbar / tool-button row / tab strip / folder-file tree, rendered &
> verified) + `widget.md` docs; plus a `WidgetToolbar` advance fix so an icon'd
> item no longer overlaps the next.

## Context

ProjecturEd has no icon concept — every widget is text. Qt's `QIcon` is pervasive
(buttons, menu items, tabs, tree nodes, toolbar). The key design insight (settled
with the user): an **icon is a *named, semantic* value**, distinct from
`GraphicsImage` (a baked raster blit with no color field). An icon must **tint to
the widget's foreground** (and mute when disabled) and **scale with the font** —
behaviour a raster can't give but text and vector strokes can. The select chevron
already proves the pattern: `_push_chevron!` emits tinted `GraphicsLine`s, not a
`GraphicsImage`.

So an `Icon` is to `GraphicsImage` as `GraphicsText`+`StyleText` is to a bitmap of
rendered text: the semantic layer vs. one pixel realization. We make the icon a
**name**, and a **registry** resolves it to one of three renderers — all of which
already exist as primitives:

| Backing | Emits | Tint / scale | v1 |
|---|---|---|---|
| **Vector** | `GraphicsPolyline`/`Line`/`Circle` | ✅ / ✅ | **default, shipped** |
| **Glyph-font** | `GraphicsText` (icon font + codepoint) | ✅ / ✅ | interface ready; font bundled later |
| **Raster** | `GraphicsImage` (`ImageDocument`) | ❌ / ❌ | interface ready; for brand art |

"Both/all three" coexist from day one because the widget printer never branches on
backing — it asks the registry to *draw `icon` at this color and size*, exactly as
it asks `measure` to size text. (Verified primitives: `GraphicsPolyline`,
`GraphicsSpline`, `GraphicsLine/Circle/Rect` all exist; no icon font is bundled
yet — `font_ubuntu_*` only — which is why vector is the v1 default. The glyph route
also hits the known SDL no-font-fallback / tofu constraint, so it waits for a
real bundled icon font.)

## Scope decisions (recommendations ✅)

1. **Icon value = a `Symbol` name, resolved by a registry.** ✅ No new document
   type in v1 — `icon = :save`. The registry is the extensibility seam; a richer
   `Icon` struct can wrap it later if a use case needs selectability.
2. **Uniform renderer signature.** ✅ Every registry entry is a callable
   `(elems, x, y, size, color) -> nothing` that pushes graphics. Vector entries
   push strokes; a glyph entry pushes a `GraphicsText`; an image entry pushes a
   `GraphicsImage`. The backing is hidden in the closure — pluggable by name with
   no widget-code change.
3. **v1 ships a small built-in vector set; glyph/raster are interface-only.** ✅
   ~10 common icons hand-authored as tinted polylines (generalising the chevron).
   `register_icon!(name, renderer)` lets a bundled icon font or image icons drop in
   later.
4. **Icon size derives from the adjacent text** (cap/line height), not a new theme
   token — so an icon next to a label always matches it. ✅

## Implementation

### 1. Icon registry + render seam (`projection/primitive/WidgetToGraphics.jl`, or a small `Icon.jl`)
- `const ICON_REGISTRY = Dict{Symbol,Function}()` and
  `register_icon!(name::Symbol, renderer)`.
- `_push_icon!(elems, name, x, y, size, color)` — look up `name`; call its renderer
  with the tint `color` (the caller passes the widget's foreground, already muted
  when disabled) and `size`. Unknown name ⇒ no-op (or a faint placeholder box, like
  the image-not-decoded path). `icon_width(name, size) -> Int` for layout (icons are
  square: `size`).
- **Built-in vector set** (each a renderer drawing in a `size×size` box, scaled from
  unit coords, using `GraphicsPolyline`/`Line`/`Circle` tinted by `color`):
  `:plus :check :x :chevron_down :chevron_right :folder :file :save :pencil :trash
  :search :menu` (+ generalise the existing chevron/checkmark drawers into named
  entries). Keep each to a few segments.
- **Pluggable backings (interface, demonstrated):** helpers
  `glyph_icon(font::StyleFont, codepoint) -> renderer` (pushes a `GraphicsText`) and
  `image_icon(image::ImageDocument) -> renderer` (pushes a `GraphicsImage`), so a
  caller can `register_icon!(:brand, image_icon(logo))`. No icon font is bundled in
  v1; the glyph helper is exercised with an Ubuntu glyph in a test only.

### 2. `icon` slot on the presenters (`document` + `projection`)
- `WidgetButton` and `WidgetMenuItem` gain an optional `icon::Any` (a Symbol).
  **`Action` already has an `icon` slot** — a command-bound widget takes its icon
  from `command.icon` (falling back to the widget's own `icon`), exactly as it
  already takes the label/enabled from the command.
- Printers: when an icon is present, draw it left of the label (icon box = text
  height, a small gap), tinted to the **same foreground the label uses** (so it
  mutes with the widget); grow the widget's content width by `icon + gap`. Reuse
  the existing `_button_label_content` / menu-item label paths. Toolbar entries are
  `WidgetMenuItem`s, so they inherit it for free.
- Reference mapping / readers unchanged (an icon is presentation only).

### 3. `WidgetToolButton` (icon-first button)
- Falls out of #2: a `WidgetToolButton(icon; tooltip=…, command=…)` convenience that
  builds a square `WidgetButton` with an `icon` and empty/short label. (Thin
  constructor over `WidgetButton`; no new projection.)

### 4. Tabs & tree node icons (include if cheap, else follow-up)
- Optional `icon` on `WidgetTabbedPane` tab entries and `WidgetTree` nodes, drawn
  before the tab/node label via `_push_icon!`. Defer if it complicates the tuple
  APIs; the button/menu/toolbar path is the core deliverable.

### 5. Example + docs
- Add icons to the gallery (`make_widget_document_example`): a `:save` icon on the
  Save button and File›Save command, `:folder`/`:file` in the tree, a small
  `WidgetToolButton` row in the toolbar.
- Document the icon model in
  [documentation/document/widget.md](../../documentation/document/widget.md): icon =
  named + theme-aware (≠ `GraphicsImage`); the registry + uniform renderer; the
  three backings and when each applies; `Action.icon`.

## Verification

New `WidgetIconTest.jl` (registered in `ProjecturedTest.jl`; run via the
worktree-root env `julia --project=. -e 'using Projectured, ProjecturedExample,
ProjecturedTest; test_widget_icon()'`):

- **Registry:** `_push_icon!` for a built-in name emits tinted vector primitives at
  the requested size; an unknown name is a no-op; the same call with a different
  `color` recolors the output (proves tinting).
- **Pluggable backing:** `register_icon!(:g, glyph_icon(font, 'A'))` then
  `_push_icon!(:g, …)` emits a `GraphicsText`; `image_icon` emits a `GraphicsImage`
  — same call site, different primitive (proves the seam).
- **Widget binding:** a `WidgetButton(...; icon=:save)` renders the icon left of the
  label and is wider than the same button without an icon; a disabled button draws
  the icon in the muted color (walk the canvas for the icon primitives' color). A
  command-bound button takes its icon from `command.icon`.
- **Visual check:** render the gallery (`write_example_image("widget", png)`) and
  confirm icons sit beside labels, tinted and aligned — as we did for the gallery.
- **Regression:** `test_widget_action`, `test_widget_button_behavior`,
  `test_widget_menu`, and `test_printer(widget_example/widget_shell_example)` stay
  green (button/menu-item printers touched).

Delegate the (slow) Julia runs to a Sonnet subagent, reporting summaries + first
failure verbatim.

## Commit & plan upkeep

Commit incrementally (registry+vector set; widget `icon` slot + Action wiring;
tool button; example+docs), no `Co-Authored-By`. Update this plan as I go; move it
to `plan/done/` once Stage 5 is implemented. Stage 6 (forms) and any future toolbar
work then reuse the icon slot.

## Relationship to other plans
- [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) — Stage 5; unblocks
  visually-complete buttons/menus/tabs/tree/toolbar and `QToolButton`.
- [widget-actions-shortcuts.md](widget-actions-shortcuts.md) — Stage 4; this fills
  the `Action.icon` slot it reserved.
- [inline-text-images.md](../done/inline-text-images.md) /
  [widget-button-behavior-and-image-content.md](../done/widget-button-behavior-and-image-content.md)
  — the existing `ImageDocument` → `GraphicsImage` raster path the image-backed icon
  renderer reuses (raster art stays raster; icons are the themeable layer on top).
