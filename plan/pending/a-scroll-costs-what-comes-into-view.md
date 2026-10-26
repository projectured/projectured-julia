# A scroll costs what comes into view

Status: PENDING, 2026-10-26. Not started. The way of the change is my
recommendation, and it is open.

## The ask

On 2026-10-26 the owner read the timing of
[a-scroll-copies-the-pixels-that-stay-in-view.md](../done/a-scroll-copies-the-pixels-that-stay-in-view.md)
and said: "we should investigate further, and we should figure how this change
can actually make things faster and guard that". That plan lets the partial paint
copy the pixels of a viewport whose content only moved. Its timing found no gain.

## What the investigation found

All runs used `main` `eb4d80fb0` in a clean worktree, through `bounded-run`. The
scene is a Julia file of 4999 lines in a focused file tab of the application
window, 1600 × 1000 pixels, density 1, supersample 2. Each notch scrolls 48
pixels.

**1. The gutter makes every frame cost the whole file.** `TextBlockToScrollLayout`
puts the gutter of each line, a small canvas with the line number and the fold
mark, into one canvas with no layout and with overlap, together with a pointer
shape over the whole gutter. A canvas with no layout cannot stop at the edge of
the view. So the walk, the recording, the guards and the paint visit all 4000
gutter rows in every frame. The walk keeps 115,880 records: 695 bounds, 43,501
origins and 33,195 guards. A profile of the walk of a scroll frame: 495 samples
make the guards again at the new place, and 306 record the moved content.

**2. The focus ring stops the copy.** The focused pane has a ring: a
`GraphicsRect` over the whole pane with a transparent fill, a border of 2 pixels
and corners of 3. Rule 3 of the copy takes a graphic outside the moved content
that meets the box as a change of all its record, unless it is a filled rectangle
whose inside covers the box. So the ring gives the whole box, and the paint paints
it.

**3. With both causes patched, the copy saves almost nothing on the graphics
card.** A scratch patch laid the gutter rows out in a vertical canvas, with the
pointer shape beside it, and let rule 3 take from a rectangle only the band of
its border and corners and the edges of a visible fill. The pixels equal a full
paint in 48 of 48 frames of the offscreen renderer. In a real window, with the
moves on and off in turns in one process, at a load of about 5:

| Julia source | Frame | Walk | Paint | Wait for the screen | Boxes copied |
| --- | --- | --- | --- | --- | --- |
| `main`, moves on or off | 299 ms | 238 ms | 60 ms | 0.5 ms | 0 |
| Patched, moves on | 15.8 ms | 5.2 ms | 0.73 ms | 9.2 ms | 90 of 45 frames |
| Patched, moves off | 15.9 ms | 4.8 ms | 0.96 ms | 9.5 ms | 0 |

The gutter fix takes the frame from 299 ms to the refresh of the screen. The copy
saves 0.2 ms of paint and costs 0.4 ms more walk. With the offscreen software
renderer, the copy takes the paint from 5.4 to 3.7 ms and the leaves drawn from
384 to 196.

**4. Why a move costs as much as a repaint.** The walk of a move records each
graphic that the render draws again at its new place, tests it against two sets
of edges, and the guards of the content and of every canvas inside it are made
again at the new place. The repaint of the content as one unit does the same
recording and the same guards. So the copy can only save paint, and on the
graphics card the paint costs about 1 ms.

## The way of the change (my recommendation; open)

A scroll must cost what comes into view, not what the view shows and not what the
file holds. Three changes do that, and a guard holds it:

1. **The gutter rows in a laid-out canvas.** The rows of the gutter go into a
   canvas with a vertical layout and no overlap, and the pointer shape of the
   gutter goes beside that canvas. The walk, the guards and the paint then stop
   at the edges of the view. This helps every frame of a text with a gutter.
2. **A rectangle outside a moved content gives its border, not its box.** Rule
   3 takes from a `GraphicsRect` the bands of its border and corners, at their
   place and where the copy moved them, and, when its fill shows, the edges of the
   fill that the move carries across. Then a focused pane copies.
