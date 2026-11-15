# Frame statistics print only their new rows

Status: DONE, 2026-10-21, on the branch `frame-statistics-rows`, in the worktree
`projectured-julia-frame-statistics`. Not landed on `main`.

## The ask

The owner, 2026-10-21, looking at the frame statistics of the OMNeT++ IDE, where
every second frame took 10 to 15 ms while nothing happened:

1. "I would like to see the most recent rows first, that is quite clear, but I
   would like to make it incremental, so it doesn't repaint everything", and
   then: "the paint in the SDL backend should not be modified, just the lazy
   print now", "lazy and incremental print".
2. "we need to rename the user interface elements which only say 'statistics'.
   what statistics? it's frame statistics if anything."

## The problem

1. **Each refresh prints every visible row again.** While a view shows the
   statistics, `FrameStatisticsFeed` flushes the recent frames into the document
   at most every 0.25 s. The flush frame takes 10 to 15 ms, and the display event
   of that frame makes one more frame, of about 1.3 ms. The flush replaces
   `frames` and `columns` with new vectors (`flush_frame_statistics!`), so the
   `rows` and `row_headers` computations of `_make_frame_table` run again and make
   a new row document for every frame (`_make_frame_list`). The rows are already a
   lazy list (`make_index_list`), so only the visible rows print, but they all
   print again. The slow colour of a row is decided when the row is made, from
   the median of all frames.
2. **`WidgetTable` can keep the print of a row.** A table whose rows are a list
   gives them to the list form of its grid, and `GridList` keeps the print of a
   row by the row document: a new head with the same rows links the prints that
   it has, and only a new row prints. The table of a data frame uses this: it
   makes each row once (`_take_made_row!`).
3. **The title says only "Statistics".** `get_document_title(::FrameStatistics)`
   gives the tree row, the breadcrumb and the tab title; the window tool command
   "Statistics" has the tooltip "Statistics: how long the frames of this window
   take"; the insertion alias is "statistics". Five tests here and one of
   `omnet-julia` (`test/ide/IdeWindowWrapTest.jl:339`) name the title.

## The model

- The page keeps one row document and one row header for each frame number that
  the ring holds. A frame never changes its values after the store recorded
  them, so its row stays the same object while the frame is in the ring. A flush
  drops the rows of the frames that left the ring.
- The slow colour of a cell is a cell that reads the slow limit, so a change of
  the median prints again only the cells whose colour changes.
- The list keeps its head at `anchor`, counted from the newest frame, as now. A
  new frame makes a new list over the same rows, so the grid prints only the rows
  of the new frames. The paint of the SDL backend does not change.
