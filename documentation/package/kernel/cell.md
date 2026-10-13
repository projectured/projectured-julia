# Reactive cells

> **Kind:** reference · **Status:** current · **Stands on:** [architecture.md](architecture.md)

This guide says what a reactive cell holds, how a read records a dependency and a
write invalidates the readers, and which invariants the engine relies on. It then
describes the modules of the cell layer and of the struct layer above it. The
engine is in [ReactiveCell.jl](../../../source/kernel/cell/ReactiveCell.jl).

The cell layer is the base of the incremental work of ProjecturEd. It is a
pull-based reactive engine, and a layer of the kernel. It imports the
performance layer, which counts its reads and writes (see the
[performance guide](performance.md)), and the fault layer, whose
`is_fault_exception` a computation in a fault scope calls (see the
[fault guide](fault.md)). Every layer above it builds on it.

## Cell

`ReactiveCell`, with its alias `Cell` for any value type, is the only reactive
kind. A cell holds a *value* or a *computation*: a function with no argument that
computes its value.

```julia
c = Cell(42)                                # holds a value
c = Cell(@computation upstream[] + 1)       # holds a computation
c = Cell(f)                                 # holds the function f as a value
c = ReactiveCell{Int}(@computation 2 * n[])  # a typed cell that holds a computation
```

The *spelling* of the argument sets which of the two a cell holds, and the value
does not. A `Computation` is the only argument of a constructor or of `c[] =` that
makes a cell compute, and `set_cell_computation!` takes a plain function:
`@computation expr` makes one for an expression, and `Computation(f)` makes one
for a function `f` that exists already. A cell stores every other argument, a
function too, so a cell can hold a callback or a predicate as data. A
`Computation` is not a value: the cell that gets it keeps the function and drops
the marker. `MutableCell` and `ImmutableCell` throw an `ArgumentError` for it,
because only a `ReactiveCell` and an `UntrackedCell` can run a computation. A
write of a `Computation` into a `MutableCell` throws the same error.

Inside an argument list, a macro call without parentheses takes every argument
after it. Where an argument follows, write `@computation(expr)`, as in
`pair(@computation(a[] + 1), b)`. `@computation f` computes the function `f` as
a value, and does not call it; write `Computation(f)` for that.

The struct also holds its `state`, the cells that it reads (`dependencies`), and
the cells that read it (`dependents`), through a `WeakRef`, so a cell does not keep
its readers alive. Both edge fields are `nothing` until the first edge. The state is
*valid*, *invalid*, *failed* or *computing*; the sections below say when
each one holds.

### Read and write

```julia
c[]                           # read: compute first if not valid, and return the value
c[] = v                       # write a value, and invalidate the dependents
c[] = @computation expr       # write a computation, and invalidate the dependents
set_cell_value!(c, v)         # the same as c[] = v
set_cell_computation!(c, f)   # the same as c[] = Computation(f)
is_cell_valid(c)              # can the next read return the value with no computation?
invalidate_cell!(c)           # invalidate the readers, and a computation of c, with no write
```

`peek(c)` is an **untracked** read. It returns the value and records no
dependency, as `untrack` of the Solid library does. The animation clock uses it
to *sample* the time, so that the sample does not depend on the clock.
`run_without_cell_tracking(f)` does the same for every read inside `f`: it runs `f` with an
empty computing stack, so no read finds a reader, and puts the stack back after.
A cell that computes inside `f` puts itself on the new stack and still records its
own dependencies.

## Dependency tracking

The tracking is automatic. Each task has its own computing stack, so an
evaluation on one task never records a reader for an evaluation on another task:

1. When a computed cell starts its computation, it pushes itself onto the stack.
2. Each `c[]` during the computation records an edge `observer ← c`. The computed
   cell that reads becomes a downstream dependent of `c`.
3. When the computation returns, the cell pops off the stack, and the engine marks
   it valid.

