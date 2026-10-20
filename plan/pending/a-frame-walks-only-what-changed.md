# A frame walks only what changed

Status: PENDING, 2026-10-21. In progress on the branch `frame-walk`, in the
worktree `projectured-julia-repaint-skip`. The owner asked to start (2026-10-21:
"Yes").

## The ask

After the plan [a-repaint-draws-only-what-its-rectangles-touch.md](../done/a-repaint-draws-only-what-its-rectangles-touch.md),
the dirty walk is the cost of a frame of the SDL backend. The owner, 2026-10-20:
"we should avoid walking lazy lists (potentially infinite)".

## The problem

The facts at `main` `636013c86`. Find each function by its name.

1. **The walk visits each drawn graphic in each frame.** `_compute_dirty_region`
   finds a change by a visit of each graphic that the render reaches, also when
   no cell changed. `_collect_elements_dirty!` loops over the drawn elements of a
   canvas, tests the field cells of each one (`_node_dirty`, a loop over
   `fieldnames`), and recurses into each nested canvas and viewport
   (`_collect_dirty_elem!`). A canvas with no layout has no early stop, so each of
   its elements is visited. The cost, on a synthetic window with one moving dot
   and a dashboard of charts with no layout, is the whole frame:

   | Charts | The walk alone | The frame |
   | --- | --- | --- |
   | 4 | 0.30 ms | 0.29 ms |
   | 16 | 0.85 ms | 0.85 ms |
   | 64 | 3.52 ms | 3.51 ms |

2. **A lazy list can be walked to its end.** A list of nodes (`ListNode`) computes
   its `prev`, `next` and `value` on demand, and it can be endless both ways. In a
   canvas with a layout and no overlap, the render and the walk stop at the edges
   of the clip. In a canvas with no layout, or with elements that overlap,
   `_is_early_stop_layout` is false. Then the render (`_render_canvas!`, its
   `prev` and `next` loops) and the walk (`_collect_drawn_nodes`,
   `_collect_listnode_dirty!`) follow the links until `nothing`, and an endless
   list never ends the frame. No producer does this now: `LayoutList`, `GridList`
   and `GridColumnList` put their lists in a canvas with a layout and no overlap.
   `_bounds_of_canvas` and `_extend_drawn_bounds!` also iterate a whole list,
   from `get_left_tail`, to size an image; a frame does not call them.

   A lazy list has a main direction and is sorted along it, so a walk can stop at
   the edge (the owner, 2026-10-20). The cost of problem 1 comes from containers
   with no direction. The dashboard of the Explorer gives its cards to a
   `GridLayout` as a vector, and a grid of a vector puts all its cells in one
   canvas with no layout and with overlap (`print_document` of
   `GridLayoutToGraphicsCanvas`), so the walk visits each card, on screen or not.
   The grid has a list form (`GridList.jl`), which draws only the rows that a
   viewport shows. A graph places its cards anywhere, in one canvas with no
   layout (`GraphLayoutToGraphics.jl`), so it has no direction at all.

3. **On the Explorer the walk is most of a steady frame.** The owner asked to
   measure the Explorer, on many pages (2026-10-20). The script
   `/var/tmp/repaint-skip/explorer_bench.jl` builds the application window as the
   application tests do, on a real `SdlBackend` window of 1600 × 1000 with no file,
   so it opens on the Explorer. It adds an animation pane at the right of the
   Explorer and a dashboard of 32 charts to the Dashboards section. It visits each
   of the 25 pages in two rounds, by the visit that `AddExplorerEntryOperation`
   makes. Each frame does what a frame of the loop does: the clock, the feeds, the
   frame and the record of its time. For each page it compares the partial paint
   with a full paint of the same frame. On `main` `932204bc0`, with a load of 3 to
   4 from other work:

   | | idle | one moving dot |
   | --- | --- | --- |
   | frame, median of each page | 0.23 to 0.99 ms | 0.37 to 1.12 ms |
   | the walk, median of each page | 0.19 to 0.94 ms | 0.20 to 0.93 ms |
   | texts drawn in a frame | 0, the message log 0.8 to 1.6 | 0, the message log 1.6 to 3.3 |
   | partial paint against full paint | same on 50 of 50 | same on 50 of 50 |

   The largest walks: the dashboard of 32 charts with 4 on screen, 0.9 ms; the
   frame statistics, 0.75 ms; the settings and the appearance, 0.5 ms.

4. **The kernel keeps no record of what it invalidated.** `invalidate_cell!` and
   `_invalidate_dependents!` (`ReactiveCell.jl`) keep no log. `CellModule.jl`,
   which exports the names of the cells, is sealed.

## The decision

The owner, 2026-10-20, chose two ways together: "Both".

- **D. A direction where one exists.** The dashboard gives its cards to its grid
  as a list of rows, so the grid draws only the rows on screen, and the render
  and the walk stop at the edges, as for a lazy list. The cost of a frame then
  follows what the screen shows.
- **B. A guard cell for each painted container, in the backend.** When the walk
  records a canvas or a viewport, it also makes a computed cell, its guard, that
  reads what the walk tests for that container: its element list, the slot and
  the field cells of each element that the render drew, and the guard of each
  nested container. While a guard is valid, nothing in its container changed, and
  the walk skips the container with one test. A change invalidates the guards from
  the graphic up to the window, so the walk goes down only along that chain. It
  uses the dependencies that the cells already track, so the kernel does not
  change. A guard reads only the elements that the render drew, so it never reads
  past the edges of a lazy list. It also covers a container with no direction,
  such as a graph.
