# Reactive cells

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The reactive cell system is the foundation of ProjecturEd's incrementality. It is a
lightweight pull-based reactive engine that replaces the original Common Lisp
ProjecturEd's `hu.dwim.computed-class`. It is a layer of the kernel. It imports
only the performance layer, which counts its reads and writes, and every layer
above it builds on it. The engine lives in
[CellModule.jl](../../../source/kernel/cell/CellModule.jl).

This guide leads with the concepts and how-to (what a cell is, how tracking and
invalidation work, the invariants, and the idioms you will meet) and then describes
the *structure* of the cell layer: its modules and how they fit together.

## Cell

A `Cell` is the only reactive primitive. A cell holds a *value* or a
*computation*: a function with no argument that computes its value.

```julia
c = Cell(42)                                # holds a value
c = Cell(@computation upstream[] + 1)       # holds a computation
c = Cell(f)                                 # holds the function f as a value
c = ReactiveCell{Int}(@computation 2 * n[])  # a typed cell that holds a computation
```

Which of the two a cell holds depends on the *spelling*, never on what the value
happens to be. A `Computation` is the only thing that makes a cell compute:
`@computation expr` makes one for an expression, and `Computation(f)` makes one
for a function `f` that exists already. Every other argument is stored,
callables included, so a cell can hold a callback or a predicate as data. A
`Computation` is cell vocabulary rather than a value: the cell that gets it
keeps the function and drops the marker. The non-reactive kinds reject it,
because only a `ReactiveCell` can run a computation.

Inside an argument list, a macro call without parentheses takes every argument
after it. Where an argument follows, write `@computation(expr)`, as in
`pair(@computation(a[] + 1), b)`. `@computation f` computes the function `f` as
a value, and does not call it; write `Computation(f)` for that.

The struct also tracks `valid`, the set of cells it reads from (`dependencies`),
and the set of cells that read it (`dependents`).

### Read and write

```julia
c[]                           # read: compute first if invalid, and return the value
c[] = v                       # write a value, and invalidate the dependents
c[] = @computation expr       # write a computation, and invalidate the dependents
set_cell_value!(c, v)         # the same as c[] = v
set_cell_computation!(c, f)   # the same as c[] = Computation(f)
is_cell_up_to_date(c)         # can the next read return the value with no computation?
```

