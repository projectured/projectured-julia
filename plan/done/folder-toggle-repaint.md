# A folder that opens repaints only the rows that change

## The owner's words, 2026-09-27

"Fix the folder toggle left painting. Add the scroll repaint step, the other two I
don't want. This will be enough."

## The problem

In the second take of S10 (`plan/pending/feature-video-screenplays.md`), a click
on the chevron of a folder in the navigator paints the whole navigator again. Only
the chevron of that row changes, the rows below it move, and the rows of the
folder come or go. Four causes make the whole tree a single unit:

1. **The tree makes new row graphics.** The rows of `WidgetTree` are a
   `CellVector` whose key is the `WTreeRow` of each row. A toggle computes the
   rows again, the `CellVector` makes a new slot for each key, and each slot makes
   a new canvas. Every row is then new to the dirty walk.
2. **Every folder row reads the set of open folders.** The content of a row reads
   `w.expanded` to draw its chevron down or right. A toggle writes that set, so
   the content of every folder row is computed again, with new graphics.
3. **The walk paints a container whole when its element list changes.** It does
   not compare the elements of the new list with the ones it painted.
4. **The walk paints a leaf whose cells are stale, also when its value is the
   same.** With 2 fixed, the chevron of every folder reads the set in a cell of
   its own, and each of those cells is stale after a toggle.

A fifth cause comes with 3: the tree has a transparent rectangle behind its rows
as a hit target. It grows with the tree, and the walk paints its old and new box,
which is the whole tree, although it draws no pixel.

## The design

- [x] **A. The tree keeps the canvas of a row by its path.** A private `Dict` in
  the closure of the printer maps a path to its canvas, as PAR-NO-PROJECTION-GLOBALS
  allows for a reconciliation cache. The top of a kept canvas is a cell that reads
  the place of its path in the geometry, so a row that moves keeps its graphics.
- [x] **B. The chevron reads the open set in a cell of its own.** The row pushes
  the chevron glyph, and the text cell of the glyph reads whether the path is open.
  The rest of the row does not read the set.
- [x] **C. The walk compares a changed element list one element at a time.** A
  paint records the keys of the elements that each canvas draws. When the element
  list of a canvas that did not move changes, the walk takes each element of the
  new list by its placement key, as it does in a list that did not change: a new
  element is painted, a moved one is painted at its old and new place, and a kept
  one only when it changed. The elements that the canvas drew before and does not
  draw now are cleared.
- [x] **D. The walk compares a stale leaf by value.** A paint records a signature
  of each leaf: the hash of the values of its cells. A stale leaf whose bounds and
  signature are the same after it is computed again is not painted.
- [x] **E. A graphic that draws nothing has no dirty bounds.** A rectangle with a
  transparent fill and no visible border gives no rectangle to the region.
- [x] **F. Tests** for A to E, and the probe of the application: a toggle paints
  the chevron of the row and the rows from it down, and nothing above it.
- [x] **G. The take**: the scroll step, the text of the page, a new take, and the
  web page. The take is `build/video/s10/take3.mp4` (59.3 s), recorded by
  `build/video/s10/take2.jl` over the timeline in `timeline2.jl`. On the web page it
  replaces `assets/videos/partial-render.mp4`, with a poster at 9.8 s, where the
  folder `chart` opens (commit `ec08cac` of `projectured.github.io`, not pushed).

## What was found while it was built

- **C needs a second phase and a walk by value.** The first try read a new list
  during the walk. That read can compute cells that the walk has still to test:
  in the test "a recording does not hide a change", a box reads the size of the
  canvas after it, and the read computed the new list of that canvas, which then
  looked up to date, so its old rectangle was not cleared. The walk now queues a
  new list (`lists`) and reads it after it has tested every cell of the frame.
  Under that canvas it walks by value (`by_value`), because a read of the list
  can have computed the cells below it: every leaf is compared by its signature
  and bounds, every canvas by the keys it draws, and a text list is painted
  again. A list never waits for another list: the second phase walks the lists
  below it at once. The clip of a viewport moved to a queue of its own
  (`clips`) that runs after every recording, because a new list inside a
  viewport adds its rectangles in the second phase, after the clip would have
  run.
- **A written value cell is not stale.** A graphic whose place is a value cell
  that a caller writes does not look changed to the walk. A printer places a
  graphic with a computed cell, so the tests do too. Under a new list, the walk
  by value finds such a move anyway.
- **The first probe of the window**: a toggle of `chart` gives 20 rectangles, the
  chevron and the text of each row that moves or comes, from the row of the folder
  down. The rows above it are not in the region. A turn of the wheel paints the
  whole navigator, because every row moves.
- **The take with a full repaint and with the partial repaint draws the same**:
  `build/video/s10/check2.jl` records the timeline of the take twice, with no
  outline and no pointer, and all 684 frames are the same.
- The test packages pass: the SDL suite (765), `test_dirty_rect` (78 with the
  three new tests), `test_widget_tree` (45), the toolbar, menu, button and shell
  tests, and `test_application_video`.