So no code declares a dependency. A read records it.

## Invalidation

The engine invalidates at once, and it computes only on a read:

- `c[] = v` or `set_cell_computation!(c, f)` walks the dependents of `c`, and
  their dependents, and marks each one invalid. No computation runs. The walk
  stops at a dependent that is invalid already, and at a computing dependent:
  see the next section. A write of plain data that is `===` to the value of `c`
  walks nothing, and `invalidate_cell!(c)` walks with no write.
- The next `c[]` of a cell that is not valid calls `_recompute!(c)`. It
  removes the old upstream edges, runs the computation with tracking, and stores
  the new value.

This is the pull-based, lazy strategy. The projection printer depends on it to
stay incremental: a part of the output that nothing reads does not compute again,
also when its inputs change.

## Who writes and reads cells, and when

One task owns a set of cells that depend on each other, and only that task writes
and reads them. The owner keeps two phases apart:

1. In a **write phase**, the owner writes cells. No computation runs, and each
   write marks the readers invalid.
2. In a **read phase**, the owner reads cells, and each read computes what is
   invalid. No cell of the set changes, so all reads of the phase see the values
   of one moment.

A write between two reads of one phase can give a result that mixes an old value
and a new value. No walk of a write can repair such a result. So the rule forbids
the write, and the engine does not lock a cell. Three things follow from the rule:

- Another task never writes a cell of the set. It writes a plain store, and the
  owner moves the data into cells in its next write phase. In the editor,
  `post_operation!` and the feeds that `drain_feeds!` drains do this.
- Another task reads a cell of the set only while the owner waits for it, for
  example `fetch(Threads.@spawn c[])` inside a computation. The computing stack
  is per task, so such a read records no reader.
