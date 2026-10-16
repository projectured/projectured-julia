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
- **M2.** An acquire counts. A folder that is open in the Files tab and also shown
  as a page stays watched until its last release.
- **M3.** The kind of an entry comes with its name from one call:
  `Base.Filesystem._readdirx` gives a `DirEntry` with its type, with no `stat`.
  It is internal in Julia 1.13. The read falls back to `readdir` and `isdir` when
  the function is not there.

## Steps

Each step is one commit with its tests, in a worktree. Steps 1 to 4 are the
shared parts, which the plan of omnet-julia also uses.

- [ ] **1. The tree and the navigator acquire what they show** (decision 7, M2).
  The reader of `DocumentTreeToWidgetTree` adds an acquire for each node that
  opens and a release for each node that closes. The acquire and the release of a
  `DocumentTree` reach its open nodes. A visit of a navigator acquires its new page
  and releases the old one, and the acquire of a navigator reaches its page. An
  acquire counts. Tests: `test_tree()`, `test_navigator()`, and a test of the count.
- [ ] **2. `has_tree_children`** (decision 4). The tree slice declares it, and
  the widget tree draws a chevron from it, so a closed row reads no children.
  Tests: `test_tree()` and the tests of the widget tree.
- [ ] **3. The read task with a wait** (decisions 2 and 5): a helper that runs a
  read on a task, waits for it a short time, and answers through
  `run_on_editor_task!` with an apply operation. The step decides the slice that
  holds the helper. Tests: a test of the helper with a fast and a slow read.
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
