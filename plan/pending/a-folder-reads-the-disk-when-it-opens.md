# A folder reads the disk when it opens

The Files tab reads the disk inside computations. A folder is
`@computation(readdir(p))` (`make_filesystem_pathname`,
`source/platform/filesystem/FileSystemDocument.jl:99`), and each entry calls
`isdir` at its first read. A closed row reads the listing of its folder to know
whether to draw a chevron (`_wtree_has_children`,
`source/platform/widget/WidgetToGraphics.jl:11915`). `PAR-PURE-THUNK` forbids a
computation that reads outside state. A folder is read once and never watched.

The same problem is in two places of omnet-julia: the discovery of the INI files
and the result folders of the explorer. Their plan is
`omnet-julia/plan/pending/the-explorer-reads-a-project-when-it-opens.md`, and it
uses steps 1 to 4 of this plan.

## Requirements (the owner, 2026-10-16)

- **R1.** The listing of a folder is lazy and incremental, and it updates by itself.
- **R2.** A folder of thousands of files works.
- **R3.** An empty folder looks empty the first time it appears.

## Decisions

1. **The state is in documents** (the owner, 2026-10-16). A folder holds its
   listing as stored entries, and not as a computation. It also holds its read
   state (`:unread`, `:reading`, `:read`, or `:failed` with the error), and
   whether it is empty (`nothing` while that is not known). A print reads only
   cells.
2. **Operations change the state** (the owner, 2026-10-16). The open of a
   folder acquires it (`AcquireDocumentOperation`). The acquire starts the read
   when the folder is `:unread`, and it starts the watch. The close releases the
   folder: the watch stops, and the entries stay. The read runs on a task. Its
   answer is an apply operation on the editor task, which compares the new
   listing with the entries by name. A kept entry keeps its document, and the
   other entries are inserts and deletes. A change on the disk gives a new read
   of that folder, after a short delay, so that many fast changes give one read.
3. **The empty check covers every sub-folder of an open folder** (the owner,
   2026-10-16). The acquire of a folder also checks whether each sub-folder is
   empty, and watches each sub-folder, up to a limit of watches. Past the limit,
   a sub-folder updates its emptiness at the next read of its parent.
4. **A row shows a chevron only when its document is known to have children.**
   A new generic of the tree slice, `has_tree_children(document)`, gives `true`,
   `false`, or `nothing` while it is not known. By default it reads the children,
   as now. A folder answers from its stored state, so a closed row reads nothing
   from the disk, and an empty folder never shows a chevron.
