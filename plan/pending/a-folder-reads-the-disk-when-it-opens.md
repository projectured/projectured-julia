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

- **M1. The documents of the Files tab and the Open dialog** — decided with the
  owner, 2026-10-16 (option 2). One listing of a folder is shared, and each
  explorer keeps its own open folders, so two explorers of one workspace can show
  different open folders over the same read:

  ```julia
  project   = FileSystemDirectory(pathname = "/home/p/project", state = :read,
                                  entries = [src, test, build, readme], has_entries = true)
  workspace = Workspace(folders = [WorkspaceFolder("project", "/home/p/project", project)])

  left    = WorkspaceExplorer(workspace = workspace, open = {project, src})
  right   = WorkspaceExplorer(workspace = workspace, open = {project, test})
  chooser = FileSystemChooser(directory = project, open = {project}, name = "")
  ```

  - A folder document holds only what the disk held: its listing, its read state
    and whether it is empty. The open state is not in it, unlike `collapsed` of a
    JSON node, because two views of a shared folder must differ (the owner).
  - The Files tab shows a `WorkspaceExplorer`, and the Open dialog shows a
    `FileSystemChooser`; the two differ only in what is around the folders. A
    duplicate of a tab makes a new `WorkspaceExplorer` with a copy of the open set,
    and shares the `Workspace`: it owns what the person controls, and shares what
    it reads.
  - An explorer holds the folders that are open in it. A folder that is open in
    two explorers has two holders and is read once.
  - What a press on a file does is not in these documents. The row of a file
    answers `OpenFileOperation(path)`, and the document around the tree decides:
    the Files tab opens the file, the chooser writes the name, and any other
    holder gives it its own meaning.
  - The drawing stage (a tree view of the file system, or `DocumentTree`) is
    decided at step 6.
- **M1a. Three more decisions** (the owner, 2026-10-16: "agreed"):
  - `WorkspaceFolder` holds its folder document, made unread with the folder, so
    a document holds what was read;
  - `make_filesystem_pathname(path)` makes an unread folder, and
    `read_filesystem_folder!(folder; depth)` reads at once on the calling task,
    for scripts, examples and tests, never in a print; the `filesystem` example
    reads its fixture so its output stays the same;
  - the text view of a folder draws only what the folders hold, a folder that is
    not read shows a reading marker, and it holds nothing more than its tab.
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
- [x] **4. The watch of a folder** (decision 3) in the file change slice. A watch
  of a folder for a receiver reports only "this folder changed". An editor has a
  limit of watches. Tests: `test_file_change()`.
  - Done 2026-10-16. `watch_folder!(path; store, receiver) -> Bool`,
    `unwatch_folder!` and `is_folder_watched` in `FileChangeStore.jl`. The store
    holds a `WatchedFolder` for each receiver, and a folder shares one watcher
    with its watched files and its other receivers; the watcher stops when nothing
    watches the folder. An event of the folder, or in poll mode a new time of the
    folder, marks it in `changed_folders`, and the drain calls the new generic
    `receive_folder_change!(editor, receiver, folder) -> Bool` on the editor task.
    The watcher reads nothing of the folder.
  - The limit is of the store, `watch_limit` (by default `FOLDER_WATCH_LIMIT`,
    1000): a watch of a folder starts no new watcher past it and answers `false`;
    a folder that is watched already costs nothing, and a file that a tab shows is
    watched past the limit. A coalesce of fast changes is the receiver's: the
    changes of one folder before a drain are one report.
  - Tests: two testsets in `FileChangeStoreTest.jl` (a change reaches each
    receiver, a shared watcher stops with its last receiver; the limit). The file
    change suite (115) passes.
- [x] **5. The documents of the file system** (decisions 1, 2, 3, M1, M1a, M3).
  The stored entries, the read state, the emptiness, the acquire and the release,
  and the apply operations; `WorkspaceFolder` with its folder,
  `WorkspaceExplorer` and the open set of `FileSystemChooser`;
  `read_filesystem_folder!`. Tests in a folder of the test:
  - nothing is read before the acquire (R1);
  - a new file is one insert, and a kept entry keeps its document (R1);
  - a file that a test writes appears after a drain (R1);
  - a folder of 5,000 files is one read, and a frame draws only the rows on the
    screen (R2);
  - an empty sub-folder shows no chevron in its first frame (R3).
  - Done 2026-10-16 (it lands with step 6, because the views of the file system
    read the new documents). `FileSystemDirectory` holds `elements` (stored, in
    the order of the names), `state`, `failure`, `has_entries` and `read_count`;
    `has_folder_entries(folder)` answers from the entries of a read folder, else
    from `has_entries`. The acquire watches the folder and its sub-folders (the
    sub-folders for their emptiness, with the folder as the receiver) and reads it
    with `start_document_read!`; a read lists the names with their kinds
    (`Base.Filesystem._readdirx`) and checks each sub-folder with one `readdir`.
    `ApplyFolderListingOperation` walks the entries and the listing by name: a
    kept entry keeps its document, and each run of gone and new entries is one
    splice of `elements`, a `ReplaceReferencedValueOperation` on a range, so the
    plan of the splices can move the paths. The answer of an older read is dropped
    by `read_count`. A change of the folder reads it again, and a change of a
    sub-folder checks its emptiness (`ApplyFolderEmptinessOperation`). Both
    operations go in a `ReplaceViewStateOperation`, so undo records no read.
  - `WorkspaceFolder(name, pathname)` makes its `directory`; a file keeps the name
    and the place only. `WorkspaceExplorer(workspace)` holds `open`, the folders of
    the workspace at the start, and holds its open folders; its duplicate shares
    the workspace. `FileSystemChooser(directory)` holds `open`, the directory at
    the start. `read_filesystem_folder!(folder; depth)` reads at once, and the two
    examples of the file system read their fixture with it.
  - The file system slice uses the file change slice (a new edge), whose store of
    an editor is public: `find_file_change_store(editor)`.
  - A known cost: the empty check of a sub-folder reads its whole listing.
  - Tests: `FileSystemDocumentTest.jl` (33): unread at the start; the acquire
    reads names, kinds and emptiness; a new file is one entry more and kept entries
    keep their documents; a sub-folder that gets an entry says so; the release
    keeps the entries; a read at once to a depth; two explorers share one read; a
    folder that can not be read fails; 5,000 files are one read. The guards and
    the file change suite (115) pass.

