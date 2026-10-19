# The search below a node reads the folders that it needs

Status: DONE, 2026-10-19. The owner decided Q1 to Q3 and asked for the
implementation ("Yes to the others"). It builds on steps 1 and 2 of
[a-value-that-a-task-reads-is-a-cell.md](../done/a-value-that-a-task-reads-is-a-cell.md)
(projectured main `33a957cca` and `7c2f4d2c9`). Step 1 landed on main
(`a535e62c9`); steps 2 and 3 are done on branch `explorer`.

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
   `ExplorerSearch(place, text; depth = 10, limit = 100)` holds the node to search below, the
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

1. [x] **The listing of a folder is a background cell** (the filesystem slice).
   The read on the acquire goes; the watch stays with the holders. Tests:
   `test_filesystem()`, `test_explorer()`, the tests of the Files tab in
   `test_application()`, and a test that a closed folder in view reads nothing.
   Done; what was built is in § Step 1 as built.
2. [x] **The search** (the explorer slice, and the task slice for its row):
   `ExplorerSearch`, the match cell of each folder, its page, Return in the
   filter, the limits, its row in the task list with its status, the stop, and
   the verbs. Tests: `test_explorer()`, with a folder of 3 levels that nobody
   opened; a search whose row stays in view after a visit to another page goes
   on, and a stop reads nothing more; `test_task_verbs()` and `test_task_views()`
   with a search in the list. Done; what was built is in § Step 2 as built.
3. [x] **The guides:** `filesystem.md`, `explorer.md`, and also `tree.md`,
   `task.md`, `editor.md` (the keywords `working` and `apply`) and
   `devices-and-backends.md` (the headless backend paints); the plan moves to
   `plan/done/`.

## Step 1 as built

- **The entries stay stored, and an answer splices them** (design (c), the owner
  agreed on 2026-10-18). The answer of a read is `ApplyFolderListingOperation`, as
  before, which keeps the document of each entry that stays, by name. The model
  of § 1 computed the entries from the listing, but a computed vector gives no
  splice, and decision 1 of
  [an-insert-moves-the-paths-after-it.md](../pending/an-insert-moves-the-paths-after-it.md)
  moves the paths in the evaluation of a splice. So the listing cell only carries
  the demand, and no part that shows reads its value.
- **Two keywords of `make_background_cell`** (kernel, `ad4c05d05`, with the consent
  of the session of the background cell). `working` is a `Cell{Bool}` that the
  editor sets at the start of a work and clears when it writes the answer.
  `apply(inputs, value)` answers an operation that the editor evaluates after it
  writes the answer; a failure passes its exception. A folder gives its `reading`
  cell and `ApplyFolderListingOperation`.
- **A tree generic, `demand_tree_children(document)`** (the tree slice; the default
  does nothing). A part that shows the children of a node calls it: the entries of
  an open node, the rows of the Files tab, the table of the page of a folder, and
  the search. The quick filter and the chevrons do not call it, because the tree
  reads `get_tree_children_steps` of every row in view. A folder reads its listing
  cell.
- **The stamp** is `read_count`, the second input of the listing. A change that the
  watch reports on the folder itself adds one, so the next demand reads again.
- **The root of a workspace** has an unknown emptiness, and its chevron shows while
  it is unknown (`has_tree_children(::WorkspaceFolder)`), so the person can open it.
- **The decoration** says that a folder reads while `reading` is true. It is stored
  state and records no demand.
- **The headless backend paints in the frame** (option (A), the owner agreed on
  2026-10-18). In the tests of the explorer, 327 of 328 reads of a listing ran with
  no editor in scope: `HeadlessBackend` stored the output and read none of it, so
  only a later read of the test, outside the frame, asked for a listing. Now
  `write_to_devices!` reads each part of the output, as a real backend does: in
  paint order, each part once, with no part that throws a fault, and at most 200
  new links of a lazy list in one paint.
- **A defect that the paint found, fixed: the offset of a line of a text.** The
  offset of each line was a cell that read the offset of the line above. So the
  first read of the size of a text of about 4,000 lines went down a chain of 4,000
  cells and overflowed the stack, also with no paint. A tabbed pane that has no
  slot measures its page so (`test_open_page_operation`, `window = false`). The
  offset now adds the sums of aligned blocks of lines (`get_distance_sum`), so a
  read goes log2 of the line count deep and still reads only the lines above.

## Step 2 as built

