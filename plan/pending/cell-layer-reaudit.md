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

**The owner, 2026-10-12: "I agree with these".** Decision 1: the four states of a
cell (L03-1 D, L03-2 A, L03-3 A with `CellCycleException`). Decision 2: L03-8 B and
L03-9 B.

## Steps

- [ ] 1. The fixes that need no decision: A-1 … A-10, T-1 … T-13, E-1 (with the module
  bound under its own name in a walkthrough), G-1 … G-12.
  - [x] A-1. The inventory of SEALING.md lists the nine missing files, each after the
    file that loads before it; a comparison of the list with `source/kernel/` finds no
    gap.
  - [x] A-2 … A-10. `record_computation_fault!` is declared in the interface file and
    exported there; its fallback and the two bodies of the untracked kind are in
    `CellDefaults.jl`. `is_cell_up_to_date` of an `UntrackedCell` keeps its answer
    `true`, and its docstring says so, because the walks that read it rely on that
    answer. `find_fault_scope` has the body, and the private copy is gone.
  - [x] T-1 … T-13. Checked: `test_cell` 191, `test_untracked_cell` 48,
    `test_cell_fault_scope` 34, the walkthrough 2, the layering guard 10.
  - [x] G-1 … G-12, with the four states and a section on a cycle.
  - [x] E-1. The walkthrough shows a new computation and a new value of a cell, the
    other cell kinds, `run_untracked`, a cycle and a fault scope. A walkthrough
    session now binds the layer under its own name too, as a REPL does after `using`,
    so a line can add a method of `record_computation_fault!`. The line that adds it
    ends in `nothing`, because the count of its methods depends on the packages that
    are loaded. The three walkthrough tests pass.
- [x] 2. The decisions.
  - [x] Decision 1, the states of a cell. `valid::Bool` is `state::_CellState`, an
    `@enum` of `UInt8`, so a cell grows by nothing. It has five values: the four
    states, and *computing* split in two, because a write that reaches a computing
    cell marks it (`_COMPUTING_OUT_OF_DATE`). `_recompute!` sets *failed* in a `catch`
    that rethrows, and the walk goes on through a failed cell. A read finds a cycle
    when the cell is computing and is on the stack of its own task, so a read from
    another task does not take it for a cycle. `CellCycleException` holds the cell,
    and its message names the cell as its `show` does. The two broken tests pass, and
    a new test covers a direct and an indirect cycle. The law
    (PAR-MONOTONE-INVALIDATION, PAR-ACYCLIC-CELLS) and `cell.md` say so. The kernel
    suite passes, 4384 of 4384, with no broken test left.
  - [x] Decision 2. L03-9 B: the typed code of `_invalidate_dependents!` showed a
    dynamic `:call` of itself, for `ReactiveCell{Int}` and `ReactiveCell{Any}`; with
    `@nospecialize` it is a static `:invoke` of one body. No time was measured. L03-8
    B: the binary serializer of the platform writes `peek(c)`, and the checkpoint of
    omnet-julia asks `is_computed_cell(c)` and reads `peek(c)`; the law
    (PAR-PERSISTENCE-BY-VALUE) names both. `peek` also gives a value for a computed
    cell whose field is not set yet. Checked: the checkpoint test of omnet-julia 100 of
    100, and a binary round trip of a `ReactiveCell{Int}`.
- [ ] 3. The tests, the guards, a second audit, and the seal on the owner's word.
  - [x] The second audit (below), and its fixes.
  - [ ] The seal, when the owner says so.

## The second audit

A second auditor read the layer on a263eb855. It found every finding of the first
audit closed, except a few words (S-8), and nine new ones, S-1 … S-9, from the fixes.
It ran each defect on the bare files of the three layers.

- [x] **S-1 (High)** — `ReactiveCell` had no docstring: the comment and the `@enum` of
  the states stood between the docstring and the struct. The enum is above the
  docstring now, and a test checks `Base.Docs.hasdoc(CellModule, :ReactiveCell)`.
- [x] **S-2 (Medium)** — a cycle through `run_untracked` or an `UntrackedCell` overflowed
  the stack, because `run_untracked` sets the stack aside. It keeps the stacks that it
  sets aside in a list of the task, and the check of a cycle searches them too. Tests
  for both chains.
- [x] **S-3 (Medium)** — a read of a computing cell from another task started a second
  run that set the state to computing, so the mark of a write was lost, and the run
  that ended last stored its value. A second run keeps the mark, and a run stores its
  value only while it still finds the cell computing. A test with two tasks and a
  channel.
- [x] **S-4 (Low)** — a write or a new computation of a cell from inside its own
  computation was lost; the S-3 rule keeps them. A test.
- [x] **S-5, S-7 (Medium, Low)** — `cell.md` and the law: a cycle throws, and a write of
  a value also makes a cell up to date.
- [x] **S-6 (Low)** — a save reads a computed cell with `peek`, which can run a
  computation; a save that throws truncated the old file. `save_document` writes a
  file beside the path and moves it over the path at the end. The law and the
  comment say that a save can compute.
- [x] **S-8, S-9 (Low)** — no barrier and no print words in `CellFaultScope.jl`, and the
  message of a `RecordedFaultException` names a scope; the show of a cell that is
  not up to date says `<out of date>`; one comment of the states in place of three;
  the guide lists the fallback of `record_computation_fault!` and shows the fault
  layer in its diagram; the docstring of the walkthrough says that each call adds a
  method. `CellCycleException` has its "Use it to" paragraph.

Checked: `test_cell` 203, `test_untracked_cell` 48, `test_cell_fault_scope` 34, the
walkthrough 2, the layering guard 10.
