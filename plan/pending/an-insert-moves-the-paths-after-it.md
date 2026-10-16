# An insert moves the paths after it

An insert or a delete in a collection is a splice: a
`ReplaceReferencedValueOperation` whose last step is a range
(`make_insert_elements_operation`, `source/kernel/operation/Operations.jl:564`).
A splice changes the index of each later element of the collection. No stored
path moves with it: only an explicit `ReplaceSelectionOperation` moves the
selection. So a selection that names a later element names another element after
the splice.

The owner, 2026-10-16: "moving the selection when inserting into a list or a
collection makes general sense for many other cases". The first users are the
Files tab and the explorer, whose listings change by inserts and deletes
(`a-folder-reads-the-disk-when-it-opens.md`).

## Decisions

1. **The evaluation of a splice moves the paths that name a later element of
   the same collection** (the owner, 2026-10-16).

**My recommendations for the design** (to confirm at step 1):

- **M1. Which paths.** The selection of the editor, live and dormant. Also the
  paths that a document holds as its state, such as the address and the visits of
  a navigator, and the selection of a document tree. A document that holds paths
  answers a new generic, `move_held_paths!(document, splice)`, and the splice
  calls it for each document on its path from the root.
- **M2. A path into the replaced range.** After a delete, the path goes to the
  element after the range, or to the collection when no element is after it.
  After a replace, the path goes to the first new element.
- **M3. Undo.** The inverse splice moves the paths back by the same rule.

## Steps

Each step is one commit with its tests, in a worktree. Before each step, check
`SEALING.md` for each kernel file that the step changes.

- [ ] **1. The map of a splice** (decision 1, M2): a function of the reference
  slice that maps a path through a splice. Tests: the tests of the reference
  slice.
- [ ] **2. The selection of the editor moves**, live and dormant. Tests: the
  tests of the operations, and a list in an editor: an insert above the selected
  element keeps that element selected, and a delete of it selects the next one.
- [ ] **3. The paths that documents hold** (M1): the navigator and the document
  tree answer `move_held_paths!`. Tests: `test_navigator()` and `test_tree()`.
- [ ] **4. The documents:** `operation.md`, `selection.md` and `reference.md`.
