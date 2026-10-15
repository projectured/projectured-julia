# The roster: scroll, kept rows, and the record of a new reader

The work of `plan/done/cross-cutting-views.md`, `plan/done/roster-table-cost.md`,
`plan/done/computed-cell-stop.md` and `plan/done/dependency-reads.md` left four
findings, which the owner asked to fix on 2026-10-15:

1. **A long roster can not scroll in a tab.** A tab gives its content a free
   height, and the table of a roster makes no scroll of its own, so the rows below
   the pane can not be reached.
2. **A new list of rows prints the whole table again.** When a filter or a sort
   changes its answer, every row prints again: about 44 computations for each row
   (S4b, 2212 computations for 50 rows).
3. **A new reader scans the list of the readers of a cell.** After the check of
   the end of the list, S4b still walks 4.6 million entries for each step, from
   the records of new readers.
4. **The time of the check of the end of the list ran under load.**

## Steps

- [x] **1. The roster scrolls in a tab.** The table of a roster takes the form
  that the other long views in a tab use, and scrolls its own rows. A test shows
  a roster of 200 rows in a tab and reaches its last row with the wheel.
  - Done 2026-10-15. The cause: a tab gives its content its height as a slot,
    and the layout rules say that a table that gets a slot fills it and scrolls
    its rows (`layout-rules.md` §3b). Two `VerticalLayout`s took the slot away,
    because a stack gives a slot only to a weighted child (§4): the bar of an
    arranged place, and the layout around the table of a roster.
  - The bar is a `VerticalLayout` whose children fill its width and share its
    height (`child_width = Fill`, `child_height = Fill`), with the chips in a
    `LayoutConstraint(chips; height = Content)`, so the items take what the
    chips leave. The items stay at `children[2]`, because they can be a value
    that is no document, such as a reflected `Vector`, which a
    `LayoutConstraint` can not hold; the chips go to `children[1].child`, in the
    bar and in `Finding.jl`.
  - A `GridLayout` in the bar failed: a grid keeps the output of a child from
    its print, and the chips print a new canvas when their count changes, so
    the count stayed old. The table of a roster and the table of the groups sit
    in a `GridLayout` of one `Fill` column and one `Fill` row, which keeps their
    paths at `children[1]`; a table keeps one canvas, so the grid follows it.
  - A test in a window: a roster of 200 rows in a tab draws its last row below
    the window, and the wheel brings it into view. Without a window an editor
    has no height to give, and its canvas is as tall as its content.
  - The roster tests and every arrangement test pass.
- [ ] **2. A row that stays keeps its print.** When a filter or a sort makes a
  new list of rows, a row that is in the old list and in the new one keeps the
  print of its cells. A test checks that the drawn text of such a row is the
  same object after a change of the filter; the counts of S4b before and after.
- [ ] **3. The record of a new reader.** Done only when, after step 2, the probe
  of `plan/done/dependency-reads.md` still walks more than one million entries
  in a step of S4b or S4d. Then a record that knows the reader is new to the
  list puts it at the end with no scan, and the dead readers go out in a bounded
  way, so the list can not grow with no limit; a test pins the bound.
- [ ] **4. The time.** The six scenarios of the measure on an idle machine,
  `main` at the start of this plan against the branch, two rounds each, with a
  wait for an idle machine.
- [ ] **5. The texts.** The limits and the cost of a change in
  `documentation/package/platform/roster/roster.md`, with the counts of steps 2
  to 4.