`peek(c)` is an **untracked** read — it returns the value without registering a
dependency (cf. Solid's `untrack`), a general reactive primitive that the animation
clock uses to *sample* time rather than subscribe to it.

## Dependency tracking

Tracking is automatic. Each task has its own computing stack, so concurrent
evaluations never share it:

1. When a computed cell starts evaluating, it pushes itself onto the stack.
2. Every `c[]` that happens during evaluation registers an edge `observer ← c`
   (the observing computed cell becomes a downstream dependent of `c`).
3. When the computation returns, the cell pops off the stack and is marked valid.

Therefore, no part of the code needs to declare dependencies explicitly — they
arise as a side effect of reading.

## Invalidation

Invalidation propagates eagerly, recomputation is lazy:

- `c[] = v` or `set_cell_computation!(c, f)` walks the transitive set of `c.dependents` and
  marks them invalid (`valid = false`). The actual recomputation does NOT run.
- The next `c[]` on an invalid cell calls `_recompute!(c)`, which detaches old
  upstream links, runs the computation under tracking, and refreshes the value.

This is the pull-based / lazy strategy. It is essential to how the projection
printer stays incremental: invisible parts of the output do not recompute even
when their inputs change, because nothing pulls on them.

## Invariants the engine relies on

These hold by construction in the current code, but nothing checks them — break
one and you get a hang, a stale render, or a stack overflow rather than an error.

- **The dependency graph must be acyclic.** `_recompute!` runs a computation while
  its cell sits on the computing stack; if that computation (transitively) reads its
  own cell, recomputation recurses forever. The engine only skips a *direct*
  self-edge (`observer !== c`). It does **not** detect multi-cell cycles. A
  computed cell must never depend on itself through any chain.
- **Invalidation is monotone: invalid ⟹ all transitive dependents are already
  invalid.** `_invalidate_dependents!` stops descending the moment it meets an
  already-invalid dependent, trusting that that cell propagated its own
  invalidation when it first became invalid. This holds only because every write
  walks the *full* transitive closure and `_recompute!` is the only thing that
  re-validates. Never hand-set `valid`, and never partially invalidate a subset
  of dependents — either breaks the early-stop and leaves cells stale forever.
- **Propagation is write-driven, not value-driven.** Writing a cell invalidates
  its dependents unconditionally, with **no equality check** — setting a cell to
  the value it already holds still recomputes everything downstream, and a
  computation that returns an unchanged value does *not* stop propagation (the engine
  is not glitch-free / not value-stabilising). So `c[] = c[]` is not free; a
  printer that rewrites `selection` every frame pays for the whole subtree it
  feeds. See [the design-decisions note](../../design/architecture-decisions.md#10-propagation-is-write-driven-not-value-driven).
- **Computations must be pure and deterministic in their cell inputs.** A computation may run
  zero, one, or many times for a single logical change, and its cached result is
  reused until invalidation. It must therefore have no side effects and depend
  only on the cells it reads (no clocks, RNG, or external mutable state).
  Otherwise the cache is wrong. This is a correctness requirement, not a style
  preference.
- **Invalidation recurses on the call stack**, so its depth is bounded by the
  longest dependency chain (≈ document tree depth). Pathologically deep documents
  can overflow the stack; in practice trees stay shallow enough that this is a
  theoretical limit, noted here so it is not a surprise.
- **A computation retries only in an older world.** A computation that calls a
  method newer than the world of the task that reads it throws a `MethodError`,
  and then it runs once more through `Base.invokelatest`. In the latest world a
  `MethodError` is real, so no computation retries, and each computation of a
  chain runs once.

## How the cell appears in the rest of the codebase

Cells are *not* normally accessed directly in domain code. Every
`@document`, `@projection`, and `@iomap` macro generates a struct whose fields
are stored as `Cell` but are read and written *transparently*: `obj.f` reads the
underlying cell's value, `obj.f = v` writes into it, and `getfield(obj, :f)` is the
escape hatch that returns the raw `Cell`. This is why the bulk of the code reads
like ordinary Julia struct manipulation even though every field is reactive. The
kernel codegen behind this is [`@cell_struct`](#cellstructmodule-the-struct-of-cells)
below; the full field-wrapping mechanics live in [the macros guide](macros.md).

## Idioms you will encounter

- **A computed cell that shares a value cell** — selection cells are passed
  through unchanged between domain and projection (e.g. `JsonString.selection`
  is the very same Cell as the produced `SyntaxLeaf.selection`), so a single
  write at the document level instantly invalidates the rendered cursor.
- **`Cell(@computation ...)` for derived values** — projections wire a computed cell
  that reads upstream cells, often to translate a path from one domain to
  another (e.g. `map_reference_forward(p, nothing, j.selection)`).
- **`Cell(Cell[...])` inside `CellVector`** — the outer cell tracks the
  *structure* (the vector itself); each inner cell tracks one *element*. A
  structural change invalidates the outer cell; a value change invalidates
  only that slot, which is how the editor avoids re-rendering siblings.
- **`set_cell_computation!(getfield(obj, :field), () -> …)`** — used to lazily attach a
  computation to a field after construction; common in
  `CellVector(Computation(f))` and child-element generators.

## Best practices

- Wrap document fields in Cells via the `@document` macro rather than hand-rolling.
- Use computed cells for derived state so the system can invalidate it.
- Never cause a side effect inside a computation: it may run zero, one or many times.
- Do not read a cell during construction of a struct that has not finished its
  iomap wiring — use `Cell(@computation ...)` to defer the read.

## Layer structure

The layer is the folder [source/kernel/cell/](../../../source/kernel/cell/), and
`CellModule` is its one module. One layer sits on each side of it: the
performance layer below, whose `@count_performance` the engine counts with, and
the struct layer above, whose `@cell_struct` builds structs of cells. This guide
describes both of them too, in the sections below.

```
performance/PerformanceModule.jl  (PerformanceModule) — the counters
        │  @count_performance, used by ↓
cell/CellModule.jl                (CellModule)        — the cell kinds, one file each:
        ├─ CellInterface.jl   — AbstractCell{T} and the generics that every kind answers
        ├─ CellComputation.jl — Computation and @computation: a function is a computation, not a value
        ├─ ReactiveCell.jl    — the pull-based reactive engine
        ├─ MutableCell.jl     — a plain mutable box, with no reactive bookkeeping
        ├─ ImmutableCell.jl   — a read-only box
        └─ CellDefaults.jl    — the bodies of the other generics, one method for each kind
        │  Cell and AbstractCell, used by ↓
struct/CellStructModule.jl        (CellStructModule)  — the struct of cells:
        ├─ CellStructPlan.jl  — the parse of a struct definition that the struct macros share
        └─ CellStruct.jl      — @cell_struct and its expression builders
```

`CellInterface.jl` is the **interface file** of the layer: it declares the
contract and nothing else. The read `c[]`, the untracked read `peek` and
`is_cell_up_to_date` have their bodies in the file of each kind. The bodies of
`unwrap_cell`, `copy_cell_as`, `is_computed_cell` and `has_dependent_cells` are
in the sibling `CellDefaults.jl`.

The animation clock is a `@cell_struct` that is a *client* of the engine rather
than part of it. It is its own layer, `clock/ClockModule.jl`, above the struct
layer. It imports `CellModule` and `CellStructModule` and nothing else, and its
`ClockModule` docstring carries the full API.

The load order is the dependency order the include-order guard checks.

## CellModule — the cell kinds

A cell is a typed box `AbstractCell{T}`; the kind determines its behavior. `Cell` is
`ReactiveCell{Any}`, the pull-based reactive graph described above: a cell holds
a *value* or a *computation*; reading a cell inside the computation of another
cell records a dependency edge; writing a cell eagerly invalidates its
transitive dependents, and recomputation is lazy (on the next read). This is the
incrementality substrate the whole projection pipeline depends on. `MutableCell{T}`
and `ImmutableCell{T}` are non-reactive boxes for values that do not need the graph:
a mutable one for high-frequency state, a read-only one for derived content.

Public surface: `AbstractCell`, `is_cell_up_to_date`, `unwrap_cell`,
`copy_cell_as`, `is_computed_cell`, `has_dependent_cells`, `Computation`, `@computation`,
`ReactiveCell`, `Cell`, `set_cell_value!`, `set_cell_computation!`,
`MutableCell` and `ImmutableCell`. `peek` is an untracked read, a method of
`Base.peek`.

## CellStructModule — the struct of cells

`CellStructModule` is the struct layer, and it uses `CellModule` and nothing else.
`@cell_struct struct T [<: Super] … end` writes each field as a cell and generates
three parts:

- An inner constructor `T(values…)`. It wraps each value in a cell of the kind of
  its field. A cell of the type of the field is the cell of the field, so two
  structs can share one cell. A cell of another type throws a `MethodError`, so a
  field never holds a cell as its value.
- `getproperty` and `setproperty!`. `obj.f` reads the value of the cell,
  `obj.f = v` writes it, and `getfield(obj, :f)` returns the cell.
- A keyword constructor, when a field has a default `f = value`. It has the
  optional and required keywords of `Base.@kwdef`.

A kind is a type: `ReactiveCell`, `ImmutableCell` or `MutableCell`. A field
`f::ImmutableCell{T}` or `f::MutableCell{T}` has that kind. Every other field has
the kind that the macro gets before `struct`, or `ReactiveCell` without one. A
reactive field is a `Cell`, and an immutable or a mutable field is a cell of the
declared value type. The struct keeps its supertype and its type parameters.
`T{A}(values…)` always works, and `T(values…)` works when each parameter is the
value type of a field.

The generated code holds the kinds and `Cell` as objects, so a module that calls
`@cell_struct` needs only the macro in scope. The code names `new`, `getfield` and
`Base` without a module, so `build_cell_struct_exprs` returns it unescaped and
the macro escapes it.

The builders are public, so a macro that makes a struct of cells with parts of its
own starts from them:

- `make_cell_struct_plan` reads a `struct` definition into a `CellStructPlan`.
- The `get_cell_struct_…` functions and `find_cell_struct_parameter_slots` answer
  questions about the fields and the type parameters of a plan.
- The `build_cell_struct_…` functions return the parts as expressions, and
  `build_cell_struct_exprs` returns all of `@cell_struct`.
- `parse_cell_struct_macro_arguments` reads the kind before `struct`.

[The macros guide](macros.md) says how `@iomap`, `@projection` and `@document`
use them. At run time, `get_cell_struct_kind(x)` returns the kind of the cell in
the first field of `x`. A generated constructor calls
`get_cell_struct_argument_type(argument)` to bind a type parameter: it returns the
value type of a cell, or the type of any other value.

Public surface: `CellStructPlan`, `make_cell_struct_plan`, `add_cell_struct_field!`,
`retype_cell_struct_fields!`, `get_cell_struct_value_types`,
`get_cell_struct_field_kinds`, `get_cell_struct_parameter_names`,
`find_cell_struct_parameter_slots`, `get_cell_struct_trailing_default_count`,
`get_cell_struct_required_count`, `build_cell_struct_field_type`,
`build_cell_struct_keyword_parameters`, `build_cell_struct_keyword_constructor`,
`build_cell_struct_positional_ctors`, `build_cell_struct_exprs`,
`parse_cell_struct_macro_arguments`, `@cell_struct`, `get_cell_struct_argument_type` and
`get_cell_struct_kind`.

## PerformanceModule — instrumentation

Conditionally-compiled counters, with **no process-global store**. A store keeps
counts and times apart. The `Cell` engine bumps the reactive counts — `:reads`,
`:computes`, `:invalidations`, `:writes` — via `@count_performance` on the hot
path, and the editor measures its stages into the times `:read_time`,
`:evaluate_time` and `:print_time`, in nanoseconds, with
`@measure_performance_time`.

The active store is a **task-local dynamic binding** (`ScopedValue`):
`with_performance_counters(f)` binds a fresh store for the dynamic extent of `f`,
and everything that runs inside counts into it. Outside any such scope the binding
is `nothing`, so an unscoped cell operation counts nothing and shares no state.
That is what lets many editors run in one process without their counters
colliding (PAR-PER-EDITOR-STATE). This layer loads before the cell layer, because
`CellModule` uses it.

Counting is **compiled out by default**. `PERFORMANCE_COUNTERS_ENABLED` is
seeded at precompile from `PROJECTURED_PERFORMANCE_COUNTERS` and defaults off, so
a normal build carries no instrumentation: `@count_performance` expands to
`nothing`, and `@measure_performance_time` to its expression. Set the
environment variable to `true` and recompile to profile (or to run the
count-based demos/tests).

Public surface: `with_performance_counters(f)` (bind a fresh store for `f`),
`get_performance_counters()` (copies of the counts and the times of the active
store, both empty outside a scope), `@measure_performance_time key expr` (time
`expr`, add the elapsed ns to the time `key`), and `@count_performance key` (the
hot-path bump). The editor's read-eval-print loop
binds a fresh store and reports it every frame (see
[EditorModule.run_editor!](../../../source/kernel/editor/EditorModule.jl)), which is the
easiest way to profile what work a particular edit triggered.

Animation clock: `ClockModule` is its own kernel layer (`clock/`), above the
struct layer. See `clock/ClockModule.jl` for the API (`Clock`,
`get_reactive_clock_time`, `get_clock_time`, `set_clock_time!`, `get_wall_clock`).