5. **The first frame** (the owner, 2026-10-16: "the root document and some
   structure can be eagerly created if it's small, no? otherwise, reading marker
   is just fine"). The open starts the read and waits for it a short time. A small
   folder is complete inside the wait. A large folder, or a slow disk, shows the
   reading marker. A disk that hangs never blocks the loop longer than the wait.
6. **The projection only draws, and its reader names operations.** It draws the
   entries, the chevrons of decision 4, a reading row under an open folder that
   has no entries yet, and an error row. Its reader turns a press on a chevron,
   Right, Left and a double press into the open and the close.
7. **The tree and the navigator acquire what they show** (the owner agreed to the
   shared parts, 2026-10-16). The open of a node acquires its document, and the
   close releases it. A visit acquires the new page and releases the old one. The
   acquire of a tree or of a navigator acquires what it shows, as the acquire of a
   tab acquires each layer of the tab (`PaneSurgery.jl:405`).
8. **The selection after an insert** is the kernel plan
   `an-insert-moves-the-paths-after-it.md` (the owner, 2026-10-16).

**My recommendations for the design** (to confirm at the step that needs each):

- **M1.** The Files tab draws through `DocumentTree` over the `Workspace`, so its
  open nodes are keyed by document (`TreeDocument.jl:13`), and not by index paths
  as `FileSystemToWidgetTree` keys them now. An insert above an open folder then
  keeps the right folder open. `FileSystemToWidgetTree` goes.
- **M2. An acquire counts** — decided: a generic count (option A, the owner,
  2026-10-16: "it's A"), not a count in the watch of a folder alone (option B). The
  domain slice keeps one count for each document, for each editor;
  `acquire_document!` runs at the first holder and `release_document!` at the last.
  A folder that is open in the Files tab and also shown as a page stays watched
  until its last release, and so does every other document, such as a terminal.
- **M3.** The kind of an entry comes with its name from one call:
  `Base.Filesystem._readdirx` gives a `DirEntry` with its type, with no `stat`.
  It is internal in Julia 1.13. The read falls back to `readdir` and `isdir` when
  the function is not there.

## Steps

Each step is one commit with its tests, in a worktree. Steps 1 to 4 are the
shared parts, which the plan of omnet-julia also uses.

- [x] **1. The tree and the navigator acquire what they show** (decision 7, M2).
  The reader of `DocumentTreeToWidgetTree` adds an acquire for each node that
  opens and a release for each node that closes. The acquire and the release of a
  `DocumentTree` reach its open nodes. A visit of a navigator acquires its new page
  and releases the old one, and the acquire of a navigator reaches its page. An
  acquire counts. Tests: `test_tree()`, `test_navigator()`, and a test of the count.
  - Done 2026-10-16. The domain slice (`DocumentRelease.jl`) keeps the holders of
    an editor as a session document: `add_document_holder!` and
    `remove_document_holder!` count, and run the hooks at the first and the last
    holder; `AcquireDocumentOperation` and `ReleaseDocumentOperation` call them.
    A holder passes holds on with `hold_documents!`, and the editor records what
    each holder holds, so `release_held_documents!` releases the same documents
    also after the holder shows others. A tab, a pane tree, a `DocumentTree` and a
    `Navigator` are holders.
  - A tree or a navigator changes what it holds by a new operation,
    `ChangeHeldDocumentsOperation(holder, released, acquired)`, which acts only
    while the holder is held. So a tree or a navigator that no tab shows, such as
    the navigator of an explorer whose explorer passes nothing on, holds nothing.
    A chevron answers it inside the same `ReplaceViewStateOperation` as the write
    of the open nodes, and a visit inside the view state of the visit, so undo
    records neither.
  - The acquire, the release and the change are self-contained operations, so
    they go up the readers of the views around a tree.
  - An editor that is not an `Editor`, such as the stand-in of a pane test, counts
    nothing and runs the hooks at each call, as before.
  - The omnet-julia explorer passes no acquire to its tree and its navigator yet;
    step 1 of the plan of omnet-julia does it. Its study passes its acquire to its
    formulas through the hook directly, which still runs at the first holder.
  - Tests: two testsets in `TreeTest.jl` (a tree holds its open nodes only while a
    tab holds it; a document of two holders is released at its last; a navigator
    holds its page and a visit moves the hold). The layering guards, the tree
    (79), the navigator suites, the pane surgery (105), the file change suite (98)
    and the formula suite pass.
- [x] **2. `has_tree_children`** (decision 4). The tree slice declares it, and
  the widget tree draws a chevron from it, so a closed row reads no children.
  Tests: `test_tree()` and the tests of the widget tree.
  - Done 2026-10-16. `WidgetTreeNode` has an optional `has_children`, a function
    with no argument; when a node gives it, the row draws its chevron from it and
    reads no children while it is closed (`_wtree_has_children`). The tree slice
    declares `has_tree_children(document)`; its default reads the children, so a
    plain document keeps its chevron. `DocumentTreeToWidgetTree` gives each node
    `has_children = () -> has_tree_children(document) === true`.
  - Tests: a testset in `WidgetTreeTest.jl` (a closed node with an answer reads
    no children; an open node reads them) and one in `TreeTest.jl` (`true`,
    `false` and `nothing`). The widget tree (46), the tree (82), the reflection
    (28), the system processes (78), the work plan (82), the file system (84) and
    the task views (60) pass.
- [x] **3. The read task with a wait** (decisions 2 and 5): a helper that runs a
  read on a task, waits for it a short time, and answers through
  `run_on_editor_task!` with an apply operation. The step decides the slice that
  holds the helper. Tests: a test of the helper with a fast and a slow read.
  - Done 2026-10-16: `start_document_read!(editor, read, apply; wait)` in
    `DocumentRead.jl` of the domain slice, beside the acquire, because its users
    call it from an acquire. It runs `read()` with `Threads.@spawn` and waits at
    most `DOCUMENT_READ_WAIT` (0.05 s). A read inside the wait is applied at once,
    in the evaluation that started it. A longer read posts `apply(answer)` with
    `post_operation!`, not `run_on_editor_task!`: the post is the thread-safe door
    for a watcher to change what an editor shows, and `run_on_editor_task!` runs
    a code unit on a thread of its own. The answer is the value of the read or the
    exception that it threw, so the apply writes a failure too. An editor that is
    not an `Editor` reads at once on the calling task.
  - Tests: `DocumentReadTest.jl` (7): a fast read, a slow read that the next
    drain applies, a read that throws, and a stand-in editor.
- [ ] **4. The watch of a folder** (decision 3) in the file change slice. A watch
  of a folder for a receiver reports only "this folder changed". An editor has a
  limit of watches. Tests: `test_file_change()`.
- [ ] **5. The documents of the file system** (decisions 1, 2, 3, M3). The stored
  entries, the read state, the emptiness, the acquire and the release, and the
  apply operations. Tests in a folder of the test:
  - nothing is read before the acquire (R1);
  - a new file is one insert, and a kept entry keeps its document (R1);
  - a file that a test writes appears after a drain (R1);
  - a folder of 5,000 files is one read, and a frame draws only the rows on the
    screen (R2);
  - an empty sub-folder shows no chevron in its first frame (R3).
- [ ] **6. The Files tab on `DocumentTree`** (M1, decision 6).
  `FileSystemToWidgetTree` goes. Tests: the tests of the file system views, and
  `test_ide_file_navigator()` of omnet-julia.
- [ ] **7. The documents:** `filesystem.md`, `filechange.md`, `tree.md`,
  `navigator.md`, and the acquire in `domain.md`.
