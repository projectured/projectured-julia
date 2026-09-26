# The Explorer reads only what it shows

> **Status:** in progress, in the worktree `projectured-julia-explorer-lazy` on
> the branch `explorer-reads-only-what-it-shows`, from `6a511ab0`. Written
> 2026-09-26. The owner approved the plan and the three contract changes on
> 2026-09-26. The owner asked: "the
> workspace file explorer seems to be non-lazy, if there are many files in the
> worskpace recursively it gets slow. The explorer should be open with only the
> first level expanded and all other levels collapsed, this would immiately make
> it faster a bit, but we should also make it more lazy if possible." The owner
> chose A1 and B of the options, and said: "empty folders should not show a
> chevron". About C the owner said: "option C should be driven by the printer of
> the projections from the backend side when it actually draws the graphics on
> the screen, it already has a limit for not drawing what's outside the screen,
> that should end up not computing and reading folders and files which would
> result in graphics outside the screen".

## 1. The problem

When the Explorer opens on a folder, it does the work below for each entry under
that folder, at every depth. On this repository that is 27,986 entries in 3,092
folders. 19,377 of them are in `build/` and 6,082 are in `.git/`.

1. `make_filesystem_pathname` (`source/filesystem/FileSystemDocument.jl`) reads
   the whole tree: one `readdir` for each folder, one `isdir` for each entry,
   and one document for each entry.
2. `_fs_node` (`source/filesystem/FileSystemToWidget.jl`) makes one
   `WidgetTreeNode` for each entry, and two `GestureBinding` closures for each
   file.
3. The geometry cell of `WidgetTreeToGraphicsCanvas`
   (`source/widget/WidgetToGraphics.jl`) measures the label of every row. The
   `collapsed` set starts empty, so every row is open.
4. The elements cell makes about three graphics elements for each row.
5. The tree canvas has `layout_none`, so `_render_canvas!` (`source/sdl/Sdl.jl`)
   draws every element on each redraw, a hover redraw too.
6. Each scroll event calls `_scroll_room`, which calls `get_graphics_size` on
   the tree. That is a walk over every element, and it measures every text.

The Open and Save As dialogs (`make_file_dialog` in `source/shell/FileDialog.jl`)
do step 1 for the whole tree below the folder that they open in.

## 2. What a professional tree does

The references are the Swing `JTree` with a large model
(`FixedHeightLayoutCache`), the Qt `QTreeView` over a `QFileSystemModel`, and
the explorer of VS Code.

- **R1.** A folder is read when it opens, not before. Qt calls `fetchMore` on
  an expand. VS Code resolves a folder on an expand.
- **R2.** The view keeps the set of open nodes. A node is closed until
  something opens it. The owner of the view opens the nodes that it wants at the
  start. VS Code opens the root.
- **R3.** The view draws only the rows in the viewport. All rows have one
  height, so the row at a given y is arithmetic, and the extent is the row count
  times the row height.
- **R4.** The view does not measure a row that it does not draw. VS Code has no
  horizontal scroll by default. With horizontal scroll on, and in `JTree` with a
  large model, the width comes from the rows that are drawn.
- **R5.** A folder that the view can not read is an empty folder. It is not a
  failure of the view.

## 3. The model

### 3.1 A folder is read at its first read (B)

`FileSystemDirectory.elements` is a computed `CellVector`. Its computation calls
`readdir` once and answers one cell for each name. Each of these cells is also
computed at its first read, and it calls `make_filesystem_pathname` on its path.
That call is one `isdir`, and it makes a `FileSystemFile` or a
`FileSystemDirectory` whose own `elements` are again not read.

So the costs are these:

| Read | Disk access |
| --- | --- |
| the length of a listing | one `readdir` of that folder |
| entry `i` of a listing | one `isdir` of that entry |
| the elements of entry `i` | one `readdir` of that entry |

- A `readdir` that fails, because of a permission or because the folder is gone,
  answers an empty listing (R5).
- Nothing reads a folder again. A folder is a snapshot from its first read. To
  read it again, assign the path of the workspace folder, as before.
- A symlink that loops costs one level for each open, not a recursion without
  an end.

### 3.2 A tree node is closed until it is opened (A1)

`WidgetTree.collapsed::Set{Vector{Int}}` becomes `expanded::Set{Vector{Int}}`.
A node is closed unless its path is in `expanded`. `WidgetAccordion` already
names its open state `expanded`.

- A click on a chevron toggles the path in `expanded`. The write stays view
  state, so a history does not record it.
