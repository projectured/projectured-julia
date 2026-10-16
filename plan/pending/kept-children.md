# Children that move keep their print

`plan/done/roster-follow-ups.md` made the path of a printer context a cell, and
taught the grid of a list to keep the print of a row that moves. It recorded
limits and two ideas for the cell engine. The owner goes through them one at a
time (2026-10-16); this plan holds each decision.

## Decisions

1. **The reconciler of a vector keeps a child by its object** (option A, the
   owner, 2026-10-16). `make_reconciled_child_iomaps_cell` in
   `source/kernel/iomap/IoMapReconcile.jl` keys a child by the element itself,
   in an `IdDict`, which also keeps the element alive. One computed cell maps
   each element to its index for each change of the vector, and each child
   gets an index cell that reads it; an element at two places is not kept, and
   each of its prints takes its own index. `make_iomap(index, x)` gets the
   index cell, so the 15 callers build the context of a child from it. Today
   an insert or a delete at the front prints every child after it again, for
   example every member of a JSON object after a deleted member.
