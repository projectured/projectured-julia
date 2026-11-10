# A saved position is relative to its canvas

Status: PENDING, 2026-11-10. Not started. The owner asked for this plan after
the example below ("Probably yes, but give me an example first", then "Yes").
The way of the change and the decisions in it are my proposal.

## The ask

[a-scroll-costs-what-comes-into-view.md](../done/a-scroll-costs-what-comes-into-view.md)
made a scroll copy the pixels that stay in view and record only what comes into
view. On 2026-11-09 the owner asked to profile the walk of a scroll of a data
frame, the one scene whose frame was still over the refresh of the screen. The
profile found that the largest part of the walk updates the saved position of
each graphic that stays in view. After the example below, the owner asked for
this plan.

## What the profile found

`main` `2d8d7e117`, the main checkout (Julia 1.13.0-rc4 of the merged fork), a
real SDL window of 1600 × 1000 pixels, a data frame of 1000 rows, notches of 48
pixels, the lane `taskset -c 28,30,31` at a load of about 4. Medians of 45
notches:

- A frame takes 16.4 ms, and its walk 11.1 ms. The screen refreshes every
  16.7 ms.
- In each notch the walk moves the saved positions of about 3580 graphics,
  records 202 new graphics, makes 134 guards and runs about 717 cell
  computations.

The shares of the samples of the walk of a notch:

| Part of the walk | Share |
| --- | --- |
| Move the saved positions of the graphics that stay in view (`_record_moved_canvas!`, `_record_moved_viewport!`, `_move_records!`) | 34% |
| Compute and record the 2 or 3 rows that come into view | 26% |
| Make the guards of those rows (`_read_guard!`) | 13% |
| Find what changed (`_collect_canvas_dirty!`) | 7% |
| Other small parts | about 20% |

The garbage collector takes about 23% of all the samples of the walk, inside the
parts above. About half of its samples come from collections that the
allocation of a `WeakRef` in `_register_dependent!` starts. A call on an element whose type the compiler does not
know takes about 8%, and `objectid` in `_make_placement_key` about 4%.

## The cause

Each record is in window coordinates: the bounds in `res.dirty_bounds`, the
origin in `res.painted.origins`, the box of a viewport in `res.painted.viewports`
and the place of a guard in `res.painted.guard_places`. A scroll moves every
graphic of the content on the screen, so a move must write every record of the
content again, even when nothing in it changed.

An example. A pane is at window position (100, 50), and its rows are 20 pixels
high. A scroll moves its content up by 20 pixels: row 1 leaves the view, row 4
comes into it.

| Saved now | Before | After |
| --- | --- | --- |
| Row 1 text | (104, 50) | removed |
| Row 2 text | (104, 70) | (104, 50) |
| Row 3 text | (104, 90) | (104, 70) |
| Row 4 text | none | (104, 90) |

| Saved relative to the canvas | Before | After |
| --- | --- | --- |
| Origin of the pane content | (100, 50) | (100, 30) |
| Row 1 text | (4, 0) | removed |
| Row 2 text | (4, 20) | no change |
| Row 3 text | (4, 40) | no change |
| Row 4 text | none | (4, 60) |

The walk and the paint go down the tree from the window, and they know the
origin of each canvas on the way, so a window position is the origin plus the
saved position: row 3 is at (100, 30) + (4, 40) = (104, 70).

## The way of the change (my proposal)

1. **Each record is relative to the canvas that holds its graphic.** The bounds
   of a graphic (`res.dirty_bounds`) and the box of a viewport
   (`res.painted.viewports`) are saved relative to the content origin of the
   canvas that holds the graphic. For the content of a viewport, that origin is
   the corner of the box, in the units of the content. A canvas saves its offset
   in that origin (`res.painted.origins`), which is its scroll for the content
   of a viewport; any other graphic keeps only the mark that it was painted. The
   edges that the content of a viewport was recorded between are saved relative
   to the content origin. A recording still answers window bounds, so the union
   of a canvas, the rectangles of a move and the dirty region do not change. Each
   reader of a saved bound adds the origin that its walk carries: the dirty walk,
   the paint of the rectangles (`_is_outside_partial_paint` takes the origin),
   the rule for the graphics outside a moved content (`_collect_cover_rects!`),
   the forget of the records and the moves. The place of a guard stays in window
   coordinates: a move enters every canvas whose guard has such a place.
