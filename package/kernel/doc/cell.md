# Reactive cells

The reactive cell system is the foundation of ProjecturEd's incrementality. It is a
lightweight pull-based reactive engine that replaces the original Common Lisp
ProjecturEd's `hu.dwim.computed-class`. It is **layer 1 of the kernel** — the bottom
of the dependency DAG, the one part with no kernel dependencies that everything else
is built on. The engine lives in
[CellModule.jl](../../../package/kernel/main/cell/CellModule.jl); every other layer
is built on top of it.

This guide leads with the concepts and how-to (what a cell is, how tracking and
invalidation work, the invariants, and the idioms you will meet) and then describes
the *structure* of the cell layer — its modules and how they fit together.

## Cell

A `Cell` is the only reactive primitive. It is either *primitive* (holds a value)
or *computed* (holds a zero-arg thunk):

```julia
c = Cell(42)                      # primitive
c = Cell(() -> upstream[] + 1)    # computed
c = Cell(f; as_value=true)        # primitive holding f AS a value (a Function/Cell,
                                  #   not a thunk — the bare Cell(f) would compute it)
```

The struct also tracks `valid`, the set of cells it reads from (`deps`), and the
set of cells that read it (`dependents`).

### Reading and writing

```julia
c[]               # read  — triggers recompute if invalid; returns the value
c[] = v           # write — converts c to a primitive, invalidates dependents
set_value!(c, v)     # same as c[] = v
set_function!(c, thunk)  # switch c to a computed cell; previous deps detached
is_up_to_date(c)     # has the cached value been invalidated since last compute?
```

