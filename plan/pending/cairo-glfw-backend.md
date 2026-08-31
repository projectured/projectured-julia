# Cairo + GLFW backend

> **Status (2026-08-12): NOT STARTED.** No `package/cairo` directory exists and
> `ProjecturedCairo` has zero references anywhere in the repository. The
> reference material this plan reuses is all present and current under its new
> paths: `package/pdf/main/Pdf.jl` (the SDL-free painter set to port),
> `package/sdl/main/ProjecturedSdl.jl` (the interactive backend to mirror), and
> `package/kernel/main/backend/{BackendInterface,BackendDefaults}.jl` and
> `package/kernel/main/device/Device.jl` (the interface to implement).

## Goal

Add a new **interactive** `Backend` — `CairoBackend` — that renders the graphics
domain (`GraphicsCanvas` and its primitives) to native windows using
**Cairo.jl** for the drawing and **GLFW.jl** for the window/input, as a
peer of `SdlBackend`. Loaded with `using ProjecturedCairo`, it registers
`make_backend(:cairo)` and is a drop-in for `run!` / `run_example(backend=…)`,
touching no projection or domain code — exactly like the Web backend was.

It lives in a new opt-in package `package/cairo` (module `ProjecturedCairo`),
mirroring `package/sdl`.

## Why this is clean (what we reuse)

The graphics-domain render walk already exists **twice**, and the Cairo version
is closest to the SDL-free one:

- **`package/pdf/main/Pdf.jl`** (`PdfBackendModule`) is a complete,
  SDL-free walk of a `GraphicsCanvas`: `paint_rect!`, `paint_circle!`,
  `paint_line!`, `paint_polyline!`, `paint_spline!`, `paint_text!`,
  `paint_image!`, `paint_viewport!`, `paint_canvas!`, `paint_elem!`. Cairo's
  imaging model (paths + fill/stroke, `arc`, `set_dash`, `rectangle`+`clip`,
  `set_matrix`, image-surface `Do`) maps almost 1:1 onto these painters. **The
  Cairo painter set is the Pdf painter set with Cairo calls swapped in — and it
  is simpler than Pdf, because there is _no y-flip_:** the Cairo image surface is
  top-left / y-down, the same as the graphics domain (Pdf needed `_flip`).
- The **geometry helpers are already shared and backend-agnostic** (exported from
  `GraphicsModule`): `tessellate_spline`, `polyline_arrowhead`,
  `_canvas_content_bounds`, plus the `KAPPA` rounded-rect/circle Bézier trick in
  Pdf. Splines/arrows/rounded rects come for free.
- The **`Backend` / `Device` split** is designed for this. A new backend needs
  only `init!`, `quit!`, `measure_text`, `read_from_devices`, `write_to_devices`
  (+ optional `pointer_position`, `display_size` provider). See
  [package/kernel/doc/devices-and-backends.md](../../documentation/package/kernel/devices-and-backends.md)
  §"Adding a new backend".
- **`write_to_devices(::CairoBackend, devices, ::ScreenDocument)`** is the same
  window-reconciliation loop as SDL's (diff desired `WindowDocument.id`s against
  live windows; open/close/update-geometry; render each window's `content`
  canvas). Copy the shape of `write_to_devices(::SdlBackend, …)` and
  `_update_window_geometry!` in [package/sdl/main/ProjecturedSdl.jl](../../package/ProjecturedSdl/src/ProjecturedSdl.jl).
- **Input is *better* than SDL's**: GLFW delivers events through callbacks with a
  clean, portable key enum (`GLFW.KEY_LEFT`, …) instead of SDL's magic keysym
  integers. We translate to the same backend-agnostic vocabulary
  (`KeyDown`/`KeyUp`/`KeyPress`/`Mouse*`/`WindowCloseRequest`/…).

The only genuinely new problem Cairo+GLFW poses that SDL did not: **GLFW gives us
an OpenGL window, not a CPU pixel buffer, while Cairo renders into a CPU image
surface.** We must get Cairo's pixels onto the GLFW framebuffer. See
"Windowing & the Cairo→GLFW blit" below.

## Architecture

```
Editor.run! ─▶ read_from_devices(CairoBackend) ─▶ GLFW.PollEvents() drains
   ▲                                               callback-filled event queue
   │                                               ─▶ EventEnvelope(window_id, ev)
   └── write_to_devices(CairoBackend, ScreenDocument)
         └─ reconcile GLFW windows by WindowDocument.id
              └─ paint_canvas!(cr, content)  (Cairo image surface, y-down)
                   └─ blit surface → GLFW framebuffer → SwapBuffers
```

### Package layout (mirror `package/sdl/main`)

