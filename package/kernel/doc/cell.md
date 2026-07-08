# The cell layer

Layer 1 of the kernel — the bottom of the dependency DAG, the one part with **no
kernel dependencies** that everything else is built on. This page is an overview of
the layer's *structure* (its modules and how they fit together). For the hands-on
"how do I use cells" guide — construction, reading/writing, invalidation semantics,
the invariants, and idioms — see the repository-level
[documentation/reactive-cells.md](../../../documentation/reactive-cells.md); this
page does not repeat it.

The layer lives in [main/cell/](../main/cell/): the instrumentation counter module,
the cell module, and the animation clock, loaded in this order:

```
PerformanceCounter.jl   (PerformanceCounterModule)   — instrumentation
        │  _perf imported by ↓
CellModule.jl            (CellModule)                 — the cell kinds, one file each:
        ├─ AbstractCell.jl    — the AbstractCell{T} base + shared protocol
        ├─ ReactiveCell.jl    — the pull-based reactive engine (imports _perf)
        ├─ MutableCell.jl     — plain mutable box, no reactive bookkeeping
        └─ ImmutableCell.jl   — read-only, zero-cost wrapper
        │  Cell imported by ↓
Time.jl                 (TimeModule)                  — the global editor clock
```

The load order is the dependency order the include-order guard checks. The
animation clock (`TimeModule`) is a *use* of `Cell` (a single primitive cell that
the editor loop writes once per frame), not part of the engine, but it lives in
the cell layer because it depends on nothing else in the kernel and every
animated projection reads it — domain code that consumes `get_reactive_editor_time()`
therefore imports the cell-layer TimeModule directly, without pulling in the
editor loop.

## CellModule — the cell kinds

A cell is a typed box `AbstractCell{T}`; the kind decides its behavior. `Cell` is
`ReactiveCell{Any}`, the pull-based reactive graph: a cell is either *primitive* (a
value) or *computed* (a zero-arg thunk); reading a cell inside another cell's thunk
records a dependency edge; writing a cell eagerly invalidates its transitive
dependents, and recomputation is lazy (on the next read). This is the
incrementality substrate the whole projection pipeline rides on. `MutableCell{T}`
and `ImmutableCell{T}` are non-reactive boxes — a mutable one for high-frequency
state, a read-only one for derived content — for values that do not need the graph.

It also defines `peek` — an **untracked** read (read a cell's value without
registering a dependency), a general reactive primitive (cf. Solid's `untrack`)
that the animation clock uses to *sample* time rather than subscribe to it.

Public surface: `Cell`, `set_value!`, `set_function!`, `is_up_to_date`, `peek`. See
[reactive-cells.md](../../../documentation/reactive-cells.md) for semantics and the
unchecked invariants (acyclic graph, monotone invalidation, write-driven
propagation, pure thunks).

### `@cell_struct` — the transparent-Cell struct codegen

`CellStruct.jl` (a fragment of `CellModule`) defines the struct codegen every
declarative struct macro builds on: `@cell_struct struct T [<: Super] … end`
turns every field into a `::Cell` field and generates an **auto-wrapping inner
constructor** (raw values wrap in `Cell(v)`, Cells pass through — this is how
construction-time cell sharing works), **transparent accessors** (`obj.f`
reads the cell value, `obj.f = v` writes into it; raw cells via
`getfield(obj, :f)`), and — when a field declares a `field::T = value`
default — a **keyword constructor** with the `Base.@kwdef` optional/required
split. No supertype is injected; the struct keeps what the definition wrote.

The macro is assembled by `cell_struct_exprs(structdef)` from four exported
expr-builders (`cell_autowrap_ctor`, `cell_property_accessors`,
`cell_kw_params`, `cell_kwctor`) — together they are the **composition seam
for macro authors**: `@iomap` and `@projection` (projection layer) inject
their default supertype and return `esc(cell_struct_exprs(structdef))`
wholesale; `@document` (document layer) generates its own kind-parameterized
stem and reuses only the keyword-ctor builders. The builders emit `Cell`,
`new`, `getfield` as bare names that resolve in the delegating macro's
*caller* scope, so a module using any of these macros needs `Cell` in scope
and nothing else. See [macros.md](../../../documentation/macros.md).

Public surface: `@cell_struct`, `cell_struct_exprs`, `cell_autowrap_ctor`,
`cell_property_accessors`, `cell_kw_params`, `cell_kwctor`.

## PerformanceCounterModule — instrumentation

A single process-global `Dict{Symbol,Int}` of counters plus its API. The `Cell`
engine bumps the reactive counters **inline on the hot path** — `:reads`,
`:computes`, `:invalidations`, `:writes` — and the editor folds per-stage timings
into `:read_time`, `:evaluate_time`, `:print_time`.

Because the increments are on the hottest path (`getindex` on every cell read),
this module loads **first** and `ReactiveCell` imports the shared `_perf` dict, so
the increments stay a bare `Dict` write rather than a cross-module function call.

Public surface: `get_performance_counters()` (a copy of the dict), `reset_performance_counters!()`,
`record_performance!(key, n)` (fold in an external measurement), and `@performance_time key expr`
(time `expr`, record the elapsed ns under `key`). The editor's read-eval-print loop resets and
reports these every frame, which is the easiest way to profile what work a
particular edit triggered.

## TimeModule — the animation clock

A single global primitive cell, `EDITOR_TIME`, holding the current logical time in
seconds. The editor's read-eval-print loop writes it once per frame via `tick_editor_time!`; because cell
writes invalidate dependents, any computed cell that read the time is re-evaluated
on the next pull — which is all animation needs. It is layered *on top of* `Cell`,
so it loads **after** `CellModule`.

Two reads, named so intent is obvious:

- `get_reactive_editor_time()` — **subscribe**. A tracked read; the calling cell becomes
  a dependent and re-runs every frame. Use inside an animated thunk.
- `get_editor_time()` — **sample**. An untracked read (via `peek`) that registers no
  dependency. Use to *arm* an animation (capture a start instant) without the
  arming code itself re-running every frame.

And `tick_editor_time!(t)` — write the current logical time, invalidating everything that
subscribed. Driven by `Editor.run_editor!` (wall-clock) and by `ProjecturedVideo`
(elapsed-time frames). See `package/example/document/RotatingVector.jl` for a
worked subscribe/sample example.
