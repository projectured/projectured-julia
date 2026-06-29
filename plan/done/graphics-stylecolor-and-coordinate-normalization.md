# Graphics domain: StyleColor + coordinate-type normalization

Two related cleanups to the Graphics domain ([package/domain/src/document/Graphics.jl](../../package/domain/src/document/Graphics.jl)):

- **Part A** — replace the per-primitive `r,g,b,a::UInt8` (and `border_*::UInt8`) byte
  quads with a single `color::StyleColor` (and `border_color::StyleColor`) field, so the
  Graphics domain uses the same color type as every other layer (Text, Syntax, Widget,
  StyleStroke, StyleText).
- **Part B** — normalize the one out-of-line coordinate type: `GraphicsCanvas` stores
  `x,y,w,h::Int` while every other primitive uses `Int32`.

The two parts are independent. **Part B is done first** (tiny, isolated) as a warm-up
commit; Part A follows.

## Design decision: convert per-backend, do *not* cache bytes in the domain

The earlier exploration floated a "memoized byte `Cell` per element" middle ground. The
scope review refuted it: there are **three** Graphics backends and each needs a *different*
device encoding —

| Backend | wants | current code |
| --- | --- | --- |
| SDL ([ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl)) | `UInt8` 0–255 | `SDL_SetRenderDrawColor(rect.r, rect.g, rect.b, rect.a)` |
| PDF ([Pdf.jl](../../package/domain/src/backend/Pdf.jl)) | `0–1` Float | `c01(line.r) = line.r/255` — round-trips bytes back to float |
| Web ([ProjecturedWeb.jl](../../package/web/src/ProjecturedWeb.jl)) | int array → CSS | `_rgba(e) = Int[Int(e.r), …]` |

A single cached byte tuple would serve SDL but be wrong for PDF/Web. So:

- **The domain stores only `StyleColor`.** No byte/device field is added — that would
  re-pollute the domain with the device bytes we are removing.
- **Each backend converts in its own draw path** via a tiny local accessor. PDF in
  particular *stops* doing the `/255` round-trip — it reads `c.red` (already 0–1) directly.
- **No memoization.** The conversion is ~4 multiplies + round, dwarfed by rasterization,
  and reading the `StyleColor` cell still registers the reactive dependency, so
  dirty-tracking / incrementality is unchanged.

`StyleColor` lives in `ColorModule` ([Color.jl](../../package/domain/src/document/Color.jl)):
`struct StyleColor; red,green,blue,alpha::Float64; end`, components in `[0,1]`, plus a large
named palette (`color_white`, `color_black`, `color_solarized_*`, …) and helpers
(`color_lighten/darken/interpolate/equal`).

## Relationship to in-flight work

The working tree has an uncommitted **dashed-line** change touching `GraphicsLine` (`dash`
field), `RotatingVector.jl`, `Examples.jl`, and `ProjecturedSdl.jl`. Part A also touches
`GraphicsLine`/`RotatingVector`/`ProjecturedSdl`, so the two overlap. **Land the dash work
first** (or implement Part A on top of it) to avoid a self-conflict. RotatingVector's
hardcoded hex (`_RV_BG = (0x00,0x2b,0x36,0xff)` …) maps onto existing named constants
(`color_solarized_background_darker`, `color_solarized_magenta`, `color_solarized_blue`,
`color_solarized_green`) — convert it as part of A8.

---

## Part B — normalize `GraphicsCanvas` coordinates to `Int32`

The struct-field wart is solely `GraphicsCanvas` (`Graphics.jl:390-393`): `x,y,w,h::Int`
where every other primitive uses `Int32`. Its own constructors already pass `Int32(0)`
(widened to `Int` on store). Hit-test/bounds *function signatures* correctly use `Int`
(the working type, read via `Int(elem.x)`) — those stay.

- [x] Change `GraphicsCanvas` fields `x,y,w,h` from `Int` → `Int32`.
- [x] Verified `@document` semantics: declared types are **documentary** for the mutable
      struct (every field becomes an untyped `Cell`); the annotation only types the
      immutable `IGraphicsCanvas` mirror. Constructors already feed `Int32`, reads use
      `Int(...)`, so the change is safe.
