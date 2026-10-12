# The re-audit of the cell layer

The owner, 2026-10-12, after the seal of the performance layer: "let's go for the next
layer". The cell layer, `source/kernel/cell/`, is layer 3 of the kernel. It goes through
the audit with four checks (SEALING.md, "The audit protocol").

The audit ran on main 1e24003d8. Two auditors read the code: one did the architecture
check, and one did the test, example and guide checks. The lead confirmed the Medium
findings in the code. The tests pass: `test_cell` 160 and 2 broken (L03-1, L03-2),
`test_untracked_cell` 42, `test_cell_fault_scope` 28, `test_cell_example` 2.

## Result

The layer does not pass. Three open decisions of the re-audit of 2026-09-27 are still
defects in the engine: L03-1, L03-2 and L03-3.

| File | Architecture | Tests |
| --- | --- | --- |
| `cell/CellModule.jl` | A-7 | passes |
| `cell/CellInterface.jl` | A-2, A-3, A-9, A-10 | T-1, T-7 |
| `cell/CellComputation.jl` | A-3 | T-6 |
| `cell/ReactiveCell.jl` | A-10; L03-1, L03-2, L03-3, L03-9 | T-3, T-11, T-12 |
| `cell/CellFaultScope.jl` | A-1, A-2, A-3, A-4, A-5, A-6, A-8, A-10 | T-2, T-4, T-8, T-9 |
| `cell/MutableCell.jl` | passes | passes |
| `cell/ImmutableCell.jl` | passes | T-13 |
| `cell/UntrackedCell.jl` | A-2, A-3, A-9 | T-5, T-10 |
| `cell/CellDefaults.jl` | A-3, A-8 | T-1, T-10 |

The walkthrough shows only the reactive kind (E-1). The guide `cell.md` has five
Medium findings (G-1 … G-5).

## Check 1: the architecture

- **A-1 (Medium)** — the inventory of SEALING.md does not list `cell/CellFaultScope.jl`,
  and 8 more kernel files: `document/DeclaredType.jl`, `gesture/ChordRecognition.jl`,
  `gesture/ClickRecognition.jl`, `gesture/DwellRecognition.jl`,
  `gesture/GestureRecognition.jl`, `operation/PathChain.jl`,
  `projection/OutputPaths.jl`, `tool/RelevanceSearch.jl`. A file that is not in the
  list can not be sealed with its layer. Fix: add each in load order.
- **A-2 (Low)** — docstrings explain callers in higher layers (L03-11 came back in
  newer text): `CellInterface.jl:139-141`, `UntrackedCell.jl:11-13`,
  `CellFaultScope.jl:4-9` and its example with `print_document` at `:32-34`.
- **A-3 (Low)** — texts that the code does not keep: `is_cell_up_to_date` promises
  that `true` means a read costs nothing, but a computed `UntrackedCell` answers
  `true` and computes at each read; two default bodies are in `UntrackedCell.jl`, not
  in `CellDefaults.jl`; the retry in the newest world is for a reactive cell only; a
  `Computation` goes into an untracked cell too.
- **A-4 (Low)** — the docstring of `record_computation_fault!` says only "must not write
  a cell"; the law lets a computation write a collector with two properties. Fix: state
  them. Whether the state of the barrier in a pipeline has them is for the audit of
  the platform.
- **A-5 (Low)** — `record_computation_fault!` is an open generic that a higher layer
  extends, but it is declared in `CellFaultScope.jl`, not in the interface file.
- **A-6 … A-10 (Low)** — `find_fault_scope` only calls a private copy, and a comment
  repeats its docstring; the `using` lines are not sorted; three lines are longer than
  90 characters; two personified words; missing docstring parts in six names.

Of the re-audit of 2026-09-27: L03-4, L03-5, L03-7, L03-10 and the source part of
L03-12 stay fixed; L03-6 is partly fixed and waits for L03-8; L03-11 came back (A-2).

## Check 2: the tests

- **T-1 … T-7 (Medium)** — no test of `get_cell_computation` and `find_fault_scope`;
  no test that `set_cell_computation!` makes a valid reader out of date; no test of
  `showerror` of `RecordedFaultException`, of `show` of an `UntrackedCell` and of a
  `Computation`; `is_cell_up_to_date` of a computed `UntrackedCell` (A-3).
