# The reactive layer

Layer A of the kernel — the bottom of the dependency DAG, the one part with **no
kernel dependencies** that everything else is built on. This page is an overview of
the layer's *structure* (its modules and how they fit together). For the hands-on
"how do I use cells" guide — construction, reading/writing, invalidation semantics,
the invariants, and idioms — see the repository-level
[documentation/reactive-cells.md](../../../documentation/reactive-cells.md); this
page does not repeat it.

The layer lives in [src/reactive/](../src/reactive/) and is three single-purpose
modules, loaded in this order:

```
PerformanceCounter.jl   (PerformanceCounterModule)   — instrumentation
        │  _perf imported by ↓
Reactive.jl             (ReactiveModule)             — the Cell engine
        │  Cell used by ↓
EditorTime.jl           (EditorTimeModule)           — the animation clock
```

They were split out of a single `Reactive.jl` so each concern has its own home; the
load order above is the dependency order the include-order guard checks.

## ReactiveModule — the Cell engine

The core: the `Cell` type and the pull-based reactive graph. A `Cell` is either
*primitive* (a value) or *computed* (a zero-arg thunk). Reading a cell inside
another cell's thunk records a dependency edge; writing a cell eagerly invalidates
its transitive dependents, and recomputation is lazy (on the next read). This is
the incrementality substrate the whole projection pipeline rides on.

It also defines `peek` — an **untracked** read (read a cell's value without
registering a dependency), a general reactive primitive (cf. Solid's `untrack`)
that the animation clock uses to *sample* time rather than subscribe to it.

Public surface: `Cell`, `setval!`, `setfn!`, `isuptodate`, `peek`. See
[reactive-cells.md](../../../documentation/reactive-cells.md) for semantics and the
unchecked invariants (acyclic graph, monotone invalidation, write-driven
propagation, pure thunks).

## PerformanceCounterModule — instrumentation

A single process-global `Dict{Symbol,Int}` of counters plus its API. The `Cell`
engine bumps the reactive counters **inline on the hot path** — `:reads`,
`:computes`, `:invalidations`, `:writes` — and the editor folds per-stage timings
into `:read_time`, `:evaluate_time`, `:print_time`.

Because the increments are on the hottest path (`getindex` on every cell read),
this module loads **first** and `ReactiveModule` imports the shared `_perf` dict, so
the increments stay a bare `Dict` write rather than a cross-module function call.

Public surface: `perf_counters()` (a copy of the dict), `perf_reset!()`,
`perf_record!(key, n)` (fold in an external measurement), and `@perf_time key expr`
(time `expr`, record the elapsed ns under `key`). The editor's main loop resets and
reports these every frame, which is the easiest way to profile what work a
particular edit triggered.

## EditorTimeModule — the animation clock

A single global primitive cell, `EDITOR_TIME`, holding the current logical time in
seconds. The editor's main loop writes it once per frame via `tick!`; because cell
writes invalidate dependents, any computed cell that read the time is re-evaluated
on the next pull — which is all animation needs. It is layered *on top of* `Cell`,
so it loads **after** `ReactiveModule`.

Two reads, named so intent is obvious:

- `reactive_editor_time()` — **subscribe**. A tracked read; the calling cell becomes
  a dependent and re-runs every frame. Use inside an animated thunk.
- `editor_time()` — **sample**. An untracked read (via `peek`) that registers no
  dependency. Use to *arm* an animation (capture a start instant) without the
  arming code itself re-running every frame.

And `tick!(t)` — write the current logical time, invalidating everything that
subscribed. Driven by `Editor.run!` (wall-clock) and by `ProjecturedVideo`
(elapsed-time frames). See `package/example/src/document/RotatingVector.jl` for a
worked subscribe/sample example.