- [x] Left `points::Any` (`Tuple{Int,Int}`) as-is — a different (Any-typed) field, not part
      of the scalar wart; the read path coerces via `Int(p[1])`.
- [x] Tested: `test_graphics()` + `test_graphics_layout()` green.
- [x] **Committed:** `refactor(graphics): normalize GraphicsCanvas coords to Int32`.

---

## Part A — `StyleColor` in Graphics primitives

### A1. Domain structs ([Graphics.jl](../../package/domain/src/document/Graphics.jl))

Replace byte fields with `StyleColor`:

- [x] `GraphicsText`: `r,g,b,a` → `color::StyleColor`.
- [x] `GraphicsRect`: `r,g,b,a` + `border_r,border_g,border_b,border_a` →
      `color::StyleColor` + `border_color::StyleColor`.
- [x] `GraphicsLine`: `r,g,b,a` → `color::StyleColor`.
- [x] `GraphicsCircle`: `r,g,b,a` + `border_*` → `color::StyleColor` + `border_color::StyleColor`.
- [x] `GraphicsPolyline`: `r,g,b,a` → `color::StyleColor`.
- [x] `GraphicsSpline`: `r,g,b,a` → `color::StyleColor`.
- [x] Import `StyleColor` (+ defaults) from `ColorModule` into `GraphicsModule`.

### A2. Constructors ([Graphics.jl](../../package/domain/src/document/Graphics.jl))

Collapse the 4 positional color args to one `color::StyleColor`:

- [x] `GraphicsText(text, x, y, font, color::StyleColor=color_white)`.
- [x] `GraphicsRect(x,y,w,h, color::StyleColor=color_white, radius=0; radius_tl…, border_width=0, border_color=nothing)`.
- [x] `GraphicsLine(x1,y1,x2,y2, color::StyleColor=color_black; width=1, dash=nothing)`.
- [x] `GraphicsCircle(cx,cy,radius, color::StyleColor=color_black; border_width=0, border_color=nothing)`.
- [x] `GraphicsPolyline(points, color::StyleColor=color_black; width=1, start_arrow=false, end_arrow=false, arrow_size=8)`.
- [x] `GraphicsSpline(points, color::StyleColor=color_black; kind=:catmullrom, …)`.
- [x] Replace `_norm_rgba(::Nothing)=(0,0,0,0)` with
      `_norm_border(::Nothing)=StyleColor(0,0,0,0); _norm_border(c::StyleColor)=c`
      (transparent default; `border_width>0` still gates whether a border draws).
- [x] Update the docstrings (the `(r,g,b,a)` references).

Defaults preserve current behavior: Text/Rect default white, Line/Circle/Polyline/Spline
default black, transparent border.

### A3. SDL backend ([ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl))

- [x] Add `_rgba8(c::StyleColor) = (UInt8(round(c.red*255)), UInt8(round(c.green*255)), UInt8(round(c.blue*255)), UInt8(round(c.alpha*255)))`.
- [x] Rect (`:786-795`), Circle (`:1003-1015`): `SDL_SetRenderDrawColor(_rgba8(rect.color)...)`,
      border via `_rgba8(rect.border_color)...`; `rect.a > 0` → `rect.color.alpha > 0`.
- [x] Text (`:640`): `color = _rgba8(elem.color)`.
- [x] Line (`:823-846`), Polyline (`:928-930`), Spline (`:935-938`): replace the
      `line.r, line.g, line.b, line.a` argument groups with `_rgba8(line.color)...`;
      `pl.a == 0` → `pl.color.alpha == 0`.
- [x] Text texture cache key (`TextureCacheEntry.color::NTuple{4,UInt8}`, `:227`) keeps
      its `UInt8` key — feed it `_rgba8(elem.color)`.

### A4. PDF backend ([Pdf.jl](../../package/domain/src/backend/Pdf.jl))

