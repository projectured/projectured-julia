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

A tree with no lazy list of children draws as it does now. A tree with a
`Vector` of 5,000 children also makes only the rows that the viewport reaches,
because the rows are lazy for every tree.

## Steps

Each step is one commit with its tests, in a worktree.

- [ ] **1. The rows of a tree are a lazy list.** `WidgetTreeNode.children` takes
  a `ListNode`; the rows are a `ListNode` with the links of the model; the
  geometry, the click, the keys up and down, the chevron and the width work from
  the head. Tests: the tree suite (`WidgetTreeTest`, the tree render tests), and a
  new test: a node with 10,000,000 children opens, draws, takes a click and the
  keys, and the count of the children that it made stays below the rows of two
  viewports.
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

## Points for the owner

- **P1. The width of a tree with no offered width** is the width of the rows that
  the viewport reaches, so it can grow while a person scrolls. The other choice
  is a width that a caller gives.

## Risks

- A tree in a page that gets no height from its parent is as tall as its rows.
  For a node with a lazy list of children, that has no end; such a tree must get
  a height, as a lazy table must.
- The plan `an-insert-moves-the-paths-after-it.md` moves the open paths of a
  tree on an insert. It works with paths that count from the head.
