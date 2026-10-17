# A tree draws only the rows it shows

A tree of the platform lays out a row for each child of each open node. Only
the drawing of a row waits until the viewport reaches it. So a node with 100,000
children costs 100,000 rows at its open, and at each change of the tree after
it:

- the geometry walk of `WidgetTree` (`WidgetToGraphics.jl`, the walk of the open
  rows) visits every child of an open node, and keeps a row and an index entry
  for each;
- the keys up and down step through that full list of rows;
- the width of a tree with no offered width reads every row;
- `DocumentTreeToWidgetTree` counts the children of a node (`length` of each
  collection) and makes an entry for each.

A configuration of a simulation project can have more runs than a view can
hold, and the explorer of the simulator shows them as the children of the
configuration (the plan of the simulator, `the-explorer-reads-a-project-when-it-opens.md`,
step 2, waits for this plan). A lazy table draws only the rows that its viewport
reaches (`plan/done/a-table-scrolls-its-own-parts.md`). A tree must do the same.

## Decisions

1. **A tree draws only the rows that its viewport reaches** (the owner,
   2026-10-17: "T1, lazy, that's the projectured default"), over a tree that
   shows the first children of a node and a row for the rest.
2. **The machinery of the lazy table is the model.** The rows are a `ListNode`
   chain whose links build a row when a walk first reaches it, the head is the
   anchor, the ends of the list stop the pane, and a far scroll moves the head.
   No new mechanism.
3. **A tree with no offered width is as wide as the rows that the viewport
   reaches** (the owner, 2026-10-17: "agreed", to point P1), so it can grow while
   a person scrolls.
4. **What a viewport shows is a demand** (the owner, 2026-10-17: "it's V"), over
   a read at the visit of a page only: a viewport holds the documents of the rows
   that it shows. That is a plan of its own,
   `a-viewport-holds-the-rows-it-shows.md`, after this one.
5. **Only a tree with an open lazy list of children makes its rows as a lazy
   list** (found at step 1). The renderer walks a list forward from its head and
   draws each node up to the far edge, also the nodes above the view, so a list
   whose head stays at the first row draws every row between the first row and
   the view; a lazy table moves its head near the view for that reason, and step 2
   does the same for a tree. A laid-out list of rows starts at the rows in view by
   a search, and gives the pane the height of the rows and its bar. A tree whose
   open nodes each count their children keeps it.

## The model

The children of a node can be a lazy list. The rows of an open tree are one lazy
list: each row is a node at its path and its depth.

For example, a configuration with 100,000 runs, open, in a tree of one project:

```julia
runs = make_index_list(100_000, 1, k -> WidgetTreeNode(:play, "Run $(k - 1)", Any[]))
sweep = WidgetTreeNode(:settings, "Sweep · 100000 runs", runs; has_children = () -> true)
tree = WidgetTree(Any[WidgetTreeNode(:folder, "project", Any[sweep])];
                  expanded = Set([[1], [1, 1]]))
```

- The `next` of a row is its first child when it is open, else its next
  sibling, else the next sibling of the nearest node above it. The `prev` of a
  row is the reverse. A sibling in a lazy list is the next node of that list.
- The head of the rows is the anchor of the tree: the path of a row, by default
  the first row. The offset of the pane counts from the head, so a row before the
  head has a negative place, as in a lazy table.
- A path into a lazy list of children counts from the head of that list
  (`roots[1].children[1].children[k]`), as every path into a `ListNode` does.
- All rows have one height, so the row under a point is the row that many links
  from the head.

The states over time:

| Moment | Rows made | Run entries made |
| --- | --- | --- |
| The tree shows `project`, closed | 1 | 0 |
| A person opens `project` and `Sweep` | the rows that the viewport shows, about 40 | about 38 |
| A person scrolls down by a page | about 40 more | about 40 more |
| A person scrolls 50,000 rows down | about 40 at the new place; the head moves there | about 40 |
| A person presses the key down on the last row of the viewport | 1 more | 1 more |

What changes:

- **`WidgetTreeNode.children`** is a `Vector`, a `CellVector` or a `ListNode`.
- **The rows** are a `ListNode` that a computation makes from the roots, the
  open paths and the anchor. The pane draws them as a lazy vertical list.
- **A click** finds its row by a walk from the head. **The keys up and down**
  step to the `prev` and the `next` of the row of the selected node, which the
  tree finds from the path of the node, with the same rule as the links. The
  selection stays a path of the node, as now.