- [x] Drop the `/255` round-trip: read `c.red/green/blue` directly (already 0–1). Replace
      `c01(line.r)` → `line.color.red` etc. (`:373-379, 418-426, 441-442, 479, 486, 507-508`).
- [x] Alpha: `gs_for!(ctx, line.a)` / `t.a` → `…color.alpha` (PDF `gs` graphics-state alpha
      is already 0–1; no `/255`).
- [x] Guards `rect.a > 0`, `line.a == 0`, `t.a == 0` → `.color.alpha`.

### A5. Web backend ([ProjecturedWeb.jl](../../package/web/src/ProjecturedWeb.jl))

- [x] `_rgba(c::StyleColor) = Int[round(Int,c.red*255), round(Int,c.green*255), round(Int,c.blue*255), round(Int,c.alpha*255)]`; call as `_rgba(elem.color)`.
- [x] `_border_rgba(e)` → `_rgba(e.border_color)` (`:179-180` + use sites).

### A6. TextToGraphics bridge ([TextToGraphics.jl](../../package/domain/src/projection/primitive/TextToGraphics.jl))

The 3 conversion sites disappear — pass the `StyleColor` straight through:

- [x] `:336` and `:538-539`: delete `r,g,b,a = (UInt8(round(col.red*255))…)`; build the
      `GraphicsText` with `col` directly.
- [x] `:595-598`: the background-fill `GraphicsRect` takes `fill` (a `StyleColor`) directly.

### A7. Other Graphics-producing projections

- [x] [WidgetToGraphics.jl](../../package/domain/src/projection/primitive/WidgetToGraphics.jl)
      — the heavy file (~66 constructions). It *already* holds `StyleColor` everywhere and
      lowers at the last inch via `_rgba`/`_rgbai` (`:327, :537`). Delete those helpers and
      the `r,g,b,a = _rgba(c)` unpack lines; pass the `StyleColor`/`border_color=…` directly.
      This is a **net simplification** (≈20 unpack sites collapse). `border_color=_rgbai(c)`
      → `border_color=c`.
- [x] [GraphLayoutToGraphics.jl](../../package/domain/src/projection/primitive/GraphLayoutToGraphics.jl)
      (2 constructions + 1 border).
- [x] [GraphicsCaching.jl](../../package/domain/src/projection/primitive/GraphicsCaching.jl) (1).
- [x] [TextHighlighting.jl](../../package/domain/src/projection/primitive/TextHighlighting.jl)
      — audit (builds highlight `GraphicsRect`s).

### A8. Examples

- [x] [RotatingVector.jl](../../package/example/src/RotatingVector.jl) — convert the `_RV_*`
      hex tuples to named `color_solarized_*` constants (see "in-flight work"); drop the
      `..._RV_FOO...` splats for single `color=` args. **Do after the dash work lands.**
- [x] [example/document/Layout.jl](../../package/example/src/document/Layout.jl) (already
      uses `StyleColor`; fix any `border_color=` tuples).
- [x] [example/document/Widget.jl](../../package/example/src/document/Widget.jl) (5 sites).
- [x] [example/document/TextToString.jl](../../package/example/src/document/TextToString.jl)
      (already `StyleColor`).

### A9. Tests

Update color-constructing / `.r`/`.g`/`.b`/`.a`-reading tests:

- [x] `test/document/GraphicsLayoutTest.jl` (11), `GraphicsTest.jl` (3).
- [x] `test/backend/DirtyRectTest.jl` (6), `PdfTest.jl` (5).
- [x] `test/projection/{GraphTest,TextToGraphicsTest,WidgetIconTest,WidgetButtonTest,TableSelectionTest}.jl`,
      `test/editor/{MouseClickTest,TypeinTest,ClickRoundtripTest}.jl` — audit for color reads.
- [x] Compare colors with `color_equal`, not `==`. Image-hash tests are safe: `round(n/255*255)==n`
      round-trips exactly.

### Commits for Part A

