# A scroll copies the pixels that stay in view

Status: DONE, 2026-10-26. Steps 1 to 5 landed on `main`; the timing of step 5
found no gain. The work goes on in
[a-scroll-costs-what-comes-into-view.md](../pending/a-scroll-costs-what-comes-into-view.md).

## The ask

On 2026-10-21 the owner asked whether the partial paint of the SDL backend can
handle a scroll at a low cost. When a scroll pane scrolls, the paint can copy the
old picture of the pane by the offset and paint only what came into view. The
walk must read the old place and size without a computation in the graphics
document. It must also make sure that nothing on the screen changed, and that the
content only moved. Claude answered that this is possible. The owner asked for
this plan, with a measurement in a real window as its first step.

The line numbers are from commit `bc22297b4`. Find each function by its name
first, and use the line number only as a hint.

## The problem

A scroll pane draws its content in a `GraphicsViewport`. The content is a
`GraphicsCanvas` whose origin is the negative scroll offset
(`_push_pane_part_viewports!`, line 5571 of
[WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl)). A wheel
notch writes the scroll, and the `y` cell of the content canvas changes, for
example from 0 to −69.

The walk of the next frame, in
[SdlBackend.jl](../../source/backend/sdl/SdlBackend.jl):

1. `_collect_viewport_dirty!` (line 2840) finds that the box, the content and the
   transform of the viewport did not change. It walks the content at its new
   origin.
2. `_collect_canvas_dirty!` (line 2608) finds that the content moved. It makes the
   content one unit (`_union_unit!`, line 2558). The unit records everything that
   the render reaches again (`_record_painted_canvas!`, line 2416) and adds its old
   and new bounds to the region. A list of nodes that moved reflows down to the
   edge (`_collect_listnode_dirty!`, line 2934).
3. The clip of the viewport cuts those bounds to its box. The paint draws every
   row that the pane shows.

A first look, 2026-10-21. These numbers come from a scratch process with the
offscreen software renderer. The run was not in the measurement lane and had no
word of the owner, so the numbers only show the size of the problem. The pane has
a box of 780 × 580 pixels and 2000 rows of 23 pixels. Each frame scrolls by 69
pixels.

| Supersample | Walk and record | Paint of all rows | Paint of the 69-pixel strip |
| --- | --- | --- | --- |
| 1 | 0.57 ms | 0.65 ms | 0.19 ms |
| 2 (default) | 0.57 ms | 3.09 ms | 0.80 ms |

## The facts that the change uses

- **The guard of the content.** Each painted canvas has a guard cell
  (`res.painted.guards`) for one place (`res.painted.guard_places`: the content
  origin and the clip edges). The guard of the content of a viewport reads the
  elements, their cells and the places of the canvases inside. It does not read
  the origin of the content. The guard of the canvas that holds the viewport reads
  that origin (`_read_guarded_element`, line 3098). So a scroll makes the guard
  around the pane not valid. The guard of the content stays valid while nothing
  inside the content changes.
- **The old guard is there during the walk.** The walk tests the guards before it
  reads anything (`_is_guard_valid`, line 3048). The guards are made again only at
  the end of the walk (`_read_guard!` on the root in `_compute_dirty_region`,
  line 3123). A guard is valid only for the elements between its edges, and those
  are the elements that the last paint drew.
- **The records.** `res.dirty_bounds`, `res.painted.origins`,
  `res.painted.members` and `res.painted.viewports` are in window coordinates and
  are keyed by placement. In the first phase of the walk they hold what the last
  paint drew. The recordings run after that phase.
- **The edges.** The edges of the content of a viewport are its box
  (`_compute_viewport_content_place`, line 1306). An outer viewport does not cut
  them. SDL cuts the pixels at the clip in force.
- **The kept target.** A window paints into `res.target`, a texture of `ss` times
  the device size (`_ensure_ss_target!`, line 2121). It copies the damaged
  rectangles to the window (`damage_history` and the buffer age, in
  `_render_window!`, line 3366). The offscreen renderer paints into a surface with
  the software renderer of SDL (`open_offscreen_renderer`, line 3536). SDL cannot
  copy a texture into itself.
- **Device pixels.** A logical pixel is `ratio × ss` pixels of the target. A shift
  by `d` logical pixels gives the same pixels as a new paint only when `d × ratio
  × ss` is a whole number. At a density of 1.25 with supersample 2, a scroll by an
  odd count of pixels is 2.5 target pixels for each pixel.