3. **A move records and guards only what comes into view.** The records and the
   places of the guards of the graphics inside a viewport are kept relative to
   the content of that viewport. A move then changes the origin of the content,
   records the graphics that enter the view, forgets those that leave it, and
   keeps the records and the guards of the graphics that stay. The guard of the
   content itself reads its elements between the new edges, and each kept guard
   inside it answers at once.

The guard of this plan counts work, not time, so it holds on a busy machine:

- A walk counts what it does: the elements that it tests (`res.painted.visits`
  counts this now), the graphics that it records, and the guards that it makes.
  The last two are new counts on the paint state of a window.
- A test drives the application window with a focused Julia file tab, the Files
  pane and a data frame, as the measurement did, and paints each frame by the walk
  of the partial paint into an offscreen renderer. For each notch it asserts:
  - the pixels equal a full paint;
  - each moved viewport is copied;
  - the paint draws less than 60% of the leaves that a paint of the whole
    window draws (see [As built](#as-built));
  - the counts of the walk are the same for a file of 1000 lines and of 4000
    lines, so no part of the view costs the whole file again.
- The same test asserts that no canvas in these scenes holds more than 200
  elements with no layout, so the next gutter is found where it is made.
- The data frame copied nothing while its grid stayed where it is
  (`_make_part_region`). Its assertion of the copy was `@test_broken` until step
  3, which made the thin rules of the grid give only their ends.

## Keep

1. A partial paint gives the same pixels as a full paint, in every frame.
2. A click, a key and the pointer on the gutter work as now.
3. The rules of [a-scroll-copies-the-pixels-that-stay-in-view.md](../done/a-scroll-copies-the-pixels-that-stay-in-view.md)
   hold, except rule 3 for a rectangle.
4. Each new name follows
   [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

A time runs only on the word of the owner, in the lane `taskset -c 28,30,31`,
through `bounded-run`, with the load written beside it. A count needs neither.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [x] **The guard, failing where it must.** Done; see [As built](#as-built). Add the counts of the walk and the
   test of the three scenes. Mark each assertion that `main` fails with
   `@test_broken` and its reason: the counts that grow with the file, the copy of
   the focused pane, the copy of the data frame. Move
   `a-scroll-copies-the-pixels-that-stay-in-view.md` to `plan/done/`, with a line
   that points here. Commit.
2. [x] **The gutter rows in a laid-out canvas.** Done; see [As built](#as-built). The counts no longer grow with
   the file; promote those assertions. Run the tests of the text, the Julia domain
   and the gutter. Commit.
3. [x] **A rectangle gives its border.** Done; see [As built](#as-built). Add pixel tests: a ring over a pane that
   scrolls, and a filled rectangle that covers a part of the box. The focused pane
   copies; promote that assertion. Commit.
4. [ ] **A move records and guards only what comes into view.** The counts of the
   walk of a scroll frame fall to the rows of the strip and the edges; the test
   names the numbers. Run `test_sdl()` and `test_video()` with the offscreen
   driver. Commit.
5. [ ] **The measurement, the guides and the end.** On the word of the owner,
   time the three scenes in real windows, with the moves on and off in turns, as
   in this plan. Describe the relative records in
   [sdl.md](../../documentation/package/backend/sdl/sdl.md). Move this plan to
   `plan/done/`. Commit.

## Not in this plan

- A strip cut to the bounds of what the content draws, which would save paint on
  the software renderer when the lines are short.
- The walk of a data frame does more work at each notch: 1831 records at the first
  notch and 2308 at the sixth.

## As built

### Step 1: the guard, 2026-10-26

`_PaintedGeometry` counts the work of the last walk: `visits` as before, and the
new `recordings`, the records of bounds that the walk wrote, and `new_guards`, the
guards that it made. `_OffscreenPaintState` keeps the boxes that the last frame
copied (`last_copies`) and the leaves that it drew (`last_drawn`). `last_rects`
keeps its meaning, the rects of the last frame that painted, because a video
outlines it on a frame that paints nothing.

`test_scroll_work()` in [ScrollWorkTest.jl](../../test/projectured/editor/ScrollWorkTest.jl)
drives each scene with a `HeadlessBackend` and paints it by the walk into an
offscreen renderer at supersample 1. Six notches, on the code of `main`:

| Scene | Pixels | Copies | Leaves drawn of the whole window | Work: records, new guards |
| --- | --- | --- | --- | --- |
| Julia file of 3999 lines, focused | equal | 0 | 8249 of 8308 | 34,799, 26,544 |
| The same of 999 lines | equal | 0 | — | 8,983, 6,736 |
| Files pane over 500 entries | equal | 1 | 76 to 101 of 261 | 306, 52 |
| Data frame of 1000 rows | equal | 0 | 712 to 723 of 816 to 887 | 1831 at notch 1, 2308 at notch 6 |

The canvases with more than 200 elements and no layout: the gutter column of the
Julia file, 3203 elements. None in the other scenes.

Two decisions from this run:

- The bound of the leaves drawn is half of the leaves of a paint of the whole
  window, not the rows of the strip by their numbers. With the copy, the Files
  pane draws 29% to 39% of its window; a paint of the whole box draws 82% to 99%.
  Rows by their numbers would tie the test to the fonts and the theme.
- Six assertions fail on `main` and are `@test_broken` with their reason: for the
  Julia file, the copy, the leaves drawn, the work that grows with the file and
  the canvas with no layout; for the data frame, the copy and the leaves drawn.

### Step 2: the gutter rows, 2026-10-26

`TextBlockToScrollLayout` puts the rows of the gutter into a canvas of their own
with a vertical layout and no overlap, and the arrow of the pointer over the whole
gutter beside that canvas. A reference into a gutter so has one more step,
`left.elements[0:1]`, before the row; the forward and the backward map follow it,
and `test_text_gutter` asserts the new path. A walk and a paint stop at the edges
of the view now. The work of the walk is the same for a file of 999 lines and of
3999 lines, and no drawn canvas holds more than 200 elements with no layout; both
assertions are promoted. `test_scroll_work`, `test_text_gutter`,
`test_text_folding`, `test_text_line_numbering`, `test_scroll_pane_parts` and
`test_julia_file_view`: 142 pass, 4 broken (the copy and the leaves drawn of the
Julia file and of the data frame).

### Step 3: a rectangle gives its border, 2026-10-26

The rule for a rectangle outside a moved content (`_add_rect_cover_rects!`) took
three tries, and the tests found the fault of each:

- Bands from the record widened by the pad made two bands of full height along
  each of 15 stripes, so a frame passed 32 rectangles, the paint merged them into
  one over the box, and the hidden window copied nothing. A rectangle draws
  nothing outside its box, so the bands come from its record without the pad.
- A side band along the move gave nothing at all, and the pixel tests failed at
  each setting with a move: near its ends the copy brings pixels from outside the
  rectangle. A part with one colour along the move gives its ends, the part minus
  the part moved by the offset and back (`_add_move_ends!`): the fill and, for a
  move up or down, the side bands. The top and the bottom band, which hold the
  corners, give their place and their moved place (`_add_moved_place!`).

With the rule right, the Julia file copied both boxes but still drew 133 to 294
of about 418 leaves. Two facts made it so, and step 3 changes both:

- **A graphic that draws no pixel drew in every rectangle.** It has no record, and
  the paint draws a graphic with no record. A transparent hit target and a
  pointer shape so cost a visit, a count and, for a hit target, a fill with alpha
  0 in each rectangle. A pointer shape is now invisible (`_is_invisible_graphic`),
  and a partial paint skips an invisible graphic.
- **Each token of a row that an edge cuts gave a rectangle,** and the paint drew
  the row once for each rectangle that met it. The rectangles of a copied group
  that cross one edge line, an edge of the box across the move or the same edge
  moved by the offset, merge into one band (`_merge_edge_rects`), when the band
  is at most a quarter of the box thick along the move.

Then the Julia file draws 87 to 101 leaves in a notch, in 7 or 8 rectangles. The
data frame copies too, because the thin rules of its grid give only their ends
now, and its paint draws less than 60% of its window. The bound of the leaves
drawn is 60% of a paint of the whole window: a paint of the boxes draws about
89%. Every assertion that `main` failed in step 1 passes:
`test_scroll_work` and `test_partial_paint`, 87 of 87.

