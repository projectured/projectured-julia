# The reactive dependency edge owns its reader — **FIXED**

`ReactiveCell.dependents` was a strong `Set{ReactiveCell}`. An upstream cell therefore
**owned** every downstream cell that had ever read it, and a document pinned every
projection pipeline it had ever been printed through, plus every span a printer shed while
recomputing.

It is now a `Vector{WeakRef}`: the edge propagates invalidation and owns nothing.

## What it bought

Identical behaviour, on every suite, to the assertion — and a third to a sixth of the memory:

| suite | peak RSS before | after | result |
|---|---|---|---|
| `test_typeins` | 5.27 GB | **0.89 GB** | 1187 / 23 broken — unchanged |
| `test_click_roundtrips` | 4.07 GB | **1.00 GB** | 26 / 1 / 6 — unchanged |
| `test_text_nav_invariants_all` | 3.54 GB | **1.00 GB** | 219 / 34 broken — unchanged |
| `test_domain` | 1.94 GB | **1.37 GB** | 125990 / 93 / 1 / 9 — unchanged |

(Loading the packages alone costs 0.64 GB, so the suites now barely allocate above their
own baseline. The 93 `test_domain` failures are pre-existing on `main` — they are the
`XmlAttribute` ones Phase 1 fixes on the syntax branch — and are untouched by this.)

`test_kernel` 431 / 0 / 0 / 0, `test_base` 97, `test_visual` 51895 / 0 / 0 / 1.

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

## The fix — benchmarked; the objection does not survive

`ReactiveCell.jl` is sealed and `dependents` is written on **every** cell read inside a
computation, so the standing objection was performance. It was worth checking, and the
answer is clean: **the naive weak fix really is too slow, and the right one is faster than
what we have today.**

### The dependents set is TINY

Across the 4173 live cells of a healthy `json` pipeline (one print, one force — before any
re-print has leaked into it):

```
mean=0.85   median=1   p90=2   p99=3   p99.9=4   MAX=40
cells with >16 dependents: 1        with >64: 0
```

That is the fact everything else follows from. At size 1–4, hashing is pure overhead.

### Candidates, measured

Re-registering an **already-present** dependent — what happens on every cell read inside a
computation, and therefore the only number that really matters:

| dependents size | `Set` (today) | `WeakKeyDict` | `Vector{WeakRef}` |
|---|---|---|---|
| 1 | 5.9 ns | 42.4 ns | **1.6 ns** |
| 4 | 6.6 ns | 43.6 ns | **2.2 ns** |
| 16 | 6.0 ns | 42.0 ns | **4.1 ns** |

And the other two operations, at the realistic p50–p99 sizes:

| op | `Set` (today) | `Vector{WeakRef}` |
|---|---|---|
| detach (`_detach_upstream!`) | 13.1–13.2 ns | **8.4–10.2 ns** |
| iterate (`_invalidate_dependents!`) | 4.0–5.1 ns | **0.4–1.2 ns** |
| bytes per new edge | 100 B | **73 B** |

- **`WeakKeyDict` is 7× slower** on the hot path — its lock dominates. This is the fix to
  avoid, and it is the one you would reach for first.
- **`Vector{WeakRef}` with a linear identity scan is ~3× FASTER than today's `Set`**, faster
  to detach, 4–10× faster to invalidate, and allocates less. It is weak, so it fixes the leak.

The crossover where `Set` wins back is ~32 dependents. Exactly one cell in the pipeline
exceeds 16 (max 40); on it, registration would cost ~17 ns instead of ~7 ns. If that ever
matters, spill to a hash set above a threshold — but nothing in the measurements asks for it.

**A second-order win:** the sets are only small in a *healthy* graph. The leak inflates them
(274 dependents per document cell after a single caret walk), so today's code gets steadily
slower as it leaks — every invalidation walks the dead entries. Fixing the leak shrinks the
sets, which speeds invalidation up as well.

### The change

```julia
-   dependents::Set{ReactiveCell}      # strong: OWNS every reader, for ever
+   dependents::Vector{WeakRef}        # weak: propagates invalidation, owns nothing
```

- **register**: linear identity scan (`v[i].value === observer`); if absent, `push!(WeakRef(observer))`.
  Prune collected entries opportunistically during the scan the code is doing anyway.
- **detach**: linear scan + `deleteat!`.
- **invalidate**: iterate, skipping entries whose `value === nothing` (already collected).

`deps` (downstream → upstream) stays a strong `Set`: it points at the long-lived document,
which is alive regardless, and it is the direction that must NOT be weak (a cell must keep
its own upstream links to detach them).

Requires unsealing `package/kernel/main/cell/ReactiveCell.jl`.

## Open questions

- A weak set makes GC timing observable: `_invalidate_dependents!` must tolerate entries that
  have already been collected (skip them), and the detector forces GC before asserting.
- Worth re-running the cell-kinds read-path benchmark after the change to confirm the ~3×
  micro win survives in the real `Base.getindex(::ReactiveCell)` (it should — the registration
  is the only thing that changes).
