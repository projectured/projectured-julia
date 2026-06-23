# Extract a `ProjecturedVideo` package (move `FFMPEG` out of `ProjecturedSdl`)

## Goal

`FFMPEG` is pulled in by `ProjecturedSdl` solely for **headless video recording**
(`record_video`). Users who only want the desktop editor or screenshots
(`write_image`) shouldn't carry it. Split the video-recording feature into a new
**opt-in** package so the SDL backend stays FFMPEG-free.

## Design — `video/` → `ProjecturedVideo` *(depends on `ProjecturedSdl` + `FFMPEG`)*

`record_video` is a **seam**: the generic `function record_video end` is declared and
exported in `kernel/src/api/Backend.jl` and re-exported by the `Projectured` umbrella.
That stays in the kernel. Only the SDL-backed *method* (which is the only thing that
touches `FFMPEG`) moves.

`ProjecturedVideo` depends on `ProjecturedSdl` because video recording **reuses SDL's
offscreen renderer** to rasterise each frame, then calls `ffmpeg` to encode the frames.

### What MOVES from `sdl/src/Sdl.jl` → `video/src/ProjecturedVideo.jl`

- `import FFMPEG` (Sdl.jl:44) and the `FFMPEG.exe(...)` encode call (≈Sdl.jl:1987-1991).
- the `record_video(document, projection, gestures, filename; …)` method (≈Sdl.jl:1900-1995).
- the `_emit_frames!` helper (≈Sdl.jl:1826), used only by `record_video`.
- remove `record_video` from `ProjecturedSdl`'s `export` list (Sdl.jl:47 — keep
  `write_image`, `GraphicsCanvasToImageFile`, drop `record_video`).

### What STAYS in `sdl` (shared with `write_image`, so it must not move)

The offscreen renderer: `_open_offscreen_renderer`, `_render_canvas_offscreen!`,
`_offscreen_output_surface`, `_close_offscreen_renderer` (Sdl.jl ≈1585-1670).
`write_image` depends on these, so they remain in `ProjecturedSdl`.

### The one real design point: expose the offscreen renderer to `ProjecturedVideo`

`record_video`/`_emit_frames!` (now in `ProjecturedVideo`) call those four offscreen
helpers (in `ProjecturedSdl`). They are currently internal (`_`-prefixed, unexported).
Two ways to let the video package reach them:

- **(A) Recommended — give `ProjecturedSdl` a small public offscreen-render API.**
  Export the four helpers (optionally dropping the `_` prefix as their public names),
  so both `write_image` (internal caller) and `ProjecturedVideo` (external caller) build
  on one documented contract. Cleanest cross-package boundary.
- **(B) Qualified internal access** — `ProjecturedVideo` calls
  `ProjecturedSdl._open_offscreen_renderer(…)` etc. Works for sibling packages but
  couples to underscored internals; avoid unless we want a zero-export-change move.

Go with (A).

### Package wiring

- `video/Project.toml`: `name = "ProjecturedVideo"`, new UUID;
  `[deps]` = `ProjecturedSdl`, `FFMPEG`; `[sources]` `ProjecturedSdl = {path = "../sdl"}`.
- `sdl/Project.toml`: **remove** the `FFMPEG` dep (line 7). (No `[compat]` entry for
  FFMPEG to remove — only `SDL2_jll` is pinned.)
- `Projectured` umbrella: unchanged — it re-exports the `record_video` *generic* from
  `BackendModule`; the method now lives in `ProjecturedVideo`.

### Downstream callers that need the method (add `using ProjecturedVideo` + dep)

`record_video` callers currently get a working method via `using Sdl`; after the split
they need `ProjecturedVideo`:

- `example` (`ProjecturedExample`): `LiveExamples.jl` (`record_live_example`),
  `Examples.jl` (`record_example_video` + the gesture/timeline helpers around
  lines 615/699). Add `ProjecturedVideo` to its `[deps]` and a `using ProjecturedVideo`.
- `test` (`ProjecturedTest`): `VideoTest.jl`. Add the dep + `using ProjecturedVideo`
  (today it relies on `using Sdl`).

### Usage after the split

```julia
using Projectured, ProjecturedSdl, ProjecturedVideo
record_video(doc, proj, gestures, "out.mp4")
```

(`Projectured` = editing API; `ProjecturedSdl` = offscreen frame rendering;
`ProjecturedVideo` = the FFMPEG encode step.)

## Verification

- `ProjecturedSdl` precompiles/loads **without** `FFMPEG`; `write_image` still works
  (offscreen renderer intact) — run an image-output example.
- `record_video` works via `ProjecturedVideo` — run `VideoTest` (it already skips
  gracefully if the `ffmpeg` binary is unavailable).
- `Pkg.resolve()` succeeds for `video/`, `sdl/`, `example/`, `test/`.

## Relationship to the directory reorg

This is a **code refactor**, independent of (and doable before or after) the
[source-tree reorganization](source-tree-reorganization.md). After both land, the
end-state package set is **12**, with `video/` living at `package/video/` as a Layer-4
opt-in package whose only twist is that it depends on another Layer-4 package (`sdl`).

## Status

- [ ] Create `video/` package (`ProjecturedVideo`, deps ProjecturedSdl + FFMPEG)
- [ ] Expose sdl offscreen-render API (option A)
- [ ] Move `record_video` + `_emit_frames!` + `import FFMPEG` out of sdl; drop FFMPEG dep + export
- [ ] Update `example` + `test` (deps + `using ProjecturedVideo`)
- [ ] Verify (write_image still works; VideoTest; Pkg.resolve)
