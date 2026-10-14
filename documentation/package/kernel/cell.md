# Reactive cells

> **Kind:** reference · **Status:** current · **Stands on:** [architecture.md](architecture.md)

This guide says what a reactive cell holds, how a read records a dependency and a
write invalidates the readers, and which invariants the engine relies on. It then
describes the module of the cell layer. The engine is in [ReactiveCell.jl](../../../source/kernel/cell/ReactiveCell.jl).

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
*valid*, *invalid*, *maybe invalid*, *checking*, *failed* or *computing*; the
sections below say when each one holds.

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
   cell that reads becomes a downstream dependent of `c`. The edges keep the order
   of the first read of each cell, and the end of the computation removes a cell
   that it read twice.
3. When the computation returns, the cell pops off the stack, and the engine marks
   it valid.

So no code declares a dependency. A read records it.

## Invalidation

The engine marks at once, and it computes only on a read:

- `c[] = v` or `set_cell_computation!(c, f)` marks the direct readers of `c`
  invalid, and every valid cell below them *maybe invalid*. No computation runs.
  The walk stops below a reader that is marked already, and at a computing
  reader: see the next section. A failed reader stays failed, and the walk goes
  on through it. A write of plain data that is `===` to the value of `c` walks
  nothing, and `invalidate_cell!(c)` walks with no write. In a build with the
  counters, each write adds one to `:writes`, except a write of the same plain
  data, which adds nothing, and each mark adds one to `:invalidations`.
- The next `c[]` of an invalid or a failed cell calls `_recompute!(c)`. It
  removes the old upstream edges, runs the computation with tracking, and stores
  the new value. When the new value is plain data that is `===` to the old one,
  the cells that wait for a check below `c` stay as they are, and the counters
  add one to `:stops`. Any other value, and an exception, makes them invalid.
- The next `c[]` of a maybe invalid cell checks first. It brings each cell that
  the last computation read up to date, in the order of the reads, and stops at
  the first one that gave a new value, which made it invalid: then it computes.
  When none gave a new value, the cell is valid with no computation. A check adds
  one to `:checks`. While a cell checks, it is *checking*, and a read of it is a
  cycle, as a read of a computing cell is.

This is the pull-based, lazy strategy, with the early stop that the Salsa and
Adapton libraries have. The projection printer depends on it to stay
incremental: a part of the output that nothing reads does not compute again,
also when its inputs change, and a part whose inputs give the values that they
gave does not compute again either.

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
  is per task, so such a read records no reader. One task at a time reads for the
  owner: a read of a cell that is not valid computes it and changes the edges of
  the graph. Several tasks at once read only cells that are valid.