- **T-8 … T-13 (Low)** — the fallback of a scope with no method; `get_fault_scope(nothing)`;
  the stored kinds refuse a computation; `run_untracked` inside a computation; an equal
  write still makes the readers out of date; the stack of a computation is local to
  its task; `isbitstype` of the cell, not of `Int`.

The auditor ran each proposed test in a bare module: 36 assertions pass.

## Check 3: the examples

- **E-1 (Medium)** — `print_cell_example` shows the reactive kind only. It does not show
  `set_cell_computation!`, `set_cell_value!`, `MutableCell`, `ImmutableCell`,
  `UntrackedCell`, `run_untracked` or the fault scope. The auditor ran 14 lines that
  show them. A scope that takes a fault needs a method of `record_computation_fault!`,
  which a person can type only when the session binds the module under its own name;
  `_print_walkthrough` binds it as `Layer` only.

## Check 4: the guide

- **G-1 (Medium)** — `cell.md` says that the layer imports only the performance layer;
  it imports the fault layer too.
- **G-2 (Medium)** — the guide says that the code keeps its invariants, but L03-1 and
  L03-2 break the monotone one.
- **G-3 (Medium)** — five exports of the fault scope are not in the list of public
  names, and two are named nowhere.
- **G-4 (Medium)** — no "Try it" section, and no word on `print_cell_example`.
- **G-5 (Medium)** — a computation in a scope throws a `RecordedFaultException` only
  when the scope takes the fault; otherwise its exception goes on.
- **G-6 … G-12 (Low)** — accuracy and wording. G-13, the part on the struct layer, waits
  for the audit of layer 4.

## The open decisions of the engine

The code today, confirmed by the lead in `ReactiveCell.jl`:

- **L03-1 (High).** A cell records its reader before it computes. When the computation
  throws, the cell stays invalid, and the reader that caught the exception becomes
  valid with its own answer. The walk of a later write stops at an invalid cell
  (`_invalidate_dependents!`: "a reader that is invalid already stops the walk"), so
  that reader never computes again. Test: `CellTest.jl:401`, broken.
- **L03-2 (Medium).** A cell becomes valid at the end of each computation. A write that
  reaches it while it computes is lost, because the walk stops at a cell that is not
  valid. The heartbeat of the clock writes from a task of its own. Test:
  `CellTest.jl:419`, broken.
- **L03-3 (Medium).** A cell that reads itself through a cycle computes again, until
  the stack overflows. A `StackOverflowError` is not a fault, so no barrier records it,
  and it ends the editor.

**Facts that changed since 2026-09-29:** the barrier in a pipeline recovers by a retry
after an operation or a click, not by a change of its input, so the main reason that
the lead gave for option A of L03-1 is gone. The formula slice detects its own
cycles. The clock tells a computation that reads it not to yield.

## Decisions for the owner

1. **The states of a cell (L03-1, L03-2, L03-3 together).** Recommended (the lead's):
   one field `state` in place of `valid::Bool`, with four values, and no more memory:
   - *up to date* and *out of date*, as `valid` is today;
   - *failed*: a computation that threw. A read computes again, as today, but the walk
     of a write goes on through the cell to its readers. This is a new option D for
     L03-1: it closes the defect with no stored exception, so a cell grows by nothing,
     and a fix with Revise needs no write to take effect;
   - *computing*: a write that reaches the cell marks it, and the cell stays out of date
     at the end (L03-2 A). A read of a computing cell from inside its own computation is
     a cycle, and throws `CellCycleException`, an ordinary exception that a barrier
     records (L03-3 A).

   The two broken tests become tests; the law (PAR-MONOTONE-INVALIDATION,
   PAR-ACYCLIC-CELLS) and `cell.md` change with it. The other options are those of
   `kernel-audit-fixes.md`.
2. **L03-8 and L03-9.** L03-8, a public read of a stored value for persistence:
   recommended B, as before: a serializer asks `is_computed_cell` and reads `peek`; no
   cell file changes. New fact: an `UntrackedCell` stores no value; `is_computed_cell`
   tells it apart. L03-9, `@nospecialize` on the walk: recommended B, as before: a
   static check of the walk first, and the change only if the walk dispatches at run
   time; no measurement of time.

## Steps

- [ ] 1. The fixes that need no decision: A-1 … A-10, T-1 … T-13, E-1 (with the module
  bound under its own name in a walkthrough), G-1 … G-12.
- [ ] 2. The decisions.
- [ ] 3. The tests, the guards, a second audit, and the seal on the owner's word.