- `FileSystemToWidgetTree` starts with `expanded = {[1]}`. The root row is open,
  and each entry under it is closed. The file dialogs go through the same
  projection, so they start the same way.
- `ReflectionToWidget` starts with the paths that it opens: each node with
  children that is not an unsynced document. Now it computes the opposite set.
- Each other caller that shows children names the nodes that it opens.
- A duplicate of the Explorer opens with only the first level open.

### 3.3 The children of a node are read only when they are needed

`WidgetTreeNode.children` is a `Vector` now, and the walk calls `isempty` on it
to decide the chevron. The field accepts a `Vector` or a computed `CellVector`.
The tree reads it only in two cases:

- The row of the node is drawn. Then the tree reads the length, and a node with
  no children has no chevron. For a folder this is one `readdir`. This is the
  only read ahead, and it happens only for a drawn row.
- The node is open. Then the tree reads the length and the children.

`_fs_node` of a folder answers a node whose children are a computed `CellVector`
over the listing of the folder, with one computed cell for each entry. The user
can open only a folder that shows a chevron. A folder shows a chevron only after
its listing was read. So an open folder always has a listing that was read
already.

### 3.4 The backend draws, and so computes, only the rows in the viewport (C)

The renderer already stops early. On a canvas with `layout_vertical` and
`overlapping_elements = false`, `_render_canvas!` stops at the first element
below the bottom edge of the clip. The text view uses this: its line stack
(`source/text/TextToGraphics.jl`) is a `CellVector` of line canvases, which it
makes "without forcing them", and the content of a line is a cell that is read
only when the line is drawn.

The limit has two gaps:

- **The top edge.** The renderer draws each element above the top edge of the
  clip, and SDL clips it. To draw it, the renderer reads its content. The
  renderer gets the right and the bottom edge of the clip, but not the top and
  the left edge.
- **The size query.** `get_graphics_size` and the dirty bounds walk every element
  of a canvas, and they measure every text.

The change to the backend:

1. `_render_canvas!` gets the whole clip rectangle as a `_ClipEdges`. On a
   `CellVector` canvas with a layout and elements that do not overlap, it starts
   at `compute_first_visible_index`: a binary search on `y` for the last element
   that starts at or before the top edge. The elements before it end before the
   top edge, so the renderer does not read their content. The backward walk of
   a `ListNode` stops at the top edge of the clip, not at the top of the window.
   The forward walk of a `ListNode` from a head above the viewport stays as it
   is, because the tree does not use a `ListNode`.
2. `_collect_canvas_dirty!` and `hit_element_at` use the same rule. The dirty
   walk must read the same cells that the renderer reads. *Found while the
   proposal was written:* now the two walks differ. For a nested canvas at
   `cy > 0`, the renderer passes the bottom edge unchanged, and the dirty walk
   passes `vh - cy`, so the dirty walk stops `cy` pixels earlier. The change
   passes the same `_ClipEdges` in both.
3. A canvas with a layout, elements that do not overlap, and `w > 0` and `h > 0`
   declares its extent. `get_graphics_size`, the dirty bounds and `_scroll_room`
   take that box and do not walk the elements. The scroll pane already clamps
   with `content.h` in `_pane_scroll_y`, so `_scroll_room` then agrees with it.

The change to the tree:

1. The rows are one `CellVector` of row canvases, in the order of the open tree,
   on a canvas with `layout_vertical` and `overlapping_elements = false`. This
   follows the line stack of the text view.
2. The vector is made from `expanded` and from the listings of the open folders.
   It does not call `isdir`, it does not measure, and it does not draw.
3. A row canvas has a `y` that is arithmetic: its index times the row height.
   Its content is a computed `CellVector` that the renderer reads only when it
   draws the row: the chevron, the icon, the label, and the selection band and
   the hover band of that row. A row canvas is kept for its path, so a toggle
   does not measure the drawn rows again.
4. The tree declares its extent: the row count times the row height.
5. A press finds its row by arithmetic: `(y - content_y) ÷ row_height + 1`. The
   arrow keys move the index by one. Neither reads a row outside the viewport.

After the change, the disk access is as follows:

| Action | Disk access |
| --- | --- |
| open the Explorer | one `readdir` of the root, then for each drawn row one `isdir`, and one `readdir` more if the row is a folder |
| open a folder | nothing new for the folder, because its listing was read for its chevron; then the drawn rows, as above |
| scroll | the rows that come into view, as above |
| close a folder | nothing |

### 3.5 Why the rows are not a `ListNode`