```
package/cairo/main/
  Project.toml          # name=ProjecturedCairo; deps: ProjecturedCollection,
                        # ProjecturedGraphics, ProjecturedKernel, ProjecturedScreen,
                        # ProjecturedStyle, Cairo, GLFW, ModernGL — the same
                        # dependency set as package/sdl/main/Project.toml, plus
                        # the Cairo/GLFW/ModernGL native packages
  ProjecturedCairo.jl
```

Root `Project.toml`: add `ProjecturedCairo` to `[deps]` and `[sources]`
(`{path = "package/cairo/main"}`), like every other subpackage. There is no
umbrella `Projectured` package that imports every domain; a backend is opt-in
`using ProjecturedCairo`.

### Backend state (mirror `SdlBackend` / `SdlWindowResources`)

```julia
mutable struct CairoWindowResources
    window::GLFW.Window
    id::Symbol                     # WindowDocument.id mirrored
    surface::Cairo.CairoSurface    # ARGB32 image surface, framebuffer-sized
    cr::Cairo.CairoContext
    gl_tex::UInt32                 # texture id (0 if using glDrawPixels)
    width::Int; height::Int        # last applied logical size
    title::String; style::Symbol; bg::NTuple{4,UInt8}   # last-applied caches
end

mutable struct CairoBackend <: Backend
    windows::Dict{Symbol, CairoWindowResources}
    window_ids::Dict{GLFW.Window, Symbol}   # reverse map for callbacks
    events::Vector{Any}                     # queue filled by GLFW callbacks
end
```

## Rendering: primitive → Cairo mapping

Model each on the matching `paint_*!` in `Pdf.jl`, dropping the y-flip.

| Graphics primitive | Cairo |
|---|---|
| `GraphicsCanvas`/`GraphicsFence` | recurse over `elements`, skip fences (as Pdf/SDL do) |
| `GraphicsRect` (radius, border) | rounded-rect path via `KAPPA` `curve_to` (reuse `_rrect_path!` logic); `set_source_rgba`+`fill`; border = outer fill then inner fill, or `stroke` |
| `GraphicsCircle` (border) | `arc(cx,cy,r,0,2π)` + `fill`; hollow ring = stroke at `r−bw/2` with `set_line_width(bw)` |
| `GraphicsLine` (`width`, `dash`) | `move_to`/`line_to`; `set_line_width`; `set_dash([on,off])` when `dash!==nothing`, else clear |
| `GraphicsPolyline` (arrows) | `move_to`+`line_to` chain, `stroke`; arrowheads via `polyline_arrowhead` filled triangles |
| `GraphicsSpline` | `tessellate_spline(points,kind,segments)` → polyline path (same as Pdf) |
| `GraphicsText` | load the span's `StyleFont.filename` as a FreeType/Fontconfig font face; `set_source_rgba`; `move_to(x, y+ascent)`; `show_text` (baseline like Pdf's `ascent_px`) |
| `GraphicsViewport` (transform) | `rectangle(x,y,w,h)`+`clip`; `set_matrix`/`translate`+`scale` from `AffineTransform`; recurse; `restore` |
| `GraphicsImage` | decoded-RGBA `Vector{UInt8}` → `Cairo.CairoImageSurface` → `set_source_surface`+`paint` (skip raw SDL-texture `Ptr` form, as Pdf does) |

Colours: `StyleColor` is Float64 RGBA in `[0,1]` — pass straight to
`set_source_rgba` (no `/255` needed, unlike Pdf/SDL byte helpers).

### Text & measurement (the consistency requirement)

Layout is computed by the projection's injected `measure` function *before*
anything is drawn, so **the measurer must agree with what Cairo draws** or text
misaligns.