`peek(c)` is an **untracked** read — it returns the value without registering a
dependency (cf. Solid's `untrack`), a general reactive primitive that the animation
clock uses to *sample* time rather than subscribe to it.

## Dependency tracking

Tracking is automatic via a per-task `_computing` stack (task-local, so
concurrent evaluations never share it):

1. When a computed cell starts evaluating, it pushes itself onto the stack.
2. Every `c[]` that happens during evaluation registers an edge `observer ← c`
   (the observing computed cell becomes a downstream dependent of `c`).
3. When the thunk returns, the cell pops off the stack and is marked valid.

Therefore, no part of the code needs to declare dependencies explicitly — they
arise as a side effect of reading.

## Invalidation

Invalidation propagates eagerly, recomputation is lazy:

- `c[] = v` or `set_function!(c, f)` walks the transitive set of `c.dependents` and
  marks them invalid (`valid = false`). The actual recomputation does NOT run.
- The next `c[]` on an invalid cell calls `recompute!(c)`, which detaches old
  upstream links, evaluates the thunk under tracking, and refreshes the value.

This is the pull-based / lazy strategy. It is essential to how the projection
printer stays incremental: invisible parts of the output don't recompute even
when their inputs change, because nothing pulls on them.

## Invariants the engine relies on

These hold by construction in the current code, but nothing checks them — break
one and you get a hang, a stale render, or a stack overflow rather than an error.

- **The dependency graph must be acyclic.** `recompute!` evaluates a thunk while
  its cell sits on the `_computing` stack; if that thunk (transitively) reads its
  own cell, recomputation recurses forever. The engine only skips a *direct*
  self-edge (`observer !== c`) — it does **not** detect multi-cell cycles. A
  computed cell must never depend on itself through any chain.
- **Invalidation is monotone: invalid ⟹ all transitive dependents are already
  invalid.** `_invalidate_walk!` stops descending the moment it meets an
  already-invalid dependent, trusting that that cell propagated its own
  invalidation when it first became invalid. This holds only because every write
  walks the *full* transitive closure and `recompute!` is the only thing that
  re-validates. Never hand-set `valid`, and never partially invalidate a subset
  of dependents — either breaks the early-stop and leaves cells stale forever.
- **Propagation is write-driven, not value-driven.** Writing a cell invalidates
  its dependents unconditionally, with **no equality check** — setting a cell to
  the value it already holds still recomputes everything downstream, and a thunk
  that recomputes to an unchanged value does *not* stop propagation (the engine
  is not glitch-free / not value-stabilising). So `c[] = c[]` is not free; a
  printer that rewrites `selection` every frame pays for the whole subtree it
  feeds. See [the design-decisions note](../../../documentation/design-decisions.md#10-propagation-is-write-driven-not-value-driven).
- **Thunks must be pure and deterministic in their cell inputs.** A thunk may run
  zero, one, or many times for a single logical change, and its cached result is
  reused until invalidation. It must therefore have no side effects and depend
  only on the cells it reads (no clocks, RNG, or external mutable state) — or the
  cache is wrong. This is a correctness requirement, not a style preference.
- **Invalidation recurses on the call stack**, so its depth is bounded by the
  longest dependency chain (≈ document tree depth). Pathologically deep documents
  can overflow the stack; in practice trees stay shallow enough that this is a
  theoretical limit, noted here so it isn't a surprise.

## How the cell appears in the rest of the codebase

Cells are *not* normally accessed directly in domain code. Every
`@document`, `@projection`, and `@iomap` macro generates a struct whose fields
are stored as `Cell` but are read and written *transparently*: `obj.f` reads the
underlying cell's value, `obj.f = v` writes into it, and `getfield(obj, :f)` is the
escape hatch that returns the raw `Cell`. This is why the bulk of the code reads
like ordinary Julia struct manipulation even though every field is reactive. The
kernel codegen behind this is [`@cell_struct`](#cellstructmodule--the-transparent-cell-struct-codegen)
below; the full field-wrapping mechanics live in [the macros guide](macros.md).

## Idioms you will encounter

- **Computed cell sharing a primitive cell** — selection cells are passed
  through unchanged between domain and projection (e.g. `JsonString.selection`
  is the very same Cell as the produced `SyntaxLeaf.selection`), so a single
  write at the document level instantly invalidates the rendered cursor.
- **`Cell(() -> ...)` for derived values** — projections wire a computed cell
  that reads upstream cells, often to translate a path from one domain to
  another (e.g. `map_reference_forward(p, nothing, j.selection)`).
- **`Cell(Cell[...])` inside `CellVector`** — the outer cell tracks the
  *structure* (the vector itself); each inner cell tracks one *element*. A
  structural change invalidates the outer cell; a value change invalidates
  only that slot, which is how the editor avoids re-rendering siblings.
- **`set_function!(getfield(obj, :field), () -> …)`** — used to lazily attach a
  computation to a field after construction; common in
  `CellVector(f::Function)` and child-element generators.

## Best practices

- Wrap document fields in Cells via the `@document` macro rather than hand-rolling.
- Use computed cells for derived state so the system can invalidate it.
- Never side-effect inside a thunk — the thunk may run zero, one, or many times.
- Don't read a cell during construction of a struct that hasn't finished its
  iomap wiring — use `Cell(() -> ...)` to defer the read.

## Layer structure

The layer lives in [package/kernel/main/cell/](../../../package/kernel/main/cell/):
the instrumentation counter module, the cell engine, the transparent-cell struct
codegen, and the clock, loaded in this order:

```
PerformanceCounter.jl   (PerformanceCounterModule)   — instrumentation
        │  @count_performance imported by ↓
CellModule.jl            (CellModule)                 — the cell kinds, one file each:
        ├─ AbstractCell.jl    — the AbstractCell{T} base + shared protocol
        ├─ ReactiveCell.jl    — the pull-based reactive engine (bumps via @count_performance)
        ├─ MutableCell.jl     — plain mutable box, no reactive bookkeeping
        ├─ ImmutableCell.jl   — read-only, zero-cost wrapper
        └─ CellUnwrap.jl      — unwrap_cell: reading a slot that may hold a cell
        │  Cell / AbstractCell used by ↓
CellStructModule.jl      (CellStructModule)           — transparent-Cell struct codegen:
        ├─ StructPlan.jl      — the struct-definition parse the struct macros share
        └─ CellStruct.jl      — @cell_struct + its expr-builders
        │  @cell_struct used by ↓
Clock.jl                 (ClockModule)                — the animation clock
```

`AbstractCell.jl` is the layer's **interface file**: it declares the contract and
nothing else (AR-INTERFACE-DECLARES-ONLY). `unwrap_cell` therefore sits in the sibling `CellUnwrap.jl`
rather than beside the type it dispatches on — it has a body, and a body is
implementation.

The layer is everything at **cell dependency height**, not the reactive engine
alone: `PerformanceCounter` is a store the engine calls, `CellStructModule` is
codegen *over* `Cell`, and `Clock` is a `@cell_struct` with one reactive `time`
field.
A clock is deliberately **not** a `Document` — nothing navigates into it,
selects inside it, or projects it — so it does not belong in the document layer
above; it imports `CellModule` and nothing else. Each editor owns a private
`Clock`, ticked from OS time in its read-eval-print loop; a shared wall clock
reflects real time for reader-armed animations that have no editor of their own.
See the module docstring of `cell/Clock.jl` for the full API.

The load order is the dependency order the include-order guard checks.

## CellModule — the cell kinds

A cell is a typed box `AbstractCell{T}`; the kind decides its behavior. `Cell` is
`ReactiveCell{Any}`, the pull-based reactive graph described above: a cell is either
*primitive* (a value) or *computed* (a zero-arg thunk); reading a cell inside another
cell's thunk records a dependency edge; writing a cell eagerly invalidates its
transitive dependents, and recomputation is lazy (on the next read). This is the
incrementality substrate the whole projection pipeline rides on. `MutableCell{T}`
and `ImmutableCell{T}` are non-reactive boxes — a mutable one for high-frequency
state, a read-only one for derived content — for values that do not need the graph.

Public surface: `Cell`, `AbstractCell`, `ReactiveCell`, `MutableCell`,
`ImmutableCell`, `set_value!`, `set_function!`, `is_up_to_date`, `unwrap_cell`,
and `peek` (an untracked read extending `Base.peek`).

## CellStructModule — the transparent-Cell struct codegen

`CellStructModule` (built on `CellModule` via `using ..CellModule`) is the
compile-time struct toolkit, split out of the runtime engine so a reader of the
reactive kinds never wades through AST-rewriting codegen. `@cell_struct struct T
[<: Super] … end` turns every field into a `::Cell` field and generates an
**auto-wrapping inner constructor** (raw values wrap in `Cell(v)`, Cells pass
through — this is how construction-time cell sharing works), **transparent
accessors** (`obj.f` reads the cell value, `obj.f = v` writes into it; raw cells
via `getfield(obj, :f)`), and — when a field declares a `field::T = value`
default — a **keyword constructor** with the `Base.@kwdef` optional/required
split. No supertype is injected; the struct keeps what the definition wrote.

The macro is assembled by `cell_struct_exprs(structdef)`, which composes two
module-internal expr-builders (`cell_struct_autowrap_ctor`,
`cell_struct_property_accessors`) with the exported keyword/positional builders
(`cell_struct_kw_params`, `cell_struct_kwctor`, `cell_struct_positional_ctors`)
and the `StructPlan` parse — together the **composition seam for macro
authors**: `@iomap` and `@projection` (projection layer) inject their default
supertype and return `esc(cell_struct_exprs(structdef))` wholesale; `@document`
(document layer) generates its own kind-parameterized stem and reuses only the
keyword-ctor builders. The builders emit `Cell`, `new`, `getfield` as bare names
that resolve in the delegating macro's *caller* scope, so the emitted code needs
only `Cell` in scope; invoking `@cell_struct` itself (or a macro built on it)
requires `using ..CellStructModule`. See [the macros guide](macros.md) for the
full field-wrapping and `@document` codegen details.

Public surface: `@cell_struct`, `cell_struct_exprs`, `cell_struct_kw_params`,
`cell_struct_kwctor`, `cell_struct_positional_ctors`, `struct_macro_default`, and
the `StructPlan` parse toolkit (`StructPlan`, `struct_plan`, `add_plan_field!`,
`retype_fields!`, `declared_value_types`, `field_cell_kinds`, `cell_kind_of`,
`required_count`, `trailing_default_count`). The expr-builders
`cell_struct_autowrap_ctor` and `cell_struct_property_accessors` are
module-internal.

## PerformanceCounterModule — instrumentation

Conditionally-compiled counters of `Dict{Symbol,Int}`, with **no process-global
store**. The `Cell` engine bumps the reactive counters — `:reads`, `:computes`,
`:invalidations`, `:writes` — via `@count_performance` on the hot path, and the
editor folds per-stage timings into `:read_time`, `:evaluate_time`,
`:print_time`.

The active store is a **task-local dynamic binding** (`ScopedValue`):
`with_performance_counters(f)` binds a fresh dict for the dynamic extent of `f`,
and everything that runs inside counts into it. Outside any such scope the binding
is `nothing`, so an unscoped cell operation counts nothing and shares no state —
which is what lets many editors run in one process without their counters
colliding (AR-PER-EDITOR-STATE). This module loads **first** so `ReactiveCell` can import the
bump macro.

Counting is **compiled out by default** — `PERFORMANCE_COUNTERS_ENABLED` is
seeded at precompile from `PROJECTURED_PERFORMANCE_COUNTERS` and defaults off, so
a normal build carries no instrumentation: `@count_performance`,
`record_performance!`, and `@performance_time` expand to `nothing`. Set the
environment variable to `true` and recompile to profile (or to run the
count-based demos/tests).

Public surface: `with_performance_counters(f, store=…)` (bind a store for `f`),
`get_performance_counters()` (a copy of the active store, empty outside a scope),
`record_performance!(key, n)` (fold in an external measurement),
`@performance_time key expr` (time `expr`, record the elapsed ns under `key`), and
`@count_performance key` (the hot-path bump). The editor's read-eval-print loop
binds a fresh store and reports it every frame (see
[Editor.run_editor!](../../../package/kernel/main/editor/Editor.jl)), which is the
easiest way to profile what work a particular edit triggered.

Animation clock: `ClockModule` in the cell layer. See
`cell/Clock.jl` for the current API (`Clock`, `get_reactive_time`,
`get_time`, `tick!`, `seek!`, `get_wall_clock`).
