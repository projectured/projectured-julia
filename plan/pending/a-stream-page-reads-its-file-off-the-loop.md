# A stream page reads its file off the loop

Status: APPROVED by the owner on 2026-11-27 ("yes"). The work runs on the branch `stream-offset`.

Theme T7 of the review of the architecture
([architecture-review/README.md](architecture-review/README.md), finding WL-2 in
[work-and-logs.md](architecture-review/work-and-logs.md)). The database adapter (DD-1) is
deferred by the owner and is not in this plan.

## 1. The goal

The page of a stream of a task reads the disk only on a background task. No print, no
computation and no reader of the page opens, reads or measures the file of the stream. A
stream of any size costs the lines on the screen, and a slow disk does not make a frame slow.
The memory of a stream stays the same while the stream grows.

## 2. The decisions of the owner, 2026-11-27

- **The scope of T7:** "database adapter is deferred, task output needs to be fixed".
- **The model of the page:** "why not store a single offset into the file and discover the
  lines around that offset?" The page keeps no list of lines, in memory or in a file. Its
  state is one byte offset: the start of the line at the top. The background task reads the
  lines around that offset. This model replaces the index file (choice A), which the owner
  first agreed to.
- **The line number:** choice 1. After a jump into the middle of the file, a background task
  counts the line breaks from the nearest place where the number is known. The numbers show
  when the count is done.

## 3. Today

All of these run on the editor task, in the print or in the reader:

- `_refresh_stream_index!` calls `isfile`, `filesize`, `open` and `read` to find where each
  new line starts, and keeps every start in memory, 8 bytes for each line
  ([TaskStream.jl:24](../../source/platform/task/TaskStream.jl#L24)).
- `_read_stream_lines` opens the file and reads the lines on the screen
  ([TaskStream.jl:41](../../source/platform/task/TaskStream.jl#L41)).
- `_search_stream_lines` reads each new line of the file to find a text, and keeps the number
  of each line that holds it ([TaskStream.jl:56](../../source/platform/task/TaskStream.jl#L56)).
  The label of the bar calls it in the print. The buttons ‹ › call it in the reader, through
  `find_task_stream_matches` and `_get_top_row_for`.
- The printer computes the mark of each line on the screen again with
  `find_task_output_mark`, although the writer computed it when the line came
  ([TaskPagesToWidget.jl:467](../../source/platform/task/TaskPagesToWidget.jl#L467)).

The writer of the stream, `_read_task_stream`, writes each line to the file and flushes it at
most five times a second ([TaskExecution.jl:540](../../source/platform/task/TaskExecution.jl#L540)).
No branch of another session changes these three files (checked 2026-11-27).

## 4. The design

Each item here is a proposed decision. The approval of the plan approves them.

- **D1. The state of the page.** `TaskStreamLines` keeps byte offsets in place of line
  numbers:
  - `top_offset`, the start of the line at the top;
  - `found_offset`, the start of the line of the current match, or `-1` for none;
  - `follow`, `find_text` and `filter_text`, as today;
  - one known place: a pair of an offset and the number of its line, which is the last place
    where the page knew the line number.

  The field `index` goes, with `_TaskStreamIndex`.
- **D2. The writer keeps what it knows.** At each flush and at the end, `_read_task_stream`
  records two numbers in the `TaskOutput` of the stream: the bytes flushed and the lines
  flushed. With the number of the first line of each mark, it also keeps the offset of that
  line. So the page reads only whole lines, knows the line count at the end of the file, and
  goes to the first error with no search.
- **D3. The reads around an offset** are plain functions of a path and numbers. They read no
  document, and only the work of a background source calls them:
  - `read_stream_window(path, flushed, offset, count; text = "")`: the offsets and texts of
    `count` lines from `offset`, and the lines of one screen before it. With a text, it
    returns only the lines that hold it, and the count of all lines that it passed.
  - `count_stream_lines(path, from, to; text = "")`: the count of the lines between two
    offsets, or of the lines that hold a text.
  - `find_stream_match(path, flushed, offset, text, step)`: the offset of the next or the
    previous line that holds a text, round from the end to the start; `nothing` when no line
    holds it.

  A long line is cut at a fixed number of bytes for the screen, as the screen cuts it today.
- **D4. The background cells of a stream.** `make_task_stream` makes them, where it builds the
  document, and the sources are made there too, one set for each stream. So no state is
  global. The cells are:
  - the window of the lines on the screen;
  - the line number of the top line, counted from the nearest known place (the start, the
    end, or the known place of D1);
  - the matches of Find: their count, the place of the current one, and the offsets of the
    next and the previous;
  - the count of the lines that hold the filter text.

  A search continues from where it stopped when the file grows. The source of the stream keeps
  that point, the count of matches up to it, and the text. It keeps no list of matches.
- **D5. The printer reads only cells**, and the counts and marks of `TaskOutput`, which are in
  memory. It computes the mark of each line on the screen from its text, about 40 calls for
  each screen. That is the work for what shows.
- **D6. The operations of the bar and of the wheel read only the answers of the cells.**
  - The wheel moves by the offsets of the window, which holds one screen before the top.
  - The scroll bar has the value of D7. A jump writes the offset of the place that the value
    names, and the window goes to the start of the next line.
  - ‹ and › write the offset that the cell of Find holds. The place of the match moves by one,
    or goes round.
  - While an answer is not ready, a button gives no operation, and the label shows
    "searching".
- **D7. The scroll bar measures lines in a small file, and bytes in a large file.** The owner
  asked on 2026-11-27: "this should be true only for large files, no?"
  - **A file up to a size limit:** the bar measures lines, or the lines that hold the filter
    text. Its value is the number of the top line in the count of lines. The background task
    counts the lines of the whole file, and a jump finds the offset of its line by a count from
    the start. In a small file both are short.
  - **A larger file:** the bar measures bytes, with the value `top_offset / flushed`. A part of
    the file with long lines takes more of the bar.
  - **The limit** is a constant. Step 2 sets it from a measurement: the largest file whose count
    of lines the background task does in about 50 ms on this machine.
  - **A stream that grows past the limit** changes its measure one time. At that moment, the
    thumb of the bar can move a little.
- **D8. The exports change.** `collect_task_stream_rows` and `find_task_stream_matches` go:
  they give a list of every line or of every match, and the page keeps no such list. Their
  tests use the new cells with `wait_for_cell!`. A removed export needs the minor version step
  that the next release already needs.
- **D9. A test proves that the page reads no disk in a frame.** The test counts the calls of
  the work of the sources. It prints the page and runs each operation of the bar and of the
  wheel, and checks that no work ran before the editor runs the demands. A second check
  greps the two files and finds that only the works call `open`, `read`, `isfile` and
  `filesize`.

## 5. The steps

Each step is one commit on the branch, in a worktree of `workspace/bin/julia-worktree`. The
test of each step is `test_platform(only = "task")` and the part of the new functions.

- [x] **Step 1. The writer records the flushed bytes and lines, and the offset of the first
  line of each mark** (D2). Test: a process with known output, and the numbers after it ends.
  Done in `3f1c813d4`: 12 task parts, 980 pass, 0 fail, 0 error.
- [x] **Step 2. The reads around an offset** (D3), the measurement of the limit of D7, with tests on a temporary file: a window at
  the start, in the middle and at the end, the screen before the top, a line that has no end
  yet, an empty file, a long line, `\r\n`, a count with a text, a search forward and backward
  and round.
- [x] **Step 3. The state in offsets and the background cells** (D1, D4, D6, D8). The tests of
  the page use the cells.
- [x] **Step 4. The printer and the reader of the wheel and of the scroll bar** (D5, D6, D7,
  D9). Steps 3 and 4 are one commit (§7).
- [ ] **Step 5. The guide.** The section of the stream page in
  [task.md](../../documentation/package/platform/task/task.md) describes the offset and the
  background reads, and its list of limits loses the search that holds the editor task. Then
  the run before the land, the land with the approval of the owner, the record of the lists
  of the packages that the land changes, and this plan moves to `plan/done/`.
  - [x] The guide: `209970c2f`.
  - [x] The run before the land, 2026-11-27, on the branch rebased over main `e7de4c2c0`, with no
    network: 785 parts, all done; 3,522,145 pass, 0 fail, 0 error, 3823 broken; 1 h 55 min. The
    branch adds and removes no `@test_broken` and no `@test_skip`. The broken counts differ from
    the record `36537ff00` of 03:50 only in parts that main renamed or added (the click plan).
  - [x] The fast parts of omnet-julia against the branch (its `CLAUDE.md`), in a worktree of its
    main with no network: 265 parts, all done; 42,897 pass, 0 fail, 0 error, 265 broken. The
    first try stopped in a precompile that ran out of its 9 GB; the second had 20 GB.
  - [ ] The land, with the approval of the owner.
  - [ ] The record of the lists of the test packages whose files the land changes (`ProjecturedPlatformTest`).

## 6. Not in this plan

- The database adapter (DD-1): deferred by the owner.
- The rows of the page as the general lazy list (step 2 of WL-2): theme T5.
- The repeated parts of the documents of outside state (CC-7) and the value that a period
  samples (CC-3).

## 7. What the work found

**Step 1.** The writer counts the bytes that it writes: `println` adds one line break to a line
that `eachline` gave with no line break, so a line takes `sizeof(line) + 1` bytes. The flushed
bytes and lines are recorded after each flush and once more after the file closes. The sync of
the shadow also copies a stream when only its flushed size changed, because the last record comes
with no new line.

**Step 2.** The reads are in the section "The lines around an offset" of `TaskStream.jl`, with the
part `test_task_stream_reads` (33 pass).
- A window holds a field `top`: the index of the line that the offset names. A window that holds
  the last lines can start before that line, so the page needs the index.
- The reads are not exported. They are names of `TaskModule`, and the test calls them so.
- **The limit of D7 is 32 MB** (`_STREAM_COUNTED_SIZE = 32_000_000`). The measurement, 2026-11-27:
  one Julia process on one core, a file in `/var/tmp` that the page cache holds, lines of about
  70 bytes, and the shortest of 3 runs. A count of the line breaks takes 0.5 ms for 4 MB, 1.5 ms
  for 16 MB and 7.8 ms for 64 MB. A count with a filter reads each line and takes 4.8 ms, 18.4 ms
  and 71.6 ms. A jump to a line and a count with a filter are the slow case, about 50 ms at 45 MB,
  so the limit is 32 MB. A file that the page cache does not hold reads at the speed of the disk.

**Steps 3 and 4 are one commit.** The printer reads the state that step 3 changes, so a commit
of step 3 alone does not load.
- **The state (D1) has no place of the match.** The place of the current match is in the memory
  of the source of the stream, with the counts of the searches. A count of the place starts at
  the nearest of the start, the end and the last match whose place a search counted, so a move
  by ‹ or › counts the lines between two matches. The document keeps `top_offset`, `top_place`,
  `top_lead`, `known_offset`, `known_line`, `follow`, `find_text`, `found_offset` and
  `filter_text`.
- **A window holds 200 lines** (`_STREAM_WINDOW_SIZE`). The document does not know the height of
  the screen, so the window holds more lines than a screen shows, and the printer shows the part
  that fits. The wheel moves through the lines of the window and the lines before it.
- **One source for each stream**, with a tag on each input (`:window`, `:number`, `:search`), as
  the git documents do. The cells are made in `make_task_stream`, where the shadow makes its
  pages. So no state is global.
- **The window knows the number of its first line** when it reads from the start of the file or
  reads the last lines (`StreamWindow.number`). A move of the wheel writes the known place of the
  page, so the numbers of the next window show at once, with no count.
- **The label shows "searching"** while the search cell is provisional (`is_cell_provisional`).
  No cell of its own is needed.
- **The memory of the source has a lock.** The kernel can run two batches of one source at the
  same time, for example when the text of Find changes while a search reads.
- **The test of D9 moves the file away.** It does not count the calls of the work: a count needs
  a hook in the code of the page. With the file moved away, the page still prints the lines of its
  cells, and the wheel, Find and First error still answer. A read of the file in a print or a
  reader would find no file.
- The marks of the lines that show are computed on the loop (D5): `find_task_output_mark`
  answers from the line alone.
- The task parts: 13 parts, 1029 pass, 0 fail, 0 error (`test_task_pages` 83,
  `test_task_stream_reads` 37).

**The review of steps 1 to 4** (a code reviewer, 2026-11-27) found 9 faults. Each one held when I
checked it against the code, and each one is fixed:
1. Two notches of the wheel before the new window came moved the top once, and a notch after a
   jump undid the jump. A move now starts at the top that the page holds: while the window is
   provisional, it finds the top by its start in the window, and it gives no move when the window
   does not hold the top yet.
2. A read looped without end when the file was shorter than the flushed size, such as a file that
   a person saved through "Open as a file". A visit of the lines now stops at the end of the file.
3. At each flush, the search scanned again for the next match and the match before, and the
   window waited for that batch. The search memory now keeps, for the current match, the next
   match in the bytes read so far and the match before it, and each count keeps its first and its
   last match. A flush reads only the new bytes. The window, the numbers and the search have one
   source each, so one batch never holds another.
4. At each flush the number of the top line was counted again. The number memory keeps the
   numbers that a count found, so a later count of the same line gives it at once, and a count
   of another line starts at the nearest of them.
5. One read of a file that was gone broke all three cells. A source answers the empty answer for
   a stream whose file is gone.
6. The bar could show the place of an older filter. The answer of the number cell holds its
   filter, and the bar uses its place only for the filter of the page. A jump reads the value in
   the measure that the bar shows (`_compute_stream_bar` gives the count of lines only when the
   bar measures lines).
7. `_find_stream_line_start` and `_find_stream_place_offset` never answer `nothing`, so they are
   `_compute_stream_line_start` and `_compute_stream_place`.
8. The docstring of `StreamWindow.top` now names the lead.
9. Each table of the memories keeps at most 8 entries (`_STREAM_MEMORY_SIZE`).

New tests: a file shorter than its flushed size, a search of a file that grows, and two notches
of the wheel before the new window. The task parts with new workers: 13 parts, 1040 pass, 0 fail,
0 error (`test_task_pages` 86, `test_task_stream_reads` 45).