- The title is "Frame statistics", the tool command "Frame statistics", and the
  insertion aliases "frame statistics" and "statistics".

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [x] **The rename.** Done; see [As built](#as-built). The title, the tool command and its tooltip, the
   aliases; the five tests of this repository. The test of `omnet-julia` follows
   when this lands. Run the tests that name the title. Commit.
2. [x] **The rows by frame number.** Done; see [As built](#as-built). In `FrameStatisticsToWidget.jl`. A test: a
   flush that adds frames keeps the row documents of the frames that stay, as the
   same objects, and makes rows only for the new frames; the slow colour follows a
   new median. Run the statistics tests, `test_platform()` and the feed test of
   the umbrella package. Commit.
3. [x] **The numbers and the guide.** Done; see [As built](#as-built). In the measurement lane, on `main` and on
   the branch: the time of the flush frame on the frame statistics page of the
   application window, with the window open long enough to hold the 1000 frames
   of the ring. The guide of the statistics slice says how the rows are kept. The
   plan moves to `plan/done/`. Commit.

## Rule of measurement

Take each time in the lane `taskset -c 28,30,31`, with `main` and the branch
interleaved as A/B/A, and write the load of the machine beside it.

## Not in this plan

- A move of the pixels of rows that only moved, in the paint of the SDL backend.
- The times of the read from the input devices and of the write to the output
  devices, which belong with the stage times of the branch `frame-guards`.

## As built

- **Step 1.** The title and the tool command say "Frame statistics"; the aliases
  are "frame statistics" and "statistics". At the rebase onto `main`, the tooltips
  had become sentences ("How long the frames of this window take."), so the
  tooltip keeps the sentence of `main`. No guide named the old
  title. `test_editor_display()` 28, `test_window_wrappers()` 58,
  `test_window_shell()` 140, `test_application()` 385 pass and 2 broken.
- **Step 2.** The rows by frame number were not enough: a probe that paints the
  page with the SDL renderer still printed every visible row in a flush, on
  `main` and on the branch alike. Three causes, each found with a probe:
  1. **The whole page printed again.** `print_document` of `WidgetTable` read
     `w.cells` to choose between the list form and the vector form
     (`_is_listed_body`), and `_check_table_parts` read `w.cells` and
     `w.row_headers` to check the list form. Both reads ran in the print, so the
     computation that builds the page depended on the list of rows itself, and a
     new list built the page, the table and its grids again. Now the form is a
     cell of its own whose value is a `Bool`, so a new list that keeps the form
     changes nothing above the table, and the check runs in a cell of its own that
     the print only peeks at. This is in the table of every widget, so a table of a
     data frame keeps its prints too.
  2. **The header column made new rows.** `_make_header_row_node` wrapped each
     row header in a new row of one cell for each new head, so the grid of the
     header column found no kept print. `_HeaderRows` keeps the row of each header
     for the head now and the head before, as `KeptListPrints` keeps prints, so a
     header that no head reaches goes.
  3. **The style of a label changed on each flush.** A style cell that read the
     slow limit computed again at each flush, and a `StyleText` is no plain data
     for the cell engine, so the same style counted as a change and the label made
     its text graphic again. Whether a frame is slow is now a cell of its own with
     a `Bool` value, and the style of a label reads that flag.

  With the three, a flush that adds two frames prints 4 rows, the two new frames
  in each of the two grids, against 34 before (the probe
  `/var/tmp/frame-statistics/row_print_probe.jl`). Two tests: a flush keeps the
  row documents of the frames that stay, and the graphics of the texts of a kept
  row are the same objects after a flush. `test_frame_statistics_feed()` 148,
  `test_platform()` 165673 pass and 7 broken, `test_dataframes()` 612,
  `test_sdl()` 1006 and the known `TreeRenderTest.jl:43, 44, 55`,
  `test_application()` 385 and 2 broken, `test_file_watch_window()` 16,
  `test_documentation()` 1.
- **Step 3.** `/var/tmp/frame-statistics/flush_bench.jl` builds the application
  window on a real `SdlBackend` with vsync off, shows the frame statistics in the
  navigator of the Explorer, runs frames until the ring holds 1000 frames, and
  then, 40 times, waits 0.26 s so the feed is due and times the flush frame and
  the frame after it. In the lane `taskset -c 28,30,31`, with a load of 2.4 to
  3.3, `main` at `3f8b6a126`:

  | | `main` | Branch |
  | --- | --- | --- |
  | flush frame, median | 13.05, 13.29, 13.67 ms | 9.82, 10.10 ms |
  | flush frame, p90 | 14.01, 14.27, 15.04 ms | 10.94, 11.09 ms |
  | of it, the render of the window, median | 12.55 ms | 7.93 ms |
  | the frame after it, median | 0.46 to 0.48 ms | 0.46 to 0.47 ms |
  | rows printed in a flush | 50 | 4 |

  The render of the window holds the print, because the cells of the rows compute
  when the backend reads them. The 7.9 ms that stay are the walk and the paint of
  a table whose visible rows all move down at each flush; the paint of the SDL
  backend did not change, as the owner asked. The rest of the flush frame was
  2.17 ms on the branch and 1.12 ms on `main`, in one run each. The guides of the
  statistics slice and of the widget slice say how the rows are kept.

