# Cheap reactive cells — pay for reactivity only where observed

Make `ReactiveCell` cheap enough that a **large** reactive document tree — up to
an entire application's state (e.g. a whole discrete-event simulator, scheduler
and all) — is affordable, by paying dependency-tracking cost only for cells that
are actually observed by a projection. Today a reactive cell is ~9× slower and 7×
larger than a mutable one, and ~90% of that gap is bookkeeping that is almost
always empty.

## Measured baseline (construction, ×1e6)

| kind | time | bytes/cell |
|------|-----:|-----------:|
| `Ref` (plain box) | 16.6 ms | 24 |
| `ImmutableCell` (isbits, inlines) | 1.2 ms | 8 |
| `MutableCell` (one box) | 12.1 ms | 24 |
| **`ReactiveCell` (current)** | **110.7 ms** | **168** |
| *just* `Set{Int}()` | 36.6 ms | 88 |

## Diagnosis

- **Eager per-cell bookkeeping.** `ReactiveCell{T}` allocates a
  `deps::Set{ReactiveCell}` **and** a `dependents::Vector{WeakRef}` at
  construction ([ReactiveCell.jl:38-39](../../package/kernel/main/cell/ReactiveCell.jl#L38-L39)).
  For a data tree almost every cell is a **primitive leaf** (reads nothing → `deps`
  stays empty) that until a projection looks at it is **observed by nothing**
  (`dependents` stays empty). The empty `Set` alone is 88 B / 36.6 ns; it plus the
  `WeakRef[]` are ~144 of the 168 B and most of the time.
- **Reactive collections wrap every element.** A reactive `CellVector` stores one
  `ReactiveCell` slot per element ([CellVector.jl:5-13](../../package/base/main/document/collection/CellVector.jl#L5-L13));
  the immutable/mutable kinds store elements directly in a plain `Vector`. So a
  reactive collection multiplies the per-cell cost by its length — a million
  queued items you are *not* looking at each cost a full `ReactiveCell`.

`MutableCell` ≈ `Ref` (one box, plain-struct speed). The whole penalty is the
reactive machinery, and most of it is avoidable.

## Levers

### L1 — lazy `deps` / `dependents`  *(highest impact, self-contained)*

Make both fields `Union{Nothing, …}`, `nothing` at construction; allocate on the
**first real dependency**:
- `dependents` allocated the first time some computation reads this cell
  (`getindex`'s register branch, [ReactiveCell.jl:98-105](../../package/kernel/main/cell/ReactiveCell.jl#L98-L105)).
- `deps` allocated the first time this cell (as a computed cell) reads another
  (`recompute!`, [ReactiveCell.jl:132-146](../../package/kernel/main/cell/ReactiveCell.jl#L132-L146)).

Every read/write/invalidate path (`getindex`, `setindex!`, `invalidate!`,
`_invalidate_walk!`, `_detach_upstream!`, `_register_dependent!` /
`_unregister_dependent!`) guards for `nothing` (treat as empty). **Semantics
identical** — an empty set/vector and `nothing` behave the same; only the *timing*
of allocation changes. Optionally free them again when they empty (drop-out of
view), so a cell that leaves the projection stops paying.

Expected: an unobserved primitive `ReactiveCell` → ~24 B / 12 ns (MutableCell
class), a **~7× memory / ~9× time** win. Only cells a projection is *currently*
observing pay the Set+Vector.

Files: `cell/ReactiveCell.jl` (struct + the read/write/invalidate/helper paths).

### L2 — lazy / cheaper reactive collection slots

A reactive `CellVector` need not pre-wrap every element in a full `ReactiveCell`.
Wrap a slot lazily on first observed access (or use a lighter slot handle), so the
unobserved bulk of a large collection (a million-event FES, a deep packet queue)
costs a plain vector entry. Care: structural reactivity (element insert / remove /
reorder) needs stable slot identity — design the lazy slot so structural
dependents still fire.

Files: `document/collection/CellVector.jl` (the `RCV` reactive storage path + element accessors).

### L4 — object-granular reactivity (inline fields)  *(only if needed)*

Store field values **inline** in a plain mutable struct with **one** reactive
tracking unit per object, instead of a cell per field → near-plain construction
speed, at the cost of **object-level** (coarser) invalidation. A structural change
to the cell-struct layout (`cell/CellStruct.jl`, `@cell_struct`/`@document`
codegen). Pursue only if L1+L2 leave the *interactive-at-scale* path too slow; for
most projectional UIs object-granular invalidation is enough anyway.

### L3 — cell-kind polymorphism  *(already supported — no framework work)*

`@document` already emits `RFoo`/`MFoo`/`IFoo` from one definition. An application
runs the **mutable** kind where it wants plain-struct speed and the **reactive**
kind where it wants incremental rendering — one schema, no duplication. Documented
here as the intended pattern; the consuming plan
(`omnetpp-julia`) relies on it.

## Phases

- [x] **P1 — measure baseline** (table above).
- [ ] **P2 — L1 lazy deps/dependents.** Implement; **run the full projectured test
      suite** (`test_all` scope; the cell suite `test_cell()` first) to prove no
      behavior change; re-measure the construction hierarchy.
- [ ] **P3 — clean cost hierarchy.** Measure plain / mutable-kind doc /
      reactive-kind doc / reactive+L1 side by side → decide whether L2 (and L4) are
      needed, on numbers not guesses.
- [ ] **P4 — L2 lazy collection slots** (if warranted).
- [ ] **P5 — L4 object-granular** (only if the interactive-at-scale path demands it).

## Notes

- **Sealed files.** `ReactiveCell.jl`, `CellVector.jl`, `CellStruct.jl` are sealed;
  the owner has authorized unsealing for this work. **Audit each against
  [documentation/architecture-requirements.md](../../documentation/architecture-requirements.md)
  before re-sealing.**
- **Correctness guard.** L1's risk is entirely "did any path forget to handle
  `nothing`". The pull-based semantics (lazy recompute, weak dependents, task-local
  computing stack) must be preserved exactly. `test_cell()` + the reactive
  incrementality tests are the gate.
- **Enables** `omnetpp-julia/plan/pending/simulator-as-reactive-document.md` — a
  simulator whose entire state is one reactive document is only affordable once an
  unobserved cell costs ~a plain box.