- **The width.** A tree takes the width that its parent offers. With no offer,
  it is as wide as the rows that the viewport reaches.
- **A far scroll.** When the top row is more than about 200 rows from the head,
  the tree writes its anchor to the path of the top row and rebases the offset,
  as the table does (section 3.6 of the plan of the table). The anchor is view
  state of the tree, as its open paths are.
- **`DocumentTree`.** A collection of children that is a `ListNode` gives a lazy
  list of entries and of nodes (`make_mapped_list`), so a document with a lazy
  collection makes only the entries that the rows reach. The open nodes, their
  holders and the paths count from the head of each lazy collection. A node
  gives the chevron from `has_tree_children`, never from a count.

A tree whose open nodes each count their children draws as it does now: it lays
out each row, the renderer starts at the rows in view, and the pane has the
height of the rows and its bar. Only a tree with an open node that holds a lazy
list of children makes its rows as a lazy list (decision 5).

## Steps

Each step is one commit with its tests, in a worktree.

- [x] **1. The rows of a tree are a lazy list.** `WidgetTreeNode.children` takes
  a `ListNode`; the rows are a `ListNode` with the links of the model; the
  geometry, the click, the keys up and down, the chevron and the width work from
  the head. Tests: the tree suite (`WidgetTreeTest`, the tree render tests), and a
  new test: a node with 10,000,000 children opens, draws, takes a click and the
  keys, and the count of the children that it made stays below the rows of two
  viewports.

  What step 1 made:
  - `WTreeListGeometry` holds the head of the rows and the node of the list of
    each row that a walk made. A row of the list (`WTreeListRow`) holds its place
    among its siblings and no node: the walk reads the node of an open row only,
    and a row reads its node when it is drawn.
  - The tree makes the lazy list only when it prints as the rows of its own pane
    and an open node holds a `ListNode` of children (decision 5). Every other tree
    keeps its laid-out rows, unchanged.
  - The click walks from the head, and a point below the last row names no row.
    The keys up and down find the neighbour from the nodes and the open paths, so
    a row that no walk made has its neighbours too. The forward map of a path
    finds the row that a walk made. A row of the lazy list has a transparent band
    of its own, so a press on its empty part lands on it.
  - The test of an open lazy list takes the open paths from the shortest and reads
    no path inside a lazy list, and it reads the count of the children of every
    other open node, so a change of them makes the rows again.
  - With no offered width, a lazy list of rows is as wide as the rows between the
    offset of its pane and the bottom of the view (decision 3).
  - Tests: `test_widget_tree` 65 (three new testsets), `test_widget_rows_scroll`,
    `test_filesystem_to_widget`, `test_document_tree` 82, `test_tree_render` 9
    (one new testset: the renderer draws an open node of 10,000,000 lazy children
    and makes about a dozen of them), `test_layout_list` 101,
    `test_scroll_pane_bar`, `test_scroll_layout` 29, `test_dataframes` 612. The
    platform suite: 163,261 pass, 7 broken, and 1 fail that fails the same on the
    code of 2026-10-16 (the process tree of a running task never syncs a row).
- [ ] **2. A far scroll moves the anchor.** The scroll operation of the pane of
  the tree writes the anchor and the rebased offset when the top row is far from
  the head. Tests: a scroll of 1,000,000 rows keeps the made rows bounded, and
  the selection and the open paths stay.
- [ ] **3. A document tree with a lazy collection.** `DocumentTreeToWidgetTree`
  maps a `ListNode` collection lazily; the open nodes and their holders work
  through it. Tests: `TreeTest`, and a document with 1,000,000 lazy children
  whose open makes only the entries that the rows reach.
- [ ] **4. The guides:** `tree.md`, the guide of the widgets of a tree, and the
  guide of the lazy list.

## Risks

- A tree in a page that gets no height from its parent is as tall as its rows.
  For a node with a lazy list of children, that has no end; such a tree must get
  a height, as a lazy table must.
- The plan `an-insert-moves-the-paths-after-it.md` moves the open paths of a
  tree on an insert. It works with paths that count from the head.
- A tree in a page with an open lazy list of children lays out each row, and each
  row finds its node by a walk from the head of the list, so a finite lazy list of
  n children costs about n²/2 reads of links there (found at the review of step 1).
- A toggle in a lazy list of rows makes the rows from the head again, so every row
  that the view shows is drawn again; the laid-out rows keep the canvas of a row
  that stays (found at the review of step 1).
