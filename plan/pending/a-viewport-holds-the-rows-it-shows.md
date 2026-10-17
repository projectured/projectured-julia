# A viewport holds the rows it shows

A document starts what it needs when a holder acquires it: a folder reads its
listing, a file watches its file (`plan/done/a-folder-reads-the-disk-when-it-opens.md`).
Today a holder is an open node of a tree, a tab or the page of a navigator. A
row that a viewport shows is no holder, so a lazy list can not read the details
of the rows that a person sees. The explorer of the simulator needs this: a
configuration can have 100,000 runs, and the details of a run (its iteration
variables) come from a process (the plan of the simulator,
`the-explorer-reads-a-project-when-it-opens.md`, step 2).

## Decisions

1. **What a viewport shows is a demand** (the owner, 2026-10-17: "it's V"): the
   documents of the rows that a view shows are held, so a scroll releases the
   rows that leave and holds the rows that come.
2. **The tree holds the rows that come into view, in the answer that brings them**
   (the owner, 2026-10-17: "Agreed", to option A), over a new step at the end of
   each frame that asks every view what it drew (the owner: "A completely new
   mechanism after each frame?"), and over a read only when a person asks. No new
   mechanism: the tree already adds a hold to the answer of a press on a
   chevron, and a background read answers with an operation since plan A.
3. **The change is view state**, so the undo records none of it, as the open of a
   node of a tree records none.
4. **The widget writes rows, the document tree holds documents.** The tree widget
   knows its rows and not the documents behind them. As it writes its open rows
   (`expanded`), it writes the rows that its view shows after the answer
   (`shown`); the document tree turns that write into holds of the documents of
   those rows, as it turns `expanded` into holds of its open documents. It keeps
   one set of holds: the open documents and the shown ones. So a node that is
   open and shown is not released when it closes.

## The model

The explorer, with the configuration `Sweep` of 100,000 runs:

```
▾ Sweep · 100000 runs
    Run 0: $n=0
    Run 1: $n=1
    …
    Run 37          ← the bottom of the window
```

The document of one run, before and after its details come:

```julia
LegacyRunEntry(number = 3, details = nothing)                     # shows "Run 3"
LegacyRunEntry(number = 3, details = Run(n = 3, repetition = 0))  # shows "Run 3: $n=3"
```

The states over time:

| Moment | The answer of the tree | Reads |
| --- | --- | --- |
| A person opens `Sweep` | open `Sweep`, and show the rows down to run 37 | the held runs 0 to 37 ask `Sweep`, which runs one `opp_run -r 0..37` |
| The read ends | — | its answer fills in the details of runs 0 to 37 |
| A person scrolls down one page | scroll, and show the rows of runs 38 to 75 | runs 0 to 37 are released; one `opp_run -r 38..75` |
| A tab opens with `Sweep` open | — | the acquire of the tree holds the documents of its first rows |
| The window gets taller | — | nothing until the next scroll or toggle |

- **`WidgetTree.shown`** is view state: the paths of the rows that the view of
  the tree shows. The reader of a tree that scrolls itself writes it beside each
  scroll, the far move of the head included, and beside each toggle: the rows
  above the toggled row stay, the toggled row stays where it was pressed, and the
  rows after it follow the new open rows down to the bottom of the view. All rows
  have one height, so the rows of the view come from the offset and the height of
  the view.
- **`DocumentTree.shown`** is view state: the documents of the rows that the
  widget shows. The reader of the document tree turns a write of `shown` of its
  widget into a write of `shown` of the tree and a change of what the tree holds:
  the open documents and the shown ones together.
- **The acquire of a tree** holds its open documents and its shown ones. A tree
  that showed no row yet holds the documents of its first rows in the order of
  the tree, as many as a view of the screen can show.
- The batch of the reads belongs to the domain of the rows: a run that is held
  asks its configuration for its details, and the configuration reads the runs
  that its rows asked for in one process.

## Steps

The steps need the lazy tree on main (`plan/done/a-tree-draws-only-the-rows-it-shows.md`).
Each step is one commit with its tests, in a worktree.

- [x] **1. The tree widget writes the rows it shows.** `WidgetTree.shown`; the
  reader of a tree that scrolls itself writes it beside a scroll, a far move of
  the head and a toggle. Tests: the tree widget suite, with a tree of a lazy list
  of 10,000,000 children: a toggle and a scroll each write the rows of the view
  after them, and a plain tree writes them as well.

  What step 1 made:
  - `WidgetTree.shown` is a trailing field after `anchor`, so the four positional
    calls of the platform pass it before the selection.
  - The reader of the rows pane of a tree writes `shown` beside each scroll that
    writes an offset, from the offset and the height of the view of the pane, and
    only when the rows change. The IO map of the tree keeps the height of its view
    (`view_height`), so a toggle writes the rows after it: the rows above the
    toggled row in the view, the row, and the rows that follow it in the new open
    rows down to the bottom of the view.
  - A toggle of a tree that scrolls itself now answers a compound, so the reader of
    the Files explorer (`_read_open_folder_write`) takes the write of the open rows
    inside a compound too, as the document tree does.
  - Tests: `test_widget_tree` 96 (a new testset), `test_filesystem_to_widget`,
    `test_file_dialog` 22, `test_document_tree` 94, `test_widget_rows_scroll`,
    `test_tree_render`.
- [x] **2. The document tree holds the documents of the shown rows.**
  `DocumentTree.shown`, the turn of the write of the widget into holds, one set
  of holds with the open documents, and the first rows at the acquire. Tests:
  `TreeTest`, with a document whose lazy collection of 1,000,000 children holds
  only the children that the view shows, a scroll that moves the holds, a close of
  a node that stays held while it is shown, and an undo that records nothing.

  What step 2 made:
  - `DocumentTree.shown` (view state, an `IdDict` of documents). The reader of the
    document tree takes the writes of `expanded` and of `shown` of its widget in
    one answer, turns each into the documents at those paths, and changes the
    holds once, against the open and the shown documents together. A child of a
    lazy list that comes into view is made by the turn.
  - The first rows at the acquire are the first fifty children of each open lazy
    list of children only (`_FIRST_SHOWN_CHILD_COUNT`), found at step 2: a tree
    whose rows all have a count would else hold each row of a small tree, and a
    close would release no node. The acquire writes them into `shown`, so the
    first write of the view replaces them.
  - Tests: `test_document_tree` 100 (a new testset in a real editor: fifty runs
    at the acquire, about ten after a wheel turn, the holds move down after more
    turns, every innermost operation of the answer is view state, and the release
    of the tab lets go of all), `test_widget_tree` 96, `test_filesystem_to_widget`,
    the navigator suites.
- [ ] **3. The guides:** the holders in `domain.md`, `tree.md`, and the tree
  in `widget.md`.

## Risks

- A window that grows, a list that changes by itself, and a scroll that a
  program makes (the scroll to a selection) write no `shown`: the rows that come
  into view that way read their details at the next scroll or toggle.
- The first rows at the acquire are counted in the order of the tree with no
  view, so they can be more than the view shows.
