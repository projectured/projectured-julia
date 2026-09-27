# Layer 03 — cell (`source/kernel/cell/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed.

## Verdict

The cell layer is small and sealed, it follows the placement, interface, export and naming rules, and its 100 tests pass. The engine has one high defect: when a reader catches the exception of a failed computation, later writes stop at the failed cell, and the reader never computes again. `FaultCatchingProjection` catches in exactly this way, so its fault mark stays after the person fixes the input. Two medium defects come from the lack of a state for a cell that computes now: a write during a computation is lost, and a cycle overflows the stack past every barrier. Three more medium defects are a write that is not atomic, a `MutableCell` that stores a `Computation`, and a new computed cell with an undefined value. The texts of the layer say nothing about exceptions and threads, and they call a direct self-read safe, which is false.

## Shape

- Purpose: the reactive primitive. `AbstractCell` and three kinds (`ReactiveCell`, `MutableCell`, `ImmutableCell`), the `Computation` marker, and the pull-based engine: dependency record on read, eager invalidation on write, lazy computation on the next read.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `CellModule.jl` | 46 | 🔒 | module docstring, `using ..PerformanceModule`, the export block, the includes |
  | `CellInterface.jl` | 157 | 🔒 | `AbstractCell` and six bodiless generics |
  | `CellComputation.jl` | 65 | 🔒 | `Computation` and `@computation` |
  | `ReactiveCell.jl` | 393 | 🔒 | `ReactiveCell`, `Cell`, the engine (read, computation, invalidation, write, `peek`, the two edge helpers, `show`) |
  | `MutableCell.jl` | 41 | 🔒 | the mutable box that records no reader |
  | `ImmutableCell.jl` | 41 | 🔒 | the box that can not be written |
  | `CellDefaults.jl` | 37 | 🔒 | the bodies of five generics, and the rejection of a `Computation` by the two stored kinds |

- Imports: `PerformanceModule` only. Imported by: 9 kernel module files (struct, clock, document, reference, selection, operation, iomap, projection, editor), and by almost every package above the kernel.
- Public surface: 15 exported names, plus methods of `Base.getindex`, `Base.setindex!`, `Base.peek` and `Base.show`. All 15 names have users outside the kernel in projectured-julia. The names with the fewest users are `get_cell_value_type` (clipboard), `copy_cell_as` (collection, serialization), `is_computed_cell` (collection) and `has_dependent_cells` (statistics, and the editor wait in `Feeds.jl`). omnet-julia and inet-julia use 11 of the 15 names. No exported name is without a user.
- State: no module-level mutable state. The computing stack is task-local, under the key `:projectured_reactive_computing`. The graph itself, that is the `valid` flags, the `dependencies` sets and the `dependents` vectors, has no lock and no owner. It is safe only when every task that touches a cell runs on one thread and does not yield inside a computation.
- Tests: [CellTest.jl](../../../test/kernel/cell/CellTest.jl), one file, 100 assertions, all pass in the baseline run. It covers a chain, the switch between a value and a computation, a conditional dependency, the weak edge (a leak test), a typed cell, the three kinds, a function as a value, `has_dependent_cells`, the forms of `@computation`, and the retry of a `MethodError`. It does not cover a computation that throws under a reader that catches, a cycle, a write while a reader computes, and several public names (see L03-13).

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 5 | 1 |
| Shape | 0 | 0 | 1 |
| Types/performance | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 2 |
| Tests | 0 | 0 | 1 |

## Findings

### L03-1 A reader that catches a failed computation stays stale after the input changes