- **The task slice** (`3b739ca1b`): `TaskWorkItem.jl` declares
  `get_work_item_identifier`, `describe_work_item_kind`, `stop_work_item!` and
  `describe_work_item`, and a group answers them. `collect_work_items(list)` gives
  the open items. The first column of the Tasks pane is "item", because it holds
  `T3` and `S1`. For a group, the count of running items reads its status only, as
  before, so the heading and the badge depend on the same cells.
- **The explorer slice comes after the task slice** in `ProjecturedPlatform.jl`,
  and its row in `PLATFORM_SLICE_EDGES` has "task".
- **The search** (`715583bc6`): the steps are a plain value (`steps::Any`),
  because the `@document` macro makes a field declared `Vector{Any}` a
  `CellVector`. A search is walk-opaque, because it holds the root section again.
  `collect_tree_children` gets `list_limit`, so a search reads every child of a
  collection and only the head of a lazy list. The page says "No match yet." while
  the result is provisional.
- **An operation with no reference must say that it carries its subject.**
  `StartExplorerSearchOperation` answers `is_self_contained_operation`; without
  it, the default reader of a step of the root chain drops it, and Return did
  nothing, with no fault.
- **A visit opens the node of its page** through `make_tree_reveal_operation`, a
  new function of the tree slice: it writes the open places as a chevron does and
  holds the documents of the nodes that open.
- **A search waits while nothing shows it**: a test shows that a folder below
  stays unread while neither the page nor a row of the search shows, and that the
  search ends when its row under the node of the tasks shows.
- **A known limit:** the search does not watch the folders that it reads, so a
  later change on disk reaches its result only through a holder of the folder,
  such as an open node of the tree.

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
- **Q3. The limits. Decided (the owner, 2026-10-18): a depth of 10 and 100
  matches by default**, which the page names when it stops there.
- **Q4. How does the task list hold a search? Decided (the owner, 2026-10-19:
  "yes I agree").** The task list, its rows and its verbs took only a group of
  tasks, and the explorer slice was included before the task slice. Option (a):
  the task slice gets a small interface of a work item, and the explorer slice
  comes after the task slice and answers it for the search. The options that
  were not taken: (b) a search as a group of one task, which runs no task; (c) a
  list of searches in the explorer, against Q2.

## Step 2, the design

- **The work item of the task list** (task slice, `TaskWorkItem.jl`). The list
  holds a group, a closed group, or any other work item. A work item answers
  `get_work_item_identifier` (`T3`, `S1`), `describe_work_item_kind(item, count)`
  ("1 search", "2 searches"), `stop_work_item!` and `describe_work_item(item;
  limit)`. Its state and its line come from its decoration
  (`get_document_decoration`, `work_item = true`), so the interface needs no
  word of state. A group answers the interface too. `add_task_group!`,
  `remove_task_group!` and `find_navigator_address` of the list take any work
  item. The Tasks pane draws a row for each open item: its identifier, its title
  as a link to its page, its kind, its state and its line from the decoration,
  and Stop and Close. The heading counts each kind: "2 groups · 1 search · 1
  running", and a list of groups only reads as before. `list_task_groups`,
  `find_task_group`, `describe_task_group`, `stop_tasks!` and
  `close_task_group!` take any work item.
- **Stop keeps the row** (this refines § the model, 3, which said that Stop takes
  the row out). For a group, Stop and Close are two buttons and two verbs, and a
  search follows them: Stop keeps the matches that the search found, and the
  search reads nothing more; Close takes the row out and leaves a closed row, as
  for a group.
- **The search** (explorer slice): `ExplorerSearch` holds the root section of the
  explorer, the steps from it to the node, the text, the limits, its identifier
  (`S1`, `S2`, … in the order of the searches of the list of the session), the
  time of its start, and whether it stopped. Its result is a cell for each node
  below the node, in a tree of entries that the walk makes, as the tree of a
  `DocumentTree` makes its entries. The cell of a node reads a cell that asks for
  the children (`demand_tree_children`), so the node waits while that cell is
  provisional, and the count of the nodes that wait is the count of those cells.
  A node on the path to itself is not entered again. A lazy list of children is
  read for its first `limit` nodes.
- **Return in the filter** answers `StartExplorerSearchOperation(explorer, text)`:
  the node is that of the page of the navigator, or the root. Its evaluation
  makes the search, adds it to the list of the session, and shows its page in
  the navigator; the caret stays in the field. It is no edit, so undo records
  none.
- **A press on a match** answers `OpenPageOperation(root, address)`. The explorer
  opens the rows above the page that a visit of its navigator shows, when the
  page is below its root section. So a link on any page in the explorer shows its
  node in the tree, and a match does too.

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
