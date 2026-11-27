# A text and a shape rasterize at the scale they show

The owner, 2026-11-27, after the fix of the soft text (commit 8299d6558): "the proper
text rasterization for actual zoom level. can even be considered for shapes in
general". Not now: the owner left it for later.

## What is there now

The SDL backend rasterizes a text once, at the device pixel ratio, and scales the
texture to where it lands ([sdl.md](../../documentation/package/backend/sdl/sdl.md),
"The texture is rasterized at the device pixel ratio"). A window paints into a target
`supersample` times its size, 2 by default, and the copy to the window scales it down.

- A text on whole texels, which is every text outside a scaled viewport, samples
  nearest. The copy of the target gives back each texel, so the window shows the
  glyphs as the hinting fitted them. This is the fix of 8299d6558.
- A text at a scale that is not whole texels, inside a viewport with a scale, is a
  1× texture magnified or shrunk by a filter: linear on a renderer with a graphics
  card, nearest on the software renderer (`_render_element!` of a `GraphicsText` in
  [SdlBackend.jl](../../source/backend/sdl/SdlBackend.jl)). So a zoomed text is soft
  or uneven, and the two renderers draw other pixels for it.
- A shape gets its smooth edges only from the supersample and the copy down: its
  edges are rasterized at the device resolution of the target, and the average of
  each block smooths them.

## The idea

1. A text rasterizes at the size it shows: the device pixel ratio times the scale in
   force, with the hinting at that size. Its texture then lands on whole pixels at
   any zoom and needs no filter, and both renderers draw the same pixels. The cache of
   text textures keys on that size, so a zoom makes new entries; a zoom animation
   needs a bound on them, or a step of the size.
2. A shape computes the coverage of each pixel by its own edges (analytic
   anti-aliasing), so it needs no supersample. With texts as in 1, the window could
   paint at its own size, with no target twice as large and no copy down: a quarter
   of the pixels, and text with no step between rasterizing and the screen, which
   LCD subpixel text (`TTF_RenderUTF8_LCD`) needs.

## Questions before it is a plan

- How many painters 2 touches: each painter of a curve, a ring and a filled quad
  counts on the copy down to smooth its edges today.
- Whether a partial paint stays the same as a full paint under each clip, which the
  current nearest sample guarantees for a text on whole texels.