- **The scroll bar.** The bar of a pane lies over the content that it scrolls. Its
  thumb shows for `show_duration` seconds after a scroll (line 893 of
  WidgetToGraphics.jl). So in most scroll frames a graphic from outside the
  content covers a part of the box.
- **The skip.** The partial paint skips a graphic whose record does not meet the
  rectangle (`_paint_dirty_rects!`, line 3256). So a narrow rectangle costs the
  graphics that it meets.

## The way of the change (my recommendation; open)

**The walk proves a move, and the paint copies the box before it paints the
rectangles.** A move is a viewport whose content only moved by an offset `d`. The
paint copies the pixels of its box by `d` in the kept target. Then it paints the
rectangles of the frame, which hold only what the copy cannot give.

### The conditions of a move

The walk takes a move for a viewport only when all of these are true:

1. The box, the content and the transform are as the last paint recorded them,
   and the transform is plain.
2. The origin of the content differs from its recorded origin by `d`.
3. The old guard of the content is valid, and its place is the recorded origin
   with the same edges.
4. `|dx|` is less than the width of the box, and `|dy|` is less than its height.
   No outer viewport and no edge of the window cuts the box, because the
   recording tests the edges of the box itself (rule 2 of the rectangles).
5. The device pixel ratio is a whole number. Then `d` and each edge of the box
   are whole device pixels too. A text rasterizes at the ratio and is scaled by
   the supersample. At another ratio, the edge of a rectangle can cut a text off
   the grid of its texels, and the software renderer of SDL then samples it on
   another grid (see [As built](#as-built)).
6. No outer viewport has a scale.
7. The box does not overlap the box of another move of the frame, except when
   one box holds the other and the two moves have the same `d`. The table of a
   data frame has two such viewports in each column (see
   [As built](#as-built)).
8. After the recordings, the old guard is still valid. A read of a new row must
   not have changed a row that stays in view.

When a condition is false, the move paints its box. That box is a change like
any other, so it joins the region before a copied move takes the rectangles from
outside the contents (rule 3 below). A copy that carries the old pixels of such a
box then repaints them.

### The rectangles of a move

1. **The strip.** The part of the box that the copy has no pixels for: the box
   minus the box moved by `d`. This is one rectangle, or two for a move on both
   axes.
2. **Rows that enter or leave the view.** The content did not change, so the last
   frame is the new frame moved by `d`. The last paint drew the elements between
   the old edges, which are the edges moved by `d` in the new frame. The walk of
   the move takes each element between the union of the two edges:
   - An element between both edges is recorded at its new place, and gives no
     rectangle.
   - An element between the new edges only gives its new bounds, cut to the box.
   - An element between the old edges only gives its record moved by `d`, cut
     to the box, because its old pixels lie there after the copy. Its records,
     and the records of all that it draws, are cleared.

   This rule finds ink that reaches past the box of a row. The strip alone does
   not find it. Two more cases give rectangles:
   - An element between both edges that is not a canvas gives its bounds when
     they cross an edge of the box at its new place or at its old place. The
     edge cuts it by another amount in each frame, and the software renderer of
     SDL samples a scaled texture that a clip cuts on another grid.
   - A viewport inside the content gives its box when it has a scale, because
     its content lies on the grid of its own units, and when the edge of the box
     cuts it. Any other viewport inside the content is recorded as moved content,
     between its own box in both frames.
3. **Graphics from outside the content.** The copy moves the pixels of a graphic
   that is not in the content but meets the box: the thumb of the scroll bar, a
   drag badge, or a background with a border. After the recordings, the walk goes
   from the window down to the viewport by the records, as the paint does. For
   each graphic whose record, widened by the pad, meets the box, it adds that
   record cut to the box and the same rectangle moved by `d`. The walk skips a filled rectangle when the area
   inside its border and its corners covers the box, because that area has the
   same color at each pixel. The old place of a graphic that changed in the frame
   is a rectangle of the region. So each rectangle of the region from outside the
   content that meets the box is also added, cut to the box and moved by `d`.
4. **A move inside the box of a move.** A viewport from outside the content
   that is itself a move by the same `d` is not a graphic of rule 3. Its pixels
   inside its own box are right after the copy. It gives its own strip, and the
   band that its box covers after the copy but did not cover before: its box
   moved by `d`, minus its box, cut to the outer box. The paint copies only the
   outer box.
5. **A box with a scale that a rectangle cuts.** The paint draws it after all
   the rectangles, whole, the smaller boxes first. The software renderer of SDL
   samples the scaled content that a clip cuts on another grid, so the cut part
   of a rectangle must be drawn over. Before this change,
   `_extend_over_scaled_viewports!` added such a box only when no rectangle
   covered it, and a rectangle painted after the one that covered it could
   still cut it. That fault was older than
   this plan, but a scroll over a chart meets it often.

### The records

The walk of the move records each element that the render draws again, at its new
place, as the unit does now. The records stay in window coordinates. The walk
reads only cells that are valid, except the cells of the rows that come into
view, which the paint must compute anyway.

### The copy

- **Window.** A scratch texture on the resources of the window, with the size of
  the largest box that a move copied. The target makes it again when the target
  is made again, and the window frees it. The copy goes from the box to the
  scratch texture, and from there to the box moved by `d`. It runs in target
  pixels, at scale 1, with no clip, and with the blend mode none. The box of a
  move joins the damage of the frame and `damage_history`.
- **Offscreen.** `SDL_RenderFlush`, then a move of the rows of the surface in
  place, in the order that the sign of `dy` gives.
- **A move with no copy.** The paint drops a move when a rectangle of the frame
  covers its box, for example after `_limit_dirty_rects` (line 3239) or
  `_extend_over_scaled_viewports!` (line 2231).

`_compute_dirty_region` keeps its answer, the rectangles, for the tests that use
it. A new function answers the rectangles and the moves, and
`_compute_dirty_region` takes the rectangles from it. `_render_window!` and
`render_offscreen_changes!` (line 3900) call the new function.

### Other ways, and why this plan does not take them

- **Compare the pixels.** A read of a texture back to the processor stalls the
  graphics card. The guard proves the move with no pixel.
- **Copy the target into itself.** SDL does not allow a texture as the source and
  the target of one copy.
- **A second target of full size.** A window of 2560 × 1440 logical pixels at
  density 2 and supersample 2 has a target of 10240 × 5760 pixels, which is
  236 MB. A scratch texture of the size of a box is much smaller.

## Keep

1. A partial paint gives the same pixels as a full paint of the same frame, also
   in a frame with a move.
2. The first paint, a paint with `partial_render = false`, `write_image` and
   `write_offscreen_frames!` copy nothing.
3. A frame with no move gives the same rectangles as now.
4. The state stays on the resources of the window (`PAR-PER-EDITOR-STATE`). Add
   no process-global value.
5. `debug_dirty` outlines the rectangles that the paint draws. So in a scroll it
   outlines the strip and the rows at the edges, not the box.
6. Each new name follows
   [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

A time runs only after the owner gives the word for that run. Take each time in
the measurement lane, `taskset -c 28,30,31`. Interleave `main` and the branch as
A/B/A, and write the load of the machine beside the number. A count needs no idle
machine and no word.

## Steps

Do the work in the worktree `projectured-julia-scroll-copy`, on the branch
`scroll-copy`. Commit each step. Do not land on `main` before the owner approves.

1. [x] **Count the moves of a scroll now.** Done; see [As built](#as-built). On 2026-10-21 the owner said that
   the machine is not idle for a while, and asked to continue. So this step takes
   counts only, which need no idle machine. The times of `main` and the branch
   come in step 5.
   - In a scratch process, build the application as `record_application_video`
     builds it, with a `HeadlessBackend`. After each frame, paint the canvas of
     the window with `render_offscreen_changes!`, so the walk of the partial
     paint runs. Use three panes: a Julia source of more than 3000 lines, the
     Files tree over a folder of 500 entries, and a data frame of 1000 rows.
   - Push 30 wheel notches at each pane, with the pointer on the pane.
   - Count, for each pane, the frames in which conditions 1 to 5 are true, and
     write which condition is false in the other frames. Also count the area
     that the paint draws, and the leaves that it draws. A content that builds
     its rows again from the scroll has a guard that is not valid, and the copy
     gives it nothing.
   - Write the counts in [As built](#as-built). If no pane takes a move, stop and
     report to the owner. If a pane takes moves, go on to step 2.
2. [x] **The pixel tests of a scroll.** Done: five testsets, each at the four
   settings, 34 of 34 pass in `test_partial_paint()`. In
   [PartialPaintTest.jl](../../test/backend/sdl/backend/PartialPaintTest.jl),
   add the testset "a scroll", which compares a partial paint with a full paint
   by `find_differing_frames`. The frames include:
   - a scroll by 16, 69 and −23 pixels, and a scroll by more than the box;
   - a scroll on both axes in one frame;
   - a glyph that rises above the ascent of its font, and a negative left
     bearing, at the edges of the box;
   - a list of nodes that scrolls;
   - a viewport inside the content, and a scrolled viewport that the box of an
     outer viewport cuts;
   - a translucent dot over the pane that stays, and one that moves in the same
     frame;
   - a rectangle with a border under the box, and stripes under the box;
   - a scroll and a change of a row in the same frame;
   - two panes that scroll in the same frame;
   - a viewport with a scale around the pane, and one inside the content;
   - supersample 2 at the densities 1, 2 and 1.25.

   The tests pass now, because the paint draws the whole box. Commit.
3. [x] **The copy of a box.** Done. `SdlWindowResources` has the field `scratch`
   at its end, so each of its six callers passes `C_NULL` for it.
   `_copy_target_box!` copies through the scratch texture, which
   `_ensure_scratch_texture!` makes or grows. `_copy_surface_box!` moves the rows
   of the surface with `unsafe_copyto!`, after `SDL_RenderFlush`. Each one answers
   false when it cannot copy, so the caller can paint the box instead. The test "a
   copy of a box moves the pixels that stay in it" passes at the four settings and
   in a hidden window, with the X11 driver and with the offscreen driver; both
   gave the accelerated `opengl` renderer. Add the copy for a window target and for an
   offscreen surface, and the scratch texture on the resources of the window. The
   walk does not use it yet. Add a test: paint a scene, copy a box by an offset,
   and compare with the same pixels moved in Julia. Do the test in an offscreen
   renderer, and in a hidden window for the texture path. Commit.
4. [x] **The walk finds a move, and the paint copies first.** Done; see
   [As built](#as-built). Add the conditions,
   the three kinds of rectangle, the records, the cut by the outer viewports, the
   rule that drops a move, and the damage of the box. Then:
   - The tests of step 2 pass.
   - Add a count: a scroll by 69 pixels of 2000 rows of 23 pixels in a box of 580
     pixels draws exactly the rows that meet the strip widened by the pad. The
     test names the rows by their numbers.
   - Add a test in a hidden window: `_render_window!` paints the scrolls of step
     2 with `partial_render = true` and with `partial_render = false`, and the
     pixels of the two targets are the same.
   - Run `test_sdl()` in `ProjecturedSDLTest`,
     `test/backend/video/editor/VideoTest.jl` and
     `test/backend/video/editor/ApplicationVideoTest.jl`. Each must give zero
     `Fail`, zero `Error`, and the same count of `Broken`.

   Commit.
5. [ ] **The measurement, the guides, and the end.**
   - When the owner says that the machine is idle, measure a scroll on `main`
     and on the branch, in a real window with `partial_render = true` and the
     panes of step 1. For each scroll frame, take the time of the frame, the walk
     (`_walk_window_change!`), the paint (`_paint_dirty_rects!`), the copy to the
     window, and the present. Write the numbers in [As built](#as-built).
   - [x] In a real window, read the target after each scroll frame, and compare
     it with a full paint of the same frame. Done; see [As built](#as-built).
   - [x] In [sdl.md](../../documentation/package/backend/sdl/sdl.md), describe the
     move in the paragraph of the partial paint, in the present tense. Add a
     design decision that says why the walk proves a move by the guard and not by
     the pixels. Done. The design decision links this plan in `plan/pending/`,
     because the check of the documentation refuses a link to a file that is not
     there; the move of the plan changes the link.
   - Move this plan to `plan/done/`, and change the link in `sdl.md` with it.
     Commit.

## Not in this plan

- Records relative to the content of a viewport, so that a scroll changes one
  record and not one record for each visible graphic.
- A pane whose content builds its rows again from the scroll offset.
- The pan of a `WidgetTransformPane`, and a viewport with a scale.
- A scroll by a part of a device pixel, at a density such as 1.25.
- An outline of the copied box under `debug_dirty`.
- The canvas of 4003 elements with no layout in the view of a Julia source,
  which each rectangle visits whole.
- The grid of the table of a data frame, which stays where it is while the
  cells scroll, so a scroll of a table paints the whole table (see
  [As built](#as-built)).
- Three scenes of the random test of the review, seeds 38, 292 and 416, whose
  partial paint differs from a full paint on `main` too, with no move.
- A list of nodes in a pane that scrolls by pixels: the render draws it from its
  head, so the walk records each node above the view again in each frame.

## As built

### Step 1: the moves of a scroll, 2026-10-21

A scratch probe on `main` at `bc22297b4`, in the test lane `taskset -c 24-27`,
with no time taken. Each editor has a `HeadlessBackend` and a window of
1600 × 1000 pixels. After each frame, the probe paints the canvas of the window
by the walk of the partial paint, into an offscreen renderer with supersample 2 at
density 1. A copy of `_collect_viewport_dirty!` tests conditions 1 to 5 for each
viewport whose box is as painted and whose content moved. Each notch is
`MouseScroll(0, -1)` at a point on the pane, 0.5 s after the notch before it, and
each notch scrolls 48 pixels.

| Pane | Notches with a move | Viewports that move in one notch | Leaves that the paint draws in one notch now |
| --- | --- | --- | --- |
| A Julia source of 4999 lines in a file tab of the application window | 30 of 30 | 2: the gutter and the text | about 10,200 |
| The Files pane in a tab, over a folder of 50 folders and 450 files | 29 of 30 | 1 | about 270 |
| A data frame of 1000 rows in a tab | 30 of 30 | 4: two in each column | about 1,400 |

Each move in the table met conditions 1 to 5. The facts that the steps after
this one use:

- **Two moves, one inside the other.** In the data frame, the viewport
  `(8, 119, 131, 992)` holds the box of the viewport `(19, 125, 121, 986)`, and
  `(131, 119, 1592, 992)` holds `(142, 125, 1581, 986)`. Each moves by
  `(0, -48)` in each notch. The inner viewport is not in the content of the outer
  one, because the walk reached it, and a walk does not enter a content that
  moved. So condition 7 lets two moves overlap when one box holds the other and
  the offsets are the same, and rule 4 of the rectangles says what the inner
  move gives.
- **The records grow during a scroll.** In notch 20 of the Files pane the
  backend forgot its records and painted the whole window, because the records
  passed twice the count of the last full paint plus 10,000. A moved content is
  recorded again as a unit, and the records of the rows that left the view stay.
  The walk of a move clears them (rule 2 of the rectangles).
- **The Julia source paints thousands of elements that it does not show.** Its
  box shows 36 texts, but a canvas of 4003 elements with no layout lies inside
  it, and the walk keeps only 1667 records for the whole window. The paint cannot
  stop early in a canvas with no layout, and it draws a graphic that has no
  record. So each
  rectangle of a scroll frame visits that canvas whole. The copy makes the
  rectangles smaller, but it does not change this.

### Step 4: the move in the walk, 2026-10-21

The pixel tests of step 2 found three faults of the first version, and a review
of the diff by the `code-reviewer` agent found two more. Each one changed a rule
above:

| Fault | Found by | What changed |
| --- | --- | --- |
| Two full paints of the software renderer at supersample 2 differ after a scroll by 15 or 16 pixels, for a text "Ṏ row 1" that the top edge of the box cuts | pixel test | rule 2: an element that crosses an edge gives its bounds |
| A viewport with a scale of 2 in the content: its content origin is rounded to its own units, so a move by 17 moves its content by 18 | pixel test | rule 2: such a viewport gives its box |
| At the density 1.25, a rectangle that cuts a text draws other pixels than a full paint. This holds for a partial paint with no move too | pixel test | condition 5: the ratio is a whole number |
| A move that is not copied, in the box of a move that is copied: the copy carried its old pixels, and no rectangle repainted them | review | a box that is painted joins the region before the rectangles from outside |
| A box with a scale that one rectangle covers and a later one cuts: the later one draws its cut part. The fault is older than this plan | review | rule 5 |

The review also found that a row that left the view kept the records of all that
it holds. The walk now forgets them. In 200 notches of 48 pixels, rows that are
canvases keep 205 records, and text rows keep 72. Without the move they grow to
6205 and 1872. A list of nodes grows to 3109 records with the move and without
it, because the render draws a list from its head.

The results, in the test lane, with no time taken:

- `test_partial_paint()`: 66 of 66 pass, with the X11 driver and with the
  offscreen driver. A scroll by 69 pixels of 2000 rows of 23 pixels in a box of
  290 pixels gives one move by `(0, -69)`. Its rectangles meet rows 13 to 16; a
  paint of the box draws 13 rows. In a hidden window at the density 1 the
  accelerated `opengl` renderer copied a box, and its target equals a full paint.
- The random scenes of the review: 300 of 300 pass in the first test. In the
  second test, 1494 of 1500 pass. The 6 that fail are seeds 38, 292 and 416, and
  each one fails in the same frame and the same pixels with no move. Seed 38 also
  fails so on `main`.
- `test_sdl()` with the offscreen driver: 1053 pass, and the test of the tree
  render fails 2 and errors 1, as on `main`. `test_video()`: 74 pass. It fails
  `json_build_live` 2, the pointer test 2 and the zoom test 1, as on `main`, and
  the take whose window cannot paint 1. That take also failed on `main` at
  `f593feb4a` at the same time, and passed there an hour before.

### Step 5: the live check, 2026-10-21

The owner let three real SDL windows of 1600 × 1000 pixels open on the screen,
with `partial_render` on, at the density 1 and the supersample 2. Each window
took 30 wheel notches, pushed into the pending inputs of the backend. After each
frame, a script read the kept target, painted the same frame in full, and read
the target again.

| Window | Frames compared | Frames that differ | Boxes copied |
| --- | --- | --- | --- |
| A Julia source in a file tab of the application window | 60 | 0 | 56 |
| The Files pane over a folder of 500 entries | 60 | 0 | 30 |
| A data frame of 1000 rows | 60 | 0 | 0 |

The data frame copied no box, although its four viewports move in each notch.
`_make_part_region` puts the grid of the cells, a rule of 1 pixel at each row
and at each column, in a viewport with the same box as the pane of the cells.
That viewport keeps its origin while the cells move by 48 pixels. So each rule
is a graphic from outside the moved content (rule 3), and gives two rectangles,
at its place and at the place where the copy moves it: about 150 in a notch. Above
32 rectangles the paint merges them into one, which covers the boxes, so it
copies nothing and paints the whole table. The pixels are right. A merge of the
rectangles at each edge into one band did not lower the count, and the change
does not keep it.

### Step 5: the timing, 2026-10-26

On the word of the owner, in a clean worktree at `main` `31b19cda3`, in the lane
`taskset -c 28,30,31`, at a load of about 1.6 that rose to 2.3 during the
compile and fell again. Real SDL windows of 1600 × 1000 pixels, the density 1, the
supersample 2, the accelerated `opengl` renderer. In each window the moves
switched on and off in six blocks of 15 notches (on, off, on, off, on, off) in one
process, after a warm-up of 24 notches. A frame is the first `run_frame!` after a
notch. The medians, in milliseconds:

| Pane | Moves | Frame | Walk | Copy | Paint | Rest of the paint of the window | Boxes copied |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Julia source | on | 299.2 | 238.0 | 0.0 | 60.0 | 0.5 | 0 |
| Julia source | off | 298.7 | 235.8 | 0.0 | 59.7 | 0.5 | 0 |
| Files pane | on | 16.5 | 1.7 | 0.01 | 0.45 | 13.7 | 45 |
| Files pane | off | 16.5 | 1.6 | 0.0 | 0.39 | 14.0 | 0 |
| Data frame | on | 75.5 | 69.4 | 0.0 | 4.2 | 0.5 | 0 |
| Data frame | off | 86.6 | 78.2 | 0.0 | 4.9 | 0.5 | 0 |

What the numbers show:

- **The Files pane copies, and the copy saves no time that the processor
  measures.** Its paint costs about 0.4 ms in both modes. The rest of the frame
  is the copy to the window and the present, which waits for the refresh of the
  screen, about 14 ms.
- **The Julia source copies nothing.** Its walk finds both moves, and the
  rectangles cover both boxes. Rule 3 meets the focus ring of the pane, a
  `GraphicsRect` at `(8, 90)` of 1584 × 879 with a transparent fill, a border of
  2 pixels and corners of 3 pixels. Rule 3 skips only a filled rectangle whose
  inside covers the whole box, so it adds the whole ring, and the paint paints
  both boxes. The ring draws only its border, so the rule can give the band of
  the border and the edges of a visible fill instead. The live check of
  2026-10-21 copied 56 boxes in the same scene; this ring was not there then.
- **The walk of the Julia source costs 238 ms.** The walk keeps about 116,000
  records for its window now, against 1667 on 2026-10-21. A change on `main`
  after 2026-10-21 makes this view draw far more graphics. It is not a cost of
  the copy, and it is the largest cost of the frame.
- **The data frame copies nothing**, as the live check found, and its walk takes
  about 9 ms less with the moves on. The walk of a move records the content
  instead of the unit of the content.