The list form of `WidgetTable` (`source/widget/WidgetTableList.jl`) puts its rows
in a `ListNode`. The tree does not, for three reasons:

- A `ListNode` canvas has no extent (`is_infinite_canvas`), so the scroll pane can
  not clamp it or give its scroll bar a length. The tree has an end and a known
  row count.
- A `ListNode` gives the row at an index only by a walk. A press and the arrow
  keys need the row at an index.
- The vector holds one cell for each row of the open tree, and each cell is
  cheap. `QTreeView` holds the same (`viewItems`), and so does the list of VS
  Code.

## 4. Decisions

- **D1 (owner).** A1: the set of open nodes replaces the set of closed nodes.
- **D2 (owner).** B, with a computed cell. The direction of the owner for C
  needs a pull. The renderer can pull a computed cell. It can not pull an
  explicit operation.
- **D3 (owner).** An empty folder shows no chevron. So a drawn folder row reads
  its listing once.
- **D4 (owner).** C is driven by the backend when it draws the screen.
- **D5 (plan).** No `Base.Filesystem._readdirx`. It gives the entry types without
  a `stat`, but it is internal to Base in Julia 1.13. The type of an entry comes
  from `isdir`, and only for a drawn row.
- **D6 (plan).** The rows are a `CellVector` of lazy row canvases, as in 3.5.
- **D7 (plan).** The sentence of `filesystem.md` "A computed cell must not read
  the disk as a side effect of a print" changes to: a folder is read once, at
  its first read, and nothing watches it.
- **D8 (plan).** `CellVector(@computation(keys); element)` computes one slot for
  each key, and a slot computes `element(key)` at its first read. The listing
  of a folder and the children of a tree node use it. `CellVector(@computation
  expr)` can not do this: it wraps each value in a new cell, and `Cell(x)` of a
  cell holds the cell as a value. A 2-argument `CellVector(a, b)` goes to the
  inner constructor of the struct, so `element` is a keyword.
- **D9 (plan).** The names: `compute_first_visible_index` (a search that always
  answers an index), `has_declared_extent`, and the private `_ClipEdges`,
  `_compute_first_drawn_index` and `_read_folder_names`.

## 5. Open questions

- **Q1. The width of the tree.** The extent across needs the width of every
  label, and a label of a row outside the viewport must not be measured (R4).
  Also, the label of a row comes from its node, and the node is one `isdir`.
  - (a) The tree takes the width that the pane offers. A label that does not
    fit is clipped. There is no horizontal scroll. This is the default of VS
    Code, and the list form of `WidgetTable` does the same for its columns.
  - (b) The width of the widest row that was drawn. This is `JTree` with a large
    model. The renderer must report what it drew back to the tree, and that is a
    new mechanism.
  - (c) The width of the widest row of the open tree. This measures and reads
    every entry of every open folder. It breaks the rule of the owner.

  *Answer (owner, 2026-09-26):* (a), "clip is ok".
- **Q2. The selection in a folder that closes.** `JTree` and VS Code move the
  selection to the folder. *Answer (owner, 2026-09-26):* "not now". The
  selection stays where it is, and the band of a row that does not show is not
  drawn. Section 8 holds it.

## 6. Steps

Do the work in a worktree. Commit after each step. Take a baseline on `main`
before step 1: `test_filesystem()`, `WidgetTreeTest.jl`,
`ReflectionToWidgetTest.jl`, `test_graphics()`, and the text-to-graphics and SDL
render tests that step 4 touches.

- [x] **Step 0. The baseline.** `test_filesystem()`, `test_substrate()` and
  `test_sdl()` on `6a511ab0`, in the worktree before any change.
  *Result:* file system 54 pass. Substrate 85,078 pass, 3 fail, 2 errors, 1
  broken; the 5 faults are all in `SplitPaneDragTest.jl` (lines 83, 85, 118,
  136 and 137). SDL 690 pass.

A test checks laziness with `is_cell_up_to_date`: a listing that nothing read
is not up to date. A test does not measure time. A time measurement needs the
approval of the owner and an idle machine.

- [x] **Step 1. A folder is read at its first read (3.1).** Add the form of D8
  to `CellVector`. Find out first if the `@document` constructor of
  `FileSystemDirectory` takes a computed `CellVector`. Test: `make_filesystem_pathname` on the fixture reads no listing
  below the root. A folder without read permission gives an empty listing.
  `FileSystemToSyntax` still prints the whole fixture.
  *Done.* The positional constructor of `FileSystemDirectory` takes the
  computed `CellVector` as it is. `test_filesystem_document()` in
  `test/filesystem/document/FileSystemDocumentTest.jl` checks the reads, a
  folder without permission and a folder that is gone. `test_filesystem()`: 67
  pass (54 before, and 13 new).
