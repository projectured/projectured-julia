# The reactive dependency edge owns its reader

`ReactiveCell.dependents` is a strong `Set{ReactiveCell}`. An upstream cell therefore
**owns** every downstream cell that has ever read it, and a document ends up pinning
every projection pipeline it has ever been printed through.

This is a real leak, on `main`, and it is what makes the test suite eat memory.

## The mechanism

[`ReactiveCell.jl`](../../package/kernel/main/cell/ReactiveCell.jl) — **🔒 sealed**:

- reading a cell inside a computation registers the edge in both directions —
  `push!(c.dependents, observer)` (strong) and `push!(observer.deps, c)`;
- the **only** place an edge is ever removed is `recompute!`, which detaches a cell's own
  *upstream* links (`_detach_upstream!`) before re-evaluating.

So a cell that is simply **discarded** never recomputes again, its edges are never
removed, and the upstream cell holds it alive for ever. Nothing in the system detaches
a dead reader.

The `deps` direction (downstream → upstream) is fine: it points at the long-lived
document, which is alive anyway. It is the `dependents` direction (upstream → downstream)
that must not own.

## What leaks

Measured on the `json` example, 2026-07-14:

| change | live (post-GC) | pinned edges |
|---|---|---|
| 348 **selection moves**, one pipeline | 706 MB → 706 MB | flat |
| 200 **structural edits** (insert a node, remove it), one pipeline | +100 kB **per edit**, linear | +3.4 **per edit**, linear |
| one **caret walk** (`_walk_cursor` re-prints per keystroke) | +690 MB **per walk** | +36 317 **per walk** |
| five caret walks | 723 → 3 478 MB, linear | 36 317 → 181 585, linear |

**Selection moves are flat — but that is an OPTIMIZATION, not a property.** The printers go
to deliberate lengths to reuse cells across a selection change (`_DecoCache`, span
stability, IoMap identity keyed on the child object), so the selection path happens not to
create new cells and therefore has nothing to leak. Every change that reuse does *not* cover
leaks. Do not read that row as "the editor is fine".

**Structural edits leak.** Insert a node and remove it again, 200 times, through a single
pipeline: the live pipeline's own cell count never moves (3908 throughout), but the number
of dependency edges hanging off those live cells grows linearly. Those edges are *dead*
cells — the discarded sub-pipeline of the removed node — pinned by the surviving pipeline.
~3.4 edges and ~100 kB per edit, for ever. A long editing session is a slow leak.

**Re-printing leaks the whole pipeline.** `print_document` builds a fresh one; each of its
cells registers itself in the `dependents` of every document cell it reads; when the
pipeline is thrown away nothing detaches it. `_walk_cursor` re-prints once per keystroke
([ClickRoundtripTest.jl](../../package/visual/test/editor/ClickRoundtripTest.jl)), so a walk
retains one whole pipeline per caret. That is why the suites are so heavy — on `main`:
`typeins` 5.3 GB, `click_roundtrips` 4.1 GB, `nav_invariants` 3.5 GB peak RSS.

(On the syntax branch `nav_invariants` is 7.4 GB, but that is **not** a regression: Phase 1
fixed examples that previously threw immediately — `mixed` alone now walks 499 carets where
it used to die — so more walks actually run. Every phase after Phase 1 is flat.)

## The detector

[`CellTest.jl`](../../package/kernel/test/cell/CellTest.jl) — *"an upstream cell does not
retain a discarded downstream cell"*. Builds 100 computed cells that read one source,
forces them, drops them, GCs, and asserts the source's `dependents` is back where it
started. Currently `@test_broken` (they all survive). **When the fix lands this flips to an
unexpected pass — promote it to `@test`.**

## The fix — undecided, needs the seal broken

`ReactiveCell.jl` is sealed, and `dependents` is written on **every** cell read inside a
computation, so this is on the hot path. Do not patch it casually.

1. **Weak `dependents`** — the architecturally correct fix: the edge exists to propagate
   invalidation, not to own. A discarded pipeline's cells become collectable and
   invalidation skips the dead ones. **Risk:** a `WeakRef`/`WeakKeyDict` insert on every
   dependency registration; the cell-kinds work already found that runtime branches on the
   reactive read path cost ~2×, so this must be benchmarked before and after.
2. **Explicit disposal** — keep `dependents` strong, add `dispose!(iomap)` that walks a
   discarded pipeline and calls the existing `_detach_upstream!` on each of its cells; make
   every re-printing caller invoke it. Leaves the hot path untouched, but correctness rests
   on discipline: the leak returns wherever someone forgets.

   **Weakened by the structural-edit finding.** Disposal is tractable for a whole discarded
   pipeline, which has an owner and an obvious moment of death. It is *not* tractable for the
   cells a printer sheds mid-recompute: there is no `iomap` to dispose, no owner, and no
   moment — a node is simply rebuilt and its old spans become garbage. Those are exactly the
   ~3.4 edges per structural edit, and disposal cannot reach them. So (2) fixes the tests and
   leaves the editor leaking.

**Recommendation: (1).** The structural-edit leak is inside a single live pipeline, where
there is nothing to "dispose" — only (1) reaches it.

## Open questions

- Benchmark the read path (`Base.getindex(::ReactiveCell)`) before committing to (1). This is
  the one real objection: `dependents` is written on every cell read inside a computation, and
  the cell-kinds work found runtime branches there cost ~2×.
- A weak set makes GC timing observable; the detector already forces GC, but invalidation must
  tolerate entries that have been collected.
- `deps` (downstream → upstream) can stay strong: it points at the long-lived document, which
  is alive anyway. Only `dependents` must weaken.