- [x] **6. The views of the Files tab, the Open dialog and the text view** (M1,
  M1a, decision 6). The drawing stage reads the open set of the explorer and what
  the folders hold; the step decides whether that is a tree view of the file
  system or `DocumentTree`. Tests: the tests of the file system views, and
  `test_ide_file_navigator()` of omnet-julia.
  - Work 2026-10-16 (it lands with step 5). The drawing stage stays a tree view
    of the file system, `FileSystemToWidgetTree`, and not `DocumentTree`, because
    the open folders are in the explorer, which `DocumentTree` would hold a second
    time. Its input is a `WorkspaceExplorer`: a root for each folder of the
    workspace, named as the folder; the open nodes come from `open` of the
    explorer, by document; a chevron answers the write of `open` and a
    `ChangeHeldDocumentsOperation`, in one `ReplaceViewStateOperation`. A row is
    the path `workspace.folders[k].directory.elements[a]…` of the explorer, both
    ways. A bare folder keeps the view of before, with its root open.
  - The nodes read only what the folders hold: a folder has a chevron when it is
    known to hold entries, or while it reads; an open folder with no entries yet
    shows a row "reading", and one that can not be read a row "can not read: …".
    The text view puts " …" or " (can not read)" after the name of such a folder.
  - A row of the renderer for `WorkspaceExplorer` comes before the row of
    `WorkspaceDocument`, in the slice and in the application. The `explorer`
    insertion, the Explorer tool of the window and the Files pane of the
    application make a `WorkspaceExplorer`; omnet-julia's IDE too, on its branch
    `folder-reads-on-open`. A `WorkspaceFolder` always holds a folder document, also
    for a path where nothing is yet.
  - The file action stays a parameter of the view (`open_file`), so each user of
    the tree passes its own.
  - The SDL render test checks R2 in the view: only the rows that the pane draws
    build their nodes. It also gets its size by an offer, which fixes its known
    error on main (`WidgetTree` has no field `size`).
  - The windows of the application test run no window start, so the test reads
    the Files pane of each window at once (`_app_make_window`).
  - Tests: the file system suite (116), the window shell (138), the file dialogs
    (14), the application (380, 2 broken, as on main), the SDL render test (8),
    and the omnet-julia IDE tests with the baselines of main (the file navigator
    27/1, the window wrap 49, select and paste 47/1/8). The sweeps of the three
    examples of the file system fail only at a type-in into a `pathname`, as on
    main; there are more such places, because a workspace folder holds its folder
    tree (`files`: 3771 against 294 on main) and the folders hold more fields.

- [x] **6b. The Open dialog draws and works** (the owner, 2026-10-16: "agreed, B":
  a step of its own after the Files tab lands). The view of a `FileSystemChooser`
  is unfinished: it is not registered with the renderer, its reader drops every
  press, and it builds the action that writes the name and never uses it; no test
  draws the dialog. The step: the view draws the tree of the folders from the open
  folders of the chooser, with the rows, the chevrons and the reading row of the
  Files tab, and the name field under it; a chevron opens or closes a folder and
  changes what the chooser holds; a press on a file writes its name. Tests: a
  dialog drawn in an editor, a chevron that opens a folder that then reads, and a
  press on a file that writes `name`.
  - Done 2026-10-16. `FileSystemChooserToWidget` draws a `GridLayout` of one
    column, the tree over the field, with the rows `[Fill, Content]`: the tree is
    built as the tree of an explorer, from `open` of the chooser, with the file
    action `WriteChosenNameOperation`; the field is a `WidgetText` whose content
    is the name of the chooser. The paths map `children[1].roots[1].children[a]…`
    to `directory.elements[a]…` and `children[2].content<rest>` to
    `name<rest>`, so a key in the field edits `name`. A chevron answers the write
    of `open` and the change of the holds. The renderer takes the view through
    `make_graphics_projection(::Type{<:FileSystemChooser})`, chained with
    `GridLayoutToGraphicsCanvas`, so the tree and the field draw as widgets. The
    file system slice uses the layout slice (a new edge).
  - The docstring of the chooser said that a folder row sets `directory`; no
    code did, and this step builds no such row, so the docstring says what is.
  - The first read of a session can take longer than the wait, because its code
    compiles at that call; the test waits for the read, and a person sees the
    reading row for that moment.
  - Tests: a testset in `FileDialogTest.jl` (22 with the others): the dialog draws
    its folder; a double press on a file writes the name; a chevron opens a folder
    that then reads; a key in the field edits the name. The file system suite
    (116), the window shell (138) and the guards pass.

- [ ] **7. The documents:** `filesystem.md`, `filechange.md`, `tree.md`,
  `navigator.md`, and the acquire in `domain.md`.