2. **A canvas moved when its own offset changed.** The walk compares the offset
   of a canvas in its container, not its window origin. The old bounds of a unit
   are its saved bounds plus the origin of its container, which did not move:
   when the container moved, the container is the unit. A content whose scroll
   changed is a unit or a move, as now. A list that moved reads the old bounds of
   its nodes at its old origin, its new origin less the change of its offset.
3. **A canvas that draws all that it holds inside the edges is whole.** A
   recording marks a canvas whole when it drew every element, when the bounds
   of each lie inside the edges, and when each canvas or viewport among them is
   whole. A viewport is whole when its box lies inside the edges, it has no
   scale and its content is whole. All that a whole canvas holds is whole, so its
   guard reads all its elements and needs no place: the place of its guard is the
   mark "whole", which a move does not change.
4. **A move does not enter a kept canvas that stays whole.** The record of a
   move tests each element that the content draws before and now, as now. A kept
   element that was recorded whole and whose bounds lie inside the new edges
   keeps its records and its guard, and the walk does not enter it: everything
   in it is drawn in both frames, at the same saved positions. Any other kept
   element is entered as now: a row that an edge cuts, a viewport with a scale,
   a text that an edge cuts. So a notch costs the rows that come into view, the
   rows that leave it and the rows at the edges.
5. **The scaled viewports keep a window box of their own.** A viewport with a
   scale is never whole, so a move enters it, and
   `_extend_over_scaled_viewports!` reads the window boxes that the walk saved
   for those viewports alone.

A web browser scrolls in the same way: it changes the scroll offset of a layer
and keeps the positions of what the layer holds.

## Decisions (my proposal)

- **D1. The records keep their keys and their dictionaries.** Only the frame of
  reference of each value changes, so the forget, the count of records and the
  full paint after too many records stay as they are.
- **D2. The check of random scenes becomes a test.** A scratch check of random
  scenes found a fault of the rule for a rectangle that 87 pixel tests passed
  (ebefff784). Step 1 adds it to `test_partial_paint()` with 40 fixed seeds at
  the four settings of supersample and density of the scroll tests. A generator
  of its own makes the numbers, so a seed gives the same scene on every Julia.
- **D3. The guard of the work is the height of the window.** A scroll that costs
  what comes into view costs the same in a taller window. `test_scroll_work`
  scrolls each scene in a window of 1000 and of 2000 pixels and compares the
  graphics that a move enters.

## Keep

1. A partial paint gives the same pixels as a full paint, in every frame.
2. The rules of the two plans of the scroll hold:
   [a-scroll-copies-the-pixels-that-stay-in-view.md](../done/a-scroll-copies-the-pixels-that-stay-in-view.md)
   and [a-scroll-costs-what-comes-into-view.md](../done/a-scroll-costs-what-comes-into-view.md).