Land incrementally, keeping the tree buildable at each step where feasible:

1. `refactor(graphics): StyleColor fields + constructors` (A1–A2).
2. `refactor(graphics): convert StyleColor per-backend (SDL/PDF/Web)` (A3–A5).
3. `refactor(graphics): pass StyleColor through projections` (A6–A7).
4. `refactor(graphics): StyleColor in examples + tests` (A8–A9).

(Because A1–A2 change the constructor arity, the tree may not fully build until A3–A5 land;
group 1+2 into one commit if a partial build is undesirable.)

---

## Verification

- Targeted first (per repo convention — never default to `test_all`):
  `test_example(json_example)` for the Text→Graphics path, `WidgetButtonTest`/`GraphTest`
  for Widget/graph paths, `PdfTest` + `DirtyRectTest` for backends, and a visual
  `run_example` / `write_example_image` on RotatingVector and a widget screen.
- Then a broader sweep (`test_printers`/`test_readers`) once targeted tests pass.
- Watch for: float-equality in tests (use `color_equal`); the PDF alpha graphics-state
  (`gs`) no longer needs `/255`; the `border_width>0` gating unchanged.

## Risks

- **Breadth, not depth** — mechanical change across ~15 files. The only logic subtlety is
  the transparent-border default and the alpha guards switching from `a>0` (byte) to
  `color.alpha>0` (float).
- **Arity change** ripples to every call site; a missed site is a method-not-found at load,
  caught immediately.

---

## Implementation notes (as-built)

Done on branch `graphics-stylecolor` (worktree off HEAD `76c7bcf`; the dash work was
already committed by then, so there was no in-flight overlap after all). Four commits:
`refactor(graphics): normalize GraphicsCanvas coords to Int32`; `… use StyleColor in the
Graphics domain`; (domain + backends + projections folded into that one); `… StyleColor in
examples + tests`.

Deviations / discoveries:

- **PDF kept the byte path (A4 deviation).** Rather than thread floats through `c01` and the
  `UInt8`-keyed ExtGState alpha-dedup (`gs_for!`), each PDF painter call site converts via a
  local `_rgba8(::StyleColor)` and feeds the existing byte helpers unchanged. The float→byte
  round-trip is preserved but harmless (identity for the values used), and the alpha-dedup
  machinery is untouched. Lower-risk than the planned rewrite; revisit only if the round-trip
  ever matters.
- **WidgetToGraphics funnel-first strategy.** Converting the shared helpers (`_push_panel!`,
  `_push_box!`, `_push_hover_surface!`, `_push_box_rects!`, `_push_text!`, `_push_chevron!`,
  `_icon_path!`, `glyph_icon`) to take/pass `StyleColor` absorbed most of the ~66 call sites;
  the remaining direct unpack-and-construct sites and a few byte-literal scrims/shadows/
  highlights (`_WT_HL_*`) were converted individually. `_rgba`/`_rgbai` deleted.
- **`_push_text!` wrapper strip via `sed`** (`/_push_text!/ s/_rgba(…)/…/`) — a uniform
  mechanical transform across 17 identical-shaped calls.
- **TextHighlighting needed no change** — it emits into the Text layer (`fill_color`), not
  Graphics primitives.
- **RotatingVector** hex consts mapped exactly onto `color_solarized_background_darker`
  (base03), `_content_darker` (base01), `_content_light` (base0), `_magenta`, `_blue`,
  `_green`; `using Projectured` re-exports them. Verified visually (PNG renders correctly).
- **`test_dirty_rect()` fails pre-existing**, not a regression: `UndefVarError: Sdl` (an
  aborted package-rename reference in `DirtyRectTest.jl`, which this work never touched).
  Confirmed identical failure on the untouched baseline.

Verified: domain + SDL + PDF + Web precompile; `test_graphics`, `test_graphics_layout`,
`test_text_to_graphics`, `test_write_pdf`, `test_widget_button_behavior`, `test_widget_icon`
pass; RotatingVector renders to pixels with the correct Solarized palette.
