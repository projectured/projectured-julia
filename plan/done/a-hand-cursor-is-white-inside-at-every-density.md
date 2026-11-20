# A hand cursor is white inside at every density

## Problem

The hand cursor of a tab drag is clear in the middle again, on a display at 100%
(`Xft.dpi: 96`). Step 3 of the plan "the system cursors come from the cursor
theme" made the hands white inside, but it was checked and tested only at a
density of 2. The owner works at two locations, with a display at 100% at one and
at 200% at the other.

Cause, found with `_make_glyph_cursor_image` of main:

| Density | Size | Pixel at the hot spot |
| --- | --- | --- |
| 1.0 | 22×21 | `93919191`, partly clear |
| 1.5 | 32×32 | `ffffffff`, white |
| 2.0 | 42×42 | `ffffffff`, white |

- `_fill_enclosed_pixels!` counts a pixel as a wall only when its alpha is `0xff`.
- At a density of 1, the glyph is 19 pixels, and its smoothed lines are about 1.6
  pixels wide. Almost no pixel of a line is fully opaque.
- The white outline is the white glyph blended 8 times around the black one. A blend
  of partly opaque pixels stays below 255, and stores a color that the alpha
  darkens.
- So the wall has gaps, the flood from the edge goes into the palm, and nothing
  becomes white. The lines also show the background through them.

The video backend draws the open, the closed and the pointing hand as Lucide glyphs
with a white outline of graphics texts, and has no fill at all. So a video shows
the three hands clear in the middle at every density.

## Design

Decisions (mine, the owner asked for the fix in both backends):

1. The image of a glyph cursor comes from the coverage of the glyph, not from blends
   of surfaces. The glyph renders once, in black, and its alpha is the ink coverage.
   - The outline coverage of a pixel is the largest ink coverage in the square of
     `outline` pixels around it.
   - A pixel has the alpha of its outline coverage and the gray `255 - ink`, so the
     line is black over a white outline, with a straight alpha.
2. A wall is each pixel that is at least half opaque. Each wall pixel becomes fully
   opaque, and each pixel that the walls close in becomes opaque white. The flood
   still moves in four directions only.
3. `ProjecturedSDL` exports `make_glyph_cursor_pixels(glyph, size, ratio)`. It gives
   the pixels as the data of a `GraphicsImage`, `(bytes, width, height)`, in the
   order red, green, blue, alpha. The SDL cursor makes its surface from these bytes,
   and SDL converts it to ARGB8888 for the cursor.
4. The video backend draws each of its three hands as a `GraphicsImage` of
   `make_glyph_cursor_pixels`, at the density of the take, at its own size of 22
   logical pixels, at the place where the text of the glyph was. The hot spots stay
   as they are.
5. The tests check the hot spot of each SDL hand at the densities 1, 1.5 and 2, and
   the middle of each video hand at the densities 1 and 2.

## Steps

1. [x] The SDL hand image from the coverage of the glyph, with walls at half
   opacity; `make_glyph_cursor_pixels` exported; `test_sdl_pointer_shape` with the
   three densities. Done:
   - `make_glyph_cursor_pixels` starts SDL_ttf when nothing started it yet
     (`TTF_WasInit`). A probe with no backend failed with "Font load failed"
     without it.
   - `_read_surface_alpha` converts the glyph surface to ARGB8888 before it reads
     the alpha, and `_make_cursor_pixels` makes the ARGB matrix from the ink.
   - At a density of 1 the palm and the fingers of both hands are white now. The
     hot spot of one hand at one density is `fbfbfbff`: a line near it gives it a
     little ink, so it is a wall with the gray `0xff - 4`. The test asks for an
     opaque hot spot whose colors are each at least `0xf0`.
   - `test_sdl_pointer_shape` passes 48 of 48 in the worktree, with the offscreen
     driver: the hot spot of each hand at 1, 1.5 and 2, a ring of half opaque
     pixels, and a ring of ink with a gap of one pixel, which the outline closes,
     and a gap of three pixels, which stays open. The naming guard and
     `test_sdl_layering` pass.
2. [x] The video hands as an image of `make_glyph_cursor_pixels` at the density of
   the take; `test_video_pointer_shape` checks that each hand is white inside. Done:
   - `_make_pointer_shape_graphics` takes `density`, and `_make_pointer_graphics`
     gives it the density of the take. The overlay draws at the density of the
     frame, and the renderer scales it by the supersample, as it did the text.
   - A probe drew each hand in the old and the new form at the densities 1 and 2.
     The box of the drawn pixels is the same for each pair, so each hot spot stays
     at its place. At the point inside, the old hand shows the gray background and
     the new hand is white, at both densities.
   - The point inside the pointing hand is (6, 14) logical pixels from its hot
     spot, in the palm below the finger.
   - `test_video_pointer_shape` passes 41 of 41, and `test_video_layering` passes.
     `test_application_video` records a pointer over a part that is not a hand, so
     it does not reach the image, and I did not run it.
3. [x] Look at the images of both backends at the densities 1 and 2. Done:
   - The SDL hands at 1, 1.5 and 2, enlarged on a light and a dark background:
     each one is white inside, with black lines and a white outline that shows on
     the dark background.
   - The video hands, old and new, at 1 and 2 on gray: the old ones are gray inside,
     the new ones white, at the same places.
   - A script on the real display (`DISPLAY=:0`, the x11 driver, no window) made a
     color cursor from the pixels of each hand at 1 and 2. SDL takes the surface
     in the byte order red, green, blue, alpha. The offscreen driver of the tests
     makes no cursor, so only this script checks that call.