- **The rule for lists.** A canvas that holds a list of nodes must have a layout
  and no overlap, because only then is the drawn part of the list finite. The
  constructor of `GraphicsCanvas` refuses another canvas over a list of nodes.
  The three producers keep this rule now.

Not taken: a log of invalidated cells in the kernel, which needs a change of the
sealed `CellModule.jl`; and a bound on the list walks alone, which the early stop
already gives.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [x] **The rule for lists.** Done; see [As built](#as-built). `GraphicsCanvas` refuses a list of nodes with
   `layout_none` or with overlap. A test in the graphics suite. Run
   `test_platform()` and `test_sdl()`. Commit.
2. [x] **D: the dashboard draws the rows on screen.** Done; see [As built](#as-built). `_build_card_grid` in
   `DashboardToWidget.jl` gives the cards to the grid as a `ListNode` of rows of
   the column count. The path of card `k` in the grid becomes
   `children[row][column]`, both ways, in `_find_path_below` and in the reference
   maps of `DashboardToWidget`. Tests: the dashboard tests pass; a dashboard of 64
   cards in a pane that shows 4 builds the rows on screen and no others. Run the
   explorer tests, `test_platform()` and `test_sdl()`. Commit.
3. [ ] **B: the guards.** A guard for each recorded canvas and viewport, in the
   painted records of the window. `_collect_canvas_dirty!` and
   `_collect_viewport_dirty!` skip a container whose guard is valid and whose
   place did not change; the walk reads each guard again after it records. Tests:
   a frame with no change reads no element; one changed leaf among 5000 visits
   only the guards on its chain and the elements of the canvases on that chain;
   `test_partial_paint()`, `test_dirty_rect()` and `test_laid_out_canvas()` pass.
   Run `test_sdl()` and `test_video()` against `main`. Commit.
4. [ ] **The numbers and the guides.** On `main` and on the branch, in the
   measurement lane: `explorer_bench.jl` in both modes, 100 frames, two rounds,
   for the walk and the frame of each page of the Explorer and the check of each
   page; and `repaint_bench.jl` for the walk alone with 4, 16 and 64 charts.
   `sdl.md` describes the guards, and the guide of the explorer the rows of the
   dashboard. The plan moves to `plan/done/`. Commit.

## Rule of measurement

Take each time in the lane `taskset -c 28,30,31`, with `main` and the branch
interleaved as A/B/A, and write the load of the machine beside it.

## Not in this plan

- `_bounds_of_canvas` and `_extend_drawn_bounds!`, which size an image.
- The walk of a canvas with a layout, which already stops at the edges.
- Other grids that get a vector of cells: each one can take the list form later.
- The walkers that read a lazy list to its end: the paint of `HeadlessBackend`
  (`example/kernel/BackendHeadless.jl`, `_paint_list!`) and `search_documents`.
- The cost of a switch to a page: on a return visit ProjectionList takes 170 ms
  and DocumentTypeList 100 ms, and BackgroundWorkLog and Workspace compile 77 ms
  and 30 ms on each visit; a first visit in a fresh process is up to 11 s, almost
  all compilation.

## As built

- **Step 1.** A cell can give the list of a canvas after the canvas is made, as
  `LayoutList` does, so the constructor alone can not keep the rule. The exported
  `check_list_canvas` refuses a list with no layout or with overlap. The keyword
  constructor of `GraphicsCanvas` and `hit_element_at` call it, and so does
  `_render_canvas!` of the SDL backend: inside the guarded call of the parent the
  fault is recorded and the rest of the window draws. The walk and the recording
  do not throw, so one such canvas can not stop the paint of the window: they
  leave the list and record nothing for it. A new test gives an endless lazy
  list through a cell: the walk, the render and the hit test read none of its
  nodes, and the same list with a layout reads the 60 rows in the window. The
  test of the graphics layout built a list canvas with the default overlap; it
  now builds it with no overlap and checks the refusals. `test_platform()`:
  165658 pass, 7 broken. `test_sdl()`: 992 pass, and only the known
  `TreeRenderTest.jl:43, 44, 55` of `main` fail.
- **Step 2.** A scroll pane finds a list only in its content or in a direct child
  (`_find_list_canvas`), so the grid is now the content of the pane itself, made
  in a computation of that content; the vertical layout that held it is gone. The
  list form needs a height: a pane with no offered height takes its height from
  its content, and a list has none, so it would show no row. So a page with a
  height gives its rows as a list, and a page with no height, such as the page of
  an editor with no window size, keeps the vector form and draws every card.
  The list form also divides only an offered width, so with no width its column
  is `Fixed(card_width)`. The two reference maps read the form from the grid that
  the page shows (`_get_grid_shape`). With the SDL renderer, a dashboard of 64
  cards on a page of 1100 × 500 builds 1 row at the print and 8 of its 22 rows at
  the render, and the walk reads the same 8 (`test_dashboard_render`). Two
  walkers read a lazy list to its end and so built all 22 rows in a first test:
  the paint of `HeadlessBackend` (`_paint_list!`) and `search_documents`; the
  test of the SDL suite searches with a `descend` that enters no graphics and no
  list. The helper `_nav_drawn` of the navigator tests now takes the value of a
  node of a list.
