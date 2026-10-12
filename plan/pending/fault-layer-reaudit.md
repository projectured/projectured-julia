# The re-audit of the fault layer

The owner, 2026-10-12: "let's do the complete re-audit of the fault layer". This is
the first layer that goes through the audit with three checks (SEALING.md, "The
audit protocol"). Every kernel file is unsealed since 4d8a5ffe8.

The audit ran on main 4d8a5ffe8. Two auditors read the code: one did the
architecture check, and one did the test check and the example check. The lead
read the code behind every High and Medium finding and confirmed each one. The
lead also confirmed E-2 by a run. The five fault test suites pass, 92 of 92.

## Result

The layer does not pass. Each file has at least one finding: 8 in the
architecture, 12 in the tests and 2 in the examples.

| File | Architecture | Tests | Examples |
| --- | --- | --- | --- |
| `fault/FaultModule.jl` | A-3, A-4 | passes | — |
| `fault/FaultInterface.jl` | A-5 | passes | — |
| `fault/FaultDefaults.jl` | A-6, A-8 | T-12 | — |
| `fault/FaultRecord.jl` | A-7 | T-5, T-8, T-9 | — |
| `fault/FaultStore.jl` | A-1, A-2, A-6, A-7 | T-1, T-2, T-6, T-7 | — |
| `fault/FaultPolicy.jl` | A-6 | passes | — |
| `fault/FaultCascade.jl` | A-4 | T-3, T-11 | — |
| `fault/FaultBarrier.jl` | A-1, A-4 | T-4, T-10 | E-1 (the layer) |

## Check 1: the architecture

- **A-1 (High) — a new fault that does not fit in a full store reaches no tier.**
  `FaultStore.jl:173-176`: a full store adds 1 to `dropped` and answers
  `nothing`. The key does not go in `undrained`, so no drain, no log and no
  console sees it. `FaultBarrier.jl:62` reports by itself only when there is no
  store. No code outside the tests reads `dropped`. This breaks "a barrier never
  swallows a fault in silence" (PAR-REPORT-NEVER-THROWS). It is the open part of
  L01-1, and it waits for decision 1.
- **A-2 (Low) — a stop exception in the drain loses the records after it.**
  `FaultStore.jl:214-226` empties `undrained` before the hand-over. If a target
  rethrows a stop exception, the keys after it are gone until their count reaches
  the next power of ten. Fix: before the rethrow, put the keys that were not
  handed over back in `undrained`.
- **A-3 (Low) — the export block.** `FaultModule.jl:41-45`: the statement of
  `FaultStore.jl` does not list the names in the order that the fragment defines
  them, and one statement names two fragments. The file is on the list
  `EXPORT_UNMIGRATED` of `test/suite/exports.jl`. Fix: the order of the fragment,
  one statement for each fragment, and the file off the list. This is L01-11.
- **A-4 (Low) — the console is a copy, not a fallback.** The law says that a
  report goes to the first tier that works, and each tier falls to the next.
  `report_frame_faults!` (`editor/FaultBarriers.jl:39-43`) gives each drained
  record to the console also when a target took it. The texts say both:
  `FaultCascade.jl:12-15` calls the console a fallback, and `drain_faults!` says
  the caller reports the same records on the console. `FaultBarrier.jl:30` says
  "one line per new fault", but a record gets a line again at each power of ten.
  `FaultModule.jl:32` says `FaultCascade.jl` holds five tiers; it holds tiers 3 to
  5. Waits for decision 3.
- **A-5 (Low) — two seam docstrings are not true.** `FaultInterface.jl:89` and
  `:104` say that a barrier asks `is_passthrough_exception`; every catch-all arm
  asks it. `FaultInterface.jl:11-12` says `append_fault!` runs once per new
  record; it runs again at each power of ten.
- **A-6 (Low) — docstrings name callers in higher layers**
  (PAR-NO-CONSUMER-DOCS). `FaultPolicy.jl:41-42` lists `Editor`, `make_editor`,
  `build_editor` and `run_editor!`; `FaultPolicy.jl:47` shows `make_editor`;
  `FaultStore.jl:242-243` names the safe mode; `FaultDefaults.jl:17` names the
  editor. The examples at `FaultPolicy.jl:20` and `:47-48` pass the strict policy,
  which is already the default, so they show a step that changes nothing.
- **A-7 (Low) — kernel examples name a domain.** `FaultRecord.jl:25` and
  `FaultStore.jl:40` use `origin = JsonToSyntax` from ProjecturedJSON. Fix:
  `origin = p.inner`, as `FaultStore.jl:145` does.
- **A-8 (Low) — comments repeat the seam docstrings** (PAR-TIGHT-COMMENTS).
  `FaultDefaults.jl:4-5`, `:20-21` and `:24-25` repeat the paragraph "The default
  is …" of the seams in `FaultInterface.jl`. Keep `:10-12`, which states a
  constraint.

The other requirements pass. `run_fault_barrier!` still has seven keywords and
one call site outside the tests, as the owner accepted on 2026-09-24.

## Check 2: the tests

`julia tool/survey-interface-tests.jl FaultModule`: 1 of 19 exports has no test
that names it.

- **T-1 (Medium)** — `reset_consecutive_fault_count!` has no test.
  `editor/SafeMode.jl:36` and `:52` call it. Test: it answers the store, it sets
  the one counter to 0 and leaves another counter, and it answers `nothing` for no
  store.
- **T-2 (Medium)** — `attach_fault_target!` promises that a target is not
  attached twice. Test: attach one target twice, drain one record, and assert one
  hand-over.
- **T-3 (Medium)** — `report_fault!` promises the sound when the console tier
  fails (`FaultCascade.jl:32-34`, `:89-100`). No test makes the console throw.
  Test: a logger that throws, and the answer `:sound`.
- **T-4 (Medium)** — every barrier test closes the console, so no test sees the
  report of a barrier with no store (`FaultBarrier.jl:60-65`). Test: with no
  store, one `[fault]` line; with a store, no line.
- **T-5 (Medium)** — `make_fault_record` promises that an exception whose own
  `showerror` throws gives its type name. Only the stop exception is tested
  (`FaultRecordTest.jl:16-17`). Test: a `showerror` that calls `error`.
- **T-6 (Low)** — a full store keeps the first keys and answers `nothing` for a
  new one; a known key still counts; the default capacity is 64.
- **T-7 (Low)** — a record keeps the message and the reference of its first
  occurrence.
- **T-8 (Low)** — the traceback is `""` without a backtrace, and a long one is cut
  to 12 lines that end in `"  …"`.
- **T-9 (Low)** — an origin that is a type, and one that is a value, give their
  type names.
- **T-10 (Low)** — the defaults of `run_fault_barrier!`: the fallback `nothing`,
  the origin `:editor`, the reference; and a stop exception leaves no record.
- **T-11 (Low)** — `FaultCascadeTest.jl:81` asserts `isa Symbol`; assert
  `=== :console`. And a device fault with the sound off plays no sound.
- **T-12 (Low)** — `FaultDefaultsTest.jl:53` asserts that the output holds a bell;
  assert that it is one bell.

The test that the strict policy is the default of `make_editor` belongs to the
audit of the editor layer (`EditorBuild.jl:144`).

## Check 3: the examples

- **E-1 (Medium)** — the layer has no walkthrough. A REPL session can show it
  with kernel names: a store, a policy, a barrier that answers a value and then
  the fallback, the count of one key, the consecutive count, a full store that
  drops, a drain, `report_fault!`, `is_passthrough_exception` and the strict
  policy. The console and the sound can not be shown: they write to the global
  logger and to the terminal, which a test of the full text can not read. Add
  `print_fault_example` with a test of its full text.
- **E-2 (Low)** — `example/kernel/Walkthrough.jl:29` shows a value in the world of
  the caller. A line that answers a function prints a warning about the world age
  (confirmed on Julia 1.13.1). Fix: show the value through `Base.invokelatest`.

## Decisions for the owner

1. **L01-1 — a fault that the full store drops.** A: the drain reports the count
   of the dropped faults. B: the drops count into one overflow record. C: B, and
   a full store forgets the oldest key that the drain already handed over. D: a
   clear of the fault log. **Recommended (the lead's): C**, because with A, B and
   D a long session fills the store once and every new kind of fault after it is
   only a number.
2. **L01-2 with L01-12 — the targets of the safe mode grow, and the safe-mode seam
   is in the wrong layer.** L01-2 A: the store gets `detach_fault_target!`, and the
   safe mode detaches what it attached. L01-12 A: `make_safe_mode_projection`
   moves to the editor layer, beside `enter_safe_mode!`. **Recommended (the
   lead's): A and A.**
3. **A-4 — the console after a target.** A: the code follows the law: the frame
   reports on the console only a record that no target took, and a device fault
   still plays the sound. B: the law follows the code: the console always gets a
   copy, as the log of the process. **Recommended (the lead's): A**, because the
   law is the written decision, and with B a policy with the console off plays the
   sound for a fault that the log already shows.

**The owner, 2026-10-12: "point 1: agreed / point 2: agreed / point 3: agreed".**
The decisions are C for L01-1, A for L01-2, A for L01-12, and A for A-4.

## Steps

- [ ] 1. The fixes that need no decision: A-2, A-3, A-5, A-6, A-7, A-8, E-2.
  - [x] A-5, A-6, A-7, A-8 and E-2 (ee69d5133). The new example of
    `make_strict_fault_policy` is a barrier around a parse, so it names no editor.
- [ ] 2. The tests T-1 … T-12, and the walkthrough `print_fault_example` (E-1).
- [ ] 3. The three decisions.
  - [x] L01-1 C. The field `dropped` is gone: the overflow record holds that
    count. The overflow record has the site `:store`, the origin `:FaultStore`,
    the exception type `:Nothing` and a fixed message. It does not count against
    the capacity, and the store never forgets it, so its count is every fault
    that did not fit. The store forgets the oldest key in the order of first
    occurrence that does not wait for the drain. The tests of the capacity cover
    T-6.
- [ ] 4. The fault tests, the cell example test, and the guards. Then the audit of
  the changed files again, and the seal on the owner's word.

## Outside the layer

- `editor/FaultBarriers.jl:8` says that `make_editor` turns the barriers on. It
  starts strict.
- `adapter/mcp/McpServer.jl:123` and `:272` are catch-all arms that do not ask
  `is_passthrough_exception` (POLICY-1).
- The open item L01-4, the length of the traceback, is in
  `a-fault-is-easy-to-see-and-stays-small.md`.
