# A clip is set in device pixels

Status: DONE, 2026-10-20, on the branch `scaled-viewport-clip`, in the worktree
`projectured-julia-repaint-skip`. Not landed on `main`.

## The ask

The plan [a-repaint-draws-only-what-its-rectangles-touch.md](../done/a-repaint-draws-only-what-its-rectangles-touch.md)
found a fault on `main`: a dirty rectangle that cuts a viewport with a scale of
2 at an odd pixel keeps a band of old pixels. The owner, 2026-10-20: "1: fix".

## The problem

SDL 2.32.10 keeps a clip in device pixels. `SDL_RenderSetClipRect` multiplies the
rectangle by the scale in force when it is called, and a later scale change does
not move the clip. `SDL_RenderGetClipRect` answers the clip divided by the scale
in force, cut to whole units. A probe at scale 2 set the clip of columns 11 to 15
and read it back as `(5, 0, 2, 5)`.

`_render_viewport!` uses both in a way that rounds:

1. A viewport with a scale sets its clip after the scale change, in the units of
   its content: `round(box.x / sx)`. With a scale of 2, a clip edge at an odd
   pixel moves by one pixel. The probe: the clip of columns 11 to 15 set this
   way drew columns 12 to 15.
2. A viewport reads the clip in force with `SDL_RenderGetClipRect`. Inside the
   content of a viewport with a scale, that read is cut to whole content units,
   so a viewport inside it intersects with a wrong clip.

A full paint has the clip of the whole window, so the fault shows only when the
clip edge of a partial paint cuts such a viewport.

## The model

Each clip is read and set at the scale 1, in device pixels, and the scale of the
content is set after the clip. A device rectangle covers each pixel that the
logical box touches: the corner rounds down and the far edge rounds up.

- `_render_viewport!` reads the scale in force, sets the scale 1, reads the clip
  in force, intersects it with the device box of the viewport, sets the clip,
  and only then sets the scale of its content. It restores the clip at the scale
  1, and then the scale in force.
- `_paint_dirty_rects!` sets the clip of each rectangle, and fills its
  background, at the scale 1 in device pixels, so the clip and the fill cover the
  same pixels also at a scale that is not a whole number.

## Steps

1. [x] **The test and the fix.** Done; see [As built](#as-built). The scaled-viewport testset of
   `PartialPaintTest.jl` moves a bar to odd and even pixels, across a viewport
   with a scale of 2 and across a viewport inside it, at supersample 1 and 2, and
   at a density of 1.25. The marker `@test_broken` goes. The fix as in
   [The model](#the-model). Run `test_partial_paint()`, then `test_sdl()` and
   `test_video()` against the baseline of `main` at `636013c86`. Commit.
2. [x] **The guide and the plan.** Done. `sdl.md` says how a clip is set. The plan moves
   to `plan/done/`. Commit.

## As built

- **The clip in device pixels was not enough.** With it, the outer viewport was
  right at odd positions, but text inside the scaled content still differed at a
  clip edge on an odd pixel. The software renderer draws a scaled texture that a
  clip cuts off its grid of pixels with another sampling. Rectangles with alpha
  in the same content were equal. A GPU window clips each pixel and has no such
  fault, but the video backend paints with the software renderer.
- **So a rectangle that cuts a scaled viewport grows to its whole box.**
  `_extend_over_scaled_viewports!` runs at the end of `_compute_dirty_region`,
  after the pad, so `debug_dirty` outlines what is painted. It takes the boxes of
  `res.painted.viewports` whose transform has a scale. The box of a viewport
  inside scaled content is in the units of that content; a rectangle that meets
  it only repaints more. The passes go on until no box grows a rectangle. This
  follows the rule that the walk already had: a change inside a viewport with a
  scale repaints its whole box.
- **The clip in device pixels stays.** It fixes a fault of the full paint too: a
  viewport with a scale of 2 at x = 51, of width 101, drew device columns 52 to
  151 on `main` and lost column 51. It now draws 51 to 151. The test "a viewport
  with a scale clips at the device pixels of its box" checks this at supersample
  1 and 2.
- **Suites.** `test_sdl()`: 989 pass, 2 fail, 1 error, 0 broken. The 2 fail and the
  error are the known `TreeRenderTest.jl:43, 44, 55` of `main`. `test_video()`: 74
  pass, 6 fail, the known failures of `main`.
