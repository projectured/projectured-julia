# The search below a node reads the folders that it needs

Status: PROPOSED, 2026-10-18. It builds on steps 1 and 2 of
[a-value-that-a-task-reads-is-a-cell.md](a-value-that-a-task-reads-is-a-cell.md)
(projectured main `33a957cca` and `7c2f4d2c9`). No step has started.

## The ask

Step 6c of [the-explorer-shows-what-the-editor-holds.md](../done/the-explorer-shows-what-the-editor-holds.md),
which the owner deferred on 2026-10-18 and then put on the background cell ("then
we can build on top of that"). Its §5.7 says: Return in the filter starts a search,
"Find 'smoke' below Files". The search walks below the selected node with a limit
of depth and of count, reads what is not read, and shows the matches as a list on
a page in the navigator. A press on a match opens its node and shows its page. The
search shows its progress and can stop.

## What exists

- **The quick filter** (6a) reads only the rows that the tree has read
  (`collect_read_tree_children`), so it finds `smoke.ini` only in a folder that is
  open or was open.
- **A folder** (`FileSystemDirectory`) keeps its entries as documents in
  `elements`. A holder acquires it, such as an open node of a tree: the acquire
  reads the folder off the loop (`start_document_read!`), and the answer
  (`ApplyFolderListingOperation`) keeps the document of each entry that stays, by
  name, so an open place stays open. The holder also watches the folder, and a
  change reads it again. The chevron answers from stored state
  (`has_folder_entries`), so a closed folder reads nothing.
- **The background cell** answers its last answer or its default while its value
  is still to come, is provisional, and records a demand. After the print of a
  frame, the editor starts one work for each source with demands, and the answers
  come back through the inbox. A walk of the documents starts no work by default.
  `wait_for_cell!` waits for a final value; on the editor task it computes the
  demanded values itself and so blocks the loop.

## The model

1. **The listing of a folder is a background cell.** Its inputs are the path of the
   folder and a stamp that a change of the watch writes. Its source reads all the
   folders that one frame demands, in one task. Its default is the listing of the
   last read, or none. The entries stay documents in `elements`, computed from the
   listing, and an entry that stays keeps its document, by name, as the roster
   keeps its rows. So whoever reads the children of a folder reads the folder,
   and nobody else does: an open node of a tree, the page of the folder, and the
   search.
   - The chevron keeps to stored state (`has_folder_entries`) and never reads the
     listing cell, or every closed folder in view would read its disk. The
     emptiness of a sub-folder stays a stored answer of the watch of its parent
     (`ApplyFolderEmptinessOperation`).
   - The decoration of a folder says that it reads while its listing is
     provisional, with a query that records no demand, and a failure comes with
     the answer. A decoration that read the listing would read every folder row
     in view.
   - A holder keeps only the watch: a watch is no value.
2. **The search is a computation, not a task** (my recommendation, Q2). A document
   `ExplorerSearch(place, text; depth, limit)` holds the node to search below, the
   text, and the limits. Its matches are a computation that goes down the children
   of the node as the tree gives them (`get_tree_children_steps`, and of a lazy
   list its first nodes) and keeps each node whose label holds the text. A folder
   that is not read yet answers the default and records a demand, so the matches
   are provisional while a folder below is read, and they grow frame by frame as
   the answers come. The computation stops at the depth and at the count of
   matches.
   - **Where it shows.** Return in the filter opens the page of the search in the
     navigator beside the tree. The page lists the matches, each with its place
     below the node; a press on a match opens its node and shows its page, as a
     match of the quick filter does.
   - **The progress.** While the matches are provisional, the page says how many
     folders it waits for. When a limit stops the search, the page says so.
   - **The stop.** The page that nobody shows reads nothing, so a visit to another
     page, or Escape, stops the search. Back shows it again, and it goes on from
     what it read.
3. **The search needs nothing of a kind but its tree children.** A kind that keeps
   its children in memory, such as the task list, is searched as it is; a kind
   whose children a task reads takes part once its listing is a background cell.

## Steps

1. [ ] **The listing of a folder is a background cell** (the filesystem slice).
   `ApplyFolderListingOperation` and the read on the acquire go; the watch stays
   with the holders. Tests: `test_filesystem()`, `test_explorer()`, the
   tests of the Files tab in `test_application()`, and a test that a closed
   folder in view reads nothing.
2. [ ] **The search** (the explorer slice): `ExplorerSearch`, its page, Return in
   the filter, the limits, the progress and the stop. Tests: `test_explorer()`,
   with a folder of 3 levels that nobody opened, and a search that a visit stops.
3. [ ] **The guides:** `filesystem.md`, `explorer.md`; the plan moves to
   `plan/done/`.

## Questions for the owner

- **Q1. Who moves the listing of a folder?** It is one of the five reads that the
  background cell plan moves after its pilot, each in a plan of its own. My
  recommendation: this plan moves it, because the search needs it first, and the
  session of the background cell hears of it before step 1.
- **Q2. A computation or a task?** §5.7 of the explorer plan said "a task, as every
  task does", with a row in the task list. A task would wait for each folder off
  the loop with `wait_for_cell!`, which reads through the loop every 50
  milliseconds. My recommendation: a computation, as above, because the model
  already does the work, the progress and the stop; the cost is that the search
  has no row in the task list.
- **Q3. The limits.** My recommendation: a depth of 10 and 500 matches, which the
  page names when it stops there.

## Not in this plan

The drawing of a part that is provisional (step 3 of the background cell plan): until
it lands, the page of the search shows its matches as they come, which a search
shows anyway. A search by the content of a file. The other four reads of the
background cell plan.
