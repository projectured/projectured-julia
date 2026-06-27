# `WidgetTransformPane` — one affine-transform pane subsuming scroll + zoom

> **Status: in progress.** Rewritten 2026-06-27 from the earlier separate
> `WidgetZoomPane` draft, after working through how zoom and scroll compose (a
> single transform node beats two nested clipping viewports). File:line
> citations verified against the current tree (`package/...`).

## Goal

A single pane that carries a **2D affine transform** over its content and edits
it from gestures, with live repaint. One node subsumes:

- `WidgetScrollPane` — a pure **translation** (`scroll_position`),
- a zoom pane — a pure **scale** (`zoom`),
- and their combination (zoomable + pannable canvas, with zoom anchored at the
  cursor) — which two *nested* clipping viewports cannot express cleanly.

```
WidgetScrollPane : transform = translate(−scroll)
(zoom pane)      : transform = scale(zoom)
WidgetTransformPane : transform = arbitrary affine M  (translate ∘ scale today)
```

## Why a transform pane, not two widgets (the decision)

Nesting `WidgetScrollPane(WidgetZoomPane(content))` does **not** give a
zoom-and-pan canvas, because a `GraphicsViewport` **clips at a fixed box**
([`_render_viewport!` ProjecturedSdl.jl#L665](../../package/sdl/src/ProjecturedSdl.jl#L665)):
the inner zoom viewport clips the magnified content before the outer scroll
viewport can pan it (and the reverse order magnifies the scroll viewport itself,
scrollbar and all). The transforms *do* compose on the read path — each reader
inverts its own layer — but the **clips fight**. The clean composition is a
**single viewport carrying one matrix and one clip**, with one reader doing both
gestures and one inversion. That also makes **zoom-toward-cursor** trivial: it is
one matrix update on one document, instead of a cross-document
`scroll`+`zoom` coordination.

## Transform scope: translate + scale now, rotation later (renderer-bound)

The matrix abstraction is fully general affine, but the **renderer** dictates
what ships:

- **Translate + (non-uniform) scale** — maps directly onto the mechanism already
  in the backend: `SDL_RenderSetScale` for scale + a baked origin offset for
  translate (exactly how the display scale, offscreen render, and scroll offset
  already compose: [ProjecturedSdl.jl#L1401](../../package/sdl/src/ProjecturedSdl.jl#L1401),
  [#L1632](../../package/sdl/src/ProjecturedSdl.jl#L1632)). Clip rects stay
  axis-aligned, hit-testing inverts trivially. **This is what this plan ships.**
- **Rotation / shear** — SDL has no global affine state; every primitive would
  have to be pushed through the matrix and drawn via `SDL_RenderGeometry`
  (already used for lines: [#L806](../../package/sdl/src/ProjecturedSdl.jl#L806)),
  glyphs via `SDL_RenderCopyEx`, rounded-rect AA redesigned (the per-row corner
  bands assume horizontal rows: [`_fill_corner_band!`#L690](../../package/sdl/src/ProjecturedSdl.jl#L690)),
  and clipping replaced by a stencil/geometry mask (`SDL_RenderSetClipRect` is
  axis-aligned only). Web (`canvas.setTransform`) and PDF (`cm`) would get
  rotation nearly free; SDL is the gate. **Out of scope — future Phase.** The
  document/reader/hit-test math is written general so only the renderer changes.

## Architecture (term-by-term mirror of the scroll pane)

The scroll pane is the precedent for "viewport-backed pane carrying transient
view state mutated by a gesture": document
[`WidgetScrollPane` Widget.jl#L653-L687](../../package/domain/src/document/Widget.jl#L653),
printer [WidgetToGraphics.jl#L2189-L2255](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2189),
single-field-write op [`_scroll_by`#L2274](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2274)
(the former `ScrollWidgetOperation` folded into `ReplaceReferencedValue`,
[Widget.jl#L1191](../../package/domain/src/document/Widget.jl#L1191)), reader with
coord inversion + `.content` re-root
[#L2278-L2314](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L2278),
viewport variant [#L4216-L4307](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4216),
factory entry [#L4144](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4144).
`WidgetTransformPane` reuses every seam.

### 1. Value type — `AffineTransform` (Geometry module)

In [Geometry.jl](../../package/domain/src/document/Geometry.jl) (next to
[`Point2D`#L49](../../package/domain/src/document/Geometry.jl#L49)) add an
immutable affine value mapping **local → screen**:

```julia
struct AffineTransform   # [a c e]   screen.x = a*lx + c*ly + e
    a::Float64; b::Float64; c::Float64; d::Float64; e::Float64; f::Float64
end                      # [b d f]   screen.y = b*lx + d*ly + f
const affine_identity = AffineTransform(1,0,0,1,0,0)
affine_translate(tx,ty) = AffineTransform(1,0,0,1,tx,ty)
affine_scale(sx,sy)     = AffineTransform(sx,0,0,sy,0,0)
∘ (compose), inv (invert), apply(M, x, y)::Tuple   # small helpers + tests
is_axis_aligned(M) = M.b == 0 && M.c == 0           # renderer fast-path guard
```

### 2. Graphics node — `transform` on `GraphicsViewport`

Add `transform::AffineTransform` (default `affine_identity`) to
[`GraphicsViewport` Graphics.jl#L404-L419](../../package/domain/src/document/Graphics.jl#L404),
keyword in the constructor so existing call sites are unchanged. A viewport
clips to its rect (as today) and renders its content under `transform`. This
reuses all four backends' existing viewport handling instead of adding a new
node type; scroll's inner-canvas offset and a transform pane's matrix compose in
one node.

### 3. Renderer — honour `transform` (translate + scale subset)

- **SDL** `_render_viewport!` ([#L665](../../package/sdl/src/ProjecturedSdl.jl#L665)):
  when `is_axis_aligned(transform)`, compose scale into `RenderSetScale` and bake
  translate into the origin passed to `_render_canvas!` (offset = `tx/scale` in
  pre-scale space, the established trick), then restore — mirroring the
  offscreen push/compose/render/restore. `_collect_viewport_dirty!`
  ([#L1207](../../package/sdl/src/ProjecturedSdl.jl#L1207)) expands the dirty
  region by the scale. A non-axis-aligned matrix → assert/skip for now (Phase 4).
- **Web** [ProjecturedWeb.jl#L231](../../package/web/src/ProjecturedWeb.jl#L231)
  (and L317/450/506): `ctx.setTransform(a,b,c,d,e,f)` — full affine free.
- **PDF** [Pdf.jl#L533](../../package/domain/src/backend/Pdf.jl#L533): `cm` operator.
- **Console**: no-op (round to identity); must not crash.

### 4. Hit-testing — invert once at the boundary

`hit_element_at` (GraphicsModule) descends into a transformed viewport by
mapping the query point through `inv(transform)`; the existing axis-aligned AABB
tests then run in local space unchanged. This is the read-path twin of the
render transform and is what makes the reader's coordinate inversion correct.
Cache invalidation: the viewport is already a non-cacheable boundary
([GraphicsCaching.jl#L36](../../package/domain/src/projection/primitive/GraphicsCaching.jl#L36),
[#L180](../../package/domain/src/projection/primitive/GraphicsCaching.jl#L180)) —
confirm a `transform` change still invalidates.

### 5. Widget — `WidgetTransformPane`

**Document** ([Widget.jl](../../package/domain/src/document/Widget.jl), next to
`WidgetScrollPane`): fields `content::Any`, `transform::AffineTransform`
(transient view state, default `affine_identity`), `content_fill_color`,
`position`, `size`, box-model, `selection`; convenience constructor
`WidgetTransformPane(content; transform=affine_identity, …)`, `setfn!` into
`content`, module exports (`WidgetTransformPane`, `IWidgetTransformPane`). No new
operation type — edits are `ReplaceReferencedValue(tp, "transform", M')`.

**Printer** `WidgetTransformPaneToGraphicsCanvas`: like the scroll printer, but
emit `GraphicsViewport(clip=pane box, transform=tp.transform, content=recursed
canvas)`. `map_reference_backward` prepends `FieldReference("content")`
(identical to scroll).

**Reader** `projection_read`: gestures edit the matrix (all via
`ReplaceReferencedValue`), forward other events to content with the pointer
mapped through `inv(transform)`, re-root the returned op at `.content`:

| Gesture | Matrix update |
|---|---|
| `MouseScroll(;ctrl)` wheel | zoom about cursor: `M' = T(cx,cy) ∘ S(f) ∘ T(−cx,−cy) ∘ M`, `f` clamped so total scale ∈ `[MIN,MAX]` |
| `MouseScroll` (no ctrl) | pan: `M' = T(0, ∓step) ∘ M` (still scrolls when nested) |
| `KeyDown(:0;ctrl)` | reset: `M' = affine_identity` |
| `KeyDown(:plus/:minus;ctrl)` (Phase 3) | zoom about pane center |

`MouseScroll` carries `modifiers` ([Mouse.jl#L158](../../package/kernel/src/device/Mouse.jl#L158))
and `@event_case` matches modifier flags after `;`
([EventCase.jl#L92](../../package/kernel/src/device/EventCase.jl#L92), precedent
`KeyDown(:period; ctrl)`#L15). Constants near the scroll fallbacks
([WidgetToGraphics.jl#L297](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L297)):
`ZOOM_STEP=1.1`, `ZOOM_MIN=0.25`, `ZOOM_MAX=4.0`.

**Viewport variant + factory + wrapper**: `WidgetTransformPaneToGraphicsViewport`
mirroring the scroll one; register in the factory map
([#L4144](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L4144));
optional `make_transform_projection` next to `make_scrolling_projection`
([example/.../Wrapper.jl](../../package/example/src/projection/Wrapper.jl)).

### 6. Back-compat

`WidgetScrollPane` stays as-is (offset baked into the inner canvas's `(x,y)`);
it is orthogonal to and composes with `transform`. No separate zoom widget is
added — zoom is `WidgetTransformPane` with a scale matrix. (A later cleanup
*could* reimplement `WidgetScrollPane` as a translate-only `WidgetTransformPane`,
but that is not required and is out of scope here.)

## Implementation phases

### Phase 1 — `AffineTransform` + `GraphicsViewport.transform` + SDL + hit-test (backend-only, de-risk)
1. `AffineTransform` value type + helpers (`∘`, `inv`, `apply`, `is_axis_aligned`) + unit test.
2. `transform` field on `GraphicsViewport` (default identity) + constructor kw.
3. SDL `_render_viewport!` + `_collect_viewport_dirty!` honour translate+scale.
4. `hit_element_at` inverts `transform` on descent; click-roundtrip assertion at scale 2.
   *(ships nothing user-visible; proves the mechanism)*

### Phase 2 — `WidgetTransformPane` document + printer + reader
5. Document struct, constructor, `setfn!`, exports.
6. `WidgetTransformPaneToGraphicsCanvas` printer (viewport with transform).
7. Reader: `MouseScroll(;ctrl)` zoom-to-cursor, plain scroll pan, `Ctrl+0` reset,
   coord inversion + `.content` re-root.
8. Factory entry + viewport variant + example `widget_transform_pane_example`.

### Phase 3 — other backends + keyboard + docs
9. Web `setTransform`, PDF `cm`, console no-op.
10. Keyboard zoom (`Ctrl +/−`), `make_transform_projection` wrapper.
11. Guide row + "Transform / zoom-pan" subsection in
    [documentation/document/widget.md](../../documentation/document/widget.md).

### Phase 4 — rotation / shear (future, out of scope)
12. SDL `RenderGeometry` rects, `RenderCopyEx` glyphs, rounded-rect AA redesign,
    stencil clip. Document/reader/hit-test already general.

## Testing (smallest scope first, per CLAUDE.md)

- `AffineTransform` unit test (`∘`/`inv`/`apply` round-trips, `inv∘ == identity`).
- Reader unit test: `MouseScroll(0,-1,x,y, Modifiers(ctrl=true))` → expected
  `ReplaceReferencedValue("transform", …)` with the point under the cursor fixed;
  plain scroll → pan, not zoom; `MousePress` → inverted coords hit the right child.
- `test_example(widget_transform_pane_example)`; add `; check_reaches_all=true`.
- `hit_element_at` roundtrip through a `transform=scale(2)` viewport
  ([ClickRoundtripTest.jl](../../package/test/src/editor/ClickRoundtripTest.jl)) +
  `test_write_image` at non-identity transform.
- Regression: `test_example(widget_scroll_pane_example)` (shared viewport changed).
- Do **not** run `test_all` to verify.

## Out of scope

- Rotation / shear rendering (Phase 4).
- Reflow zoom (re-layout at larger font) — this is geometric zoom.
- Persisting/serialising `transform` (transient view state).
- Pinch/trackpad gestures (not in the event model).

## Open questions

1. **Per-axis vs uniform scale** in the zoom gesture — plan uses uniform; the
   matrix supports per-axis if a use case appears.
2. **Zoom gesture binding** — Ctrl+wheel (so plain wheel still pans/scrolls when
   nested). Switch to plain wheel only if the pane is always outermost.
3. **Fold `WidgetScrollPane` into the transform pane** later, or keep both?
   Plan keeps both; folding is a separate cleanup.

## Files to touch

- [`package/domain/src/document/Geometry.jl`](../../package/domain/src/document/Geometry.jl) — `AffineTransform` + helpers.
- [`package/domain/src/document/Graphics.jl`](../../package/domain/src/document/Graphics.jl) — `GraphicsViewport.transform`.
- [`package/sdl/src/ProjecturedSdl.jl`](../../package/sdl/src/ProjecturedSdl.jl) — `_render_viewport!`, `_collect_viewport_dirty!`.
- `hit_element_at` (GraphicsModule) — invert transform on descent.
- [`package/domain/src/document/Widget.jl`](../../package/domain/src/document/Widget.jl) — `WidgetTransformPane` + ctor + exports.
- [`package/domain/src/projection/primitive/WidgetToGraphics.jl`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl) — printer, reader, viewport variant, factory entry, constants.
- [`package/web/src/ProjecturedWeb.jl`](../../package/web/src/ProjecturedWeb.jl), [`package/domain/src/backend/Pdf.jl`](../../package/domain/src/backend/Pdf.jl), [`package/domain/src/backend/Console.jl`](../../package/domain/src/backend/Console.jl) — viewport transform.
- [`package/example/src/document/Widget.jl`](../../package/example/src/document/Widget.jl) + example list + [`Wrapper.jl`](../../package/example/src/projection/Wrapper.jl) — example & wrapper.
- New tests in `package/test/src/`; [widget guide](../../documentation/document/widget.md) update.