- A computation runs in a read phase, so it writes no cell that another cell
  reads. It can write a cell that it made in the same run, and a collector that
  no cell reads: [PAR-NO-WRITE-IN-THUNK](../../rule/architecture-invariants.md#par-no-write-in-thunk)
  gives the conditions.

The engine uses the rule in one place: the walk of a write stops at a computing
cell. A write that reaches a computing cell comes from inside its own computation,
which writes a cell that it made in the same run. That computation reads the new
value after its write, so its value is right when it ends.

In the editor, the editor task is the owner. A frame runs its steps one after the
other on that task. A drain and an applied operation write cells. A read of the
input against the IO map, a print and a paint read cells. So no write falls
inside a read. The animation clock follows the rule too: the editor writes its
clock at the start of a frame, and a document that animates takes the clock of
the editor that shows it.

## A computation that throws

A computation that throws makes its cell *failed*. The next read runs it again,
and the exception goes up the stack of the reads; the engine keeps no exception. A
reader can catch the exception and answer something else. That reader is then
valid while the cell that it read is not, so a failed cell passes the walk of a
later write on to its readers, and the reader computes again.

A computation also keeps its **fault scope**: the scope that held when its
`Computation` was made, or when `set_cell_computation!` gave it to a cell. A
computation made while a computation in a scope runs takes that scope too. A fault
barrier prints its part inside `run_in_cell_fault_scope`. When a computation in a scope
throws a fault, it calls `record_cell_fault!` with the scope. When the scope
takes the fault, it answers `true`, and the computation throws a
`RecordedCellFaultException`, which a computation above passes on unchanged. When it
answers `false`, as a scope with no method does, the exception goes on as it is. An
exception that is not a fault, and a `MethodError` in an older world, go on with no
call. `get_cell_fault_scope(cell)` answers the scope that the computation of `cell`
keeps, and `find_cell_fault_scope()` answers the scope that a computation made now
keeps: a barrier calls it to find the scope that encloses it. A computation made outside every scope
keeps a bare function, so a cell outside every barrier runs with no scope. The barrier and its scope are in
[fault.md](../platform/fault/fault.md).

## A cycle

A computation that reads its own cell, directly or through other cells, is a
cycle. The read finds the cell *computing*, on the stack of its own task or on a
stack that `run_without_cell_tracking` set aside, and throws a `CellCycleException`, an
ordinary exception: a barrier records it, and the editor goes on. Each cell of
the cycle is failed, and a write that breaks the cycle reaches their readers.

```julia
a = Cell(0); b = Cell(@computation a[] + 1)
a[] = @computation b[] + 1
a[]                     # throws a CellCycleException
a[] = 5; b[]            # 6
```

## Invariants the engine relies on

The engine keeps these invariants. A cycle throws a `CellCycleException`. When code
above breaks another invariant, the result is a stale value or a stack overflow,
and not an error.

- **The dependency graph must stay acyclic.** The engine finds a cycle and throws
  a `CellCycleException`, but the cells of the cycle have no value until a write
  breaks it. So a computed cell must never read itself, directly or through any
  chain.
- **Invalidation is monotone: when a cell is invalid, all its transitive
  dependents are invalid too.** `_invalidate_dependents!` stops at a dependent
  that is invalid already, because that cell made its own dependents
  invalid when it became so. This holds only because each write walks the *full*
  transitive closure, and only `_recompute!` and a write of a value make a cell
  valid. A failed cell passes the walk on, because a reader that caught its
  exception can be valid. A computing cell stops the walk, because only its
  own computation writes a cell that reaches it. Never set the state by hand, and
  never invalidate only a part of the dependents. Both break the early stop and
  leave cells stale for good.
- **One task writes and reads a set of cells, in phases that do not overlap.** A
  write from another task, or a write inside a read phase, can leave a reader
  valid with a stale value. See
  [Who writes and reads cells, and when](#who-writes-and-reads-cells-and-when).
- **Propagation follows the writes, not the values.** A write to a cell
  invalidates its dependents, with **no `==` check**. Only a write of plain data
  that is `===` to the value that the cell holds invalidates nothing: a value
  that is `isbits`, a `String` or a `Symbol`, into a cell that holds no
  computation. A write of the same mutable value still makes everything
  downstream invalid, because the value can have changed inside. A computation
  that returns an unchanged value does *not* stop the propagation. So `c[] = c[]`
  of a mutable value has a cost: a printer that writes `selection` in each frame
  pays for the whole subtree that it feeds. `invalidate_cell!(c)` makes the
  readers compute again with no write. See
  [the design-decisions note](../../design/architecture-decisions.md#10-propagation-is-write-driven-not-value-driven).
- **A computation must be pure and deterministic in its cell inputs.** A
  computation can run zero, one or many times for one logical change, and the
  engine keeps its result until the next invalidation. So a computation must have
  no side effect, and it must depend only on the cells that it reads: no clock, no
  random number generator and no other mutable state. Otherwise the kept result
  is wrong. This is a requirement for correctness.
- **Invalidation recurses on the call stack**, so the longest dependency chain
  sets the depth of the recursion. That chain is about as long as the depth of
  the document tree. A very deep document can overflow the stack, and the engine
  does not check the depth.
- **A computation retries only in an older world.** A computation that calls a
  method newer than the world of the task that reads it throws a `MethodError`,
  and then it runs once more through `Base.invokelatest`. In the latest world a
  `MethodError` is real, so no computation retries, and each computation of a
  chain runs once.

## How the cell appears in the rest of the codebase

Domain code does not usually read a cell directly. Each `@document`,
`@projection` and `@iomap` macro makes a struct whose fields are `Cell`s, and code
reads and writes them as plain fields: `obj.f` reads the value of the cell,
`obj.f = v` writes into it, and `getfield(obj, :f)` returns the `Cell` itself. So
most of the code reads like ordinary Julia code on structs, and every field is
reactive. The kernel code generator for this is
[`@cell_struct`](#cellstructmodule-the-struct-of-cells), below. The details of
the field wrapping are in [the macros guide](macros.md).

## Idioms you will meet

- **A computed cell that shares a value cell.** A document and its projection
  pass the selection cell through unchanged. For example, `JsonString.selection`
  is the same `Cell` as the `SyntaxLeaf.selection` that the projection makes. So
  one write at the document level invalidates the cursor on the screen at once.
- **`Cell(@computation ...)` for a derived value.** A projection makes a computed
  cell that reads upstream cells, often to map a path from one domain to another.
  An example is `map_reference_forward(p, nothing, j.selection)`.
- **`Cell(Cell[...])` inside `CellVector`.** The outer cell holds the
  *structure*, which is the vector. Each inner cell holds one *element*. A change
  of the structure invalidates the outer cell, and a change of a value invalidates
  only its slot, so the editor does not render the siblings again.
- **`set_cell_computation!(getfield(obj, :field), () -> …)`.** It gives a field a
  computation after the construction. `CellVector(Computation(f))` and the
  generators of child elements use it.

## Best practices

- Let the `@document` macro wrap the fields of a document in cells. Do not write
  the wrapping by hand.
- Use computed cells for derived state, so that the engine can invalidate it.
- Never cause a side effect inside a computation: it can run zero, one or many
  times.
- Do not read a cell while a struct is under construction and its IO map is not
  complete. Use `Cell(@computation ...)` to read the cell later.

## Layer structure

The layer is the folder [source/kernel/cell/](../../../source/kernel/cell/), and
`CellModule` is its one module. Two layers sit below it: the fault layer, whose
`is_fault_exception` a fault scope calls, and the performance layer, whose
`@count_performance` the engine counts with. The struct layer above builds structs of
cells with `@cell_struct`. This guide describes the struct layer too; the
[fault guide](fault.md) and the [performance guide](performance.md) describe the
layers below.

```
fault/FaultModule.jl              (FaultModule): the fault and its predicate
        │  is_fault_exception, used by ↓
performance/PerformanceModule.jl  (PerformanceModule): the counters
        │  @count_performance, used by ↓
cell/CellModule.jl                (CellModule): the cell kinds, one file each
        ├─ CellInterface.jl   : AbstractCell{T} and the generics that every kind answers
        ├─ CellComputation.jl : Computation and @computation, the marker of a computation
        ├─ ReactiveCell.jl    : the pull-based reactive engine
        ├─ CellFaultScope.jl  : the fault scope that a computation keeps, and where its fault goes
        ├─ MutableCell.jl     : a plain mutable box, with no reactive bookkeeping
        ├─ ImmutableCell.jl   : a read-only box
        ├─ UntrackedCell.jl   : a cell that computes at each read and records no reader
        └─ CellDefaults.jl    : the bodies of the other generics, one method for each kind
        │  Cell and AbstractCell, used by ↓
struct/CellStructModule.jl        (CellStructModule): the struct of cells
        ├─ CellStructPlan.jl  : the parse of a struct definition that the struct macros share
        └─ CellStruct.jl      : @cell_struct and its expression builders
```

`CellInterface.jl` is the **interface file** of the layer: it declares the
contract and nothing else. The read `c[]`, the untracked read `peek` and
`is_cell_valid` have their bodies in the file of each kind. The bodies of
`unwrap_cell`, `get_cell_value_type`, `make_similar_cell`, `is_computed_cell`,
`get_cell_computation`, `has_dependent_cells` and the fallback of
`record_cell_fault!` are in the sibling `CellDefaults.jl`.

The animation clock is a `@cell_struct` that uses the engine, and it is not a
part of the engine. It is its own layer, `clock/ClockModule.jl`, above the struct
layer. It imports `CellModule` and `CellStructModule` and nothing else, and the
docstring of `ClockModule` holds the full interface: `Clock`,
`get_reactive_clock_time`, `get_clock_time` and `set_clock_time!`.

The load order is the dependency order that the include-order guard checks.

## CellModule: the cell kinds

A cell is a typed box, `AbstractCell{T}`, and its kind sets what it does. `Cell`
is `ReactiveCell{Any}`, the pull-based reactive graph above: a cell holds a
*value* or a *computation*. A read of a cell inside the computation of another
cell records a dependency edge. A write to a cell invalidates its transitive
dependents at once, and they compute again on their next read. The whole
projection pipeline depends on this for its incremental work.

`MutableCell{T}` and `ImmutableCell{T}` are boxes that do not use the graph. A
mutable box holds state that changes often, and a read-only box holds a value
that never changes.

`UntrackedCell{T}` holds a computation and keeps no value. Each read runs the
computation with `run_without_cell_tracking`, so the cell records no reader, and no read
inside the computation records one. A change of what the computation reads
reaches no computation that read the cell: some other part must make the readers
compute again. A style field of a projection that reads its theme is the main
use, where one wrapper makes the whole view print again after a change of the
theme. A plain value makes a constant, and a write is a `MethodError`.
The kind is an immutable struct with one pointer, so a struct of cells holds it
inline, and two structs can share its function.

Public surface: `AbstractCell`, `is_cell_valid`, `invalidate_cell!`, `unwrap_cell`,
`get_cell_value_type`, `make_similar_cell`, `is_computed_cell`,
`get_cell_computation`, `has_dependent_cells`, `run_without_cell_tracking`, `Computation`,
`@computation`, `ReactiveCell`, `Cell`, `CellCycleException`, `set_cell_value!`,
`set_cell_computation!`, `run_in_cell_fault_scope`, `record_cell_fault!`,
`RecordedCellFaultException`, `get_cell_fault_scope`, `find_cell_fault_scope`,
`MutableCell`, `ImmutableCell` and `UntrackedCell`. `peek` is an untracked read, a method of
`Base.peek`.

`get_cell_computation(c)` answers the computation of a reactive cell, or `nothing`.
A caller puts a computation around it with `set_cell_computation!`, so it acts on
each value that the cell makes: the walk of the part under the pointer follows
each node of a lazy list when the list builds it. That walk reads the node inside
the computation of the link, so it reads it with `run_without_cell_tracking`: the link must
not compute again when a part of the node changes.

## Try it

`print_cell_example()` in `ProjecturedKernelExample` prints a REPL session with the
layer: a value, a computation, a write that makes the readers invalid, `peek`, a
chain, the other cell kinds, `run_without_cell_tracking` and a fault scope. Each line runs as it
prints. Type the lines yourself after `using ProjecturedKernel.CellModule`, and change
them.

```julia
using ProjecturedKernelExample
print_cell_example()
```

## CellStructModule: the struct of cells

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

A kind is a type: `ReactiveCell`, `ImmutableCell`, `MutableCell` or
`UntrackedCell`. A field `f::ImmutableCell{T}`, `f::MutableCell{T}` or
`f::UntrackedCell{T}` has that kind. Every other field has the kind that the macro
gets before `struct`, or `ReactiveCell` without one. A reactive field is a `Cell`,
and an immutable, a mutable or an untracked field is a cell of the declared value
type. The struct keeps its supertype and its type parameters.
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
`find_cell_struct_parameter_slots`, `get_cell_struct_required_count`,
`build_cell_struct_field_type`, `build_cell_struct_keyword_parameters`,
`build_cell_struct_keyword_constructor`, `build_cell_struct_positional_constructors`,
`build_cell_struct_exprs`, `parse_cell_struct_macro_arguments`, `@cell_struct`,
`get_cell_struct_argument_type` and `get_cell_struct_kind`.

## The performance layer

The performance layer below the cell layer counts the work of the cells: the
engine adds to the counts `:reads`, `:computes`, `:invalidations` and `:writes`
with `@count_performance`, in a build with the counters. The
[performance guide](performance.md) describes the layer.
