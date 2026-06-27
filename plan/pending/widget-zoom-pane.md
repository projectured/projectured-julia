# Zoom in/out — a `WidgetZoomPane` parallel to `WidgetScrollPane`

> **Status: planning / not started.** Generated 2026-06-27 against the current
> tree (`package/domain/src/...`). File:line citations below are verified.

## Goal

Let the user **zoom the content of a pane in and out** (uniform geometric
magnification — text, rects, lines all scale together, like zoom in a browser or
PDF viewer), driven by a gesture, with live repaint. The design is a deliberate
**term-by-term mirror of `WidgetScrollPane`**: where the scroll pane carries a
transient *offset* (`scroll_position`) and translates its content, the zoom pane
carries a transient *scale* (`zoom`) and magnifies its content.

```
WidgetScrollPane : translate content by (-scroll.x, -scroll.y)
WidgetZoomPane   : scale     content by  zoom
```

Because both ultimately render through a `GraphicsViewport`, they compose: a
zoom-and-pan canvas is a viewport that carries *both* an offset and a scale (see
**Open questions / combined pane** below).

## Why this mirrors the scroll pane (the precedent, verified)

`WidgetScrollPane` is the reference implementation for "a viewport-backed pane
that carries transient view state mutated by a wheel gesture":

- **Document** — [`WidgetScrollPane`](../../package/domain/src/document/Widget.jl#L653-L687):
  `content::Any`, a transient `scroll_position::Point2D` (default `Point2D(0,0)`),
  the standard box-model fields, and `selection`. The convenience constructor
  wraps each field in `Cell(...)`.
- **Printer** — [`projection_print(::WidgetScrollPaneToGraphicsCanvas, …)`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2189-L2255):
  computes the viewport extent from the parent-allocated size (or `size`
  fallback), derives `inner_x = -scroll.x` / `inner_y = -scroll.y` cells
  ([L2210-L2212](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2210-L2212)),
  recurses into `content`, and wraps the recursed canvas in a `GraphicsViewport`
  whose inner `GraphicsCanvas` is positioned at `(inner_x, inner_y)`
  ([L2235-L2240](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2235-L2240)).
- **Operation** — a scroll turn is a single-field write, not a bespoke op:
  [`_scroll_by`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2274-L2276)
  returns `ReplaceReferencedValue(sp, "scroll_position", Point2D(old+Δ))`, and the
  old value is read at read time. (The former `ScrollWidgetOperation` was folded
  into `ReplaceReferencedValue` — see [Widget.jl L1191-L1199](../../package/domain/src/document/Widget.jl#L1191-L1199).)
- **Reader** — [`projection_read(::WidgetScrollPaneToGraphicsCanvas, …)`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2278-L2314):
  intercepts `MouseScroll` (hit-tests, multiplies by the font's line step from
  `p.measure("M", p.font)`, emits `_scroll_by`); forwards every other event to
  the content, **inverting the transform** on the pointer coords —
  `lx = x - cox + scroll.x`, `ly = y - coy + scroll.y`
  ([L2302-L2310](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2302-L2310)) — and re-roots any path-bearing op via
  `map_reference_backward` (`ConcreteReferencePath(FieldReference("content"), …)`,
  [L2266-L2269](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2266-L2269)).
- **Viewport variant** — [`WidgetScrollPaneToGraphicsViewport`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4216-L4307)
  is a separate composable projection emitting a bare `GraphicsViewport`; it is
  what `make_scrolling_projection` in
  [example/.../Wrapper.jl](../../package/example/src/projection/Wrapper.jl) wraps
  any projection in to make it scrollable.
- **Factory wiring** — the scroll pane is registered in the `WidgetToGraphics`
  type-dispatch map at [L4144](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4144).
- **Example** — `make_widget_scroll_pane_document_example`
  ([example/.../document/Widget.jl L235-L238](../../package/example/src/document/Widget.jl#L235)).

The zoom pane reuses *every one* of these seams.

## The one genuinely new thing: a `scale` on `GraphicsViewport`

Scroll needs no graphics-layer change — it bakes the offset into the inner
canvas's `(x, y)`. **Zoom cannot** be expressed by repositioning, because a true
zoom must also magnify glyph rasterization and stroke widths, not just element
*positions*. (Pre-multiplying child coordinates would scale layout but leave text
and line thicknesses at 1×.) So zoom requires a render-time scale applied to the
viewport's subtree.

The mechanism already exists in the backend and just needs a per-viewport hook.
The SDL backend already composes a render scale at two boundaries:

- the global display scale — `SDL_RenderSetScale(renderer, scale, scale)` with
  `scale = _DISPLAY_SCALE[]` ([ProjecturedSdl.jl L1401-L1410](../../package/sdl/src/ProjecturedSdl.jl#L1401),
  [L1490-L1493](../../package/sdl/src/ProjecturedSdl.jl#L1490)); and
- the offscreen image render — `SDL_RenderSetScale(renderer, sc*S, sc*S)`
  ([L1632](../../package/sdl/src/ProjecturedSdl.jl#L1632)).

The display-scale refactor ([plan/done/global-display-scale.md](../done/global-display-scale.md))
established the invariant: **all projection geometry is logical; a single
`RenderSetScale` at the boundary magnifies uniformly with zero per-element
multiplies.** A zoom is exactly the same trick applied to one subtree.

### Decision: add `scale::Float64` to `GraphicsViewport`

[`GraphicsViewport`](../../package/domain/src/document/Graphics.jl#L404-L419)
today is `(x, y, w, h, content, selection)` and clips `content` to its rect
([`_render_viewport!` ProjecturedSdl.jl L665-L676](../../package/sdl/src/ProjecturedSdl.jl#L665)).
Add a `scale::Float64` field (default `1.0`, keyword in the constructor so the
~existing call sites are unaffected). A viewport with `scale != 1.0`:

- **clips** to its rect as today, then
- renders its inner canvas under an *additional* render scale of `scale`,
  composed with whatever scale is already active (display scale / SSAA). In SDL:
  read the current scale, set `RenderSetScale(cur * scale)`, render the inner
  canvas at `scale`-divided offsets, restore. Mirror the
  push/compose/render/restore shape already used for the offscreen render.

A viewport is the right home for `scale` (rather than a new `GraphicsTransform`
node) because zoom naturally **clips** — a magnified canvas overflows its pane —
and because it makes zoom and scroll *compose in one node*: the inner canvas
keeps its `(-scroll.x, -scroll.y)` origin and the viewport carries `scale`.

### Backends and helpers that must honour `scale`

`GraphicsViewport` is consumed in four backends + two domain helpers; each needs
the scale threaded through (most are a small edit, several already special-case
the viewport):

- **SDL** — `_render_viewport!` ([L665](../../package/sdl/src/ProjecturedSdl.jl#L665)),
  and the dirty-rect collector `_collect_viewport_dirty!`
  ([L1207](../../package/sdl/src/ProjecturedSdl.jl#L1207)) must expand the dirty
  region by `scale`.
- **Web** — `ProjecturedWeb.jl` handles `GraphicsViewport` at
  [L231/317/450/506](../../package/web/src/ProjecturedWeb.jl#L231) (apply a CSS
  transform / canvas scale).
- **PDF** — `Pdf.jl` at [L533](../../package/domain/src/backend/Pdf.jl#L533).
- **Console** — `Console.jl` (text backend; zoom likely a no-op / rounds to 1×,
  but must not crash).
- **Hit-testing** — `hit_element_at` (GraphicsModule) must divide pointer coords
  by `scale` when descending into a scaled viewport, so clicks land on the right
  element. This is the read-path twin of the render scale and is what makes the
  reader's coordinate inversion (below) correct.
- **GraphicsCaching** — the cache treats a viewport as a non-cacheable boundary
  already ([GraphicsCaching.jl L36](../../package/domain/src/projection/primitive/GraphicsCaching.jl#L36),
  [L180](../../package/domain/src/projection/primitive/GraphicsCaching.jl#L180));
  confirm the scaled subtree still invalidates correctly when `zoom` changes.

This backend surface is the **bulk of the work** and the main risk; the widget
itself is small. Phase 1 below de-risks it before any widget code is written.

## The widget: `WidgetZoomPane` (term-by-term mirror)

| Concern | `WidgetScrollPane` | `WidgetZoomPane` |
|---|---|---|
| transient state | `scroll_position::Point2D = (0,0)` | `zoom::Float64 = 1.0` |
| gesture | `MouseScroll` (no modifier) | `MouseScroll(; ctrl)` (+ optional `KeyDown(:plus/:minus; ctrl)`) |
| step | `±dy * line_step` | `× zoom_factor` per notch (e.g. `1.1`), clamped to `[min,max]` |
| operation | `ReplaceReferencedValue(sp,"scroll_position",old+Δ)` | `ReplaceReferencedValue(zp,"zoom",clamp(old*factor))` |
| printer transform | inner canvas at `(-sx,-sy)` in viewport | viewport `scale = zoom` |
| reader coord inversion | `lx = x - cox + sx` | `lx = (x - cox) / zoom` |
| reference re-root | `.content` prepend | `.content` prepend (identical) |

### Document — `package/domain/src/document/Widget.jl`

Add next to `WidgetScrollPane` ([L645-L689](../../package/domain/src/document/Widget.jl#L645)):

```julia
@document struct WidgetZoomPane <: WidgetDocument
    content::Any
    content_fill_color::StyleColor
    position::Point2D
    size::Point2D
    zoom::Float64            # transient view state, default 1.0 (like scroll_position)
    visible::Bool
    margin::Inset; margin_color::StyleColor
    border::Inset; border_color::StyleColor
    padding::Inset; padding_color::StyleColor
    selection::Reference
end
```

with a convenience constructor `WidgetZoomPane(content; zoom::Float64=1.0, …)`
mirroring `WidgetScrollPane`'s ([L669-L687](../../package/domain/src/document/Widget.jl#L669)),
a `setfn!` delegating into `content` ([L689](../../package/domain/src/document/Widget.jl#L689)),
and the module exports (`WidgetZoomPane`, `IWidgetZoomPane`) alongside the scroll
pane exports ([L26](../../package/domain/src/document/Widget.jl#L26),
[L42](../../package/domain/src/document/Widget.jl#L42)). No new operation type —
zoom is a `ReplaceReferencedValue` single-field write, exactly like scroll
([Widget.jl L1191-L1199](../../package/domain/src/document/Widget.jl#L1191)).
Document `zoom` as transient, non-serialised view state in the docstring (the
[widget guide](../../documentation/document/widget.md) calls `scroll_position`
the canonical example of transient view state).

### Printer — `WidgetZoomPaneToGraphicsCanvas`

Copy `WidgetScrollPaneToGraphicsCanvas`
([L2189-L2255](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2189))
and change the transform:

- viewport extent computed identically (parent-allocated `available_width/height`
  or `size` fallback, inset-reduced);
- instead of `inner_x/inner_y` from scroll, keep the inner canvas at origin and
  set the viewport's `scale = w.zoom` (read through a `Cell` so it stays
  reactive: `zoom_cell = Cell(() -> getfield(w,:zoom)[])`);
- recurse into `content` with the viewport extent as available size — **note** the
  content sees the *unscaled* logical extent (it lays out at 1× and the viewport
  magnifies), which is the desired "zoom" semantics (vs. "reflow", out of scope);
- `map_reference_forward` returns `nothing`; `map_reference_backward` prepends
  `FieldReference("content")` — **identical** to the scroll pane
  ([L2257-L2269](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2257)).

### Reader — `projection_read(::WidgetZoomPaneToGraphicsCanvas, …)`

Mirror [L2278-L2314](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2278):

```julia
@event_case evt begin
    MouseScroll(dx, dy, x, y; ctrl) => begin          # Ctrl+wheel = zoom
        hit_element_at(canvas, x, y) === nothing && return nothing
        old    = getfield(iomap.input, :zoom)[]
        factor = dy < 0 ? ZOOM_STEP : 1/ZOOM_STEP       # wheel up = zoom in
        new    = clamp(old * factor, ZOOM_MIN, ZOOM_MAX)
        return ReplaceReferencedValue(iomap.input, "zoom", new)
    end
end
# forward other events to content, inverting the scale on pointer coords:
#   lx = round((x - cox) / zoom);  ly = round((y - coy) / zoom)
# then map_reference_backward re-roots the returned op at `.content.<rest>`.
```

`MouseScroll` *without* Ctrl falls through (so a zoom pane nested in a scroll pane
still scrolls; with Ctrl it zooms). The `@event_case` modifier syntax
`MouseScroll(…; ctrl)` is supported — `MouseScroll` carries `modifiers`
([Mouse.jl L158-L166](../../package/kernel/src/device/Mouse.jl#L158)) and
`@event_case` matches modifier flags after `;`
([EventCase.jl L92](../../package/kernel/src/device/EventCase.jl#L92),
precedent `KeyDown(:period; ctrl)` at [L15](../../package/kernel/src/device/EventCase.jl#L15)).

Constants (define near the scroll fallbacks at
[WidgetToGraphics.jl L297-L303](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L297)):
`ZOOM_STEP = 1.1`, `ZOOM_MIN = 0.25`, `ZOOM_MAX = 4.0`.

### Viewport variant + factory + composable wrapper

- Add `WidgetZoomPaneToGraphicsViewport` mirroring
  [`WidgetScrollPaneToGraphicsViewport`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4216-L4307)
  for the bare-viewport composable case.
- Register `WidgetZoomPane => WidgetZoomPaneToGraphicsCanvas(...)` in the
  factory map next to the scroll pane ([L4144](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4144)).
- Optionally add `make_zooming_projection` next to `make_scrolling_projection`
  ([example/.../Wrapper.jl](../../package/example/src/projection/Wrapper.jl)).
- Re-export the new types from the umbrella module(s) wherever `WidgetScrollPane`
  is re-exported.

### Example

Add `make_widget_zoom_pane_document_example` next to the scroll-pane example
([example/.../document/Widget.jl L235-L238](../../package/example/src/document/Widget.jl#L235))
and register `widget_zoom_pane_example` in the example list, so
`run_example(widget_zoom_pane_example)` / `write_example_image(...)` work.

## Implementation phases

### Phase 1 — `scale` on `GraphicsViewport`, backend-only (de-risk first)
1. Add `scale::Float64=1.0` to `GraphicsViewport` + keyword constructor
   ([Graphics.jl L404-L419](../../package/domain/src/document/Graphics.jl#L404)).
2. Honour it in **SDL** `_render_viewport!` (compose `RenderSetScale`, scale the
   inner offsets) and `_collect_viewport_dirty!`; verify with a hand-built
   viewport (`scale=2`) via `write_example_image` that the subtree renders 2×
   and clips correctly.
3. Make `hit_element_at` divide coords by `scale` inside a scaled viewport;
   add/extend a click-roundtrip assertion.
4. Thread `scale` through **web**, **PDF**, **console** backends (console may
   round to 1×). This phase ships nothing user-visible but is the real work.

### Phase 2 — `WidgetZoomPane` document + printer + reader (mirror scroll)
5. Add the `WidgetZoomPane` struct, constructor, `setfn!`, exports.
6. Add `WidgetZoomPaneToGraphicsCanvas` (printer sets viewport `scale=zoom`;
   reader handles `MouseScroll(; ctrl)` → `ReplaceReferencedValue(zp,"zoom",…)`
   and forwards other events with `/zoom` coord inversion + `.content` re-root).
7. Register in the factory map; add the viewport variant + `make_zooming_projection`.
8. Add the example and wire it into the example list.

### Phase 3 — polish (optional, can defer)
9. Keyboard zoom: `KeyDown(:plus/:equals; ctrl)` / `KeyDown(:minus; ctrl)` /
   `KeyDown(:0; ctrl)` → reset to `1.0`, routed by selection.
10. **Zoom toward the cursor** (keep the point under the pointer fixed) by
    adjusting an offset on zoom — only meaningful in the **combined** pane (see
    below); pure zoom-about-origin is the Phase 2 default.
11. Guide + docs: add a `WidgetZoomPane` row to the widget hierarchy table and a
    "Zoom" subsection in [documentation/document/widget.md](../../documentation/document/widget.md),
    mirroring the scroll-pane prose.

## Testing (smallest-scope first, per CLAUDE.md)

- **Reader unit test** (new, `package/test/src/projection/`): feed a synthetic
  `MouseScroll(0,-1,x,y, Modifiers(ctrl=true))` and assert the emitted
  `ReplaceReferencedValue("zoom", clamp(old*step))`; feed one without Ctrl and
  assert it forwards/does-not-zoom; feed a `MousePress` and assert the coord
  inversion (`/zoom`) lands on the right child. Mirror the routing-test style in
  [ProjectionConfiguringTest.jl](../../package/test/src/projection/ProjectionConfiguringTest.jl).
- **Per-example**: `test_example(widget_zoom_pane_example)` (printer + reader +
  navigation in one); add `; check_reaches_all=true` for navigation coverage.
- **Graphics/backend**: a `hit_element_at` roundtrip through a `scale=2` viewport
  ([ClickRoundtripTest.jl](../../package/test/src/editor/ClickRoundtripTest.jl)
  style) + `test_write_image` at a non-1× zoom.
- **Regression**: existing scroll-pane tests must still pass (the shared
  `GraphicsViewport` changed) — `test_example(widget_scroll_pane_example)`.
- Do **not** run `test_all` to verify — use the targeted functions above.

## Out of scope

- **Reflow zoom** (re-laying out content at a larger font, so lines re-wrap) —
  this plan is *geometric* zoom (uniform magnification). Reflow is the
  font-scale axis, a different feature.
- Persisting / serialising `zoom` (transient view state, like `scroll_position`).
- Pinch-to-zoom / trackpad gestures (no such gesture in the event model today).
- A zoom-bar control (cf. `WidgetScrollBar`) — could be a later parallel.

## Open questions

1. **Standalone widget vs. fold into the scroll pane (recommended path).**
   This plan delivers a **standalone `WidgetZoomPane`** (the literal "similar to
   `WidgetScrollPane`" reading). But since `scale` lives on `GraphicsViewport`,
   the cleaner end state is a **combined zoom+pan pane** — one viewport carrying
   *both* `scroll_position` and `scale` (the usual "zoomable canvas" you also
   drag to pan, with zoom-toward-cursor in Phase 3). **Recommendation:** build
   `WidgetZoomPane` standalone now (Phases 1-2), and treat folding zoom into
   `WidgetScrollPane` (or a shared `WidgetCanvasPane`) as a fast follow once the
   `GraphicsViewport.scale` machinery is proven. Flagging for the maintainer
   because it changes whether a new widget type is added or an existing one
   grows a field.
2. **Zoom gesture: Ctrl+wheel vs. plain wheel.** Plan assumes **Ctrl+wheel**
   (so plain wheel still scrolls, and a zoom pane composes inside a scroll pane).
   If a zoom pane is meant to be the *outermost* surface, plain wheel could zoom
   directly — decide per intended use.
3. **Console backend** under non-1× zoom: round to nearest integer cell scale,
   or treat as 1× (no-op)? Plan assumes no-op to avoid a text-grid blowup.

## Files to touch (summary)

- [`package/domain/src/document/Graphics.jl`](../../package/domain/src/document/Graphics.jl) — `GraphicsViewport.scale`.
- [`package/domain/src/document/Widget.jl`](../../package/domain/src/document/Widget.jl) — `WidgetZoomPane` + ctor + exports.
- [`package/domain/src/projection/primitive/WidgetToGraphics.jl`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl) — printer, reader, viewport variant, factory entry, constants.
- [`package/sdl/src/ProjecturedSdl.jl`](../../package/sdl/src/ProjecturedSdl.jl) — `_render_viewport!`, `_collect_viewport_dirty!`.
- [`package/web/src/ProjecturedWeb.jl`](../../package/web/src/ProjecturedWeb.jl), [`package/domain/src/backend/Pdf.jl`](../../package/domain/src/backend/Pdf.jl), [`package/domain/src/backend/Console.jl`](../../package/domain/src/backend/Console.jl) — viewport scale.
- `hit_element_at` in the GraphicsModule — scale-aware coord descent.
- [`package/example/src/document/Widget.jl`](../../package/example/src/document/Widget.jl) + example list + [`Wrapper.jl`](../../package/example/src/projection/Wrapper.jl) — example & composable wrapper.
- New reader test in `package/test/src/projection/`; [widget guide](../../documentation/document/widget.md) doc update.
