# The cost of a read that records a reader

The measure of the stop (`plan/done/computed-cell-stop-measure.md`) found that
its experiment made two steps over lists about a quarter faster than `main`,
also with no stop: S4b, a save that the filter of a roster sees, 22 ms against
30 ms, and S4d, a change of one call under a grouped roster, 10 ms against 12
ms. The experiment found a cell that a run read before at the read, and then did
not record the reader again. The final engine (`plan/done/computed-cell-stop.md`)
removes the repeats at the end of a run, so it records the reader at each read
that is not a repeat of the last one, and it does not have that gain.

A record of a reader scans the list of the readers of the cell, to keep it free
of repeats and of collected readers. A cell that many cells read, such as a gap
of a grid that every child reads, has a long list, and a scan of it at each read
costs.

## Steps

- [x] **1. Where the time goes.** In S4b and S4d, count the scans of
  `_register_dependent!` and `_unregister_dependent!`, the entries that each one
  walks, and how often the reader is the last entry already. A probe in a
  scratch process redefines the two functions; no file changes.
  - Done 2026-10-14, for each step, on `main` cc0977a78:

    | | records | entries walked | found | found at the end | new |
    |---|---|---|---|---|---|
    | S4b | 46493 | 9.9 million | 18726 | 18473 | 27767 |
    | S4d | 30582 | 2.2 million | 13995 | 13952 | 16588 |
    | S2 | 7157 | 25431 | 6379 | 6379 | 778 |

  - A reader that is in the list already is at the end of it in 98 to 100
    percent of the cases, and the scan from the front walks the whole list to
    find it. A record of a new reader walks the whole list too, to keep out a
    repeat and to take out the collected readers.
- [x] **2. The change.** The smallest change of `ReactiveCell.jl` that step 1
  points at, such as a read that finds the reader at the end of the list and
  walks no further. A test in `CellTest.jl` pins what the change promises.
  - Done 2026-10-14. `_register_dependent!` looks at the last entry first. The
    entries walked fall to 4.6 million in S4b, 0.87 million in S4d and 1885 in
    S2. The test of the order of the dependencies asserts that a cell that a
    run read again keeps its reader once.
  - The walks of a new reader stay. To leave them out, a record must know that
    the reader is new to the list, and the collected readers must go out in
    another way, or the list grows with no bound; that is outside this plan.
- [ ] **3. The checks.** The counts of the six scenarios of the measure, which
  must not change; the time of the six scenarios against `main` on an idle
  machine; the suites of the kernel and the platform.