3. Each new name follows
   [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

A time runs only on the word of the owner, in the lane `taskset -c 28,30,31`,
through `bounded-run`, with the load written beside it. A count needs neither.
`main` and the branch run on the same Julia.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [ ] **The guards of the work, failing where they must.** Count the graphics
   that the record of a move enters (`_PaintedGeometry`), and give the count to
   `test_scroll_work`. For each of the three scenes, assert that a notch in a
   window of 2000 pixels enters at most 10% more graphics than in a window of
   1000 pixels; mark each assertion that `main` fails with `@test_broken` and its
   reason. Add the check of random scenes to `test_partial_paint()` (D2). Commit.
2. [ ] **The three faults of `main` that step 1 found.** The owner said to fix
   them first (2026-11-11), because step 3 changes the records that these paths
   read, and a test that fails already hides a new fault. See
   [As built](#as-built). Commit each fix with a test that fails before it:
   - a. [x] two zoomed viewports that overlap; done, see [As built](#as-built);
   - b. a partial paint at 2.5 device pixels for each pixel;
   - c. the Julia file, which no longer copies.
   The fix of a comes before the commit of step 1, whose random scenes it makes
   stable. Promote each assertion of step 1 that a fix makes pass.
3. [ ] **Records relative to their canvas.** Points 1, 2 and 5 of the way of the
   change. The counts and the pixels do not change. Run `test_sdl()`,
   `test_scroll_work()` and `test_video()` with the offscreen driver. Commit.
4. [ ] **A move does not enter a whole canvas.** Points 3 and 4. Promote the
   assertions of step 1 that pass, and write the counts in this plan. Run the
   same tests, and `test_dataframes()`, because a change of a table shows there
   first. Commit.
5. [ ] **The measurement, the guide and the end.** On the word of the owner,
   time the three scenes in real windows on `main` and on the branch, and
   profile the walk of the data frame again. Describe the frame of reference of
   the records and whole canvases in
   [sdl.md](../../documentation/package/backend/sdl/sdl.md). Move this plan to
   `plan/done/`. Commit.

## Not in this plan

- The `WeakRef` that each read of a cell allocates (`_register_dependent!`), and
  the garbage collection that it starts: about 23% of the walk.
- The calls on elements whose type the compiler does not know: about 8%.
- The computation of the rows that come into view: about 26%. That is the work
  of the projection of the table, and it is needed.

My estimate: the walk of a notch of the data frame falls from 11 ms to about
7 ms. The measurement of step 4 tells.

## As built

### Step 1: what the new tests found on `main`, 2026-11-11

The count `kept_entries` and the window of 2000 pixels work: each scene gives one
`@test_broken` for the height of the window, as planned. The new tests also found
three faults that `main` has without this branch:

1. **Two zoomed viewports that overlap.** In the random scene of seed 1 at the
   setting (1, 1), two viewports with a scale of 2 have boxes of 80 × 40 pixels
   that overlap. `_extend_over_scaled_viewports!` paints each box whole, in the
   order of the values of `res.painted.viewports`, a dictionary keyed by the
   placement keys, which come from `objectid`. The box painted last cuts the other
   viewport, whose texture the software renderer then samples on another grid:
   21 pixels of its text differ in frame 9. The order changes with the addresses
   of the objects, so the scene fails in some processes and passes in others.
2. **A ratio of 2.5 device pixels for each pixel.** At supersample 2 and density
   1.25, 30 of 40 random scenes differ from a full paint, by 72 to 2105 device
   pixels in the first frame that differs, with no copy. The code of `main` gives
   the same frames and pixels. The cause is not found.
3. **The Julia file no longer copies.** `test_scroll_work` fails its assertions
   of two copies and of the share of leaves drawn for the Julia file, as on
   `main` since at least `19e56d912` (2026-11-06). It passed when the scroll work
   landed (`bc379a52c`).

### Step 2a: two zoomed viewports that overlap, 2026-11-11

`_extend_over_scaled_viewports!` now paints two boxes of viewports with a scale
that overlap, where neither holds the other, as the box that holds both
(`_merge_crossing_boxes!`), and it adds no box that a painted box holds. The new
pixel test "two viewports with a scale whose boxes overlap" puts the second
viewport at an odd pixel, (101, 71), so the clip of each box cuts the other
inside a pixel of its zoomed content. Before the fix it failed in frames 2 to 4
at the settings (1, 1), (2, 1) and (2, 1.25), in each of five runs; at even
pixels it passed, because a cut on the grid of the zoom samples the same. After
the fix it passes at all four settings. The random scene of seed 1 at (1, 1),
which failed in 2 of 3 processes, passes in 3 of 3 and in 30 runs in one
process; the 40 seeds at (1, 1), (2, 1) and (2, 2) pass in 3 processes each.
`test_partial_paint()`: 83 pass, 1 broken (density 1.25, fault b).

