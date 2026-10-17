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

1. **What a viewport shows is a demand** (the owner, 2026-10-17: "it's V"): a
   viewport holds the documents of the rows that it shows, so a scroll releases
   the rows that leave and acquires the rows that come.
2. **Each part answers for itself**, by the rule of the owner that nothing is
   decided globally that a part can decide locally: a projection says which of
   its documents it shows in a viewport, and asks its child IO maps for theirs.
   The editor keeps only what is global: the end of a frame, and the compare.
3. **The change is view state**, so the undo records none of it, as the open of a
   node of a tree records none.

## The model

After the paint of a frame, the editor asks its root IO map for the documents
that it shows. A projection answers with a list of `holder => documents`. The
default answer is the answers of its child IO maps. The editor compares the
documents of each holder with what the holder holds, and evaluates one
operation of view state for each holder that changed.

- **The scroll pane** gives its content the viewport: the rectangle that it
  shows, in the coordinates of the content.
- **A view of a lazy list**, such as the rows of a tree, answers the places of
  the rows that cross the viewport. It walks from the head, as the renderer and
  the clamp of the pane walk, so it reads only rows that the paint built.
- **The projection that knows the documents of the rows**, such as
  `DocumentTreeToWidgetTree`, maps those places to its documents, and names a
  holder for them.
- **The holder of the shown rows** is an object of its own for each view, which
  the editor keeps in a session document. It is not the document of the view,
  because a tree already holds its open nodes, and a node can be open and shown
  at the same time.

For example, the explorer with the configuration `Sweep` of 100,000 runs open:

```julia
# After the frame that drew the run rows 0 to 37:
answer = [shown_rows(tree) => [run_0, run_1, …, run_37]]
ReplaceViewStateOperation(ChangeHeldDocumentsOperation(shown_rows(tree), Any[], Any[run_0, …, run_37]))
```

The acquire of a run entry asks its configuration for its details. The
configuration reads all the runs that were asked in one process. The states over
time:

| Moment | Rows held | Reads |
| --- | --- | --- |
| A person opens `Sweep`; the frame draws runs 0 to 37 | runs 0 to 37 | one process, `-r 0..37` |
| The answer comes | the same | none; the rows show "Run 3: $n=3" |
| A person scrolls down by a page; the frame draws runs 38 to 75 | runs 38 to 75; 0 to 37 are released | one process, `-r 38..75` |
| A person makes the window taller; the frame draws runs 38 to 90 | runs 38 to 90 | one process, `-r 76..90` |
| The tab closes | none | none |

The batch of the reads belongs to the domain of the rows: the acquire of a run
entry posts the read of its configuration, so the acquires of one frame give one
process.

## Steps

The steps need step 1 of `a-tree-draws-only-the-rows-it-shows.md`. Each step is
one commit with its tests, in a worktree.

- [ ] **1. The shown documents of a view, and the step at the end of a frame.**
  The protocol `collect_shown_documents(projection, iomap, viewport)` with its
  default that asks the child IO maps; the scroll pane gives its content its
  viewport; the editor, after the paint of a frame that drew something, collects
  the answers and evaluates the changes of what each holder holds; a holder of
  shown rows is held while its view answers it, and released when its view no
  longer does. Tests: a test view of a lazy list of 1,000 documents in a pane:
  after a frame the drawn documents are acquired, a scroll releases and acquires,
  a close releases all, and the undo has no entry.
- [ ] **2. A tree answers the documents of its shown rows.** The tree widget
  answers the paths of its rows that cross the viewport, and
  `DocumentTreeToWidgetTree` maps them to its documents. Tests: `TreeTest`, with a
  document whose lazy collection of 1,000,000 children opens: only the children
  that the viewport shows are acquired.
- [ ] **3. The guides:** the holders in `domain.md`, the frame in the guide of the
  editor loop, and `tree.md`.

## Risks

- The editor asks its IO maps at each frame that painted something. The cost
  grows with the size of the window, so step 1 measures it on the window of the
  simulator.
- A document is acquired one frame after the frame that draws it, so its details
  come one or more frames later. A row shows what it holds meanwhile.