- [x] **Step 2. Nodes are closed until they are opened (3.2).** `expanded`
  replaces `collapsed` in `WidgetTree`, in its reader, in its printer and in
  each caller. Find out if a new path of the workspace folder prints a new
  `WidgetTree`. If it does not, set `expanded` back to `{[1]}` when the root
  changes. Test: the Explorer on the fixture shows the root row and its entries,
  and nothing below them. A click on a chevron opens the folder and closes it
  again.
  *Done.* The keyword constructor of `WidgetTree` takes `expanded`. The
  reader of `ReflectionToWidget` reads a write of `expanded`, and a toggled path
  that is in the new set opens its node. The two trees of
  `WidgetDocumentExample.jl` and the tree of `WidgetIconTest.jl` name the nodes
  that they open, so they look as before. The file system, WidgetTree,
  ReflectionToWidget, icon and gesture tests pass. *For the landing:*
  omnet-julia `test/presentation/WatchExampleTest.jl` writes the tree's
  `collapsed` and must write `expanded`.
- [x] **Step 3. The children are read only when they are needed (3.3).** Test:
  after a print of the Explorer on the fixture, only the listings of the root
  and of the folders under the root are read. An empty folder has no chevron.
  After this step, the tree still draws every row of the open tree.
  *Done.* `_fs_node` gives a folder the children
  `CellVector(@computation(1:length(d.elements)); element = …)`. The test is in
  `FileSystemToWidgetTest.jl`. File system 78 pass. Substrate 85,080 pass, with
  the same 5 faults of `SplitPaneDragTest.jl` and 1 broken as the baseline; the
  2 more passes are the new WidgetTree test of step 2.
- [ ] **Step 4. The renderer skips what is above the top edge (3.4, backend 1
  and 2).** Test: a vertical canvas of 1,000 lazy rows in a viewport of 10 rows,
  scrolled to the middle. After a render with the offscreen renderer, only the
  rows in the viewport have their content up to date. The same for the dirty
  walk and for `hit_element_at`. Compare the text, graphics and SDL suites with
  the baseline.
- [ ] **Step 5. A laid-out canvas declares its extent (3.4, backend 3).** Test:
  the scroll room of that canvas reads no row. Compare the widget suites with the
  baseline.
- [ ] **Step 6. The tree draws its rows lazily (3.4, tree).** The tree takes
  the width that the pane offers (Q1). Test: the Explorer over a fixture folder
  with 1,000 entries, in a pane of 10 rows. After a render, only the entries in the viewport are read, and
  among them only the folders read a listing. A press and the arrow keys select
  the correct row. Selection and hover bands are drawn on the correct row.
- [ ] **Step 7. Check it in the live editor.** Open the Explorer on this
  repository with `DISPLAY=:0`. Open `build/`, scroll to its end, and close it.
  Count the listings that were read.
- [ ] **Step 8. Documents.** Update `filesystem.md` (the tree, the duplicate,
  D7, the limits), `widget.md` (`expanded`, the lazy children), and
  `graphics.md` (the two edges of the limit, the declared extent). Move the plan
  to `plan/done/`.

## 7. Risks

- Step 4 changes what the renderer reads for each vertical canvas, the text
  view too. The dirty walk must still read the same cells as the renderer.
  Compare with the baseline.
- Step 5 changes the size of a laid-out canvas whose declared box is not its
  drawn extent. The rule applies only when `w > 0` and `h > 0`, the canvas has a
  layout, and its elements do not overlap.
- The pass counts of the tests change, because they follow the number of cells.
- `FileSystemToSyntax` still reads the whole tree, because it prints every row.
  Only the fixture example uses it.
- `expanded` holds index paths. After a folder is read again, a path can name a
  different entry. Step 2 covers a change of the root path. A disk watcher later
  needs keys by name.
- `GraphicsCaching` turns a finite leaf canvas into one image. A row canvas is a
  leaf. Only the gallery example uses `GraphicsCaching`, and the Explorer does
  not.

## 8. Not in this plan

- Move the selection to a folder that closes over it (Q2).
- Hide `.git`. After B it costs one row.
- Scroll the selected row into view when an arrow key moves it.
- A disk watcher.
- A workspace that shows more than one folder.