- **Decision to make in Phase 1** (both the text painter and the measurer land
  together, so it's validated immediately via the PNG test):
  - **Preferred:** provide `cairo_measure_text(text, font)` using
    `Cairo.text_extents` on the same font face the painter uses, and inject it as
    the pipeline `measure=` when running on the Cairo backend — self-consistent,
    mirrors how SDL pairs `sdl_measure_text` with its text renderer.
  - **Fallback:** reuse the existing `truetype_measure_text` (pure hmtx advances,
    from `Pdf.jl`, the current default `measure`) and confirm Cairo's total
    advance for a string matches it closely; if so, no new measurer is needed and
    Cairo layout matches the SDL/PDF golden layouts exactly.
- **Emoji / glyph fallback parity** (deferred to a later phase): SDL splits a
  string into text vs emoji runs (`_font_runs`, NotoEmoji) and has DejaVu
  fallback for chrome glyphs (▾▸) — see memories
  `sdl-no-font-fallback-chrome-glyphs`, `emoji-font-fallback`. With Pango, Cairo
  gets fallback automatically; with raw FreeType faces we must port the run
  split. v1 may use the primary font only and render tofu for emoji, matching the
  Pdf backend's current single-font behaviour.

## Windowing & the Cairo→GLFW blit

GLFW owns the OS window and an OpenGL context; Cairo renders into a CPU
`ARGB32` image surface. Bridge them by uploading the surface each frame:

- **v1 (recommended, least code):** request GLFW's default (compatibility) GL
  context; per frame, after `paint_canvas!` and `Cairo.finish(surface)`:
  `MakeContextCurrent(win)` → `glRasterPos2f(-1,1)` → `glPixelZoom(1,-1)` (flip:
  Cairo row 0 is top, GL is bottom-up) → `glDrawPixels(w,h, GL_BGRA,
  GL_UNSIGNED_BYTE, surfacedata)` → `SwapBuffers(win)`. Cairo `ARGB32` in
  little-endian memory is B,G,R,A — matches `GL_BGRA`. ~6 GL calls, no shaders,
  no textures.
- **v2 (if any driver rejects legacy GL):** upload the surface to one GL texture
  (`glTexImage2D`/`glTexSubImage2D`, `GL_BGRA`) and draw a full-window textured
  quad. More robust on core-profile-only drivers; more code. `ModernGL.jl`
  supplies the GL entry points either way.

Multi-window: make each window's context current before painting/presenting it.

HiDPI: the graphics domain is in **logical** pixels; GLFW separates window size
(logical) from framebuffer size (pixels) and reports `GetWindowContentScale`.
Size the Cairo surface to the framebuffer and `Cairo.scale(cr, sx, sy)` so
content is authored in logical px (parallels SDL's `_DISPLAY_SCALE` /
`_to_device`). v1 may assume scale 1 and refine in Phase 4. Register a
`display_size` provider via `set_display_size_provider!` using GLFW monitor work
area (mirror `sdl_display_size`).

## Input: GLFW → backend-agnostic events

GLFW callbacks fire during `GLFW.PollEvents()`. Set per-window callbacks in
`init!`/on window open that push translated events into `backend.events`;
`read_from_devices` calls `PollEvents()` then pops one, wrapping it in
`EventEnvelope(window_id, event)` (window id via `backend.window_ids`).

| GLFW callback | → event |
|---|---|
| `SetKeyCallback` (PRESS/REPEAT) | `KeyDown(sym, mods, repeat)`; `ESCAPE` → `QuitEvent()` (match SDL) |
| `SetKeyCallback` (RELEASE) | `KeyUp(sym, mods)` |
| `SetCharCallback` (codepoint) | `KeyPress(Char(cp))` |
| `SetMouseButtonCallback` PRESS/RELEASE | `MouseDown`/`MouseUp(button, x, y, mods)` |
| `SetCursorPosCallback` | `MouseMove(x, y, held_button, mods)` — rate-limit idle (no-button) motion like SDL's `_HOVER_MOTION_INTERVAL` |
| `SetScrollCallback` | `MouseScroll(dx, dy, cursor_x, cursor_y, mods)` (shift-swaps axes like SDL) |
| `SetWindowCloseCallback` | `WindowCloseRequest()` |
| `SetFramebufferSizeCallback` | `WindowResizeEvent(w, h)` (logical) + recreate the Cairo surface |
| `SetWindowFocusCallback` (lost) | `WindowFocusLost()` (drives `auto_dismiss` popups) |

Need two small translation tables mirroring the SDL ones:
`glfw_key_to_symbol(::GLFW.Key)::Symbol` (nav/editing/function/chord keys →
`:left`,`:return`,`:c`,`:slash`,… — copy the vocabulary from
`sdl_keysym_to_symbol`) and `glfw_modifiers(::Int)::Modifiers`.

Cursor position for `MouseDown`/`Up`/`Scroll`: GLFW button/scroll callbacks don't
carry coordinates — read the last `CursorPos` (cache it in the cursor-pos
callback, or `GLFW.GetCursorPos(win)`).

## Milestones (each a commit; work in a git worktree)

### Phase 0 — scaffold & dependency resolution
- [ ] Create `package/cairo/Project.toml` + `src/ProjecturedCairo.jl` skeleton
      (module + imports mirroring the SDL import block).
- [ ] Add `Cairo`, `GLFW`, `ModernGL` to the package deps; add `ProjecturedCairo`
      to root `[deps]`/`[sources]`.
- [ ] Confirm resolution against the existing SDL/Cairo_jll stack. `Cairo_jll` is
      already in the Manifest, so `Cairo` should resolve; watch for a GLFW/JLL
      clash (cf. memory `gr-jll-unsatisfiable-use-cairomakie`). **Delegate the
      `Pkg.resolve`/precompile to a Sonnet subagent in an external shell — do not
      precompile the native stack in-session (crashes VS Code host).**

### Phase 1 — offscreen render (windowless, testable) — *primary de-risk*
- [ ] Port the `paint_*!` set from `Pdf.jl` to Cairo (no y-flip) into
      `ProjecturedCairo`; implement `paint_canvas!`/`paint_elem!` dispatch.
- [ ] `cairo_render_to_surface(canvas, w, h, bg) -> CairoSurface`.
- [ ] `write_cairo_image(canvas|document, projection, filename; …)` → PNG via
      `Cairo.write_to_png` (SDL-free; a peer of `write_image`/`write_pdf`).
- [ ] `cairo_measure_text` + decide measure/render consistency (see Text above).
- [ ] Test (in-session safe — no window, no native editor stack): render a known
      example canvas to PNG, assert it is produced and non-trivial; compare glyph
      advance vs `truetype_measure_text`.

### Phase 2 — single GLFW window, render-only
- [ ] `init!`/`quit!`: `GLFW.Init()`/`Terminate()`; register `make_backend(:cairo)`.
- [ ] Open one GLFW window; create matching Cairo surface; implement the blit
      (glDrawPixels v1).
- [ ] `write_to_devices(::CairoBackend, devices, ::ScreenDocument)` — reconcile a
      single window, paint its `content` canvas, present.
- [ ] Live smoke test = **user runs it in an external terminal** (heavy native
      run; hand off per memory `no-heavy-julia-runs-crash-vscode`).

### Phase 3 — input (becomes a live editor backend)
- [ ] GLFW callbacks → event queue; `read_from_devices` pops + envelopes.
- [ ] `glfw_key_to_symbol` + `glfw_modifiers`; char/mouse/scroll/close/resize/focus.
- [ ] Idle-motion rate-limit; escape→quit.
- [ ] `run_cairo_example` helper (or document `run_example(...;
      backend=make_backend(:cairo))` after `using ProjecturedCairo`).

### Phase 4 — multi-window & platform parity
- [ ] Full reconciliation: open/close/geometry/title/bg/style updates
      (`_update_window_geometry!` analogue); window styles (tooltip/floating via
      GLFW hints: decorated/floating); `auto_dismiss` on focus-lost.
- [ ] HiDPI content-scale; `set_display_size_provider!` via GLFW monitors;
      `pointer_position(::CairoBackend)` via `GetCursorPos` + window pos.

### Phase 5 — optional perf / fidelity
- [ ] Emoji/chrome-glyph font-fallback parity (Pango or ported `_font_runs`).
- [ ] Dirty-rect partial repaint (reuse `_collect_canvas_dirty!` bounds helpers).
- [ ] Texture-quad blit (v2) if legacy GL is a problem.
- [ ] Offscreen Cairo could also back `render_canvas`/`write_image` SDL-free.

## Decisions to record during implementation
- Measurer: `cairo_measure_text` injected vs reuse `truetype_measure_text`
  (validated in Phase 1).
- Blit: `glDrawPixels` (v1) vs texture+quad (v2) — which driver-portability we land on.
- Whether `run_cairo_example` lives in `ProjecturedExample` (adds a cairo dep) or
  is left as a documented `run_example(backend=…)` invocation.

## Risks / watch-list
- **Dependency resolution** with the SDL + native stack (Cairo_jll present;
  GLFW_jll new). Resolve/precompile **externally**, never in-session.
- **Legacy GL** (`glDrawPixels`) unavailable on a core-profile-only driver → v2
  texture path.
- **Text metric drift** between Cairo rendering and the injected measurer →
  caught by the Phase 1 PNG/advance test before any windowing.
- **Native run crashes the VS Code host** — all live/windowed verification is done
  by the user in an external terminal; in-session tests stay on the windowless
  Cairo PNG path + pure event-translation unit tests.

## References
- `package/sdl/main/ProjecturedSdl.jl` — interactive backend to mirror (windowing,
  `read_from_devices`, `write_to_devices` reconciliation, key/mod maps, HiDPI).
- `package/pdf/main/Pdf.jl` — the SDL-free canvas walk to port to Cairo.
- `package/console/main/Console.jl` — smallest complete non-SDL backend.
- `package/kernel/main/backend/{BackendInterface,BackendDefaults}.jl` and `package/kernel/main/device/Device.jl` — the interface to implement.
- `package/screen/main/ScreenDocument.jl` — `ScreenDocument`/`WindowDocument`.
- `package/kernel/doc/devices-and-backends.md` — §"Adding a new backend".
</content>
</invoke>