- A computation runs in a read phase, so it writes no cell that another cell
  reads. It can write a cell that it made in the same run, and a collector that
  no cell reads: [PAR-NO-WRITE-IN-THUNK](../../rule/architecture-invariants.md#par-no-write-in-thunk)
  gives the conditions.

The engine uses the rule in two places. The walk of a write stops at a computing
cell, because a write that reaches it comes from inside its own computation, which
writes a cell that it made in the same run. The value of that computation stays
right only when no other cell read the new cell before the write, which
PAR-NO-WRITE-IN-THUNK requires. And a read of a computing cell is a cycle: see
[A cycle](#a-cycle).

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
keeps, for a reactive and for an untracked cell, and `find_cell_fault_scope()`
answers the scope that a computation made now keeps: a barrier calls it to find
the scope that encloses it. A computation made outside every scope keeps a bare
function, so a cell outside every barrier runs with no scope. The barrier and its
scope are in [fault.md](../platform/fault/fault.md).

```julia
struct PartScope; faults::Vector{Any}; end
CellModule.record_cell_fault!(scope::PartScope, computation, exception; traceback) =
    (push!(scope.faults, exception); true)
scope = PartScope([])
part = run_in_cell_fault_scope(() -> Cell(@computation error("no value")), scope)
get_cell_fault_scope(part) === scope          # true
try part[] catch exception; typeof(exception) end   # RecordedCellFaultException
scope.faults                                  # [ErrorException("no value")]
```

## A cycle

A computation that reads its own cell, directly or through other cells, is a
cycle. The read finds the cell *computing* and throws a `CellCycleException`, an
ordinary exception: a barrier records it, and the editor goes on. The state alone
shows the cycle, because one task writes and reads the cells: a read of a computing
cell comes from inside its computation, also through `run_without_cell_tracking`, an
`UntrackedCell` or a task that the computation waits for. Each cell of
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
- **Invalidation is monotone: when a cell is invalid or maybe invalid, all its
  transitive dependents are invalid or maybe invalid too.** The walk of a write
  stops below a dependent that is marked already, because that cell marked its
  own dependents when it became so. This holds only because each write walks the
  *full* transitive closure, and only `_recompute!`, a check that finds no new
  value and a write of a value make a cell valid. A failed cell passes the walk on, because a reader that caught its
  exception can be valid. A computing cell stops the walk, because only its
  own computation writes a cell that reaches it. Never set the state by hand, and
  never invalidate only a part of the dependents. Both break the early stop and
  leave cells stale for good.
- **One task writes and reads a set of cells, in phases that do not overlap.** A
  write from another task, or a write inside a read phase, can leave a reader
  valid with a stale value. See
  [Who writes and reads cells, and when](#who-writes-and-reads-cells-and-when).
- **Propagation starts at a write, and stops at plain data that stays the
  same.** A write to a cell invalidates its direct readers, with **no `==`
  check**, and makes the cells below them maybe invalid. One test stops it, in
  two places: plain data, a value that is `isbits`, a `String` or a `Symbol`,
  that is `===` to the value before. A write of such a value into a cell that
  holds no computation invalidates nothing. A computation that gives such a value
  leaves the cells that wait for a check below it, and a read finds them valid
  with no computation. A mutable value counts as new at each write and at each
  computation, because it can have changed inside. So `c[] = c[]` of a mutable
  value has a cost: a printer that writes `selection` in each frame pays for the
  subtree that it feeds. `invalidate_cell!(c)` makes the readers compute again
  with no write. See
  [the design-decisions note](../../design/architecture-decisions.md#10-propagation-starts-at-a-write-and-stops-at-plain-data-that-stays-the-same).
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
  chain runs once. A real `MethodError` read from an older world makes each cell
  of a chain retry the rest of the chain: a chain of n cells runs about n²/2
  computations before the error reaches the reader.

## How the cell appears in the rest of the codebase

Domain code does not usually read a cell directly. Each `@document`,
`@projection` and `@iomap` macro makes a struct whose fields are `Cell`s, and code
reads and writes them as plain fields: `obj.f` reads the value of the cell,
`obj.f = v` writes into it, and `getfield(obj, :f)` returns the `Cell` itself. So
most of the code reads like ordinary Julia code on structs, and every field is
reactive. The kernel code generator for this is
[`@cell_struct`](struct.md#a-struct-of-cells), in the struct
guide. The details of
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
cells with `@cell_struct`. The [struct guide](struct.md) describes the layer above,
and the [fault guide](fault.md) and the [performance guide](performance.md) describe
the layers below.

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
`get_cell_computation`, `has_dependent_cells` and the fallbacks of
`record_cell_fault!` and `invalidate_cell!` are in the sibling `CellDefaults.jl`.
The method of `invalidate_cell!` for a reactive cell is in `ReactiveCell.jl`, beside
the walk that it calls.

The animation clock is a `@cell_struct` that uses the engine, and it is not a
part of the engine. It is its own layer, `clock/ClockModule.jl`, above the struct
layer, and the [clock guide](clock.md) describes it.

The load order is the dependency order that the include-order guard checks.

## CellModule: the cell kinds

A cell is a typed box, `AbstractCell{T}`, and its kind sets what it does. `Cell`
is `ReactiveCell{Any}`, the pull-based reactive graph above: a cell holds a
*value* or a *computation*. A read of a cell inside the computation of another
cell records a dependency edge. A write to a cell marks its transitive dependents
at once, and at their next read they compute again, or find by a check that what
they read gave the values that it gave. The whole
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
layer: a value, a computation, a write that makes the readers invalid, a write of
the same plain value, `invalidate_cell!`, `peek`, a chain, a new computation and a
new value of a cell, the other cell kinds, `run_without_cell_tracking`, a cycle and
a fault scope. Each line runs as it prints. Type the lines yourself after
`using ProjecturedKernel.CellModule`, and change them.

```julia
using ProjecturedKernelExample
print_cell_example()
```
