# Frame statistics print only their new rows

Status: PENDING, 2026-10-21. In progress. No decision is open.

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
- The title is "Frame statistics", the tool command "Frame statistics" with the
  tooltip "Frame statistics: how long the frames of this window take", and the
  insertion aliases "frame statistics" and "statistics".

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [ ] **The rename.** The title, the tool command and its tooltip, the
   aliases; the five tests of this repository. The test of `omnet-julia` follows
   when this lands. Run the tests that name the title. Commit.
2. [ ] **The rows by frame number.** In `FrameStatisticsToWidget.jl`. A test: a
   flush that adds frames keeps the row documents of the frames that stay, as the
   same objects, and makes rows only for the new frames; the slow colour follows a
   new median. Run the statistics tests, `test_platform()` and the feed test of
   the umbrella package. Commit.
3. [ ] **The numbers and the guide.** In the measurement lane, on `main` and on
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

Nothing yet.
