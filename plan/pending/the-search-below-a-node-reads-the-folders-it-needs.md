# The search below a node reads the folders that it needs

Status: PROPOSED, 2026-10-18; Q2 decided (a computation, shown as a work item in
the task list). It builds on steps 1 and 2 of
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
2. **The search is a computation, not a task** (Q2, decided). A document
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
   - **One match cell for each folder.** The matches below a folder are a cell of
     their own: the matches of its entries and the cells of its sub-folders. So an
     answer for one folder computes again only the cells on its path up to the
     node, and not the whole walk.
3. **The search is a work item in the task list** (Q2, decided), as a group of
   tasks is. Return in the filter makes the search, adds it to the task list of
   the session, and opens its page. The row and the page are two views of one
   search.
   - **Its status follows its result.** Running while the matches are
     provisional, with "waiting for 3 folders"; done when they are final, with
     "12 matches" and the time that it took; failed when a read failed. The
     decoration is that of a work item.
   - **It computes while it shows.** The row reads the result to say its progress,
     so the search goes on while its row or its page is in view: the task list in
     the explorer, or the Tasks tab, keeps a long search going. Ctrl+press on the
     row opens its page in a new tab, as for a group. This is the one exception
     to the rule of the explorer plan that a decoration reads stored state only:
     a work item reads its own result, because that demand is what the person
     asked for.
   - **The stop.** Stop takes the row out, as the close of a group does, so
     nothing reads the result and no read runs. The page that nobody shows
     reads nothing either; Back shows it again, and it goes on from what it read.
   - **The verbs.** The list takes a search as it takes a group (`add_task_group!`
     gets a method), and `list_task_groups`, `find_task_group`,
     `describe_task_group`, `stop_tasks!` and `close_task_group!` answer a search
     too, so the assistant sees it.
4. **The search needs nothing of a kind but its tree children.** A kind that keeps
   its children in memory, such as the task list, is searched as it is; a kind
   whose children a task reads takes part once its listing is a background cell.

## Steps

1. [ ] **The listing of a folder is a background cell** (the filesystem slice).
   `ApplyFolderListingOperation` and the read on the acquire go; the watch stays
   with the holders. Tests: `test_filesystem()`, `test_explorer()`, the
   tests of the Files tab in `test_application()`, and a test that a closed
   folder in view reads nothing.
2. [ ] **The search** (the explorer slice, and the task slice for its row):
   `ExplorerSearch`, the match cell of each folder, its page, Return in the
   filter, the limits, its row in the task list with its status, the stop, and
   the verbs. Tests: `test_explorer()`, with a folder of 3 levels that nobody
   opened; a search whose row stays in view after a visit to another page goes
   on, and a stop reads nothing more; `test_task_verbs()` and `test_task_views()`
   with a search in the list.
3. [ ] **The guides:** `filesystem.md`, `explorer.md`; the plan moves to
   `plan/done/`.

## Questions for the owner

- **Q1. Who moves the listing of a folder?** It is one of the five reads that the
  background cell plan moves after its pilot, each in a plan of its own. The
  session of the background cell does not plan to move it (2026-10-18), so this
  plan moves it, because the search needs it first.
- **Q2. A computation or a task? Decided (the owner, 2026-10-18: "Agreed").** A
  computation that is a work item in the task list (§ the model, 2 and 3). The
  options: a computation shares its reads with the tree, follows the disk, and
  needs no new mechanism, but it computes only while a part reads it and has no
  row of its own; a task has the row, the status and the verbs and goes on while
  the person looks elsewhere, but it must read the folders off the loop, with code
  of its own or with `wait_for_cell!` through the loop, and its result is a
  snapshot. The row of a work item gives the computation what the task had.
- **Q3. The limits.** My recommendation: a depth of 10 and 500 matches, which the
  page names when it stops there.

## Not in this plan

A view of the background works of the editor, each work with its source, its count
of values, its time and its failure, under Editor in the explorer: a plan of its
own, with the session of the background cell, because the editor layer keeps the
works (`BackgroundCells.jl`). The owner agreed on 2026-10-18.

The drawing of a part that is provisional is step 3 of the background cell plan,
landed on 2026-10-18 (`90a82ff91`): a filter or a sort keeps its last final rows
(`make_final_holding_cell`). The page and the row of the search do not hold: a
search shows its matches as they come. A known limit of the counts of rosters,
which this plan does not change: the count of an arranged view counts with
`compute_shown_rows`, so while a key of its filter is still to come, its pill
counts with the defaults while the table keeps its last rows; no view filters by
a value that a task reads today. A search by the content of a file. The other four reads of the
background cell plan.
