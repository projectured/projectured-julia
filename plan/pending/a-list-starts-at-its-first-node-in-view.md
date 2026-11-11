# A list starts at its first node in view

Status: PENDING, 2026-11-11. Not started. The owner asked for this plan ("Write
the next plan") after the timing of
[a-saved-position-is-relative-to-its-canvas.md](../done/a-saved-position-is-relative-to-its-canvas.md),
and asked whether it holds for a lazy list as well. It does: the lazy list is
the case that this plan is for. The way of the change and the decisions in it
are my proposal.

## The ask

The timing of the plan before this one found that the work of a scroll of a data
frame grows with the depth of the scroll. The first notches enter 45 to 195 kept
graphics, and each notch further down enters about 40 more. This plan makes a
notch cost the same at every depth.

## What the timing found

`main` `b26cae628`, a real SDL window of 1600 × 1000 pixels, a data frame of
1000 rows, notches of 48 pixels, Julia 1.13.1, the lane `taskset -c 28,30,31`.
Medians of 15 notches, in milliseconds:

| Notches | Walk | Graphics that a move enters |
| --- | --- | --- |
| 25 to 39 | 6.43 | 1323 |
| 55 to 69 | 9.31 | 2532 |
| 85 to 99 | 12.24 | 3738 |

A profile of the walk at notches 70 to 159 gives 46% of the samples to the move
into the kept graphics (`_record_moved_element!`).

## The cause

A laid-out vector starts at its first element in view. `compute_first_visible_index`
reads the positions of about `log2(n)` elements, and the render, the walk, the
record, the move, the guards, the forget and the cover rule all start at that
element.

A lazy list (`ListNode`) has no index, so `compute_first_visible_index` answers 1
for it. Each walk of a list in the SDL backend goes from the head: back along
`prev` up to the first node before the near edge, then forward along `next` up
to the first node past the far edge. `_is_drawn_element` answers that each
element is drawn, except an image and a fence. So each node between the head
and the view is drawn under the clip:

- the render draws it;
- the walk records it, and its records stay;
- a move enters it, because it is outside the edges and so not whole;
- the guard of the list reads it.

The table of a data frame is a list whose head is the row `anchor` of the view
(`DataFrameView`). A wheel scroll changes `scroll_position` and keeps the
anchor, so each notch adds two rows between the head and the view. A jump
(`jump_to_row`) moves the anchor and makes the head the row at the top.

An example. The rows are 24 pixels high, the head is row 1 at y = 0, and the view
shows y = 2400 to 3360:

| Rows | Place | Now | After the change |
| --- | --- | --- | --- |
| 1 to 100 | above the view | drawn under the clip, recorded, entered by each move | skipped: the walk reads where each one starts, and enters none |
| 101 to 140 | in the view | drawn | drawn |
| 141 | the first row past the far edge | stops the walk | stops the walk |

The records of the rows above the view also stay. So the count of records grows
with the depth, until the backend forgets all records and paints the whole
window (`_is_painted_geometry_full`). That full paint draws each row from the
head.

## The way of the change (my proposal)

1. **A node outside the view on the axis of the list is skipped.** This is the
   rule of `compute_first_visible_index`. The nodes of a laid-out list do not
   overlap and they follow the axis, so a node ends where the node after it
   starts. A node is skipped when the node after it starts at or before the near
   edge, or when the node itself starts at or after the far edge. The walk reads
   where a skipped node starts and its link, and it reads nothing in it. A node
   whose element has no position on the axis is not skipped, as the search of a
   vector answers 1 for such an element.
2. **One function decides it for each walk of a list.** The render
   (`_render_canvas!`), the nodes that the render draws (`_collect_drawn_nodes`,
   which the record, the move, the guards, the forget and the cover rule use),
   and the dirty walk (`_collect_listnode_dirty!`) skip the same nodes. The
   dirty walk keeps its order: it tests a leaf for stale cells before it reads
   its place.
3. **A node that leaves the view leaves the records.** A skipped node that was
   painted has its place cleared and its records forgotten, as a node past the
   far edge has now. So the records of a list are those of its nodes in view,
   and the count of records does not grow with the depth.

## Decisions (my proposal)

- **D1. The walk still steps from the head.** A lazy list has no index, and a
  path into it counts from its head. A step over a skipped node reads its link,
  its element and where the element starts, which is a few cell reads. The other
  way is a walk that starts at the node that the last walk found at the near
  edge. That needs a guard over every link from the head to that node: a change
  of a link above the view makes new nodes from there on, and the old nodes stay
  valid but leave the list, so a walk from an old node draws rows that the list
  no longer holds. The view that holds a long list moves its head, as the data
  frame does with a jump. Step 3 measures the time of the steps at the depth of the
  timing.
- **D2. The guards of the work scroll deep.** `test_scroll_work` scrolls the data
  frame 60 notches before it counts, and asserts that 6 notches deep in the table
  enter at most 10% more graphics in all than the first 6 notches, as the test
  of the window twice as high does.
- **D3. Lists of a new kind in random scenes of their own.** The random scenes
  have one kind of list now: texts linked by hand, with the head at the first
  node. A new test of random scenes makes lists with the head in the middle,
  rows that are canvases, links made by `set_lazy_link!`, panes that scroll far
  above and far below the head, and changes that insert or remove a node. A test
  of its own keeps the scenes of the 40 seeds that pass now.
- **D4. The hit test is not in this plan.** `hit_element_at` steps from the head
  and tests each node on the way, because its answer counts from the head. A
  press runs one walk, not one in each frame.

## Keep

1. A partial paint gives the same pixels as a full paint, in every frame.
2. The dirty walk reads the cells that the render reads, in the same order.
3. The rules of the three plans of the scroll hold:
   [a-scroll-copies-the-pixels-that-stay-in-view.md](../done/a-scroll-copies-the-pixels-that-stay-in-view.md),
   [a-scroll-costs-what-comes-into-view.md](../done/a-scroll-costs-what-comes-into-view.md)
   and [a-saved-position-is-relative-to-its-canvas.md](../done/a-saved-position-is-relative-to-its-canvas.md).
4. Each new name follows
   [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

A time runs only on the word of the owner, in the lane `taskset -c 28,30,31`,
through `bounded-run`, with the load written beside it. A count needs neither.
`main` and the branch run on the same Julia.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [x] **The guards of the work, failing where they must.** Done; see
   [As built](#as-built).
   - Give `_sw_scroll` a count of notches that it scrolls before it counts. Each
     of those frames is painted, so the paint state follows the window. Add the
     deep data frame of D2.
   - Add a test that `_collect_drawn_nodes` of a list scrolled 100 rows below its
     head answers the nodes from the row at the near edge to the last row before
     the far edge. Add the same test for a list scrolled 100 rows above its head.
     Assert which rows, not only how many.
   - Add the random scenes of lists of D3 to `test_partial_paint()`, with 40
     fixed seeds at the four settings of supersample and density.

   Mark each assertion that `main` fails with `@test_broken` and its reason.
   Commit.
2. [x] **Skip the nodes outside the view.** Done; see [As built](#as-built). Points 1, 2 and 3 of the way of the
   change. Promote the assertions of step 1 that pass, and write the counts in
   this plan. Run `test_sdl()`, `test_scroll_work()` and `test_video()` with the
   offscreen driver, and `test_dataframes()`, because a table is a list. Commit.
3. [ ] **The measurement, the guide and the end.** On the word of the owner, time
   the three scenes in real windows on `main` and on the branch, in the blocks of
   the last timing, and profile the walk of the data frame again. Describe the
   rule of the skipped nodes and the steps from the head in
   [sdl.md](../../documentation/package/backend/sdl/sdl.md). Move this plan to
   `plan/done/`. Commit.

## Not in this plan

- A walk that starts where the last walk found the view (D1).
- The hit test (D4).
- The garbage collection: 20% of the samples of the walk, in 2 of 45 notches,
  about 57 ms each.
- `objectid` and the hashes of the placement keys: about 7% of the samples.

My estimate: a notch of the data frame costs about 3 to 4 ms of walk at every
depth, which is what the timing gives when its line is drawn back to no kept
graphics. Step 3 measures it.

## As built

### Step 1: the guards of the work, 2026-11-11

- `test_scroll_work`: the rename tool renamed `_sw_has_entries_of_short_window`
  to `_sw_enters_as_few(frames, reference)`, which now takes the frames that it
  tests first, so one helper serves the window twice as high and the deep table.
  `_sw_scroll` takes `depth`, the notches that it paints and does not count. The
  data frame scrolls 60 notches and then counts 6, and `_sw_enters_as_few` of
  those notches against the first 6 is `@test_broken`. The suite gives 23 Pass
  and 1 Broken.
- `test_partial_paint`: the set "a list draws its nodes in view and skips the
  nodes outside the view" asserts the rows that `_collect_drawn_nodes` answers
  for a view 100 rows after the head (rows 101 to 107) and 100 rows before it
  (rows -93 to -99, in the order of the walk back). Both are `@test_broken`:
  `main` answers rows 1 to 107 and rows 0 to -100.
- The set "random scenes of lazy lists that scroll far from their heads" builds
  each list with `make_mapped_list` over a chain of specs, as a layout prints
  the rows of a table, and passes on `main` at the four settings. A probe of
  its 40 scenes found that the full paint changes in 208 of 320 frames, and that
  a pane shows rows of its list in 464 frames, so the scenes test the walk of a
  list.
- The suite gives 100 Pass and 2 Broken.
- `package/ProjecturedSDLTest` has no installed environment in a new worktree,
  so its tests run from `environment/all` with `using ProjecturedSDLTest`.
- The precompile of `main` warns that 1675 of the 12464 recorded calls of
  `ProjecturedPlatform`, and 164 of the 648 of `ProjecturedChart`, no longer
  resolve. That is the state of `main`; this branch changes no source.

### Step 2: the nodes outside the view are skipped, 2026-11-11

- `_is_skipped_list_node(start, following, near, far)` is the rule, with
  `_get_list_edges` for the near and the far edge and `_find_list_start` for the
  start of an element in window coordinates. The render (`_render_canvas!`),
  `_collect_drawn_nodes` and the dirty walk (`_collect_listnode_dirty!`) apply it.
  Each walk forward holds a node until it reads the start of the node after it;
  a walk back knows the start of the node that it came from.
  `_is_before_early_start` had no caller left, and it is gone.
- The dirty walk tests the head for stale cells first, with
  `_read_dirty_list_node`, because the place of a node before the head is
  computed from the place of the head. `_visit_dirty_list_node!` adds a drawn
  node to the visited nodes, or clears the place of a painted node that the walk
  skips.
- **A fault that the random scenes of step 1 found.** Seed 38 at all four
  settings: a row inserted just above the view makes new nodes from there on
  (`make_mapped_list` links them from the changed link), and the old nodes leave
  the list with their pixels on the screen. The reflow of a changed spine covered
  the old and the new bounds of the visited nodes only. On `main` the walk visited
  each row from the head, and their union was wide enough by chance; with the
  skip, the visited rows were narrower than an old row. The reflow now also
  takes the bounds that the list drew in the last paint, the record of the list
  canvas, which the walk reads before it records the list again.
- The records of the content of a node whose place the dirty walk clears stay
  until the forget after too many records, as for a node past the far edge. The
  move forgets them (`_forget_recorded_element!`). This is as on `main`.
- The guard of a list still reads where each node between the head and the
  view starts (D1), and none of their content.
- Counts of `test_scroll_work` (6 notches, kept entries, records and guards):

  | Scene | Depth | Kept entries | Records | Guards |
  | --- | --- | --- | --- | --- |
  | Julia file | 0 | 13 to 36 | 29 to 59 | 38 to 51 |
  | Julia file | 60 | 14 to 40 | 29 to 60 | 38 to 52 |
  | Files pane | 0 | 5 to 8 | 14 to 20 | 6 to 8 |
  | Files pane | 60 | 5 to 8 | 14 to 20 | 6 to 8 |
  | Data frame | 0 | 30 | 118 to 144 | 76 to 90 |
  | Data frame | 60 | 23 to 30 | 105 to 118 | 62 to 76 |

  The data frame entered 45 to 195 kept graphics in the first 6 notches before
  this step, and 1323 to 3738 in the timing at notches 25 to 99.
- Suites with the offscreen driver, Julia 1.13.1:
  - `test_sdl()`: 1333 Pass, 1 Fail, 2 Error. `main` `cfb077e2d` gives 1330
    Pass with the same three: `SdlWorkloadTest.jl` lines 29 and 72, where an
    earlier test shuts the event system of SDL down, and line 78, where a
    finished turn of an agent folds its code, so the click on `lengths_1` finds
    no target. Commit `3fd04ea4b` on `main` removed that click.
  - `test_scroll_work()`: 24 Pass, the deep data frame among them.
  - `test_video()`: 78 Pass, 1 Fail, the known `ApplicationVideoTest.jl:317`.
  - `test_dataframes()`: 613 Pass.

