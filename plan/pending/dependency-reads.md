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

- [ ] **1. Where the time goes.** In S4b and S4d, count the scans of
  `_register_dependent!` and `_unregister_dependent!`, the entries that each one
  walks, and how often the reader is the last entry already. A probe in a
  scratch process redefines the two functions; no file changes.
- [ ] **2. The change.** The smallest change of `ReactiveCell.jl` that step 1
  points at, such as a read that finds the reader at the end of the list and
  walks no further. A test in `CellTest.jl` pins what the change promises.
- [ ] **3. The checks.** The counts of the six scenarios of the measure, which
  must not change; the time of the six scenarios against `main` on an idle
  machine; the suites of the kernel and the platform.
