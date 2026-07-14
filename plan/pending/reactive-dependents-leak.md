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

## What leaks, and what does not

Measured on the `json` example (`plan/` scratch scripts, 2026-07-14):

| | live (post-GC) | `dependents` on document cells |
|---|---|---|
| one pipeline, 348 selection moves (**the editor's steady state**) | 706 MB → 706 MB | 36 470 → 36 470 |
| one caret walk (`_walk_cursor` re-prints per keystroke) | +690 MB **per walk** | +36 317 **per walk** |
| five walks | 723 → 3 478 MB, linear | 36 317 → 181 585, linear |

**The editor's steady state does not leak.** Recomputation detaches and re-registers its
own edges correctly, so moving the caret through a live pipeline is flat in both memory
and edge count.

**Discarded pipelines leak, in full.** `print_document` builds a fresh pipeline; each of
its cells registers itself in the `dependents` of every document cell it reads; when the
pipeline is thrown away nothing detaches it. `_walk_cursor` re-prints once per keystroke
([ClickRoundtripTest.jl](../../package/visual/test/editor/ClickRoundtripTest.jl)), so a
walk retains one whole pipeline per caret.

That is why the suites are so heavy — on `main`: `typeins` 5.3 GB, `click_roundtrips`
4.1 GB, `nav_invariants` 3.5 GB peak RSS. (On the syntax branch `nav_invariants` is
7.4 GB, but that is **not** a regression: Phase 1 fixed examples that previously threw
immediately — `mixed` alone now walks 499 carets where it used to die — so more walks
actually run. Every phase after Phase 1 is flat.)

Anything that re-prints leaks, so this is not only a test artifact: a projection change or
a document swap in the editor leaks the old pipeline too.

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
   every re-printing caller invoke it. Leaves the hot path untouched, but correctness then
   rests on discipline: the leak returns wherever someone forgets.

## Open questions

- Benchmark the read path (`Base.getindex(::ReactiveCell)`) before committing to (1).
- Does anything other than tests re-print in a loop? If the editor only ever re-prints on a
  projection change, (2) may be enough in practice — but (1) is still the correct model.
- A weak set can make GC timing observable; the detector may need to force GC (it does).
