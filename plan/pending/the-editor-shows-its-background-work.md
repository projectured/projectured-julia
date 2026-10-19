# The editor shows the work that it does in the background

Status: PROPOSED, 2026-10-19. The owner agreed on 2026-10-18 that this view gets a
plan of its own, after the search below a node
([the-search-below-a-node-reads-the-folders-it-needs.md](../done/the-search-below-a-node-reads-the-folders-it-needs.md),
§ Not in this plan). No step has started.

## The ask

A view of the background work of the editor, under Editor in the explorer: each
work with its source, its count of values, its time and its failure. A person who
waits for a folder, the records of a result folder, or a search, can see what the
editor reads now, what it read, how long it took, and what failed.

## What exists

- **The work of a background cell** (`source/kernel/editor/BackgroundCells.jl`,
  not sealed). After the print of a frame, `start_background_cell_work!` starts
  one work for each `BackgroundSource` with demands, through
  `start_background_work`, with the inputs of all its demanded cells. The answers
  come back as `WriteBackgroundAnswersOperation`, which writes them. A work that
  throws gives a failure (`_BackgroundFailure`) for each of its values.
- **Nothing keeps a work after its start.** `start_background_work` answers a
  `BackgroundWork` and keeps no list of them. `BackgroundDemands`, the session
  document of the demands, is emptied at each start.
- **Two models for a record of the kernel that the platform shows.** The fault
  log: the kernel declares a seam (`append_fault!`), and a platform document that
  a wrapper attaches answers it. The frame statistics: the kernel records into a
  plain store for free (`editor.frame_measurements`), and a platform feed flushes
  the store into a document only while a view shows it.
- **The Editor section** of the first content of the explorer
  (`make_editor_explorer_content`) holds the message, gesture, fault and MCP logs,
  the frame statistics, the selection inspector and the system processes.
- **A roster** shows any collection as a table, with the facets of the type of its
  items, and filters and sorts it.

## The model

1. **A record of each work.** At the start of a work the editor adds a
   `BackgroundWorkRecord`: the description of the source, the count of its values,
   the time of its start, and a few of its inputs as text. When the answers are
   written, the record gets the time of its end, the count of the values that
   failed, and the message of the first failure. A record holds no input value
   and no answer, so it keeps no document alive.
2. **A bounded log of the session.** `BackgroundWorkLog` keeps the last 100
   records of the editor, newest first, a session document of the editor
   (`get_session_background_work_log(; editor)`). A record of a work that runs is
   kept until the work ends, whatever the bound.
3. **A page of the log** under Editor in the explorer, with the title "Background
   work": a roster of the records, with the facets source, values, started, took
   (or "running"), state (running, done, failed) and failure. Its row in the tree
   says how many works run, with the running mark, and has the failed mark while a
   record of the last 100 failed.

## Steps

1. [ ] **The record and the log** (kernel, `BackgroundCells.jl`, in agreement with
   the session of the background cell). The record at the start and at the end of
   a work, the bounded log, `get_session_background_work_log`. Tests in
   `test/kernel/editor/BackgroundCellTest.jl`: a work adds a record that runs and
   then ends with its count of values; a work that throws ends with its failure;
   the log keeps 100 records; an editor that shows nothing pays one write of a
   record for each work.
2. [ ] **The page** (platform): the title, the decoration, the roster of the
   records with its facets, the entry in the Editor section, and the insertion
   alias "background work". Tests: a folder that an explorer opens adds a record
   "the listings of folders" that ends; a failed work shows its message on the
   page; the row of the log runs while a work runs.
3. [ ] **The guides:** `editor.md`, the guide of the slice of the page,
   `explorer.md`; the plan moves to `plan/done/`.

## Questions for the owner

- **Q1. Where do the records live?** (a) My recommendation: the kernel keeps the
  log as a document of cells, and writes a record at the start and at the end of
  each work. A write of a cell that nobody reads costs little, and a work starts
  at most once for each source in a frame. (b) The kernel keeps a plain store,
  and a platform feed flushes it into the document while a view shows it, as the
  frame statistics do. It costs nothing while no view shows the log, but it needs
  a feed and a flush interval. (c) A seam that a platform log answers, as the
  fault log does; it needs a wrapper of `build_editor` that attaches the log.
- **Q2. What does a record keep of its inputs?** My recommendation: the first
  three inputs as text, each at most 80 characters, so the page names the folders
  or files that a work read, and holds no value of them.
- **Q3. The bound.** My recommendation: 100 records, newest first.

## Not in this plan

- A verb that the assistant calls to read the log.
- A stop of one work from the page: the stop of a background cell is the stop of
  what reads it, such as a search.
- The works of `start_background_work` that no background cell starts, such as the
  code of the assistant.