- Category: Correctness · Severity: High · Confidence: Confirmed by a run
- Checked by the lead on 2026-09-27: A run: `a = Cell(1)`, `b` throws when `a[] == 0`, and `c = Cell(@computation(try b[] catch; -1 end))`. After `a[] = 2`, `c[]` stays `-1`, also after a direct read of `b` gives 5.
- Where: [ReactiveCell.jl:137](../../../source/kernel/cell/ReactiveCell.jl#L137) 🔒, [ReactiveCell.jl:163](../../../source/kernel/cell/ReactiveCell.jl#L163) 🔒, [ReactiveCell.jl:192](../../../source/kernel/cell/ReactiveCell.jl#L192) 🔒; the catch in [Catching.jl:126](../../../source/fault/Catching.jl#L126) (not a kernel file)
- Evidence:
  1. `getindex` records the reader before it computes: `_register_dependent!(c, observer)` (line 137) runs before `_recompute!(c)` (line 142).
  2. When the computation throws, `_recompute!` pops the stack in `finally` and never reaches `c.valid = true` (line 176). The cell stays invalid, and it keeps the edges of its partial run.
  3. A reader that catches the exception returns a value, so its own `_recompute!` marks it valid. Now an invalid cell has a valid dependent. PAR-MONOTONE-INVALIDATION forbids this state.
  4. A later write to an input of the failed cell starts `_invalidate_dependents!`. The walk meets the failed cell, finds `dd.valid == false` (line 192), and stops. The reader keeps its old value.

  A concrete case uses the fixture `OddLeafBreaker` of [FaultCatchingTest.jl:23](../../../test/fault/FaultCatchingTest.jl#L23): its output is `Cell(@computation isodd(leaf.value) ? error(…) : …)`. The barrier cell `guarded` reads `inner.output` inside `try` ([Catching.jl:132](../../../source/fault/Catching.jl#L132)) and caches a fault mark. Then `leaf.value = 2` starts the walk at the value cell of the leaf. The walk stops at the failed output cell, and the mark stays. The header of Catching.jl promises the opposite: "when the input that caused the fault changes the thunk runs again and the real output comes back by itself" ([Catching.jl:16](../../../source/fault/Catching.jl#L16)). No test covers the recovery. The gallery puts this barrier around each window by default ([Gallery.jl:318](../../../example/projectured/Gallery.jl#L318)). Whether a deep fault reaches that root barrier through a computed output cell needs a run.
- Rule: PAR-MONOTONE-INVALIDATION; bug.
- Fix: Keep a failed computation as a result. Store the exception in the cell, mark the cell valid, and rethrow the stored exception on each read until a write invalidates the cell. The walk then passes the cell, and the reader computes again when the input changes. A reader with no catch then gets the stored exception on each frame, and the failed computation does not run again. This adds a field or a state to `ReactiveCell`, so the owner must decide the form. Add a test: a reader catches, the input changes, and the reader shows the real value.
- Reach: `ReactiveCell.jl` 🔒, `CellTest.jl`, `cell.md` (the invariants), `FaultCatchingTest.jl`. `Catching.jl` needs no change.

### L03-2 A write that arrives while a reader computes is lost, and a transitive reader then stays stale

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the mechanism; Suspected for a real occurrence (it needs a computation that yields or writes)
- Where: [ReactiveCell.jl:163](../../../source/kernel/cell/ReactiveCell.jl#L163) 🔒, [ReactiveCell.jl:185](../../../source/kernel/cell/ReactiveCell.jl#L185) 🔒, [ReactiveCell.jl:208](../../../source/kernel/cell/ReactiveCell.jl#L208) 🔒
- Evidence: A cell that computes has `valid == false` until its computation returns. The walk reads that state as "invalid already", so it neither marks nor descends. Two paths can write while a reader P computes:
  1. The same task: the computation writes a cell. PAR-NO-WRITE-IN-THUNK forbids it, but `setindex!` does not look at the computing stack, so the break is silent.
  2. Another task on the same thread: the wall-clock heartbeat ([Clock.jl:176](../../../source/kernel/clock/Clock.jl#L176)) writes at each yield of its owner, also at a yield inside a computation.

  The case: P reads a computed cell Q, and Q reads the clock time T. P yields (I/O, a contended lock, `sleep`). The heartbeat writes T. Q becomes invalid, and the walk stops at P. P returns, and it becomes valid with the old value of Q. Every later write of T stops at Q, so P never computes again. When P reads T directly, the next tick repairs P; through Q, nothing repairs it. The texts promise more safety than the graph has: "Each task has its own computing stack, so concurrent evaluations never share it" ([cell.md:62](../../../documentation/package/kernel/cell.md#L62)), and PAR-PER-EDITOR-STATE ([architecture-invariants.md:922](../../../documentation/rule/architecture-invariants.md#L922)).
- Rule: PAR-MONOTONE-INVALIDATION; PAR-NO-WRITE-IN-THUNK (no check).
- Fix: Give a cell a third state, "computes now". When the walk meets a dependent in that state, it marks the dependent as invalidated during its computation, and `_recompute!` then leaves that cell invalid at the end. The same state lets a debug check in `setindex!` and `set_cell_computation!` report a write to a cell with readers while the stack of the task is not empty; the owner decides whether that check throws. State the thread contract in `cell.md`: one thread, no yield inside a computation, and other tasks write through a store.
- Reach: `ReactiveCell.jl` 🔒, `CellTest.jl`, `cell.md`, `architecture-invariants.md` (PAR-PER-EDITOR-STATE, PAR-NO-WRITE-IN-THUNK).

### L03-3 A cycle, a direct self-read included, overflows the stack, and the error passes every barrier

- Category: Correctness · Severity: Medium · Confidence: Confirmed (code read); the formula case is Suspected, because its reader rejects a cycle first
- Where: [ReactiveCell.jl:136](../../../source/kernel/cell/ReactiveCell.jl#L136) 🔒, [ReactiveCell.jl:163](../../../source/kernel/cell/ReactiveCell.jl#L163) 🔒
- Evidence: `_recompute!` has no guard for a cell that is on the stack already. The test `observer !== c` (line 136) only skips the edge. Lines 141-142 still call `_recompute!(c)`, because `c.valid` is false while `c` computes, so a direct self-read recurses too. The recursion ends in `StackOverflowError`, and [FaultDefaults.jl:29](../../../source/kernel/fault/FaultDefaults.jl#L29) makes that error pass every barrier. One cyclic printer thus stops the editor instead of one mark on the screen.

  The formula slice guards a cycle itself, with a process-global `Set` ([FormulaDocument.jl:311](../../../source/formula/FormulaDocument.jl#L311)) that returns `#CYCLE!` on re-entry. Under that guard, the engine re-enters `_recompute!(A)` while the outer run of A is on the stack. The inner run calls `_detach_upstream!(A)` and removes the edges that the outer run recorded, so A no longer depends on B after the outer run ends. The texts say "The engine only skips a *direct* self-edge" ([cell.md:93](../../../documentation/package/kernel/cell.md#L93), [architecture-invariants.md:262](../../../documentation/rule/architecture-invariants.md#L262)), which suggests that a direct self-read is safe. It is not.
- Rule: PAR-ACYCLIC-CELLS: the engine gives no signal when a caller breaks it, and a `StackOverflowError` is a passthrough exception, so no barrier can record the fault.
- Fix: Detect a re-entry in `_recompute!` with the state of L03-2, and throw an ordinary exception, for example `CellCycleException`, that names the cell. A barrier then records the cycle as a fault. Correct the two texts. The formula slice can then drop `_EVALUATING`.
- Reach: `ReactiveCell.jl` 🔒, `CellModule.jl` 🔒 (an export), `cell.md`, `architecture-invariants.md`, `FormulaDocument.jl`, `CellTest.jl`.

### L03-4 A failed write to a typed computed cell leaves the cell half changed

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [ReactiveCell.jl:208](../../../source/kernel/cell/ReactiveCell.jl#L208) 🔒
- Evidence: `setindex!` detaches the edges and sets `c.computation = nothing` before `c.value = value` converts the value to `T`. When the conversion throws, the cell has no computation and no upstream edge. A cell that was valid keeps its old value and no longer follows its inputs. A cell that nothing read keeps `valid == false` and an uninitialized value. Its next read takes the `computation === nothing` branch of `_recompute!` (line 164) and returns that value: arbitrary bits for an `isbits` type, an `UndefRefError` for another type. Example: `tc = ReactiveCell{Int}(@computation t[] + 1); tc[] = 2.5` throws `InexactError`, and `tc[]` then returns an arbitrary `Int`. The test at [CellTest.jl:120](../../../test/kernel/cell/CellTest.jl#L120) writes 2.5 only into a value cell, where the order has no effect.
- Rule: bug.
- Fix: Convert first: `v = convert(T, value)` as the first statement of `setindex!`, then change the cell.
- Reach: `ReactiveCell.jl` 🔒, `CellTest.jl`.

### L03-5 A `MutableCell` stores a written `Computation` as its value

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [MutableCell.jl:32](../../../source/kernel/cell/MutableCell.jl#L32) 🔒, [CellDefaults.jl:26](../../../source/kernel/cell/CellDefaults.jl#L26) 🔒
- Evidence: The constructors reject a `Computation`: `MutableCell(::Computation)` and `MutableCell{T}(::Computation)` throw `ArgumentError`. The write `Base.setindex!(c::MutableCell, value) = (c.value = value)` has no such method. So `m = MutableCell{Any}(0); m[] = @computation x[]` stores the marker, and `m[]` returns the `Computation`. The same holds for `object.f = @computation …` on a mutable field of a `@cell_struct` or of an `MCFoo` layout. For a `MutableCell{T}` with another `T`, the write throws a conversion `MethodError` instead of the clear `ArgumentError`. The comment at CellDefaults.jl:26 says "the two stored kinds throw", and the `Computation` docstring says that a `MutableCell` "throws an `ArgumentError` when it gets a `Computation`". Code written for the reactive layout and run on the mutable layout, the pattern that cheap-reactive-cells.md recommends, gets a wrong value with no error.
- Rule: bug; PAR-NO-NESTED-CELL (a field never holds a `Computation` as its value).
- Fix: Add `Base.setindex!(c::MutableCell, ::Computation) = _reject_computation("MutableCell")` to `CellDefaults.jl`, and a test.
- Reach: `CellDefaults.jl` 🔒, `CellTest.jl`.

### L03-6 A new computed cell has an undefined value, and the read that persistence uses throws

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the undefined field; Suspected for `save_document` (it needs a run with a computed field that nothing read)
- Where: [ReactiveCell.jl:65](../../../source/kernel/cell/ReactiveCell.jl#L65) 🔒
- Evidence: `ReactiveCell{T}(::Computation)` calls `new{T}()` and leaves `value` undefined, also for `T = Any`. `set_cell_computation!` writes `nothing` into `value` when `nothing isa T` (line 265). So the two ways to make a computed cell leave two different states. PAR-PERSISTENCE-BY-VALUE tells persistence to read `getfield(c, :value)`, and [BinarySerialization.jl:9](../../../source/serialization/BinarySerialization.jl#L9) does. For a computed `Cell` that nothing read, that read throws `UndefRefError`, so a save of such a document fails. For an `isbits` `T`, the read returns arbitrary bits with no error.
- Rule: PAR-PERSISTENCE-BY-VALUE (the read it prescribes can fail); bug.
- Fix: In the constructor, write `nothing` into `value` when `nothing isa T`, as `set_cell_computation!` does. For another `T`, give persistence a public read that says whether a stored value exists (L03-8).
- Reach: `ReactiveCell.jl` 🔒, `BinarySerialization.jl`, `CellTest.jl`.

### L03-7 The `:computes` counter does not count a computation that throws

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [ReactiveCell.jl:176](../../../source/kernel/cell/ReactiveCell.jl#L176) 🔒
- Evidence: `@count_performance :computes` comes after `c.valid = true`, so the counter skips a computation that throws. A printer that fails on each frame shows no computes, and PAR-PROFILE-WITH-COUNTERS uses this counter to find repeated work.
- Rule: PAR-PROFILE-WITH-COUNTERS.
- Fix: Count before the computation runs, or in the `finally` block.
- Reach: `ReactiveCell.jl` 🔒.

### L03-8 Persistence reads private fields of `ReactiveCell`, because the layer has no public read of the stored value

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ReactiveCell.jl:49](../../../source/kernel/cell/ReactiveCell.jl#L49) 🔒
- Evidence: `peek` computes an invalid cell, and `c[]` records a dependency. No public name returns the stored value as it is. So code outside the layer reads the fields: `getfield(c, :value)` in [BinarySerialization.jl:9](../../../source/serialization/BinarySerialization.jl#L9), and `c.computation` and `c.value` in omnet-julia `source/simulator/checkpoint/CheckpointSerializer.jl:94-98`, whose comment speaks of "the five fields". The layout of a private struct is thus a contract across three repositories, and PAR-PERSISTENCE-BY-VALUE writes the field read into the rule.
- Rule: PAR-MODULE-BOUNDARY-IS-API, in spirit: a private detail of the module is used by other modules. No guard checks a field read.
- Fix: Declare a generic in `CellInterface.jl`, for example `get_cell_stored_value(cell)`. It returns the stored value with no dependency and no computation, and its docstring says what it returns when no value exists. Then change PAR-PERSISTENCE-BY-VALUE and the two serializers.
- Reach: `CellInterface.jl` 🔒, `CellDefaults.jl` 🔒, `CellModule.jl` 🔒, `BinarySerialization.jl`, `architecture-invariants.md`, omnet-julia `CheckpointSerializer.jl`.

### L03-9 The invalidation walk calls itself through a dispatch at run time

- Category: Types/performance · Severity: Low · Confidence: Suspected (needs `@code_typed` or the trim verifier)
- Where: [ReactiveCell.jl:185](../../../source/kernel/cell/ReactiveCell.jl#L185) 🔒
- Evidence: `_invalidate_dependents!(c::ReactiveCell)` has no `@nospecialize`. It takes each reader as `dd = d::ReactiveCell`, an abstract type, reads `dd.valid`, and calls itself on `dd`. The offset of `valid` depends on `T`, and each level needs a dispatch at run time. The comment at lines 83-88 gives this reason for `@nospecialize` on the two edge helpers: "a body specialized on `T` would leave these calls unresolved" in an ahead-of-time build. The walk runs on every write.
- Rule: no written rule; the comment of the same file gives the reason.
- Fix: Mark the argument `@nospecialize`, as the edge helpers do, and measure the walk before and after.
- Reach: `ReactiveCell.jl` 🔒.

### L03-10 `copy_cell_as` ends in a preposition and does not copy

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [CellInterface.jl:109](../../../source/kernel/cell/CellInterface.jl#L109) 🔒, [CellDefaults.jl:11](../../../source/kernel/cell/CellDefaults.jl#L11) 🔒
- Evidence: The function makes a new cell with the kind and the value type of `c` and another value. It copies neither the value nor the computation of `c`. naming-rules.md drops a dangling preposition, with `get_cell_kind_of` as its own example of the error, and gives `make_` for a function whose intention is a new object.
- Rule: naming-rules.md, "The verb follows the nature of the work" and "A trailing `of` or `for` is dropped".
- Fix: A `make_` name that ends in a noun; the owner chooses it. Rename with `workspace/bin/julia-rename.jl`, then correct the prose.
- Reach: `CellInterface.jl` 🔒, `CellDefaults.jl` 🔒, `CellModule.jl` 🔒, `DocumentDefaults.jl`, `DocumentCopy.jl`, `CellVector.jl`, `FileCut.jl`, `CellTest.jl`, `cell.md`.

### L03-11 Docstrings and comments of the layer describe the layers that use it

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [ReactiveCell.jl:16](../../../source/kernel/cell/ReactiveCell.jl#L16), [ReactiveCell.jl:78](../../../source/kernel/cell/ReactiveCell.jl#L78), [ReactiveCell.jl:322](../../../source/kernel/cell/ReactiveCell.jl#L322), [CellComputation.jl:44](../../../source/kernel/cell/CellComputation.jl#L44), [CellInterface.jl:57](../../../source/kernel/cell/CellInterface.jl#L57), [CellInterface.jl:96](../../../source/kernel/cell/CellInterface.jl#L96), [CellInterface.jl:116](../../../source/kernel/cell/CellInterface.jl#L116), [ImmutableCell.jl:11](../../../source/kernel/cell/ImmutableCell.jl#L11), [MutableCell.jl:11](../../../source/kernel/cell/MutableCell.jl#L11), all 🔒
- Evidence: "a document keeps its fields in these, which is how an edit redraws the part of the screen it touched" (ReactiveCell.jl:16). "a field of a document or a `CellVector`" (CellComputation.jl:45) names a type of the collection package. "the document machinery stores some fields as cells" (CellInterface.jl:57). "Use it when copying a document" (CellInterface.jl:96). "a value a projection may read" (ImmutableCell.jl:12). "a cursor position a renderer reads once per draw" (MutableCell.jl:12). "every projection printed from a document, and every span that a printer drops" (ReactiveCell.jl:324). The prior audit of the clock removed the same kind of text from that layer.
- Rule: PAR-NO-CONSUMER-DOCS.
- Fix: State each goal in the terms of the layer: a field, a struct, a value that a computation reads. Remove `CellVector`.
- Reach: the five files 🔒.

### L03-12 The guides and two texts of the layer give an incorrect or stale picture of the engine

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [cell.md:57](../../../documentation/package/kernel/cell.md#L57), [cell.md:88](../../../documentation/package/kernel/cell.md#L88), [cell.md:93](../../../documentation/package/kernel/cell.md#L93), [cell.md:117](../../../documentation/package/kernel/cell.md#L117), [architecture.md:106](../../../documentation/package/kernel/architecture.md#L106), [CellComputation.jl:40](../../../source/kernel/cell/CellComputation.jl#L40) 🔒, [ReactiveCell.jl:387](../../../source/kernel/cell/ReactiveCell.jl#L387) 🔒
- Evidence:
  - The section "Invariants the engine relies on" of `cell.md` says nothing about a computation that throws (L03-1), and line 93 says that a direct self-edge is skipped (L03-3).
  - `cell.md` breaks writing-rules.md: "by construction" (line 88, a banned phrase), "cf." (line 57), "Pathologically" and "in practice" (lines 117-118), and 26 dashes.
  - The fan-in table of `architecture.md` (line 106) gives `CellModule` as layer 1, imported by 8 kernel files. It is layer 3, and 9 kernel module files import it. The other rows of that table also carry the old layer numbers.
  - The `@computation` docstring says that a cell computes again "after anything that it read has changed" (CellComputation.jl:40). The engine reacts to a write, also to a write of an equal value (PAR-WRITE-DRIVEN-PROPAGATION).
  - `show` prints `Cell(value, 2)` also for a `ReactiveCell{Int}`, which is not a `Cell` (ReactiveCell.jl:387).
- Rule: writing-rules.md; PAR-HONEST-DOCS; PAR-WRITE-DRIVEN-PROPAGATION.
- Fix: Add the failure and thread rules to the invariants of `cell.md`, correct line 93, rewrite the guide in the writing rules, renumber the fan-in table, write "was written" for "has changed", and print the type in `show`.
- Reach: `cell.md`, `architecture.md`, `CellComputation.jl` 🔒, `ReactiveCell.jl` 🔒.

### L03-13 The tests do not cover exceptions, cycles, concurrent writes and several public names

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: [CellTest.jl](../../../test/kernel/cell/CellTest.jl)
- Evidence: No test set covers these behaviours: a computation that throws under a reader that catches, and the input that changes after it (L03-1); a write while a reader computes (L03-2); a cycle or a direct self-read (L03-3); a failed write to a typed computed cell (L03-4); a `Computation` written into a `MutableCell` (L03-5); the stored value of a new computed cell (L03-6); `unwrap_cell`; `set_cell_value!` (only substrate tests call it); `copy_cell_as` for `MutableCell` and `ImmutableCell`; `is_computed_cell` for the two stored kinds; `peek` on a `ReactiveCell` inside a computation (only ClockTest.jl covers it, through `get_clock_time`); `show`.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: Add one test set for each behaviour. The sets for L03-1 to L03-6 must fail on the code at this commit.
- Reach: `CellTest.jl`.

## Accepted before, not raised again

- Cells hold `Any` on purpose, and a read narrows the value.
- The retry of a `MethodError` in an older world: each level of a chain retries once, so the bottom computation of a chain of ten runs eleven times (plan/done/cell-layer-audit.md; `CellTest.jl` asserts 11).
- Invalidation and computation recurse on the call stack, so a very deep chain can overflow it; `cell.md` states the limit.
- Propagation is driven by a write, with no check for an equal value (PAR-WRITE-DRIVEN-PROPAGATION).
- `has_dependent_cells` counts a collected reader until the collector sweeps it; the docstring calls it the safe error.
- The generated precompile statement files of the three repositories name `_invalidate_walk!`, which does not exist; the loaders skip such an entry (plan/done/cell-layer-audit.md).
- The edge sets are made on first use (plan/pending/cheap-reactive-cells.md, P2 done); L2 and L4 of that plan stay deferred there.

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `CellInterface.jl` holds one abstract type, six bodiless generics and their docstrings, and the guard checks it.
- The export block: one statement for each fragment, in the order of the includes and of the definitions; `CellDefaults.jl` defines no new name and has no statement.
- PAR-QUALIFIED-EXTENSION: every `Base` method is qualified; the fragments define bare; the header has one bare `using`.
- PAR-MODULE-DOCSTRING and the fragment headers; the module docstring names six fragments, and six exist.
- PAR-PER-EDITOR-STATE and PAR-NO-PROJECTION-GLOBALS: no module-level mutable state; the stack is task-local.
- The layering: the layer imports only the performance layer; the guard gives 10 of 10 in the baseline.
- PAR-NO-NESTED-CELL at construction: the stored kinds reject a `Computation`, and a function is a value (tested).
- The weak edge: the scans of `_register_dependent!` and `_unregister_dependent!` remove dead entries; the leak test passes.
- The naming of the other 14 exported names; every private name starts with a verb.
- No history comment, no line over 90 characters, no function over 60 lines, no definition over three positional arguments.
- No sealed file changed after its seal (9d945d65, 2026-09-25).
- Baseline: `Cell` 100 pass, 0 fail, 0 error.
