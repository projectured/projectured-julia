# Fix the findings of the kernel audit that need no decision

The owner asked on 2026-09-29: "create a plan for fixing all issues which don't require design
decisions from me". The issues are the 329 findings of the kernel re-audit in
[kernel-audit/](kernel-audit/README.md). Each item below names its finding. The report of the
layer holds the evidence, and this plan holds the fix and the test.

- **Base:** main at `5616fa19`. The audit ran on `15b40434`. Six classifiers read each finding
  again on `5616fa19`: 300 are unchanged, 29 moved lines, and none is fixed or wrong.
- **This plan:** 220 items: 192 whole findings and 28 parts of findings whose other part needs a
  decision. 211 items can start now. 9 items wait for a decision on another finding.
- **Not in this plan:** 125 findings need a decision of the owner, and 12 findings are in other
  plans. Both lists are at the end.
- **High findings in this plan:** L09-1, L09-2, L10-1, L10-2, L10-3, L11-1, L17-1, L18-1, L18-2 and
  L19-1, and the part of L01-1.
- **Sealed files:** 54 items change 39 sealed files. They need the owner's permission for each
  file (Phase 3, and three renames of Phase 5).

## What "no decision" means here

An item is in this plan only when all of these hold:

- The fix restores what a contract, a docstring or a rule already promises. Or it corrects text
  to match the code, adds or corrects a test, removes code with no user in the three
  repositories, or applies a naming rule that fixes the new name.
- If the report gave options, one of them is the smallest, keeps every documented contract, and
  has the same effect for a person and for the architecture. The item names that option.
- It adds no new concept, type, seam, mechanism or free name. A new function is only the
  direct counterpart of one that exists.
- It does not change what a PAR rule requires, and it does not reverse a decision that the owner
  recorded. It can correct a stale fact about the code in the law.

When a classifier was in doubt, the finding went to the decisions. The lead moved four more
items there: L17-16 (it removes a line of SEALING.md), L22-27 (a name that no rule fixes), the
PAR-NO-NESTED-CELL part of L10-13, and the splits of files into new fragments (L10-21, L17-19,
L18-23), whose names no rule fixes.

## Permission for the sealed files

A step that changes a sealed file waits until the owner gives permission for that file. The owner
can give it for all the files below at once, or step by step.

| Sealed file | Items |
| --- | --- |
| `package/ProjecturedKernel/src/ProjecturedKernel.jl` | L07-4, L09-17 |
| `backend/BackendDefaults.jl` | L09-6 |
| `backend/BackendInterface.jl` | L09-6, L09-13, L09-16 |
| `backend/BackendModule.jl` | L09-14, L09-16 |
| `cell/CellComputation.jl` | L03-11, L03-12 |
| `cell/CellDefaults.jl` | L03-5 |
| `cell/CellInterface.jl` | L03-11 |
| `cell/ImmutableCell.jl` | L03-11 |
| `cell/MutableCell.jl` | L03-11 |
| `cell/ReactiveCell.jl` | L03-4, L03-6, L03-7, L03-11, L03-12 |
| `clock/Clock.jl` | L05-1 (part), L05-2 |
| `device/Display.jl` | L07-3, L07-4 |
| `document/DocumentSearch.jl` | L10-25 |
| `document/ForwardProtocol.jl` | L10-20 |
| `event/EventInterface.jl` | L06-13 |
| `event/EventPattern.jl` | L06-3, L06-4, L06-5, L06-6 |
| `event/KeyboardEvent.jl` | L06-1, L06-9 |
| `event/ModifierKeys.jl` | L06-9 |
| `event/MouseEvent.jl` | L06-2, L06-9, L06-13, L09-2 |
| `event/WindowEvent.jl` | L06-13 |
| `fault/FaultBarrier.jl` | L01-14, L01-16 |
| `fault/FaultCascade.jl` | L01-7, L01-13, L01-14, L01-16 |
| `fault/FaultInterface.jl` | L01-14, L01-15 |
| `fault/FaultModule.jl` | L01-14, L01-16 |
| `fault/FaultPolicy.jl` | L01-14 |
| `fault/FaultRecord.jl` | L01-9 |
| `fault/FaultStore.jl` | L01-1 (part), L01-3, L01-10, L01-14, L01-15, L01-16 |
| `gesture/GestureRecognizer.jl` | L08-3 |
| `iomap/IoMapInterface.jl` | L16-9 |
| `performance/FrameMeasurement.jl` | L02-2, L02-7 |
| `performance/PerformanceCounter.jl` | L02-7 |
| `reference/ReferenceInterface.jl` | L11-7, L11-16, L11-25 (part) |
| `reference/ReferenceSearch.jl` | L11-14, L11-16 |
| `selection/SelectionDefaults.jl` | L11-3, L12-7, L12-9, L12-10 |
| `selection/SelectionInterface.jl` | L12-4, L12-7, L12-8, L12-10 |
| `selection/SelectionModule.jl` | L12-6 (part), L12-7, L12-10 |
| `struct/CellStruct.jl` | L04-8, L04-9 |
| `struct/CellStructModule.jl` | L04-7, L04-8 |
| `struct/CellStructPlan.jl` | L04-1, L04-7, L04-9 |

## Changes that a person or a caller sees

These items change behaviour on purpose, because the old behaviour broke a promise. Read them
before you approve the plan.

- **Keys (L09-1):** every backend names the letter keys `:a` to `:z`. Ctrl+Z, Ctrl+Y, Ctrl+F and
  Ctrl+Shift+D start to work in the SDL application, and Ctrl+S, Ctrl+O, Ctrl+W, Ctrl+T and
  Ctrl+Shift+P in the browser. The console gives Ctrl+letter keys.
- **Mouse (L09-2):** a side button of the mouse does nothing. Before, it was a right click on SDL
  and a left click in the browser.
- **Search (L10-1, L10-2):** `search_documents` finds every document that holds an equal value.
  `search_references` on a structure with a cycle gives fewer results, and the count no longer
  grows with `maxdepth`.
- **Chains (L13-4, L17-18):** `DoNothingOperation` and five other operations pass through a
  chain unchanged. A key that fell through a chain before can now stop at a
  `DoNothingOperation`, as its docstring promises.
- **Routes (L13-2):** `operation_reference` answers a path for `ReplaceSelectionOperation` and
  for a `ReplaceReferencedValueOperation` rooted at the editor, so `Copying.jl` and
  `AssistantTurn.jl` route these operations.
- **Documentation tools (L18-1):** `search_api`, `list_modules` and the other readers see the
  whole surface that the code tool binds. The index grows from about 800 entries to several
  thousand.
- **Inbox (L21-4, L22-5):** one drain applies at most the operations that were ready when it
  started, and it wakes the next frame for the rest.
- **Safe mode (L22-18):** after the safe mode ends, the editor paints before it reads on. An
  editor made with `Editor(…)` prints once before its first frame.
- **Log (L22-16):** the log line of an operation shows its description, not its full value.
- **Refusals:** `FaultStore(capacity = 0)`, a `Display` with a scale or a zoom of 0 or less, an
  `Agent` with `max_rounds < 1`, and a second bare `when` in one `@gestures` block now throw
  (L01-1, L07-3, L20-8, L15-7).
- **Public names:** `KeyDown` takes `repeat` as a keyword (L06-9). Seven renames change public
  names in Phase 5, among them `run_fault_barrier!`, `execute_julia_code!` and
  `get_default_llm_model`. The MCP tool keeps its wire name `execute_julia_code`.

The work found more changes of this kind:

- **Playback (N-6):** `play_live!` works again. It threw `UndefVarError` for `read!` on every
  call on Julia 1.13, so every live example of playback failed.
- **Undo (N-5):** the way back of an element overwrite in a reactive `CellVector` puts back the
  old value. Before, it put back the new one.
- **Keys (N-8):** Ctrl+\ can fire in the browser.
- **The editor loop (L21-2, L21-3, L22-6, L22-7, L22-11):** a feed, a deadline or a frame clock
  that throws no longer ends the loop. A posted operation takes an inverse first and gets the
  repairs, and its fault record names its type. An operation posted during a drain waits for the
  next frame, which runs at once. An inverse that throws leaves a fault record, so the console
  shows it.
- **Faults (L01-3, L01-10):** one drain hands a record over once, so a fault that counts 3000
  gives one console block, not four. A target that refuses a record logs only when the policy
  has the console on.
- **The agent (L20-3, L20-5):** a tool that throws gives a result with `is_error = true`, and a
  stream cut before its end ends the turn with `:error`.
- **References (L11-3, L11-20):** a step of the `M…` layout matches a pattern and descends in
  `set_selection!`, as a step of the `C…` layout does; omnet-julia builds such references. A
  referenced value gets a path only when the path evaluates back to the value.
- **Gesture tables (L15-3):** `@gestures` builds its table once, at load time, so a name that a
  pattern or a `splice` reads must be defined above the block.
- **Copies (L10-4, L10-5):** a copy keeps the type parameters of a schema and the element type
  of a vector. A plain copy with a policy of a vector that has no `similar` gives `Vector{Any}`.
- **Display (L03-12):** a typed cell shows as `ReactiveCell{Int64}(…)`; `Cell(…)` stays for
  `ReactiveCell{Any}`.
- **Clocks (L05-2, L22-20):** the heartbeat and the frame clock measure with the monotonic clock.
- **SDL input (L09-9):** the held buttons and the modifiers of an event are those of the queue at
  that event, not those at the poll.

## How to work

1. **Worktree.** Do the work in `/home/projectured/workspace/projectured-julia-kernel-fixes` on
   the branch `kernel-audit-fixes`. The renames and the `KeyDown` keyword reach omnet-julia and
   inet-julia: make a worktree there when Phase 3 or Phase 5 needs one, and land the three
   branches together.
2. **Baseline.** Before step 1.1, run on the base commit and record the counts in this plan:
   - `test_kernel()`, `test_substrate()`, `test_sdl()`, `test_web_backend()`,
     `test_console_backend()` and `test_video()`;
   - the suites of the domains that use templates with a thunk child list: `test_julia()`,
     `test_math()`, `test_fsm()` and `test_process()`;
   - `test_mcp_tools()` (2 known failures), `test_arguments()` (5 known violations), and the
     export, naming and documentation guards;
   - for omnet-julia and inet-julia: `Pkg.precompile()`, and the suites that the renames reach.
     Run the omnet-julia suites with `-t 4`, and run them in `unshare -rn`, so that no suite loads
     an Ollama model.
3. **Resources.** Give each Julia process a memory cap with `systemd-run --user`. Keep the sum
   under half of the available memory. Run tests on CPUs 24-27, builds nicely on 16-23, and use
   `TMPDIR=/var/tmp/<name>`. A run that takes more than a few minutes is a user service.
4. **Order.** Do Phase 1 first, in the order of its steps. Phases 2, 4 and 6 can then go in any
   order, but an item goes after the items that it names in "after". Phase 3 waits for the
   permission of each of its files. Phase 5 goes after Phases 2 and 3, because a rename changes
   the lines of the other items.
5. **Each step.** Make one commit for each step, or one for each item when the item is large.
   Run the narrowest test that the item names. Mark the item `[x]` in this plan. Write a fact
   or a choice that the work finds into the plan, below its item.
6. **Each phase.** At the end of a phase, run the suites of the baseline again and compare the
   counts. A change of a count needs its reason in the plan.
7. **Help.** A code expert can implement an item. A code reviewer checks each commit that is not
   trivial. The lead checks each result.
8. **Landing.** The owner decides when the branch lands. Report the commits, the counts and the
   command, and stop. Do not push.

When all items are done, move this plan to `plan/done/`.

## Phase 0 — The worktree and the baseline

- [x] Make the worktree and the branch.
  The work runs in two lanes, each in its own worktree, from the base `a1e0b8a5`, so that a
  half-done edit of one lane does not break a test run of the other:
  - Lane A: `projectured-julia-kernel-fixes`, branch `kernel-audit-fixes`. Layers 1 to 16 and
    the backends: steps 1.1, 1.2, 1.3, 1.7, 2.1, 2.2, 2.3, 2.5, 2.6, all of Phase 3, and the
    tests of these layers. Only this worktree edits this plan.
  - Lane B: `projectured-julia-kernel-fixes-b`, branch `kernel-audit-fixes-b`. Layers 13, 14 and
    17 to 23: steps 1.4, 1.5, 1.6, 1.8, 2.4, 2.7 to 2.10, and the tests of these layers.
  - Lane B merges into lane A before Phase 5. Phases 5 and 6 run on the merged branch.
  - **Merged** on 2026-09-29 as `bf4492721`. The conflicts were four test lists; both lanes had
    added the same `Base.hash` of `ProjectionReferenceStep`, and the merge keeps one. The suites on
    the merge, against the baseline:

    | Suite | Baseline | Merged |
    | --- | --- | --- |
    | `test_kernel()` | 2412 pass, 3 fail, 3 error | 3901 pass, 2 broken |
    | `test_substrate()` | 86830 and 8 known | 86907 and the same 8 known |
    | `test_sdl()` | 774 | 840 |
    | `test_web_backend()` | 38 | 99 |
    | `test_console_backend()` | 84 | 133 |
    | `test_video()` | 41 | 41 |
    | `test_mcp_tools()` | 152 | 158 |
    | `test_fault()` | 73 | 78 |
    | `test_julia()` | 407 | 410 |
    | `test_math()`, `test_fsm()`, `test_process()`, `test_formula()` | 173, 154, 304, 116 | the same |
    | `test_json()`, `test_xml()`, `test_undo()`, `test_type_reference()` | not run | 194, 73, 110, 44 |
    | `test_assistant_mvp()` | not run | 127 pass, the 4 known failures |
    | `test_conversation()` | not run | 166 pass, the 1 known failure |
    | `test_arguments()`, `test_exports()` | 6 and 3 failures | the same |

    The two broken tests of the kernel are L03-1 and L03-2, which wait for decisions.
  - **omnet-julia and inet-julia** after Phase 5, each in a scratch environment with absolute
    paths, run once against a worktree of the base `a1e0b8a5` and once against this branch with
    their own branches `kernel-audit-fixes` (the renames, N-1, the trace lines):

    | Repository | Base | Fixed |
    | --- | --- | --- |
    | inet-julia `test/suite/runtests.jl` | 20105 pass, 11 fail | the same |
    | omnet-julia `test/runtests.jl` | 12332 pass, 37 fail, 72 error | 12332 pass, 36 fail, 71 error |

    The two differences of omnet-julia come from the checkout, not from the fixes: the base ran in
    the main checkout, whose untracked folder `mm1k/` adds one NED file (one more error of
    `NedAgreement`) and one INI file (one more pass of `IniAgreement`), and whose untracked
    manifests fail "every folder holds one kind of thing". Every other test set has the same counts.
  - **Main merged in** on 2026-09-30 as `f3b8ff42b` (main at `ee5783d42`, 39 commits later, with the
    relevance model of the search). The conflicts were in the tool layer; the new tests of main
    call `execute_julia_code!`. On the result: `test_kernel()` 3967 pass and 2 broken, every other
    suite at its count, and omnet-julia and inet-julia as before.
- [x] Run the baseline of "How to work", item 2, and write the counts here.
  On `a1e0b8a5`, in the worktree of lane A, each suite in its own process (2026-09-29):

  | Suite | Pass | Fail | Error | Broken |
  | --- | ---: | ---: | ---: | ---: |
  | `test_kernel()` | 2412 | 3 | 3 | 0 |
  | `test_substrate()` | 86830 | 3 | 4 | 1 |
  | `test_sdl()` | 774 | 0 | 0 | 0 |
  | `test_video()` | 41 | 0 | 0 | 0 |
  | `test_web_backend()` | 38 | 0 | 0 | 0 |
  | `test_console_backend()` | 84 | 0 | 0 | 0 |
  | `test_mcp_tools()` | 152 | 0 | 0 | 0 |
  | `test_fault()` | 73 | 0 | 0 | 0 |
  | `test_julia()` | 407 | 0 | 0 | 0 |
  | `test_math()` | 173 | 0 | 0 | 0 |
  | `test_fsm()` | 154 | 0 | 0 | 0 |
  | `test_process()` | 304 | 0 | 0 | 0 |
  | `test_formula()` | 116 | 0 | 0 | 0 |
  | `test_arguments()` | 0 | 6 | 0 | 0 |
  | `test_exports()` | 0 | 3 | 0 | 0 |
  | `test_naming()` | 1 | 0 | 0 | 0 |
  | `test_documentation()` | 1 | 0 | 0 | 0 |

  The failures are known. The kernel has the five Rule C cases of `DocumentMacroTest.jl` and
  `MEvalBranch` of `ReferenceEvalTest.jl` (step 1.1). The substrate has two failures of
  `AnchorPointTest.jl` and five of `SplitPaneDragTest.jl`. The argument guard reports its five
  violations and its summary check. omnet-julia and inet-julia get their baseline in Phase 5.

## Phase 1 — The failures on main and the High faults in files that are not sealed

These steps change no sealed file. Do them first: they end the failures on main and the High faults that a person can meet.

### Step 1.1: Repair the two tests that fail on main

The kernel suite then has no Fail and no Error.

- [x] **L10-14** (Medium, Tests)
  Repair the test, do not mark it broken. Register the stand-in with `DocumentModule.is_collection_field_type(::Val{name}) = true` before the first `@document` that uses it, and correct the file docstring. Rename the stand-in (for example `DmCollection`), so that the registration is not a second definition of the method that ProjecturedCollection makes for `Val{:CellVector}`.
  *Test:* test_document_macro() in `julia --project=package/ProjecturedKernelTest`: the Rule C testsets pass, with 0 Fail and 0 Error.
  *Done:* lane A, 56e7fb13. The stand-in is `DmCollection`, registered before the first `@document`. test_kernel: 2422 pass, 0 fail, 0 error.
- [x] **L11-18** (Medium, Tests)
  Repair the test, do not mark it broken: write `MEvaluationBranch` at line 216 and in the comment at line 214.
  *Test:* test_reference_evaluation(): the testset 'a reference names a schema, not the layout it was built on' runs, with 0 Error.
  *Done:* lane A, 56e7fb13.

### Step 1.2: The walk and the sync of the document layer

Each fix gets the regression test of its "Checked by the lead" run.

- [x] **L10-1** (High, Correctness)
  In `_walk_document!`, for a walk leaf run the predicate and the `reported` check and return, with no `_enter_node`, so a leaf never goes into `seen`. Keep the order for other nodes, so a path that loops is not reported. Correct the comment at lines 125-131.
  *Test:* test_document_walk(): search_documents on a CellVector of two PrimitiveNumber(7) answers both documents, also for a String query.
  *Done:* lane A, 71eade34. A walk leaf does not enter the visited set. `raw = true` still answers one location for equal values, because a raw location is the value itself and the walk reports each location once, as its contract says. A scalar that is not a walk leaf (an Enum, an isbits struct, a tuple) is still collapsed by `:once_per_object`.
- [x] **L10-2** (High, Correctness)
  Under `:once_per_path`, record every node that is not a walk leaf in `seen`, not only a mutable one. Change the test at DocumentWalkTest.jl:72 so that it asserts a count that does not grow with `maxdepth`. Correct the comment at lines 128-131.
  *Test:* test_document_walk(): search_references on a three-node doubly linked ListNode list gives the same count at maxdepth 16 and 64.
  *Done:* lane A, 71eade34. The new test uses maxdepth 12, 16 and 24, because the old code hangs at 64. test_substrate: 86839 pass and the 7 known failures; test_mcp_tools: 152.
- [ ] **L10-3** (High, Correctness)
  When a leaf value is a mutable container (`AbstractArray`, `AbstractDict`, `AbstractSet`), write a copy of it into the shadow at line 83 and at line 111. The shadow then owns its value, and the next `isequal` compares by value.
  *Test:* test_document_contract(): push! into a Vector field of the source between two syncs; the second sync writes the shadow cell, and a reader of that cell computes again.
  *Moved to the decisions:* the copy breaks a real sync. A vector with unassigned slots makes the next
  `isequal` throw `UndefRefError`, and omnet-julia syncs `ParallelEngine.green_buf`, a
  `Vector{ParallelEvent}(undef, 1_000_000)`, in each slice of the dashboard, so each sync would
  also copy and compare a million slots. A vector of mutable elements that hold locks can not take
  `deepcopy`. The patch of the copy waits in `/var/tmp/kernel-fixes/a/L10-3-sync-copy.patch`.

### Step 1.3: The element step on a String

- [x] **L11-1** (High, Correctness)
  Add `evaluate_reference_step(step::ARangeReferenceStep, document::AbstractString)` that keeps the Position answer for a caret and reads the character at `nextind(document, 0, step.start + 1)`. Julia has no `nthind`, which the report names.
  *Test:* test_reference_evaluation(): on "héllo", `[3]` answers 'l', `[6]` does not resolve, and get_valid_reference_prefix keeps `{2:4}`.
  *Done:* lane A, 33e49e44. test_kernel: 2427 pass.

### Step 1.4: The thunk child list of the template engine

Use the run of the report as the regression test: `x = 1:2:5`, then `step = nothing`, on the same output.

- [x] **L17-1** (High, Correctness)
  In _find_conditional, take a field whose cell is_computed_cell and holds a marker vector, and drop the test for a bare Function. In _conditional_print, read that cell inside the state computation, and give the output node a new children cell in the _with_selection rebuild, because a write into the computed cell deletes its computation.
  *Test:* New test_projection_template_conditional_children() in ProjectionTemplateTest.jl: a probe builder writes SyntaxConcatenation(() -> ...) over an optional field; write nothing, then a value, through the same IoMap; assert that the output children follow each write and that nothing throws. Also the case x = 1:2:5 with r.step = nothing in test_julia_to_syntax().
  *Done:* lane B, fa1c8c02. `_find_conditional` reads the children cell with `peek`, so that the computation that prints the parent does not depend on the child list; the state cell holds the tracked read. Both regression tests fail on the old code. Suites: test_julia 410 (+3), test_substrate 86839 (+9), the others at their baseline. A remaining risk, for L17-15: the walk in the state cell strips the `bound` markers of the vector that it reads, so a second run on the same cached vector would make a bound leaf an introduced slot. It runs again when a thunk child list is nested in another one: the outer walk reads the inner markers cell with a tracked read, so an edit of the inner list runs the outer walk again over its stripped vector. No template of today nests two thunk lists (found by the review). The macros guide does not describe the thunk child list (for L17-23).

### Step 1.5: The pipes of the code tool

Use the run of the report as the regression test: a print of 200 000 bytes returns.

- [x] **L18-2** (High, Correctness)
  Before the evaluation, start one task for each pipe that reads it into an IOBuffer. After redirect_stdio returns, close the write ends and wait for the two tasks. This keeps the design: the process-wide redirect stays.
  *Test:* test_code_execution(): a call that prints 200 000 bytes answers all of them; run the call in a task with a bounded wait, so that a regression fails and does not hang.
  *Done:* lane B, 80b7c6c4. One reader task for each pipe starts inside `redirect_stdio`, where the pipes open; a `finally` closes the write ends and fetches the readers. The regression test fails on the old code after its 60 s bound.
- [x] **L18-5** (Medium, Correctness) — after L18-2
  Close the write ends, read the pipes and close the read ends in a finally block. Put the printed text before the error text in the answer.
  *Test:* test_code_execution(): a call that prints 1 and then throws answers the 1 before the error text; a call with a syntax error on its last line shows what its first lines printed.
  *Done:* lane B, 80b7c6c4. The run on the old code confirmed that the lines before a syntax error on the last line do run.

### Step 1.6: The Anthropic adapter

- [x] **L19-1** (High, Correctness)
  Give `_drain_sse_events!` an `input_tokens::Ref{Int}` keyword and pass it on to `_translate_sse!`. Pass the `Ref` of `stream_turn` at the two calls (Anthropic.jl:335 and :337).
  *Test:* A new testset in test/adapter/anthropic/AnthropicLlmTest.jl (ProjecturedAnthropicTest) sends a recorded SSE body (message_start, one text block, message_delta) through `_drain_sse_events!`. It asserts no throw, the text events, and an `LlmTurnEnd` that carries the input count of message_start.
  *Done:* lane B, 28c1660a. The Anthropic suite: 35 pass, 1 broken (baseline 20 and 1 broken); the new stream test fails on the old code with the `UndefVarError`. Every run of these suites had no outside network (`unshare -rn`).
- [x] **L19-2** (part) (Medium, Correctness)
  Throw when a stream ends before its terminal event, as the `stream_turn` docstring says for a dead socket, and map `stop_sequence`, `refusal` and `pause_turn` to `:end_turn` in the Anthropic adapter. The read timeout waits for its decision.
  *Test:* A test of the stream parser: an early end throws, and each stop reason maps.
  *Done:* lane B, 28c1660a. The throw at an early end is in both adapters, Anthropic and Ollama. It sits after `HTTP.open` returns, because HTTP.jl wraps an exception of the block in `RequestError`. `model_context_window_exceeded` is not in the table and goes on as its own symbol.

### Step 1.7: One name for each letter key in every backend

The docstring half (L06-1) is in step 3.6, because `KeyboardEvent.jl` is sealed.

- [x] **L09-1** (High, Correctness) — same fault as L06-1
  Each backend names every letter key a to z as :a to :z. SDL: keysyms 97 to 122 give Symbol(Char(keysym)), and the lines for single letters and their comments go. Web: a one-letter key a-z or A-Z gives its lower case. Console: a Ctrl byte 0x01 to 0x1A gives KeyDown of its letter with ctrl, except the bytes that the console reads already (0x03 quit, 0x08, 0x09, 0x0A, 0x0D).
  *Test:* test_sdl_keysym(): keysyms 97 to 122 give :a to :z (replace the assertions 'q' and 'z' to :char), and Ctrl+Z from sdl_to_keydown matches the undo pattern; test_web_backend(): 'z' and 'Z' give :z; test_console_backend(): the byte 0x1A gives KeyDown(:z) with ctrl.
  *Done:* lane A, 8ca1bfdd. SDL, the web page and the console name :a to :z; the console reads 0x01 to 0x1A as Ctrl and a letter, after the bytes that it read before. No binding or reader in the three repositories expects a letter as `:char`. test_sdl 791, test_web_backend 40, test_console_backend 86.

### Step 1.8: The whole surface for the documentation tools

This step changes what the tools answer; see "Changes that a person or a caller sees".

- [x] **L18-1** (High, Correctness)
  Make one function that answers the modules of the whole surface (what _scratch_sources gathers), and use it in place of _projectured() in _index_api, list_modules, _find_module, _api_modules, _get_writable_names and the resources. On the whole surface, index only exported names, because _flat_reexport! binds only those.
  *Test:* test_mcp_tools() (it loads packages outside the kernel): with ToolSet(), search_api("CellVector") finds it, read_function_documentation of a PaneModule function answers, and the hint offers names outside the kernel. test_declared_api() keeps its kernel-only answers.
  *Done:* lane B, cee09d74. The index grows from 533 entries (23 modules) to 2851 (77 modules); the first build takes about 1 s before and after. `_API_INDEX` still caches the index at the first use, so a package that loads later is not in it. Without the umbrella, a name that two modules export is indexed twice but bound once. The catalogues still list names that no module exports (L18-8, L18-23). test_mcp_tools: 158 (+6).

## Phase 2 — The other fixes in files that are not sealed

One step for each layer. No step changes a sealed file.

### Step 2.1: The backends

- [x] **L09-7** (part) (Medium, Architecture)
  Remove the duplicate `using` lines, and reduce the import lists of ProjecturedSdl and ProjecturedVideo to the names that each package extends. The private renderer names wait for their decision.
  *Test:* `test_sdl()` and `test_video()` pass; the load of both packages gives no warning.
  *Done:* lane A, aaf8f50e. `_bounds_elem!` and `_bounds_extend!` of GraphicsModule come in by `using` now; the offscreen renderer names stay as they were (the decision of L09-7). A load with `--warn-overwrite=yes` prints no warning.
- [x] **L09-9** (Low, Correctness)
  A MouseMove takes its held buttons from evt.motion.state. For the modifiers, the SdlBackend keeps the modifier state of the last key event in the order of the queue (keysym.mod), seeded from SDL_GetModState, and a mouse or text event reads that state in place of _current_modifiers().
  *Test:* test_input_coalescing(): a queue with a motion that holds the left button and then a release gives a MouseMove that holds the left button; a Ctrl key up after a click in the same queue leaves ctrl on the MouseDown.
  *Done:* lane A, aaf8f50e. `SdlBackend.modifiers` holds the modifiers of the last key event in queue order; a MouseMove reads `evt.motion.state`. MouseScroll still reads its position at the poll. test_sdl 801.

### Step 2.2: The document layer

- [x] **L10-4** (Medium, Correctness)
  In both copy forms, take the programmer's parameters from `typeof(document)` (the leading parameters, before the one cell parameter for each field) and call `base{params...}(args...)`. Ask `_declared_value_types` with those parameters.
  *Test:* test_document_macro(): copy_document(DmParametric(3)) isa DmParametric{Int}; copy_document(ReactiveCell, DmBounded(2.0)) throws no TypeError.
  *Done:* lane A, 75dd3879. A hand-written document still copies through its bare constructor, because no rule says which of its parameters are the programmer's. omnet-julia: `reactive_simulator` and `reactive_parallel_simulator` build by hand what a kinded copy now gives.
- [x] **L10-5** (Medium, Correctness)
  Build the copy of a vector with `similar(v)` and set each element, as the bounded path does. In the kind form a native element type can not hold a converted element, so keep `eltype(v)` only when every copy is an instance of it, as `_kinded_value_type` does for a field.
  *Test:* test_document_contract(): the copy of a vector with an abstract element type that holds one subtype keeps the element type, and a push! of another subtype works.
  *Done:* lane A, 75dd3879. The rule "keep `eltype(v)` only when every copied element fits" covers the policy form too, because a policy can put a placeholder of another type. The methods for `Vector{Cell}` and `Vector{Any}` are gone. **Check in omnet-julia at the merge:** a plain policy copy of a `Sweep` gives `Vector{Any}` now, not the narrowed type.
- [x] **L10-8** (part) (Medium, Correctness)
  Move the `CellVector` kind copy to the four-argument form, and document that form as the method that a kind adds. The signature waits for its decision.
  *Test:* `test_document_contract()`: a nested collection copies with its own kind method.
  *Done:* lane A, 75dd3879. A bounded copy of a CellVector goes through its own four-argument method and keeps the bound; a kinded copy of a nested CellVector starts with `selection = nothing`.
- [x] **L10-10** (part) (Medium, Shape)
  Remove the `try` around `fieldnames(typeof(obj))` in the walk: it does not throw. The catch around the predicate waits for L01-8.
  *Test:* `test_document_walk()` passes.
  *Done:* lane A, eb3984ec.
- [x] **L10-16** (Low, Correctness)
  In `_copy_elements`, ask `is_descendable_for_sync` for each element document, at the depth that `_sync_elements!` uses. Clamp the push loop of `_sync_elements!` to `min(limit, ns)`. Pass the partial result, not `()`, as the shadow to `sync_element_limit`. Add `@boundscheck` to `HiddenElements`.
  *Test:* test_bounded_sync(): with a policy that stops at depth 1, a shadow born by copy and a shadow grown by sync hold the same markers; a limit above length(source) throws no BoundsError.
  *Done:* lane A, 75dd3879. The report was wrong in one point: the push loop of the sync did not ask the bound either. It asks now through `_synced_child(nothing, …)`, and the limit is clamped where `sync_element_limit` is called.
- [x] **L10-17** (Low, Correctness)
  Take the kind of a rebuilt child from the cell of its slot, not from the first field of the shadow.
  *Test:* test_document_contract(): a shadow whose first field is an ImmutableCell and whose next field holds a child document syncs twice with no MethodError, and a rebuilt child is reactive.
  *Done:* lane A, 14d650d1.
- [x] **L10-18** (Low, Correctness)
  In `_sync_fields!`, read and write the `selection` field through its cell (`getfield`, unwrapped for a native source), not through `getproperty`, so a dormant SelectionDocument syncs as a document.
  *Test:* test_document_contract(): a dormant selection survives a sync, and a second sync with no change writes no selection cell.
  *Done:* lane A, 14d650d1. The write stays `setproperty!`, which writes the cell of the field.
- [x] **L10-19** (Low, Correctness)
  Remove the `fn == :ref` skip. The `AbstractArray` branch now walks an Array, so the skip of the `ref` field of Array has no use. Remove the same skip in the mirror of the walk in ConstructTest.jl:110, and correct its comments at lines 27 and 63.
  *Test:* test_document_walk(): search_documents finds a match under a field named `ref`.
  *Done:* lane A, eb3984ec.
- [x] **L10-21** (part) (Low, Shape)
  Declare `SelectionDocument` with `[C]`, remove the dead `base === nothing` check, and split `_document_expr` into private helpers under the size budget. Re-record the precompile traces of omnet-julia that name `MSelectionDocument`. The split of the file and `_declared_value_types` wait for their decisions.
  *Test:* `test_document_macro()` gives its baseline count.
  *Done:* lane A, 75dd3879 (the dead check) and adfe0143 (the helpers); seven declarations expand the same with the old and the new macro, apart from the new `getproperty`. **At the merge:** re-record the omnet-julia traces that name `MSelectionDocument`: `asset/precompile/WorkloadStatements.jl:1616` and `asset/precompile/PrecompileStatements.jl:8240`.
- [x] **L10-22** (Low, Types/performance)
  In the generated `getproperty`, call `unwrap_selection` only when `name === :selection`, which constant-folds for a literal field name. Correct the docstring claim that the call inlines away.
  *Test:* test_document_macro() and test_document_contract() unchanged; a dispatch count of a field read shows one dynamic call less.
  *Done:* lane A, adfe0143. The name test does not constant-fold: `getproperty(::T, ::Symbol)` is not inlined, so the name is compared at run time. The gain is one run-time dispatch less for each read of another field. test_kernel 2462, test_substrate 86852 and the 7 known failures.

### Step 2.3: The reference layer

- [x] **L11-4** (Medium, Correctness)
  Bind the escaped input once in an outer `let` with a gensym, and let each arm read that name.
  *Test:* test_reference_evaluation(): an input expression with a counter runs once for a `@reference_case` with five arms.
  *Done:* lane A, ad840308. The input goes into one outer `let`; hygiene gives its name a gensym.
- [x] **L11-20** (part) (Low, Correctness)
  Pass `raw = true` in `_find_referenced_value`, and reject `::Mod.T` in `_ref_type_and_fields!` with a message that names it. Parts 3 and 4 wait for their decision.
  *Test:* `test_reference_evaluation()`: `::Mod.T` throws with the message.
  *Done:* lane A, ad840308. `raw = true` alone gave a Dict with Int keys the reference `::Dict.1`, which does not evaluate; one more line keeps a path only when it evaluates back to the value, as the docstring promises ("no reference is better than a wrong one"). A capital letter after the type name marks a qualified type.
- [x] **L11-21** (Low, Shape)
  Remove the tolerance branches for a checkpoint step and the unfolded corpus row, and keep `TypeReferenceStep` as the build-time token that `fold_reference_types` folds. Remove `_has_field`, `_node_type` and `_concat`. Drop the exports `REFERENCE_RULE_MODES` and `ReferenceSyntaxStep`. Let `parse_reference_step` call the path parser.
  *Test:* test_reference_evaluation(), test_reference_builder(), test_reference_rules() pass with the unfolded row removed; test_exports().
  *Done:* lane A, 9d13e933. No stored path in the three repositories holds an unfolded type step. The step-drop of `strip_reference_types` went too, because it is the same tolerance. 32 checks of the kernel suite went with the corpus row. No caller of `get_reference_step_kind` is left, but the sealed ReferenceInterface.jl still declares it (for a later decision). reference.md:318-322 and :371 describe the removed steps (Phase 6).
- [x] **L11-23** (Low, Types/performance)
  Use a module-level sentinel constant in place of `_nomatch`. Build the pattern of an interpreted arm once at expansion. Add a memo to `_glob_match`. In `_find_referenced_value`, pass `raw = true` and drop the second annotation.
  *Test:* test_reference_rules() and test_referenced_document() unchanged; a glob with many `*` on a long name returns fast; an allocation count of one `@reference_case` call drops.
  *Done:* lane A, ad840308. Only a pattern that reads nothing at the call site is built once at expansion. A glob with 10 `*` on 36 characters took 5.8 s and takes 60 µs.

### Step 2.4: The operation and intent layers

- [x] **L13-2** (Medium, Correctness)
  In Rerooting.jl add operation_reference(op::ReplaceSelectionOperation) = op.path and a retarget_operation that makes a new ReplaceSelectionOperation. Add operation_reference for ReplaceReferencedValueOperation that answers op.reference when op.document === nothing and nothing otherwise, and a retarget_operation that keeps a carried root unchanged.
  *Test:* test_rerooting(): operation_reference answers the path of both types, and nothing for a carried root; retarget_operation replaces the path. Then test_copying_projection() and the assistant tests.
  *Done:* lane B, ba2d2a82. A carried root answers `nothing`.
- [x] **L13-4** (Medium, Correctness) — same fault as L17-18
  In Rerooting.jl answer operation_travels_unchanged = true for DoNothingOperation, QuitEditorOperation, AdjustZoomOperation, AdjustFontZoomOperation, ToggleCollapseOperation and SelectNextInsertionOperation. Delete the two type branches at ProjectionDefaults.jl:171-179 and correct the comment at :188-190.
  *Test:* test_rerooting(): each of the six types travels, and the default read_intent of a test projection answers DoNothingOperation unchanged. Then test_substrate() for the chains.
  *Done:* lane B, ba2d2a82, with L17-18. No test changed its result because of the new travel.
- [x] **L13-7** (part) (Medium, Architecture)
  Pass each spliced item as it is, and let the collection wrap it in its cell. The case of a plain `Vector` field waits for its decision.
  *Test:* `test_inversion()` with a test-local document collection.
  *Done:* lane B, b0f0c2eb. InversionTest.jl uses a test-local collection that keeps each element in a `MutableCell`.
- [x] **L13-12** (part) (Low, Correctness)
  In `_write_slot!`, refuse a field step on an `AbstractDict` and an overwrite wider than one item with a clear error, and add `CompoundOperation(operation::Operation)`. Item 1 waits for its decision.
  *Test:* `test_inversion()`: the two refusals throw, and the one-argument constructor works.
  *Done:* lane B, b0f0c2eb.
- [x] **L13-13** (part) (Low, Shape)
  Move the catch-all `invalidate_projection!` to OperationDefaults.jl, delete `describe_operation(::ReplaceViewStateOperation)` because the `WrappingOperation` method covers it, and build the field reference with `Reference(FieldReferenceStep(field))`. The move of `reroot_reference` waits for its decision.
  *Test:* `test_rerooting()` and `test_inversion()` pass.
  *Done:* lane B, 451a985b.
- [x] **L13-14** (Low, Shape)
  Sort the using lines by module name. Delete the trailing comments of the includes. Make count of delete_elements a keyword (count = 1) and change the one positional call at source/platform/text/TextDocument.jl:1310. Wrap the lines over 90 characters. Shorten the five fragment headers to one line.
  *Test:* test_arguments(), test_rerooting(), test_inversion(), and the text document tests for the call.
  *Done:* lane B, 451a985b. Six fragment headers were long, not five: `Description.jl` had one too. The `OperationInterface.jl` header no longer says where the bodies are; its three banners name the files (for L13-16). The one positional call of `delete_elements` at `TextDocument.jl:1310` names `count`. omnet-julia and inet-julia have no call of either builder.
- [x] **L14-1** (Medium, Architecture)
  Add make_inverse_operation(document, ::CollectedIntentsOperation) = DoNothingOperation() in Intent.jl, and import make_inverse_operation beside reroot_operation in IntentModule.jl.
  *Test:* test_intent() (L14-3): the inverse of a CollectedIntentsOperation is DoNothingOperation().
  *Done:* lane B, 70903277. Its test is in the `CollectedIntentsOperation` testset of RerootingTest.jl until L14-3 makes `test_intent()`.
- [x] **L14-4** (Low, Architecture) — same fault as L17-3
  In the default bridge return Intent(change.gesture, op, change.description, change.domain), so the labels stay.
  *Test:* A testset: a projection with no 4-argument reader keeps the description and the domain of the Intent that it reads.
  *Done:* lane B, 70903277. L17-3 builds on this change of the same bridge.
- [x] **L14-5** (Low, Shape)
  Delete with_intent_labels and its export (the smaller option). No code, test, example or plan in the three repositories calls it.
  *Test:* test_exports() and test_kernel_layering(); the kernel loads.
  *Done:* lane B, 70903277.
- [x] **L14-7** (Low, Shape)
  Sort the using lines by module name (OperationModule before ReferenceModule). Wrap Intent.jl:1 (126 characters) and :78 (95).
  *Test:* test_kernel_layering(); no behaviour changes.
  *Done:* lane B, 70903277. The `Intent.jl` header is one line of 89 characters. test_kernel 2476 in lane B; test_substrate 86839; test_json 194; test_xml 73; the others at their counts.
- [x] **L17-18** (Low, Shape)
  Add operation_travels_unchanged(::ToggleCollapseOperation) = true and operation_travels_unchanged(::SelectNextInsertionOperation) = true in the operation layer, and delete the two branches of the default read_intent.
  *Test:* test_rerooting(): operation_travels_unchanged is true for both; the default read_intent of a fixture projection forwards both unchanged.
  *Done:* lane B, ba2d2a82, with L13-4.

### Step 2.5: The binding layer

- [x] **L15-1** (Medium, Correctness)
  In get_document_gesture_bindings ask for S first, then for S.name.wrapper when the two differ. This keeps the promise of @gestures, a table for any document type; the other option (an error in @gestures) breaks that promise.
  *Test:* test_gesture_binding(): a test-local [DC] document with @gestures on its bare name fires its key.
  *Done:* lane A, 358e1e7f.
- [x] **L15-2** (Medium, Architecture) — same fault as L17-10
  Declare function get_document_gesture_bindings_own end and function get_instance_gesture_bindings end, with their docstrings, in GestureBindingInterface.jl. Keep the two default methods in GestureBinding.jl.
  *Test:* test_kernel_layering() (the interface guard) and test_gesture_binding().
  *Done:* lane A, 358e1e7f.
- [x] **L15-3** (Medium, Types/performance)
  Let @gestures build its table once in a hidden const at the call site, as @gesture_set does, and let the emitted method return it. Bind the pattern expression once, not twice. Delete the false comment at Gestures.jl:181-182 and correct the docstring of get_document_gesture_bindings: the walk stays uncached, and each table is a constant.
  *Test:* test_gesture_binding(): two calls of get_document_gesture_bindings_own(T) answer the same vector, and the suite passes.
  *Done:* lane A, 358e1e7f. **Changes what a caller sees:** `@gestures` builds its table at load time, so a name that a pattern or a `splice` reads must be defined above the block. No call site in the three repositories breaks, and the docstring says it.
- [x] **L15-7** (Low, Correctness)
  Raise an error in _parse_gesture_block on a second bare when(expr) in one block. This keeps the documented 'optional, block-level' precondition; the other option (only as the first entry) adds a limit that no text states.
  *Test:* test_gesture_binding(): macroexpand of a block with two when(expr) throws.
  *Done:* lane A, 358e1e7f.
- [x] **L15-8** (Low, Correctness)
  Add using ..SelectionModule to GestureBindingModule.jl, and read the selection with get_selection(target) at GestureBinding.jl:218 and :243. Keep the explicit selection argument for a target that is not a document. Do the same in projection/GestureBindings.jl and drop its hasproperty and hasfield guards.
  *Test:* test_gesture_binding(): an [M] document with a table fires its key.
  *Done:* lane A, 358e1e7f. In projection/GestureBindings.jl only the selection read changed.
- [x] **L15-9** (part) (Low, Shape)
  Stop the export of `collect_binding_intents`, which has no caller outside its file. The three names that only tests use wait for their decision.
  *Test:* `test_gesture_binding()` passes.
  *Done:* lane A, 358e1e7f.
- [x] **L15-11** (Low, Shape)
  Move the parse of one rule out of _parse_gesture_block (87 lines, budget 60) into a helper. Fold the two equal branches of _type_name into one test.
  *Test:* test_gesture_binding().
  *Done:* lane A, 358e1e7f. test_kernel 2449, test_substrate 86852 and the 7 known failures, test_julia 407, test_json 194, test_undo 110.

### Step 2.6: The iomap layer

- [x] **L16-7** (Low, Types/performance)
  Write inner_iomap::Any and keep its meaning in the docstring. In reconcile_child_iomaps fill a new Dict in the loop and let it replace the old one (hold it in a Ref, so the closure boxes no reassigned local); drop the Set and the copy of the keys.
  *Test:* test_iomap_reconcile() (L16-3) and test_copying_projection().
  *Done:* lane A, 24b8185a. Its test is L16-3 (Phase 4).

### Step 2.7: The projection layer

- [x] **L17-3** (Medium, Correctness) — same fault as L14-4
  In the bridge and in read_template_intent, build the answer with the 4-argument Intent constructor, so description and domain stay. When change.route is a non-empty reference, answer Intent(change.gesture, nothing), because these readers do not follow a route.
  *Test:* New kernel test with a fixture projection: the bridge keeps description and domain; a change with a route of one step answers operation === nothing. Then test_referenced_document_editor() for insert_elements! into a nested element.
  *Done:* lane B, 50200364. A route that is a `ConcreteReference` gives `Intent(gesture, nothing)`; the template reader keeps the description and the domain.
- [x] **L17-4** (Medium, Correctness)
  Add Base.hash(s::ProjectionReferenceStep, h::UInt) = hash(s.output_path, hash(objectid(s.projection), hash(:ProjectionReferenceStep, h))), as the report gives.
  *Test:* New kernel test: two make_introduced_reference results with the same projection and path are ==, have the same hash, and a Set of the two has length 1.
  *Done:* lane B, 490aac09.
- [x] **L17-5** (Medium, Architecture)
  In _mixed_print and in _sections_print, make the child IoMaps of the spliced collection and of each section with reconcile_child_iomaps, as _node_print does, in place of one computation that prints every child.
  *Test:* Substrate test with a mixed node and a sections node: insert one element; assert that the IoMaps of the other elements are === the IoMaps before the insert.
  *Done:* lane B, 582cc6c1, through one private helper `_reconcile_element_iomaps`. omnet-julia's IniToSyntax.jl (a mixed node) and NedToSyntax.jl (sections) get this change; they are not run yet.
- [x] **L17-6** (Medium, Architecture)
  Carry value_field in KeySlot and InlineWiring, and write FieldReferenceStep(String(value_field)) in _key_leaf_sel, the slot mappers, the mixed mappers and the inline mappers. Share doc.selection as it is only when the output field has the name of the input field (value_field === bound_field).
  *Test:* Substrate test: a template leaf with bound(:x, ...) in a field that is not value; assert that a caret .x{1} maps to that field of the leaf and back.
  *Done:* lane B, a42da081. The leaf shares `doc.selection` only when `value_field === bound_field`.
- [x] **L17-7** (Medium, Architecture)
  In the gesture descent, call read_intent(child.projection, recursion, Intent(evt), child) and read its operation. Pass recursion from read_template_intent into a private gesture helper with 4 arguments. Keep the RecursiveProjection disambiguations of ReaderDefaults.jl, or remove the ones that only the 3-argument path needs.
  *Test:* Substrate test: a template node whose child projection has only a 4-argument reader; a key at the child reaches that reader. Then test_example(json_example).
  *Done:* lane B, 50200364. The descent `_read_template_gesture(iomap, evt; recursion)` takes 3 arguments, because it never reads the projection.
- [x] **L17-10** (Medium, Architecture) — same fault as L15-2
  Declare function get_projection_gesture_bindings end, with its docstring, in ProjectionInterface.jl. Keep the default method and read_projection_gesture in GestureBindings.jl, correct its header, and correct the export order in ProjectionModule.jl.
  *Test:* test_kernel_layering() and test_documentation(); test_exports() for the export order.
  *Done:* lane B, d48309e7.
- [x] **L17-11** (part) (Medium, State)
  In the two inspectors, derive the context from the one that the printer receives (`with_exact_size(make_child_context(ctx, EmptyReference()); width = nothing, height = nothing)`). The fault log and the gesture log wait for their decision.
  *Test:* The inspector suites pass; a clock read in an inspector subtree follows the editor clock.
  *Done:* lane B, d11f9b63.
- [x] **L17-13** (Low, Correctness)
  In the default map_reference_backward, answer make_introduced_reference(projection, iomap.input, reference) in place of the literal @reference(iomap.input, proj(projection, ^(reference))).
  *Test:* New kernel test: the default backward map of a path is == make_introduced_reference(p, input, path), and its terminal type is Position. Then test_example(json_example), because the strict == separates the two forms in a stored caret.
  *Done:* lane B, 39f2dece. Three hand-built literals of the old form stay outside the kernel: MarkdownToSyntax.jl:329, RstToSyntax.jl:912, DatabaseInstanceToDbCatalog.jl:110.
- [x] **L17-19** (part) (Low, Shape)
  After the engine fixes of this layer, wrap the lines of ProjectionTemplate.jl over 90 characters, and give the private helpers with 4 to 7 positional arguments keywords. The split of the file waits for the decision on new file names; the export block is in export-block-rule.md.
  *Test:* `test_substrate()` gives its baseline count.
  *Done:* lane B, 15a3f818. No line is over 90 characters, and no private helper takes more than 3 positional arguments. test_kernel 2488 in lane B (the 6 known failures stay there), test_substrate 86852 and the 7 known failures, the domain suites at their counts, `test_example(json_example)` 4977.
- [x] **L17-20** (Low, Types/performance)
  Dispatch the two generic mappers on the wiring type (_forward(w::NodeWiring, ...)) in place of the isa chain of 7 branches. Type the wiring fields that hold types (intype, outtype, bound_type, retype). Declare projection, input, output and wiring of RuleIoMap as ImmutableCell fields, which @cell_struct supports.
  *Test:* test_projection_template_fixed_children() and test_example(json_example).
  *Done:* lane B, 935aea03. `value_checkpoint` and the `in_type` and `checkpoint` of `KeySlot` are typed too. The four constant fields of `RuleIoMap` are `ImmutableCell{Any}`, so a printer walk counts fewer cells.
- [x] **L17-21** (part) (Low, Correctness)
  Make `withhold_offer` throw an `ArgumentError` for an axis that is not `:x` or `:y`. The names wait for their decision.
  *Test:* A new case: `withhold_offer` with `:z` throws.
  *Done:* lane B, 30f5eb54.

### Step 2.8: The tool layer

- [x] **L18-6** (Medium, Correctness)
  Make search_guides and search_api answer a message for a limit below 1 before the rank, read a real limit with round(Int, limit) in _get_hit_count, and compute the footer only when shown is not empty.
  *Test:* test_search_answer(): limit = 0, -1 and 2.5 answer text and do not throw, for search_guides and for search_api.
  *Done:* lane B, 4656fa027. A limit of `NaN` or `Inf` from the REPL still throws in `round`; a tool call can not give either.
- [x] **L18-7** (Medium, Correctness)
  Keep the state of a code fence in _index_guide_sections, as _split_doc_paragraphs does, so that a line that starts with # inside a fence stays body text.
  *Test:* test_search_answer(): no section of the guide index has a heading that starts with '@broken:' or 'Fragment of', and the section of testing-guide.md that holds that fence keeps the line.
  *Done:* lane B, b5dfd9fdc.
- [x] **L18-8** (Medium, Correctness)
  In list_modules, filter the types of each module as _api_types does (the declared names, no schema variant), and list each module once.
  *Test:* test_declared_api(): under a pair declaration, resource://modules names only the declared types, no schema variant, and each module once.
  *Done:* lane B, e61504cd5. `list_types` still lists the schema variants of a whole module; the item named `list_modules` only.
- [x] **L18-13** (part) (Medium, State)
  Take `_INDEX_LOCK` in `register_guide_root!` for the write. Where the roots belong waits for its decision.
  *Test:* `test_declared_api()` passes; a new case registers a root and reads a guide of it.
  *Done:* lane B, b5dfd9fdc. The test passes on the old code too, because the race needs two threads.
- [x] **L18-16** (Low, Correctness)
  End the whole-module branch of _declared_sentence with " are " also when chosen == 0.
  *Test:* test_declared_api(): the description of a whole-module declaration holds 'The functions of ToyApi are in scope'.
  *Done:* lane B, 94a42d90e.
- [x] **L18-18** (Low, Correctness)
  Read the argument with get(args, "code", nothing), so that execute_julia_code answers 'No code was given'.
  *Test:* test_declared_api(): call_tool of execute_julia_code with no code argument answers 'No code was given' and does not throw.
  *Done:* lane B, 94a42d90e.
- [x] **L18-20** (Low, Correctness)
  Measure the short form with Base.invokelatest(repr, value; context = :limit => true), and call summary through Base.invokelatest in _summarize_value.
  *Test:* test_code_execution(): a call that defines a struct and a Base.show for it and returns a value answers the text of that show method.
  *Done:* lane B, f3cd7993a.
- [x] **L18-21** (Low, Correctness)
  In _all_guides, index the files that sit directly in documentation/package/ under the prefix package/, so that package/README.md is resource://guide/package/README.
  *Test:* test_search_answer(): read_guide("package/README") answers the file, and the guide list names it once.
  *Done:* lane B, b5dfd9fdc. The documentation guard derives the same name (test/suite/documentation.jl).
- [x] **L18-22** (part) (Low, Shape)
  Delete `get_api_modules`, `register_tools!` and `register_resources!` with their exports: they have no user in the three repositories. The other seven names wait for their decision.
  *Test:* `test_kernel()` and the omnet-julia load pass.
  *Done:* lane B, defbf97dc. No repository calls the three names.
- [x] **L18-23** (part) (Low, Shape)
  Keep one function for the names that a declaration gives a module (`_is_declared`, `_find_declared_names` and `_api_types` use it), and shorten `register_default_tools!`, `search_api` and `_scratch_module` under the size budget. The split of Documentation.jl waits for the decision on new file names; the export block is in export-block-rule.md.
  *Test:* `test_declared_api()` and `test_search_answer()` pass.
  *Done:* lane B, 4656fa027 to defbf97dc. `_find_declared_names` is the one function for the declared names. test_kernel 2506 in lane B; test_mcp_tools 158; test_assistant_mvp 127 and 4 known failures. The lines that L18-28 cites in DefaultTools.jl moved: :228-229 is :201, :285-288 is :269, :169 is :331.

### Step 2.9: The llm and agent layers

- [x] **L19-5** (Low, State)
  Replace the one `Ref` with a `Dict` keyed by `(models_url, api_key)` under a lock, so each key and URL gets its own answer. The report gives two ways; the keyed cache is the smaller, and it keeps the documented ask once in a process (anthropic.md), where a cache on the instance asks once per backend.
  *Test:* AnthropicTest.jl: two calls of `get_newest_anthropic_model` with different `models_url` values (one served by a local `HTTP.serve` stub, one not reachable) answer different models.
  *Done:* lane B, 9fdc1490. The cache still keeps the fallback answer of a failed request; the lock is held during the request, so each address and key is asked once.
- [x] **L20-3** (Medium, Correctness)
  Let the call on the editor task answer `(text, is_error)`: the normal arm gives `(output, _is_error_output(output))`, the catch arm gives `(text, true)`, and `AgentToolResult` takes that flag. The `AgentToolResult` docstring already says that `is_error` says whether the tool failed.
  *Test:* AgentLoopTest.jl (L20-7): a ScriptedLlm round calls a tool whose handler calls `error(...)`; assert that the `AgentToolResult` has `is_error == true`.
  *Done:* lane B, 9fdc1490. AssistantTurn.jl:218 keeps its own copy of the text check; the assistant half of the finding is not in this plan.
- [x] **L20-5** (Medium, Correctness)
  Start each round with `stop = nothing`, and after `stream_turn` returns set `stop = :error` when no `LlmTurnEnd` or `LlmFailure` came. This is the smallest form of the report's fix; the report also sends a synthetic `LlmFailure` to `on_event`, which the assistant does not read today, so it is left out.
  *Test:* AgentLoopTest.jl: a ScriptedLlm round with text and a tool call and no terminal event; assert that `run_turn!` answers `:error` and runs no tool.
  *Done:* lane B, 9fdc1490.
- [x] **L20-6** (Medium, Architecture)
  In both catch arms, add `is_passthrough_exception(e) && rethrow()` first, and guard `sprint(showerror, e, traceback)` with a try that answers a fixed text, as FaultRecord.jl:74-102 does. The shared exported helper of the report is left out: it needs a new public name and a choice of layer.
  *Test:* AgentLoopTest.jl: a tool whose handler throws `InterruptException()`; assert that `run_turn!` throws it and sends no `AgentToolResult`.
  *Done:* lane B, 9fdc1490, in AgentLoop.jl and Mcp.jl. When `showerror` throws, the text is the name of the exception type, as FaultRecord.jl does.
- [x] **L20-8** (Low, Correctness)
  Add `max_rounds >= 1 || throw(ArgumentError(...))` to the keyword constructor of `Agent`.
  *Test:* AgentLoopTest.jl: `@test_throws ArgumentError Agent(llm, ToolSet(); max_rounds = 0)`.
  *Done:* lane B, 9fdc1490.
- [x] **L20-9** (part) (Low, Shape)
  Make `Agent` a `struct` (no code writes a field), drop `::Function` from the two callbacks of `run_turn!`, and let the error of `make_agent_server` list the loaded servers from the method table, as LlmDefaults.jl does. `AgentEvent` waits for its decision.
  *Test:* `test_agent_loop()` passes (L20-7).
  *Done:* lane B, 9fdc1490.
- [x] **L20-10** (part) (Low, Shape)
  Sort the `using` lines of AgentModule.jl by module name. The export block is in export-block-rule.md.
  *Test:* The layering guard passes.
  *Done:* lane B, 9fdc1490. test_kernel in lane B: 2436 pass and the 6 failures that step 1.1 repairs in lane A; test_ollama 101; test_mcp_tools 158; test_assistant_mvp 127 pass and 4 fail, the same 4 as before the step (AssistantMvpTest.jl:383 and :384, a layout fault).

### Step 2.10: The feed and editor layers

- [x] **L21-2** (Medium, Correctness) — same fault as L22-6
  In `drain_feeds!`, run each `drain_changes!` in its own `_run_barrier(editor, :evaluate; origin = typeof(feed), fallback = 0)`, in place of the one barrier at EditorLoop.jl:179-181. Write in the `drain_changes!` docstring that a drain that throws is recorded and the next feed still drains.
  *Test:* test_editor_feeds(): two feeds under `FaultPolicy()`, and the first throws in `drain_changes!`; assert that the second drains in the same frame and that one fault record has the type of the first as its origin.
  *Done:* lane B, f708fa106, with L22-6.
- [x] **L21-3** (Medium, Correctness) — same fault as L22-7
  In `compute_wait_timeout`, compute each `compute_wake_deadline` inside `_run_barrier(editor, :evaluate; origin = typeof(feed), fallback = nothing)`, so a feed that throws counts as no deadline, and say so in the docstring. Of the two ways of the report, only the barrier keeps the editor alive, as plan/done/the-editor-survives-a-fault.md requires ('must not stop the editor'); a sentence in the contract alone does not.
  *Test:* test_editor_wait(): a feed whose deadline throws, under `FaultPolicy()`; assert that `compute_wait_timeout` answers the other bounds and that a fault record exists.
  *Done:* lane B, 5a6a9fe4a, with the part of L22-7. The deadline case is in `test_editor_wait`.
- [x] **L21-4** (Medium, Correctness) — same fault as L22-5
  As L22-5: `drain_operations!` takes at most the operations that were ready when the drain started (at most `INBOX_CAPACITY`) and sets `editor.wake_pending` when some remain. Write in the `drain_changes!` docstring that a drain moves what the store held when the drain started.
  *Test:* test_editor_inbox(): a task posts in a loop while the editor drains; assert that one drain answers at most the count that was ready, and that `wake_pending[]` is true after it.
  *Done:* lane B, eb193821c, with L22-5.
- [x] **L22-2** (Medium, Correctness)
  In `run_frame!`, when the read loop ends at the cap, at a read that threw (give the read barrier the fallback `_BARRIER_FAILED` to tell it from no input), or at a dropped IoMap, set `editor.wake_pending[] = true`, so the next turn of `run_editor!` skips the wait. EditorLoop.jl:34 already says 'whatever is left waits for the next frame'.
  *Test:* test_editor_frame_drain(): a reader that throws on a `MouseUp` under `FaultPolicy()`; after `run_frame!`, assert `editor.wake_pending[]`. The same after a frame that reaches `MAX_OPERATIONS_PER_FRAME`.
  *Done:* lane B, 041289a87.
- [x] **L22-5** (Medium, Correctness) — same fault as L21-4
  In `drain_operations!`, take at most the operations that were ready when the drain started, and set `editor.wake_pending` when some remain. In `run_editor!`, call `yield()` once in a frame whose wait was skipped: the `run_editor!` docstring (EditorLoop.jl:119-121) says that the wait is where cooperative tasks get their turn.
  *Test:* test_editor_inbox(): a task that posts in a loop does not hold one drain for ever; after the drain, `wake_pending[]` is true.
  *Done:* lane B, eb193821c. The drain takes `min(Base.n_avail(inbox), INBOX_CAPACITY)`; `yield()` runs whenever the timeout is 0 or less. An operation posted during a drain waits for the next frame, which runs at once.
- [x] **L22-6** (Medium, Correctness) — same fault as L21-2
  Move the barrier and the repairs of `evaluate!` into one private function that applies one operation, with no log line and no write of `editor.operation`. Call it from `evaluate!` and for each posted operation in `drain_operations!`. Put one barrier around each `drain_changes!` (L21-2).
  *Test:* test_editor_frame_drain(): under `FaultPolicy()`, a posted operation that fails half way is taken back by its inverse, and the next posted operation applies in the same drain; a feed that throws does not stop the next feed.
  *Done:* lane B, f708fa106. A private `_evaluate_operation_guarded!` applies one operation; each feed drain runs in its own barrier. **Changes what a caller sees:** a posted operation takes an inverse first and gets the repairs, and its fault record names its type.
- [x] **L22-7** (part) (Medium, Correctness)
  Wrap `get_frame_clock_time` in `_run_barrier(editor, :device; ...)` with the wall time as the fallback. The deadline part is L21-3; the wait and its counter wait for their decision.
  *Test:* `test_editor_fault_barriers()` (L22-17): a clock that throws gives the wall time.
  *Done:* lane B, 5a6a9fe4a. The clock barrier uses the default `:device` counter; no new counter, no time limit.
- [x] **L22-10** (Medium, Correctness)
  In the `finally` of `run_editor!`, nest the three steps in `try ... finally` so that each runs when an earlier one throws, and let the first exception go on. The docstring says that the loop quits its backend 'also when it throws'.
  *Test:* test_editor_inbox(): a call posted with `wait = false` that throws `InterruptException` is still in the inbox when the loop ends; assert that `run_editor!` throws it and that a backend stub saw `quit_backend!`.
  *Done:* lane B, 5a03af00e. When two steps throw, Julia raises the later one and keeps the first in `current_exceptions()`.
- [x] **L22-11** (Medium, Architecture)
  In `_make_operation_inverse`, the inverse block of `_repair_after_operation_fault!` and `_repair_selection!`: `catch exception`, then `is_passthrough_exception(exception) && rethrow()`, then `record_fault!(editor.faults, :evaluate; origin = <the operation type or the repair>, exception, traceback = catch_backtrace())`.
  *Test:* FaultBarriersTest.jl (L22-17): under `FaultPolicy()`, an operation whose `make_inverse_operation` throws leaves one fault record; an `InterruptException` from the inverse goes through the repair.
  *Done:* lane B, feb0b3c57. The selection repair records the origin `:_repair_selection!`. An inverse that throws now leaves a record, so the console shows it.
- [x] **L22-16** (Medium, Types/performance)
  Log `describe_operation(operation)` in place of the interpolated operation, still at `@info`, so the `evaluate!` docstring ('Logs the operation') stays true. The report's `@debug` or switch changes what the message log shows, so it is left out.
  *Test:* test_escape_quit() or a new testset: `@test_logs` sees an info line with the `describe_operation` text of a `ReplaceSelectionOperation` that `evaluate!` applies.
  *Done:* lane B, 6342ba2ee. The line reads, for example, `[operation] select .value`.
- [x] **L22-18** (Low, Correctness)
  In `read!`, when `leave_safe_mode!(editor)` answers true, clear `editor.operation`, set `editor.wake_pending`, and return `false`, so that `run_frame!` paints before it reads on. In `run_editor!(editor)`, print once in the `:print` barrier before the first frame when `editor.iomap === nothing`.
  *Test:* test_fault_safe_mode(): in the safe mode, Escape and a key in one read; assert that the key applies on the next frame. test_editor_wait(): an `Editor(...)` with a queued key applies it in its first frame.
  *Done:* lane B, 3258bf26a.
- [x] **L22-20** (Low, Correctness)
  Read `time_ns()` for `t_start` and `frame_started`, and convert the differences to seconds.
  *Test:* test_editor_wait() as a regression run; no test can step the system clock.
  *Done:* lane B, 82d56f21e.
- [x] **L22-25** (Low, Shape)
  Move `evaluate!` and `print!` into ReadEvaluatePrint.jl and keep the barrier helpers in FaultBarriers.jl; move `get_fault_store(editor)` into Editor.jl; correct the header of EditorLoop.jl to name `get_frame_clock_time` and `make_editor`. The other way, headers that list what each file holds now, makes the headers longer than the budget of L22-30.
  *Test:* test_kernel() as a regression run; the fragments share one namespace, so no caller changes.
  *Done:* lane B, 5e0941da9, with the last "thunk" of L01-15 in `print!`.
- [x] **L22-26** (part) (Low, Shape)
  Sort the 18 `using` lines of EditorModule.jl by module name, put a comment above `import ..FeedModule: drain_changes!` that says the module extends it, and list the fragments in the module docstring. The server options wait for their decision; the export block is in export-block-rule.md.
  *Test:* The layering guard passes.
  *Done:* lane B, 99209b910.

## Phase 3 — The fixes in sealed files

Each step changes sealed files. **Before each step, ask the owner for permission for each sealed file that it names** (SEALING.md). The owner can give the permission for the whole phase at once. A step whose files have no permission waits, and the other steps go on.

### Step 3.1: The fault layer

Sealed files: `FaultBarrier.jl`, `FaultCascade.jl`, `FaultInterface.jl`, `FaultModule.jl`, `FaultRecord.jl`, `FaultStore.jl`.

- [x] **L01-1** (part) (High, Correctness) — 🔒 `FaultStore.jl`
  Reject `capacity < 1` in the constructor of `FaultStore` with an `ArgumentError`, as `FrameMeasurementStore` does. The report of the dropped faults waits for its decision.
  *Test:* `test_fault_store()`: `FaultStore(capacity = 0)` throws.
  *Done:* lane A, f0ba5e65.
- [x] **L01-3** (Medium, Correctness) — 🔒 `FaultStore.jl`
  In `record_fault!`, push the key onto `undrained` only when `undrained` does not hold it; the record already has the latest count. Chosen over `unique!` in the drain: the same result, and `undrained` stays small. Change the test to expect one hand-over.
  *Test:* test_fault_store: 3000 faults of one key before one drain give one record with count 3000, and the target gets it one time.
  *Done:* lane A, f0ba5e65. A probe on the old code handed one record over 4 times.
- [x] **L01-7** (Low, Correctness) — 🔒 `FaultCascade.jl`
  Call `_enter_fault_report!` and `_leave_fault_report!` each in its own `try`; when one fails, use depth 1 and go on to the console tier. Change the test to expect `:console` for `AngryStore()` with `FaultPolicy()`.
  *Test:* test_fault_report: report_fault!(AngryStore(), record; policy = FaultPolicy(), backend = AngryBackend()) answers :console, and store.depth stays 0.
  *Done:* lane A, f0ba5e65. A store that fails to enter gives depth 1, and the leave is then skipped; the leave has its own try.
- [x] **L01-9** (Low, Correctness) — 🔒 `FaultRecord.jl`
  Give a `Type` that is not a `DataType` or a `UnionAll` a name from `string`: `_get_fault_origin_name(origin::Type) = origin isa DataType || origin isa UnionAll ? nameof(origin) : Symbol(string(origin))`.
  *Test:* test_fault_record: make_fault_record with origin = Union{Int, String} and with origin = Union{} gives a record and does not throw.
  *Done:* lane A, f0ba5e65.
- [x] **L01-10** (Low, Correctness) — 🔒 `FaultStore.jl`
  Give `drain_faults!` a keyword `policy = FaultPolicy()`, skip the refusal line when `policy.is_console_enabled` is false, and pass `editor.fault_policy` from `report_frame_faults!`. Chosen over an answer that carries the failures: smaller, and the same result.
  *Test:* test_fault_store: a target that throws, drained with the quiet policy, writes no log line (@test_logs); with FaultPolicy() it writes one.
  *Done:* lane A, f0ba5e65. `drain_faults!(store; policy = FaultPolicy())`; FaultBarriers.jl passes `editor.fault_policy`. It also changes `_log_fault_report_failure` in the sealed FaultCascade.jl.
- [x] **L01-13** (Low, Shape) — 🔒 `FaultCascade.jl`; after L01-6
  Remove `report_fault!(store, ::Nothing; …)` and its test line: it has no caller outside that test in the three repositories. Keep the depth, because the docstring of `report_fault!` promises it, and let the nested-call set of L01-6 cover it.
  *Test:* test_fault_report passes without the nothing line; the nested-call set of L01-6 reaches the depth > 1 arm.
  *Done:* lane A, f0ba5e65, after L01-6.
- [x] **L01-15** (Low, Documentation) — 🔒 `FaultStore.jl`, `FaultInterface.jl`
  Replace 'thunk' with 'computation' in the docstrings and comments of the fault layer and of the editor files, and in the index row of PAR-NO-WRITE-IN-THUNK. Keep the rule IDs.
  *Test:* A grep for 'thunk' in source/kernel/fault and source/kernel/editor finds only rule IDs; test_documentation().
  *Done:* lane A, f0ba5e65, except one line: FaultBarriers.jl:176, inside `print!`, still says "thunk", because lane B moves `print!` out of that file (L22-25). **Change it after the merge.** The index row of PAR-NO-WRITE-IN-THUNK is in Phase 6.
- [x] **L01-16** (Low, Documentation) — 🔒 `FaultStore.jl`, `FaultBarrier.jl`, `FaultCascade.jl`, `FaultModule.jl`
  State each contract for any caller (for example 'Call it once per frame, outside every computation'), remove the text about callers in higher layers, and remove the seven include comments of FaultModule.jl.
  *Test:* test_documentation().
  *Done:* lane A, f0ba5e65. test_kernel 2470, test_fault 73.

### Step 3.2: The performance layer

Sealed files: `FrameMeasurement.jl`, `PerformanceCounter.jl`.

- [x] **L02-2** (Medium, Correctness) — 🔒 `FrameMeasurement.jl`
  In `record_frame_measurements!`, throw the 'in both groups' error before any change of the store when a name of `times` is also a name of `counts`.
  *Test:* test_frame_measurements: a call with :x in both groups throws ArgumentError, and frame_count, end_times and the columns stay as before.
  *Done:* lane A, f00f3135. The old "in both groups" throw in `_record_frame_values!` went too, because no call reaches it.
- [x] **L02-7** (Low, Documentation) — 🔒 `PerformanceCounter.jl`, `FrameMeasurement.jl`
  Add a 'Use it to' paragraph and an example to the names that a person or a model calls to profile, and cut the header of PerformanceCounter.jl to one line and the switch.
  *Test:* test_documentation().
  *Done:* lane A, f00f3135, for the seven names that a person calls to profile; `record_frame_measurements!` and `FrameMeasurementSummary` are not called to profile.

### Step 3.3: The cell layer

Sealed files: `CellComputation.jl`, `CellDefaults.jl`, `CellInterface.jl`, `ImmutableCell.jl`, `MutableCell.jl`, `ReactiveCell.jl`.

- [x] **L03-4** (Medium, Correctness) — 🔒 `ReactiveCell.jl`
  Convert first: write the method as `setindex!(c::ReactiveCell{T}, value) where {T}`, and do `v = convert(T, value)` before any change of the cell; then store `v`.
  *Test:* test_cell: tc = ReactiveCell{Int}(@computation t[] + 1); tc[] = 2.5 throws InexactError; tc still follows t after a write to t.
  *Done:* lane A, b92e4165d.
- [x] **L03-5** (Medium, Correctness) — 🔒 `CellDefaults.jl`
  Add `Base.setindex!(c::MutableCell, ::Computation) = _reject_computation("MutableCell")` to CellDefaults.jl.
  *Test:* test_cell: a write of @computation into MutableCell{Any}(0) throws ArgumentError, and the cell keeps 0; the same through a mutable field of a @cell_struct.
  *Done:* lane A, b92e4165d.
- [x] **L03-6** (Medium, Correctness) — 🔒 `ReactiveCell.jl`
  In `ReactiveCell{T}(::Computation)`, write `nothing` into `value` when `nothing isa T`, as `set_cell_computation!` does, and correct the comment above it. The case of another `T` goes with L03-8.
  *Test:* test_cell: getfield(Cell(@computation 1), :value) === nothing before the first read; test_serialization: a save of a document with an unread computed field works.
  *Done:* lane A, b92e4165d. A cell whose `T` does not admit `nothing` still has an undefined value; that waits for L03-8.
- [x] **L03-7** (Low, Correctness) — 🔒 `ReactiveCell.jl`
  Move `@count_performance :computes` above `push!(stack, c)` in `_recompute!`, so that a computation that throws also counts. Chosen over the `finally` block: the same count, and the cleanup stays clean.
  *Test:* Only in a build with the counters: a computation that throws adds one to :computes. No default test can see it (L02-1, L02-3).
  *Done:* lane A, b92e4165d. No default test: a probe with the counters on gave `:computes` 0 on the old code and 1 on the new.
- [x] **L03-11** (Low, Documentation) — 🔒 `ReactiveCell.jl`, `CellComputation.jl`, `CellInterface.jl`, `ImmutableCell.jl`, `MutableCell.jl`
  State each goal in the terms of the layer (a field, a struct, a value that a computation reads), and remove the names of documents, projections, renderers and `CellVector`.
  *Test:* test_documentation().
  *Done:* lane A, 06abbae0e.
- [x] **L03-12** (Low, Documentation) — 🔒 `CellComputation.jl`, `ReactiveCell.jl`
  Correct cell.md:93 and the same sentence of PAR-ACYCLIC-CELLS (a direct self-read also recurses), apply the writing rules to cell.md, renumber the fan-in table of architecture.md, write 'was written' in the docstring of @computation, and let `show` print `ReactiveCell{T}` for a typed cell.
  *Test:* test_cell: repr(ReactiveCell{Int}(2)) starts with the type name, and repr(Cell(2)) with 'Cell('; test_documentation().
  *Done:* lane A, 06abbae0e. cell.md follows the writing rules now, and its anchors still work. The fan-in table of architecture.md also had stale counts for EventModule and ReferenceModule. cell.md does not say what the engine does with a computation that throws, or the rules for threads: that waits for L03-1 and L03-2.

### Step 3.4: The struct layer

Sealed files: `CellStruct.jl`, `CellStructPlan.jl`.

- [x] **L04-1** (Low, Correctness) — 🔒 `CellStructPlan.jl`
  In `make_cell_struct_plan`, skip only a `LineNumberNode` and a `String`, and throw an `ArgumentError` that names any other expression of the body, as `_reject_inner_constructor` does.
  *Test:* test_cell_struct_plan: a body with `const a::Int` throws ArgumentError, and a field docstring still parses; then test_document_macro() and test_kernel().
  *Done:* lane A, 1006a6759. No body of `@document`, `@cell_struct`, `@iomap` or `@projection` in the three repositories is rejected.
- [x] **L04-9** (Low, Documentation) — 🔒 `CellStructPlan.jl`, `CellStruct.jl`; after L04-7, L04-8
  Add a 'Use it to' paragraph and an example, with the goal of a macro writer, to the fifteen names that have neither.
  *Test:* test_documentation().
  *Done:* 7fc5cbfd5. 14 names, not 15, because L04-7 made one private; each example gives the value that its comment states.

### Step 3.5: The clock layer

Sealed files: `Clock.jl`.

- [x] **L05-1** (part) (Medium, Documentation) — 🔒 `Clock.jl`
  Add one sentence to the docstring of `start_wall_clock!`: a computation that reads the clock must not yield. The engine change waits for L03-2.
  *Test:* Documentation only.
  *Done:* lane A, 40496d8b8.
- [x] **L05-2** (Low, Correctness) — 🔒 `Clock.jl`
  Take `start` and each tick from `time_ns()`, converted to seconds, in place of `Base.time()`.
  *Test:* test_clock: the sets for start, stop, restart and continue still pass.
  *Done:* lane A, 40496d8b8.

### Step 3.6: The event layer

L09-2 changes `Sdl.jl` and `client.js` too; do its code part in the same commit.

Sealed files: `EventInterface.jl`, `EventPattern.jl`, `KeyboardEvent.jl`, `ModifierKeys.jl`, `MouseEvent.jl`, `WindowEvent.jl`.

- [x] **L06-1** (Medium, Shape) — 🔒 `KeyboardEvent.jl`; same fault as L09-1
  Restore the documented vocabulary. The KeyDown docstring states that each letter key has the name of its lower-case letter, :a to :z, and every backend follows it (L09-1). No new table, function or type goes into the event layer.
  *Test:* No test for the docstring. The backend tests of L09-1 assert :a to :z on SDL, the web and the console.
  *Done:* lane A, 793648547.
- [x] **L06-2** (Medium, Documentation) — 🔒 `MouseEvent.jl`
  The MouseScroll docstring states that a positive dy is a turn of the wheel away from the user, which scrolls up, and that a positive dx is a scroll to the right, as SDL and the web page send them.
  *Test:* No test for the docstring. L09-18 adds a test that SDL and the web give dy > 0 for a turn away from the user.
  *Done:* lane A, 793648547.
- [x] **L06-3** (Low, Correctness) — 🔒 `EventPattern.jl`
  _build_modifier_test reads the modifiers through get_modifier_keys, with the function put into the expression as a value, so that the expansion resolves in any module.
  *Test:* test_event_case(): the rule WindowResize(; ctrl) on a WindowResize event gives no error and no match.
  *Done:* lane A, 793648547.
- [x] **L06-4** (Low, Correctness) — 🔒 `EventPattern.jl`
  build_event_field_bindings returns body at once when rule.type === nothing, as its docstring promises.
  *Test:* test_event_module(): through a small test macro, the rule _ => 1 gives the body back and no MethodError.
  *Done:* lane A, 793648547.
- [x] **L06-5** (Low, Correctness) — 🔒 `EventPattern.jl`
  The first option of the report: an inner constructor of EventPattern checks that each modifier flag is :ctrl, :shift, :alt or :meta, and throws an ArgumentError that names the flag, as the macro path does. The field type stays Vector{Symbol}, as the docstring states.
  *Test:* test_event_module(): KeyDownPattern(:s; modifiers = [:control]) throws an ArgumentError.
  *Done:* lane A, 793648547.
- [x] **L06-6** (Low, Correctness) — 🔒 `EventPattern.jl`
  _describe of MouseDown and MouseUp gives 'Left button down' and 'Left button up' (and 'button down', 'button up' with no button), after the prefix of the modifiers.
  *Test:* test_event_module(): describe_event_pattern(MouseDownPattern(:left)) is 'Left button down', and MouseUpPattern(:right; modifiers = [:ctrl]) gives 'Ctrl+Right button up'.
  *Done:* lane A, 793648547.
- [x] **L06-9** (Low, Shape) — 🔒 `KeyboardEvent.jl`, `ModifierKeys.jl`, `MouseEvent.jl`
  Apply the rule 'A Bool is never positional': the short KeyDown form takes repeat as a keyword, KeyDown(key, modifiers; repeat = false, time). The docstrings of ModifierKeys and MouseButtons show only the keyword and name forms. The callers in source/ (Sdl.jl:403, Web.jl:597, Console.jl _with_alt_modifier, Web.jl:539, Console.jl:429, sdl_modifiers) and the tests use keywords.
  *Test:* test_event_module(): KeyDown(:a, ModifierKeys(); repeat = true, time = 0.0).repeat is true; then test_sdl_keysym(), test_web_backend(), test_console_backend() and test_gesture_recognizer() pass.
  *Done:* lane A, 793648547. omnet-julia and inet-julia have no `KeyDown` call with a positional `repeat`, and no positional `ModifierKeys` or `MouseButtons` call. `sdl_to_keydown(keysym, mod, is_repeat::Bool; time)` still takes a positional Bool; it was not in the list of this item.
- [x] **L06-13** (Low, Documentation) — 🔒 `MouseEvent.jl`, `WindowEvent.jl`, `EventInterface.jl`
  The MouseButtons example uses time = 0.0. MouseDown, MouseMove and WindowResize say 'logical pixels'. The header of EventInterface.jl says that the body of get_event_time is in EventDefaults.jl.
  *Test:* No test (docstring text). The corrected example gives true in a session.
  *Done:* lane A, 793648547.

### Step 3.7: The device layer

Sealed files: `Display.jl`, `ProjecturedKernel.jl`.

- [x] **L07-3** (Low, Correctness) — 🔒 `Display.jl`
  An inner constructor of Display requires scale > 0 and zoom > 0 and throws an ArgumentError for any other value (NaN too). The docstring states the limit.
  *Test:* test_device_module(): Display(scale = 0) and Display(zoom = -1.0) throw an ArgumentError (with L07-5).
  *Done:* lane A, 6a8b4076a, with a `# @positional:` marker on the new inner constructor (e8b5ab4d4). A direct write such as `display.scale = 0` still bypasses the check.
- [x] **L07-4** (Low, Documentation) — 🔒 `Display.jl`, `ProjecturedKernel.jl`
  The Display docstring says that the SDL backend draws each logical pixel as get_device_pixel_ratio(display) device pixels, and that the web, console and video backends do not read the Display. The layer diagram says 'layer 7 - the devices and their physical properties'.
  *Test:* No test (docstring text).
  *Done:* lane A, 6a8b4076a.

### Step 3.8: The gesture layer

Sealed files: `GestureRecognizer.jl`.

- [x] **L08-3** (Low, Documentation) — 🔒 `GestureRecognizer.jl`
  In pop_gesture!, replace the sentences that name the editor and the tests with 'source answers the next input, or nothing'. The recognizer calls get_event_time(event) in place of event.time (lines 97, 101, 158), as its docstring says. editor.md:48-50, :206-210 and :499-501 say that the chord table of an editor is empty, and the list of events that a reader gets adds WindowClose, WindowResize and WindowDefocus.
  *Test:* test_gesture_recognizer() passes with the same count.
  *Done:* lane A, ccb1e4aae.

### Step 3.9: The backend layer

Sealed files: `BackendDefaults.jl`, `BackendInterface.jl`, `BackendModule.jl`, `MouseEvent.jl`, `ProjecturedKernel.jl`.

- [x] **L09-2** (High, Correctness) — 🔒 `MouseEvent.jl`
  The first option of the report: a backend drops a button that the vocabulary does not name. SDL: _sdl_button_sym gives :right only for 3 and nothing for 4 and more, and the poll makes no MouseDown or MouseUp for it. Web: buttonSym in client.js gives left only for 0 and null for 3 and more, and the page sends nothing; Web.jl drops a button name other than left, middle and right. The MouseDown docstring states the rule.
  *Test:* test_input_coalescing(): an SDL button 4 makes no mouse event; test_web_backend(): a mousedown message with an unknown button makes no event.
  *Done:* lane A, 793648547. The web test checks only that the server passes `dy` through; no test covers the sign in client.js.
- [x] **L09-6** (Medium, Architecture) — 🔒 `BackendInterface.jl`, `BackendDefaults.jl`
  Remove the keyword display of get_display_size, which no caller outside a test passes: the interface, the default, SDL (always display 0, now Sdl.jl:4183), VideoBackend.jl:217 and FaultExamples.jl:144. The docstring says 'the usable size in logical pixels'.
  *Test:* test_headless_backend(): get_display_size(b) is (1280, 800); remove the line with display = 2.
  *Done:* lane A, 29568ee3e.
- [x] **L09-13** (Low, Shape) — 🔒 `BackendInterface.jl`
  The Backend docstring states the order initialize_backend!, configure_devices!, open_native_windows!, as make_editor calls them, and what configure_devices! promises (it fills the devices of the editor in place; a backend that draws with a device keeps that device). initialize_backend! stops saying that it creates windows. play_live! calls configure_devices!(backend, devices) before open_native_windows!.
  *Test:* A playback test with a small backend that records its calls: play_live! calls initialize_backend!, configure_devices! and open_native_windows! in that order.
  *Done:* lane A, 29568ee3e. Its test is in test/kernel/playback/PlaybackTest.jl, the file that L23-6 plans.
- [x] **L09-14** (Low, Shape) — 🔒 `BackendModule.jl`
  Remove the two comments on the include lines, which repeat the docstring (PAR-TIGHT-COMMENTS).
  *Test:* No test; the export guard for the planned part.
  *Done:* lane A, 29568ee3e.
- [x] **L09-16** (Low, Documentation) — 🔒 `BackendModule.jl`, `BackendInterface.jl`
  BackendModule: remove 'measure text', write 'is not' and 'initialize', and say where the backends are (opt-in packages, the console in the substrate, the headless double in an example package). BackendInterface.jl: remove 'may' for a possibility, 'e.g.', 'HiDPI', the objects that act as persons, and the names of callers (the editor loop, a feed flush, the follower window); state timeout_seconds > 0 for wait_for_input.
  *Test:* No test (docstring text); the documentation and naming guards pass.
  *Done:* lane A, 29568ee3e.
- [x] **L09-17** (Low, Documentation) — 🔒 `ProjecturedKernel.jl`; after L09-1
  Write the backend part of devices-and-backends.md again from the table in the Shape section of 09-backend.md (four backends and the headless double, open_native_windows!, wait_for_input and wake_backend!, no tooltip in the browser, read! in ReadEvaluatePrint.jl). Correct editor.md:404-407, system-anatomy.md:320-322, :374 and :495-498, the record_video example in ProjecturedVideo.jl:18, the _emit_frames! sentence in ProjecturedSdl.jl:12, and the layer 9 text in ProjecturedKernel.jl:36.
  *Test:* test_documentation() passes.
  *Done:* lane A, 0202a0bb7. PAR-BACKEND-SEAM in architecture-invariants.md still says that `convert_web_key_to_symbol` mirrors `sdl_keysym_to_symbol` (Phase 6).

### Step 3.10: The sealed files of the document layer

Sealed files: `DocumentSearch.jl`, `ForwardProtocol.jl`.

- [x] **L10-20** (Low, Correctness) — 🔒 `ForwardProtocol.jl`
  In `_forward_defs`, make the forwarded `push!`, `insert!`, `deleteat!` and `setindex!` return `x`, the wrapper. Emit `Base.length` over the field in `@adapt_map_protocol`.
  *Test:* test_document_contract(): push!(wrapper, v) === wrapper; length and collect work on a toy type under @adapt_map_protocol.
  *Done:* lane A, 1462e0874. `JsonObject` and `XmlElement` have a length now. The own `setindex!` of an adapted map still returns the value.
- [x] **L10-25** (Low, Documentation) — 🔒 `DocumentSearch.jl`
  Name concepts, not functions or types of higher layers. Rewrite the personified sentences with the mechanism as the subject. Merge the fifth paragraph of the `Document` docstring. Give the reason for the place of SelectionDocument without the count: the macro splices the type as an object, so the type must be at or below this layer.
  *Test:* test_documentation(); no code change.
  *Done:* lane A, 1462e0874.

### Step 3.11: The sealed files of the reference layer

Sealed files: `ReferenceInterface.jl`, `ReferenceSearch.jl`, `SelectionDefaults.jl`.

- [x] **L11-3** (Medium, Correctness) — 🔒 `SelectionDefaults.jl`
  Chosen option: test the layout family (`AFieldReferenceStep`, `ARangeReferenceStep`, `ATypeReferenceStep`) in each `isa` of the two matchers, of strip and fold, of `_copy_reference_step` (an M step copies to an M step) and of `_selection_child` in SelectionDefaults.jl.
  *Test:* test_reference_rules(): each corpus row matches the same on a path of M steps; test_reference_evaluation(): copy_reference copies an M range step.
  *Done:* lane A, 2b175b2cc. In omnet-julia the M-step references of `make_statistic_reference` and `collect_result_values` can now match an arm and descend in `set_selection!`. `_drop_terminal_cursor` and `_mutate_terminal_step!` of SelectionDefaults.jl still test the C layout only.
- [x] **L11-7** (Medium, Correctness) — 🔒 `ReferenceInterface.jl`
  Add a `Base.hash` that agrees with `==` to the seven step types. Change the fallback `==(::ReferenceStep, ::ReferenceStep)` to `a === b`. State in the `ReferenceStep` docstring that a step type defines `==` and a consistent `hash`.
  *Test:* test_reference_evaluation(): a toy step type with no `==` equals itself; test_text(): two equal paths with a text-range step have equal hashes and give one element in a Set.
  *Done:* lane A, 2b175b2cc. The seven types and their tests: the three text steps (test_text), PointReferenceStep (test_point_reference), ChartSampleReferenceStep (test_chart), SequenceChartRowReferenceStep (test_sequencechart), ProjectionReferenceStep (test_reference_evaluation). The fallback `==` is `===`, in ReferenceStep.jl.
- [x] **L11-14** (Medium, Types/performance) — 🔒 `ReferenceSearch.jl`
  In `_PATH_WALK`, carry the location as a cheap reversed chain of steps (for example nested tuples), and build a `Reference` for each result only, in `search_references`.
  *Test:* test_document_walk() and test_referenced_document() answers unchanged; an allocation count of search_references on a deep toy tree drops.
  *Done:* lane A, 0d4328d57. A location is a `Pair{Any,Any}(parent, step)` chain, because a nested tuple gets a new type at each depth. A chain of 200 nodes: 17.1 MB before, 2.60 MB after.
- [x] **L11-16** (Medium, Documentation) — 🔒 `ReferenceInterface.jl`, `ReferenceSearch.jl`
  Correct each of the twelve items in place so that the text matches the code. Items 5 and 6 also change the sealed ReferenceInterface.jl and ReferenceSearch.jl, and item 6 about twelve comments in other packages.
  *Test:* test_documentation(); no code change.
  *Done:* lane A, 705fd1bfc and 5e715ab5b. Item 6 also corrected 16 comments in 12 other packages.
- [x] **L11-25** (part) (Low, Documentation) — 🔒 `ReferenceInterface.jl`
  Delete the history comments, move each misplaced comment to its code, and correct the header of ReferenceInterface.jl so that it names where the seam defaults are. The rule text waits for its decision.
  *Test:* Documentation only.
  *Done:* lane A, 705fd1bfc.

### Step 3.12: The selection layer

Sealed files: `SelectionDefaults.jl`, `SelectionInterface.jl`, `SelectionModule.jl`.

- [x] **L12-4** (Medium, Documentation) — 🔒 `SelectionInterface.jl`
  Move the goals 'move the caret after an edit' and 'select what a search found' to a new 'Use it to' paragraph of replace_selection!, with an example that writes at the root document. Keep only 'build a document that nothing holds yet' for set_selection!.
  *Test:* test_documentation().
  *Done:* lane A, e360373f0.
- [x] **L12-6** (part) (Low, Documentation) — 🔒 `SelectionModule.jl`
  Say in the module docstring of `SelectionModule` that a document extends `has_dormant_selection`, and that no other generic of the layer has a method outside it. The value readers wait for their decision.
  *Test:* Documentation only.
  *Done:* lane A, e360373f0.
- [x] **L12-7** (Low, Shape) — 🔒 `SelectionModule.jl`, `SelectionInterface.jl`, `SelectionDefaults.jl`
  Wrap the eight lines over 90 characters. Shorten the fragment headers of SelectionInterface.jl and SelectionDefaults.jl to one line each.
  *Test:* test_kernel_layering() and test_document_contract(); no behaviour changes.
  *Done:* lane A, e360373f0.
- [x] **L12-8** (Low, Documentation) — 🔒 `SelectionInterface.jl`
  clear_selection!: say that it clears the selection along the path that the document holds; delete 'the whole document' and 'all its children'. replace_selection!: say that a caret move in a leaf writes the selection cell of the leaf once and writes no ancestor cell; the start/stop write in place applies only where the path starts with the range step.
  *Test:* test_documentation().
  *Done:* lane A, e360373f0.
- [x] **L12-9** (Low, Documentation) — 🔒 `SelectionDefaults.jl`
  Replace the comment with: 'At a divergence the old branch is cleared, or kept and marked dormant when a document on it asks to keep it. Marking walks the same path as a clear and writes a flag.' Then correct code-quality-rules.md section 2, which names this line as the history comment that waits for permission.
  *Test:* The grep of code-quality-rules.md section 2 finds no match in source/kernel/selection/.
  *Done:* lane A, e360373f0. A comment near SelectionDefaults.jl:240 repeats the claim of L12-8 that a caret move writes no selection cell; it is not in the item. code-quality-rules.md §6 says that 27 comments match the history grep; 32 match today.
- [x] **L12-10** (Low, Documentation) — 🔒 `SelectionInterface.jl`, `SelectionDefaults.jl`, `SelectionModule.jl`
  Correct the headers: the interface declares nine generics; the defaults header is one line (L12-7); the module docstring names the dormant generics and map_selection_forward. Replace 'a tab group', 'a pane group', 'a tabbed pane' and 'CellVector' with the concept. In selection.md: the layers are 11 and 10; link SelectionMismatchException to its own section; delete the fallback sentence at lines 319-321.
  *Test:* test_documentation().
  *Done:* lane A, e360373f0.

### Step 3.13: The sealed files of the iomap layer

Sealed files: `IoMapInterface.jl`.

- [x] **L16-9** (Low, Documentation) — 🔒 `IoMapInterface.jl`
  Remove the idiom and the personification in IoMapInterface.jl; drop ChainingIoMap; add the optional cell kind to the @iomap signature; replace 'unminimal', the string example and 'crucially'; make the fragment header one line; wrap line 95; add IoMapReconcile.jl and the reconcilers to architecture.md and system-anatomy.md; say in PAR-STABLE-IOMAP-IDENTITY that the key is the identity and the index.
  *Test:* test_documentation().
  *Done:* lane A, dfd3b7281.

## Phase 4 — The missing tests

The tests that no fix above adds. A test that belongs to a fix is in the step of that fix.

### Step 4.1: Tests of the fault layer

- [x] **L01-6** (Medium, Tests) — after L01-18
  Add one test set for each tier in the new `FaultCascadeTest.jl`: `:console` with the console on (a `Test.TestLogger` gets one error), `:sound` with the console off (a backend that counts its sounds), the extra sound for a `:device` record, and a nested call (`depth > 1`).
  *Test:* test_fault_cascade: each tier gives its symbol, and the counts of the test logger and of the sound backend match.
  *Done:* lane A, 3c7a0aed. One set for each tier: console, sound, the extra sound of a device fault, and a nested report.
- [x] **L01-18** (Low, Tests)
  Move `test_fault_report` to the new `FaultCascadeTest.jl` (its function becomes `test_fault_cascade`), wrap the lines over 90 characters, and send the console tier to a `Test.TestLogger`.
  *Test:* test_fault_cascade passes, and the log of the kernel suite holds no '[fault] device in AngryBackend' block.
  *Done:* lane A, 3c7a0aed. The new test function is `test_fault_cascade`.

### Step 4.2: Tests of the performance layer

- [x] **L02-3** (Medium, Tests)
  Test the store with no switch: bind `PerformanceModule._counters` to `_make_performance_counter_store()` with `Base.ScopedValues.with`, call `_bump_count!` and `_bump_time!`, and read `get_performance_counters()`. Chosen over a child process: smaller and faster.
  *Test:* test_performance_counter: inside the scope the counts and the times hold the added values; outside the scope they are empty.
  *Done:* lane A, aae653e7.
- [x] **L02-8** (Low, Tests)
  Move the two editor test sets to a new test file of editor/Feeds.jl under test/kernel/editor/, and call `EditorModule.record_frame_performance!` by its qualified name, as FrameStatisticsFeedTest.jl does. No new export.
  *Test:* test_frame_measurements passes and loads only PerformanceModule; the moved sets pass in their new file.
  *Done:* lane A, aae653e7. The new file is test/kernel/editor/FeedsTest.jl with `test_editor_frame_performance`, because `test_editor_feeds` exists. test_kernel 2481, test_substrate 86852 and the 7 known failures.

### Step 4.3: Tests of the cell layer

- [x] **L03-13** (Low, Tests)
  Add one test set for each name with no test: unwrap_cell, set_cell_value!, copy_cell_as for MutableCell and ImmutableCell, is_computed_cell for the stored kinds, peek inside a computation, and show. Add the sets for L03-4 to L03-6 with their fixes, and mark the sets for L03-1 and L03-2 @test_broken until the owner decides.
  *Test:* test_cell: the new sets pass, and the Broken count grows by the marked sets.
  *Done:* lane A, 4f24012b3, with two `@test_broken` sets for L03-1 and L03-2. No set for a cycle (L03-3), because it overflows the stack.

### Step 4.4: Tests of the struct layer

- [x] **L04-10** (Low, Tests)
  Add test sets for a `mutable struct` and for `add_cell_struct_field!` followed by `build_cell_struct_exprs` now. Add the set for L04-1 with its fix. The sets for L04-2 to L04-4 follow those decisions.
  *Test:* test_cell_struct and test_cell_struct_plan: the new sets pass.
  *Done:* lane A, 1006a6759. The sets for L04-2 to L04-4 wait for their decisions. `build_cell_struct_exprs` parses the definition again, so a default that `add_cell_struct_field!` records has no constructor; the test checks only that the field exists.

### Step 4.5: Tests of the clock layer

- [x] **L05-4** (Low, Tests)
  Add a test set: start a heartbeat, read a computed cell of `get_reactive_clock_time`, wait with a bound until `is_cell_up_to_date` is false, and read a larger value. Make the docstring of the file name what it tests.
  *Test:* test_clock: the new set passes within its bound.
  *Done:* lane A, 40496d8b8. A 5 s bound; the set also passes on the old code, so it adds coverage and is no regression test. test_kernel 2559 pass and 2 broken; test_substrate 86852 and the 7 known failures; test_julia 407, test_fault 73, test_sdl 801, test_serialization 58.

### Step 4.6: Tests of the event layer

- [x] **L06-15** (Low, Tests) — after L06-3, L06-4, L06-5, L06-6
  Add the missing cases: the four has_*_modifier_key functions, get_modifier_keys of a KeyChord and of a window event, get_event_time of an event type of another module, the text of KeyUp, MouseDown, MouseUp and KeyChord patterns, and the cases of L06-3 to L06-5. The tests of the eight unused names wait for L06-7, and the rename of EventCaseTest.jl waits for L06-10.
  *Test:* test_event_module() and test_event_case() pass with the new cases.
  *Done:* lane A, 14197cb96.

### Step 4.7: Tests of the device layer

- [x] **L07-5** (Low, Tests) — after L07-3
  Add a test of the values that L07-3 rejects, and rename the test 'a backend writes the properties in place' to 'each device is mutable'.
  *Test:* test_device_module() passes with the new test.
  *Done:* lane A, 4f7277a35.

### Step 4.8: Tests of the gesture layer

- [x] **L08-4** (Low, Tests)
  Add a double click whose second click is in another window (count 1), and the limits of the click windows (a release at 5 px or after 0.3 s is no click, because the test is a strict <). Remove sleep(0.35) and keep the two event times. The two chord cases (another event between the keys, keys of two windows) go with L08-1.
  *Test:* test_gesture_recognizer(): the new cases pass, and the run is 0.35 s shorter.
  *Done:* lane A, da6e4b620.

### Step 4.9: Tests of the backend layer

- [x] **L09-18** (Low, Tests) — after L09-1, L09-2
  Put one table of inputs into each of the three existing backend tests: the letters a to z (L09-1), the three buttons and a side button (L09-2), and a wheel turn away from the user, dy > 0 (L06-2); through sdl_to_keydown and the SDL poll, _decode_and_enqueue! of the web backend, and _next_event! of the console. Add kernel tests of the defaults of get_pointer_position and open_native_windows!. Correct the docstring of HeadlessBackendTest.jl (no measure).
  *Test:* test_sdl_keysym(), test_input_coalescing(), test_web_backend(), test_console_backend() and test_headless_backend() pass with the new cases.
  *Done:* lane A, d5afaed21. test_kernel 2593 pass and 3 broken; test_sdl 840; test_web_backend 99; test_console_backend 133; test_video 41; test_substrate 86852 and the 7 known failures. "the server wakes the editor" failed once at 5.56 s against its 5 s bound under a machine load of 18, and passed again.

### Step 4.10: Tests of the document layer

- [x] **L10-15** (Medium, Tests) — after L10-1, L10-2, L10-3, L10-4, L10-5
  Add one test case for each fixed finding, in the commit of its fix. Add a kernel test of SelectionDocument and unwrap_selection with a toy document, of `get_edited_field` and `replace_wrapped_document!`, and direct tests of `@forward_protocol` and `@adapt_map_protocol`.
  *Test:* test_document_contract(), test_document_macro(), test_document_walk(), test_bounded_sync().
  *Done:* lane A, ededda49a.
- [x] **L10-26** (Low, Tests) — after L12-5
  Declare DmValueSel at the top level with the other fixtures. Move the four selection testsets into the kernel selection test file that L12-5 adds. Delete the history phrases.
  *Test:* test_document_macro() prints no world-age warning; the moved cases pass in the kernel selection test.
  *Done:* lane A, 95f946579. The one selection testset of DocumentContractTest.jl moved as four sets; the 8 world-age warnings of the kernel log are gone.

### Step 4.11: Tests of the reference layer

- [x] **L11-19** (Medium, Tests) — after L11-1, L11-3, L11-4, L11-7
  Add toy-document tests to ReferenceEvalTest.jl for get_valid_reference_prefix, is_valid_reference, try_evaluate_reference, copy_reference, concat_references, extend_reference, fold_reference_types and search_references. Add the multi-byte, M-step, `nothing` and arm-word rows with their fixes. Rewrite TypeReferenceTest.jl on toy documents in the folded form in the kernel suite.
  *Test:* test_reference_evaluation(), test_reference_rules().
  *Done:* lane A, 425985581. TypeReferenceTest.jl moved to the kernel on toy documents and runs in `test_kernel` (`test_all` never called the old one). The rows of `nothing` and the arm words wait for L11-2. plan/pending/test-suite-green.md still names the deleted file.

### Step 4.12: Tests of the selection layer

- [x] **L12-5** (Medium, Tests)
  Add test/kernel/selection/SelectionTest.jl with test_selection() and test-local @document types: a mismatch throws SelectionMismatchException and keeps the cell; replace_selection! clears the divergent branch; a caret move writes no ancestor selection cell; a keeper marks a branch dormant and a later write makes it live; map_selection_forward carries the dormant state; @with_selection builds a typed path. Register it in KernelSuite.jl and ProjecturedKernelTest.jl.
  *Test:* test_selection().
  *Done:* lane A, 74a207206 (`test_selection`). Nothing in it asserts what L12-1 or L12-2 question.

### Step 4.13: Tests of the operation and intent layers

- [x] **L13-11** (Medium, Tests)
  Add testsets for: the 'next hole' evaluation; describe_operation of each kernel type and the (operation, root) form; splice_string, splice_number and splice_value!; the reroot of a document-rooted ReplaceReferencedValueOperation; the defaults of operation_reference, retarget_operation and operation_travels_unchanged. Make the ToyList override in TraversalTest.jl use .items[i].
  *Test:* test_rerooting(), test_inversion(), test_traversal(), and a new test_description().
  *Done:* lane B, 908ac1a91 (`test_description` is new), except the ToyList part: `child_reference_steps` gives one step for each child and `.items[i]` is two steps, so it waits for the decision of L13-3.
- [x] **L14-3** (Medium, Tests)
  Add test/kernel/intent/IntentTest.jl with test_intent(): a route that starts with the steps, one that does not, a route of nothing, the labels that each constructor keeps, and ClaimedGesture. Move the two testsets of CollectedIntentsOperation and merge_collected_intents from RerootingTest.jl. Register it in KernelSuite.jl and ProjecturedKernelTest.jl.
  *Test:* test_intent() and test_rerooting().
  *Done:* lane B, 908ac1a91 (`test_intent`).

### Step 4.14: Tests of the binding layer

- [x] **L15-6** (Medium, Tests) — after L15-1, L15-8
  Add testsets: claimed with and without override; get_instance_gesture_bindings and the order instance before type; the three-argument read_bound_gesture; a [DC], an [M] and an [I] document; an operation that returns nothing so that a later rule fires.
  *Test:* test_gesture_binding().
  *Done:* lane A, 63d52e5e4.
- [x] **L15-14** (Low, Tests)
  Delete the four testsets of matches_event_pattern and describe_event_pattern after a check that EventModuleTest.jl asserts the same cases; move a case that it lacks there. Delete 'old hand-written' from the header.
  *Test:* test_gesture_binding() and test_event_module().
  *Done:* lane A, 63d52e5e4.

### Step 4.15: Tests of the iomap layer

- [x] **L16-3** (Medium, Tests)
  Add test/kernel/iomap/IoMapReconcileTest.jl and IoMapDefaultsTest.jl (test_iomap_reconcile(), test_iomap_defaults()): a delete and a front insert make the later children again; an element that goes away leaves the cache; one object at two indexes gets two child IoMaps; a make_iomap that returns nothing; reconcile_child_iomap with the same and with a new object; the supertype and the kind argument of @iomap; the three accessors. Register both in KernelSuite.jl and ProjecturedKernelTest.jl.
  *Test:* test_iomap_reconcile() and test_iomap_defaults().
  *Done:* lane A, 31abfb9b5. `reconcile_child_iomaps` calls `make_iomap` again at each computation for a slot whose answer was `nothing`, although its docstring says "only for a new or moved slot" (with L16-4). test_kernel 3487 pass and 2 broken; test_substrate 86866 and the 7 known failures.

### Step 4.16: Tests of the projection layer

- [x] **L17-12** (Medium, Tests) — after L17-1
  Add kernel tests with fixture documents for with_inner_size, with_size_range, get_property, the typed make_child_context, the default mappers, the branches of the default reader, the bridge, read_routed_intent, ProjectionReferenceStep (==, show, the .proj DSL), @projection and read_projection_gesture. Add substrate tests for each wiring kind (tokens, sections, mixed, conditional) with an edit through the same IoMap.
  *Test:* The new test functions, each run alone: for example test_projection_defaults() in test/kernel/projection/ and test_projection_template_wirings() in test/platform/projection/.
  *Done:* lane B, a1c05ca12 (`test_projection_macro` and `test_projection_template_wirings` are new). test_kernel 2826 in lane B and the 6 known failures; test_substrate 86871 and the 7 known failures; test_mcp_tools 158; test_anthropic 38 and 1 broken.

### Step 4.17: Tests of the tool layer

- [x] **L18-14** (Medium, Tests)
  Make the four assertions exact: compare the answer of string(Cell) with the quoted name, or also assert that the answer holds no UndefVarError.
  *Test:* test_declared_api().
  *Done:* lane B, 7e6c25115.
- [x] **L18-15** (Medium, Tests) — after L18-1, L18-2, L18-5, L18-6, L18-7, L18-8
  Add kernel cases for an observer that throws, call_tool with an unknown name, the replacement in register_tool!, and register_guide_root!, and move the observe_evaluations! case down from EvaluatorToplevelTest.jl. The cases of L18-1, L18-2, L18-5, L18-6, L18-7 and L18-8 come with those fixes.
  *Test:* test_declared_api() and test_code_execution().
  *Done:* lane B, 7e6c25115. The observer lines of EvaluatorToplevelTest.jl stay: they test the evaluator, which a kernel test can not reach; the kernel case is beside them.

### Step 4.18: Tests of the llm and agent layers

- [x] **L19-9** (Low, Tests)
  Add test/kernel/llm/LlmDefaultsTest.jl with `FakeLlm`: the error of `make_llm` and `default_llm_model` for a kind that no package answers, the answer of `get_llm_backend_names()`, `is_walk_opaque(::Llm)`, and the conversions of the `LlmRequest` and `LlmMessage` constructors. Register it in the kernel test package and suite.
  *Test:* test_llm_defaults() in ProjecturedKernelTest.
  *Done:* lane B, 8512f0c9a (`test_llm_defaults`, with a test-local kind `:llm_defaults_probe`).
- [x] **L20-7** (Medium, Tests)
  Add test/kernel/agent/AgentLoopTest.jl with `ScriptedLlm` and a NamedTuple target: the round cap and its answer, `LlmFailure` gives `:error`, a tool that throws (the fault record and `is_error`), a tool name that no tool answers, a stream with no terminal event, and the order of the `AgentToolResult` events. Rename AgentSeamTest.jl to AgentDefaultsTest.jl and `test_agent_seam` to `test_agent_defaults`.
  *Test:* test_agent_loop() and test_agent_defaults() in ProjecturedKernelTest.
  *Done:* lane B, 8512f0c9a. AgentSeamTest.jl is AgentDefaultsTest.jl (`test_agent_defaults`); the link in testing-guide.md follows.

### Step 4.19: Tests of the feed and editor layers

- [x] **L21-7** (Low, Tests) — after L21-2, L21-3
  Move test/kernel/feed/FeedTest.jl to test/kernel/editor/FeedsTest.jl (it tests editor/Feeds.jl). Add a drain that throws (L21-2) and a deadline that throws (L21-3).
  *Test:* test_editor_feeds() from its new file, with the two new cases.
  *Done:* lane B, 7a9421d5c. **At the merge:** lane A made test/kernel/editor/FeedsTest.jl too (`test_editor_frame_performance`); join both bodies in one file, keep one include in ProjecturedKernelTest.jl, and join the export line of KernelSuite.jl.
- [x] **L22-17** (Medium, Tests) — after L22-6, L22-11
  Add test/kernel/editor/FaultBarriersTest.jl with a backend that throws on demand in `read_from_devices` and `write_to_devices` (in the test file or ProjecturedKernelExample) and an operation that fails half way. Cover repairs 0 to 2, the two breakers at their limits, a reader that throws in `run_frame!`, a feed that throws in the drain, a queued call that throws in `_answer_waiting_calls!`, and the zoom keys.
  *Test:* test_editor_fault_barriers() in ProjecturedKernelTest.
  *Done:* lane B, 6a4d272b5. FaultBarriersTest.jl has 39 checks, with the tests of L22-7 and L22-11.
- [x] **L22-31** (part) (Low, Tests)
  Add a kernel test of `find_rooted_operation` with a stand-in projection that follows a route, and drive `walk_repl_loop` through a real `Editor` and `run_frame!`. The private names that the tests use wait for their decision.
  *Test:* The two new test sets pass.
  *Done:* lane B, 53696f49d: the test of `find_rooted_operation` (DocumentEditsTest.jl). **Moved to the decisions:** `walk_repl_loop` through a real `Editor` and `run_frame!`. It drives the REPL sweep of every example; through `read!`, an Escape that no reader takes becomes a quit, and the zoom keys and the click pairing change what each example reports. test_kernel 2582 in lane B; test_fault 78; test_substrate 86852 and the 7 known failures; test_sdl 774; test_web_backend 38; test_mcp_tools 158.

## Phase 5 — The renames

Each rename changes a public name. Run the tool with `--report` first, and read `--show-other`. Then correct the prose, which the tool skips. The renames of `run_fault_barrier`, `get_cell_struct_trailing_default_count` and `build_cell_struct_positional_ctors` change sealed files: they need the permission of phase 3. The renames that reach omnet-julia or inet-julia need a worktree there, and the three branches land together.

### Step 5.1: The renames, with `workspace/bin/julia-rename.jl`

- [x] **L01-14** (Low, Naming) — 🔒 `FaultBarrier.jl`, `FaultModule.jl`, `FaultCascade.jl`, `FaultStore.jl`, `FaultPolicy.jl`, `FaultInterface.jl`
  Rename `run_fault_barrier` to `run_fault_barrier!` with workspace/bin/julia-rename.jl, then correct the prose in the docstrings, fault.md and system-anatomy.md.
  *Test:* test_fault_barrier(); test_naming(); a grep finds no `run_fault_barrier(` without `!`.
  *Done:* fc5bb7a69. projectured-julia asset/precompile/PrecompileStatements.jl keeps two `run_fault_barrier` entries: that file says "Do not edit", and replay skips a stale entry.
- [x] **L04-7** (Low, Shape) — 🔒 `CellStructPlan.jl`, `CellStructModule.jl`
  Remove `get_cell_struct_trailing_default_count` from the export block, rename it to `_get_cell_struct_trailing_default_count` with workspace/bin/julia-rename.jl, test it through `get_cell_struct_required_count`, and remove it from the public list in cell.md.
  *Test:* test_cell_struct_plan: get_cell_struct_required_count is right for no, one and all trailing defaults; test_exports(); test_naming().
  *Done:* c84269d5a. Its test goes through `get_cell_struct_required_count`.
- [x] **L04-8** (Low, Naming) — 🔒 `CellStruct.jl`, `CellStructModule.jl`
  Rename `build_cell_struct_positional_ctors` to `build_cell_struct_positional_constructors` with workspace/bin/julia-rename.jl, and make `parameters` of `build_cell_struct_keyword_constructor` a keyword.
  *Test:* test_cell_struct(); test_cell_struct_plan(); test_document_macro(); test_arguments().
  *Done:* 372505784.
- [x] **L10-23** (Low, Naming)
  Rename `sync_element_limit` to `compute_sync_element_limit` with workspace/bin/julia-rename.jl, and give the private helpers `is_same_document_type`, `copy_shadow_element` and `is_walk_leaf` a leading underscore. Update the prose that names them and the protocol list in test/suite/arguments.jl.
  *Test:* test_naming(), test_arguments(), test_bounded_sync(), test_document_reflection().
  *Done:* 708b6b50b. `copy_shadow_element` left the protocol list of test/suite/arguments.jl, because that guard skips private helpers. omnet-julia 0f4a2ee1 and inet-julia 06ead56 rename `is_walk_leaf` in their precompile asset files.
- [x] **L11-24** (part) (Low, Naming)
  Rename `ReferenceEvalTest.jl` to `ReferenceEvaluationTest.jl` and its testset "ReferenceEval" to "ReferenceEvaluation". The name of `ref"…"` waits for its decision.
  *Test:* `test_kernel()` runs the file under its new name.
  *Done:* c8cc9e453.
- [x] **L18-25** (Low, Naming)
  Rename with workspace/bin/julia-rename.jl: api_entry_bindings to get_api_entry_bindings, api_source_name to get_api_source_name, execute_julia_code to execute_julia_code!, execute_julia_expression to execute_julia_expression!. Keep the MCP tool name "execute_julia_code", a wire string.
  *Test:* test_naming(), test_code_execution() and test_declared_api(); then Pkg.precompile and the assistant tests in omnet-julia.
  *Done:* 986e50931; omnet-julia 446f8359 (7 files). Prose that names the MCP tool keeps `"execute_julia_code"`; prose that names the Julia function takes the `!`. The answer in SearchScaleCorpus.jl is `execute_julia_code!`.
- [x] **L19-6** (Low, Naming) — after L19-3
  Rename `default_llm_model` to `get_default_llm_model` with workspace/bin/julia-rename.jl (a value at a known place takes `get_`). Then correct the prose in agent.md, anthropic.md and ollama.md.
  *Test:* test_anthropic_model() and test_ollama_backend() with the new name; the naming guard.
  *Done:* fad43d423; omnet-julia d76c2b4c (a corpus answer).

## Phase 6 — The text

Text only. The documentation guards must pass after each step.

### Step 6.1: The law and the architecture guide

Each item corrects a fact about the code. No item changes what a rule requires.

- [x] **L01-5** (part) (Medium, Documentation)
  Say in fault.md, the `Editor` docstring and the header of FaultBarriers.jl that `make_editor` turns the barriers on and that `run_editor!` keeps the policy of its editor (decision 3 of plan/done/an-editor-is-made-before-its-loop-runs.md). The policy of the tests waits for its decision.
  *Test:* Documentation only; the documentation guards pass.
  *Done:* ba53c6c94.
- [x] **L01-17** (part) (Low, Documentation)
  Move the section PAR-REPORT-NEVER-THROWS under the title that the index gives it, and add a `fault/` row to the folder table of architecture.md. The wording of the carve-out waits for its decision.
  *Test:* Documentation only; the documentation guards pass.
  *Done:* e871a9730. The section PAR-REPORT-NEVER-THROWS stands under "Editor, devices, and backends".
- [x] **L02-6** (Low, Documentation)
  Say that the counters live in the scope of one frame of one editor, remove the history sentence, say that `perf!` logs only with the switch on and an applied operation, point the link of `run_editor!` to EditorLoop.jl, name the frame measurement store in the folder row, and call PerformanceModule a layer.
  *Test:* test_documentation().
  *Done:* e871a9730 and the guide commits of Phase 6.
- [x] **L05-3** (Low, Documentation)
  Add one sentence to PAR-STORE-THEN-DRAIN: the heartbeat of a wall clock is the accepted exception, on the thread of the task that reads the clock.
  *Test:* test_documentation().
  *Done:* e871a9730 and the guide commits of Phase 6.
- [x] **L06-14** (Low, Documentation)
  Write the event part of devices-and-backends.md again from the EventModule docstring: nine fragments, EventPattern.jl, get_event_time, the current names (matches_event_pattern, describe_event_pattern, parse_event_pattern_rule, build_event_pattern_expr, build_event_field_bindings), a type resolves in the module of the pattern, and WindowQuit is a request to quit. Correct system-anatomy.md:369-371 and architecture.md:107 and :167.
  *Test:* test_documentation() passes.
  *Done:* ba53c6c94. EventModule has eight fragments, as its docstring says.
- [x] **L10-13** (Medium, Documentation) — after L10-1
  Rewrite the file tree, the selection paragraph and the contract surface of document.md, and replace the example of a private program. Correct the selection union in macros.md. In architecture-invariants.md correct the stale fact of PAR-DOCUMENT-IDENTITY: the cell layout is an immutable struct. The text of PAR-NO-NESTED-CELL waits for its decision (L10-13, decision part).
  *Test:* test_documentation(); no code change.
  *Done:* e871a9730, e0289d67f. The text of PAR-NO-NESTED-CELL waits for its decision.
- [x] **L17-27** (Low, Documentation)
  Correct each statement: projection-system.md (the editor calls the 4-argument print; Intent has five fields, and route is one; no pipeline uses the pure pair), macros.md (18 files use @projection_template, and hand-written printers remain), naming-rules.md:384-385 (the marker words are not exported), architecture.md:111 (ProjectionModule is layer 17).
  *Test:* test_documentation().
  *Done:* e871a9730 and the guide commits of Phase 6.
- [x] **L22-28** (Low, Documentation) — same fault as L01-5
  Say that `make_editor` turns the barriers on and `run_editor!` keeps the policy of its editor, and drop the stale claim that no test calls `run_editor!`.
  *Test:* None; the change is text only.
  *Done:* e871a9730. One sentence of the second half of PAR-REPORT-NEVER-THROWS says now that `make_editor` turns the barriers on and `run_editor!` keeps the policy of its editor; the requirement sentence did not change. So the law shows the conflict of L01-5 for the decision.

### Step 6.2: The design documents and guides

- [x] **L11-15** (Medium, Documentation)
  Write `__ =>` in the three examples, and `children[i].rest...` in the example of projection-system.md.
  *Test:* test_documentation(); each corrected snippet expands with no LoadError.
  *Done:* ecbf64638. Each corrected example expands with no error; a bare `_` arm still raises.
- [x] **L13-10** (Medium, Documentation)
  Rewrite the comment above the catch-all: a reader that declines returns nothing; the catch-all accepts any value that is not an Operation, so a stray value does no harm. Correct operation.md:298 the same way.
  *Test:* test_documentation().
  *Done:* 30b8284fa.
- [x] **L13-16** (Low, Documentation)
  Module docstring: six fragments, OperationInterface.jl, four open seams, and describe_reference. Correct the headers of Operations.jl and OperationInterface.jl. Point AdjustZoomOperation to OperationDefaults.jl. Replace StringReplaceRangeOperation at Description.jl:43 with a real name. Correct the Operation example and the insert_elements signature. Give QuitEditorException a docstring. Drop 'the collection package' and 'the editor loop'. Rewrite the layer section of operation.md from the six files.
  *Test:* test_documentation().
  *Done:* 30b8284fa. The headers of Operations.jl and OperationInterface.jl were correct; the paths of the table of distinct operations in operation.md are corrected.
- [x] **L14-8** (Low, Documentation)
  IntentModule.jl: say that the types sit in layer 14, above the operation layer, and drop 'the binding layer above'. ClaimedGesture: describe it by concepts; drop JSON, XML, fire_gesture_bindings, 'the generic reader bridge', ProjectionModule and '(now)'. CollectIntents: delete 'ClaimedGesture is the precedent'. Intent: show five fields in the signature line, and say that WindowInput is an event of the event layer. projection-system.md: link Intent.jl and show five fields.
  *Test:* test_documentation().
  *Done:* 30b8284fa.
- [x] **L15-5** (Medium, Documentation)
  Correct the signatures of fire_gesture_bindings (565) and fire_named_gesture_binding (598). Add GestureBindingInterface.jl with read_gesture to the tree (552-557). Correct the downward edges (630-633): EventModule once, add IntentModule, drop DocumentModule: Document. Write move_to_field(doc; from, to) at 606 and engineer-tour.md:191. Put the command palette in the gesturehelp package (625).
  *Test:* test_documentation().
  *Done:* c4cfab7fd.
- [x] **L17-14** (Low, Correctness)
  Say in the docstring of print_document(projection, input) that the form is for a leaf or a wrapped pipeline, because it passes recursion = nothing. Correct projection-system.md:110-112: the editor calls the 4-argument form.
  *Test:* test_documentation().
  *Done:* c75ec8a44.
- [x] **L17-22** (Low, Documentation)
  Correct each path and name: documentation/testing.md to the testing guide, package/kernel/doc/... to documentation/package/kernel/..., 'Sequential' to ChainingProjection, and `[_with_selection](@ref)` to plain text. Delete the citations of plan/pending/cell-kind-documents.md with L17-24.
  *Test:* test_documentation().
  *Done:* c75ec8a44.
- [x] **L18-26** (Low, Documentation) — after L18-1
  Name each process-global value of the layer, and why it is there, in the ToolModule docstring and agent.md:59. Correct the empty-API sentences (Tool.jl:189, Documentation.jl:1262, agent.md:362, mcp-guide.md:50) after L18-1. Delete the remark about the wall clock at Documentation.jl:876.
  *Test:* test_documentation().
  *Done:* 205fb718e. mcp-guide.md says that `search_api` reads the declared API, or every loaded package when none is declared.
- [x] **L18-29** (Low, Documentation)
  Show the api keyword in the docstring signatures of list_modules, read_module_documentation, read_type_documentation and read_function_documentation. Drop 'tips and tricks' (also in DefaultTools.jl:291). Move each comment above the function that it describes. Say in _is_interface_name that the prefix I means immutable. Name ApiEntry and observe_evaluations! in the ToolModule docstring and agent.md:30.
  *Test:* test_documentation().
  *Done:* 205fb718e.
- [x] **L19-3** (Low, Shape)
  Keep the generic and correct its docstring: it answers the model that the backend falls back to, and a backend can choose another model for an empty name (the Anthropic adapter asks the Models API first). Correct agent.md:287 to match.
  *Test:* None; the change is text only.
  *Done:* ed36607bc (on the merged branch).
- [x] **L19-7** (Low, Documentation)
  List the five fragments in the LlmModule docstring (the seams in LlmInterface.jl, the fallbacks in LlmDefaults.jl). Correct agent.md:213-217 and :282 (`get_llm_backend_names` is in Llm.jl). Write ProjecturedAnthropic and ProjecturedOllama for the package `Llm`/`llm` in the three rule and design documents.
  *Test:* None; the change is text only.
  *Done:* ea5c06ef7.
- [x] **L20-11** (Low, Documentation)
  Say in the module docstring that the module holds both halves. Name AgentInterface.jl as the file of the seam and add AgentDefaults.jl in system-anatomy.md and agent.md; write one AgentModule in place of the two.
  *Test:* None; the change is text only.
  *Done:* ea5c06ef7.
- [x] **L21-6** (Low, Documentation)
  Name kinds in place of consumers (a feed that holds a queue of operations, the read step of a frame); write 'the default does nothing, for a feed whose producers never wake the editor'; add `TooltipFeed` to the table of editor.md and drop 'so far'; state the fault store and the tick cadence in the present tense.
  *Test:* None; the change is text only.
  *Done:* db435e0eb.

### Step 6.3: The docstrings and comments of files that are not sealed

- [x] **L10-12** (Medium, Documentation)
  Correct the six statements: the injected field is `Union{Nothing, Reference, SelectionDocument}`, and an explicit `selection` field is accepted when it is last; the kind constructors are `ICFoo`/`MCFoo`; the bare constructor builds `DCFoo`; the layout codes include `I`; the file has eight emitters; the comment at line 593 gives the current union.
  *Test:* test_documentation(); no behaviour change.
  *Done:* 9c2aa9bab, with the IC and MC prefixes in macros.md. The file has 11 `_emit_` functions, so its header names them with no count.
- [x] **L10-24** (Low, Documentation)
  Delete each history phrase. Keep a constraint that the code can not show in one sentence in the present tense.
  *Test:* test_documentation(); no code change.
  *Done:* 9c2aa9bab.
- [x] **L15-13** (Low, Documentation)
  Correct 'below' at GestureBindingInterface.jl:20; add override to the signature at GestureBinding.jl:16; name the three fragments, get_instance_gesture_bindings, fire_named_gesture_binding and CollectIntents in the module docstring; remove the consumer names, 'layer' for a pipeline stage, and the idioms; delete the repeat of the grammar at Gestures.jl:6-28; wrap the ten lines over 90 characters.
  *Test:* test_documentation().
  *Done:* d533e5eb6. The `@gestures` docstring still says that `event` is in scope of a rule body; that waits for L15-4.
- [x] **L16-2** (Medium, Documentation)
  Rewrite the compound printer example: child_iomaps = reconcile_child_iomaps(...); the mappers read iomap.child_iomaps (no []); build the reference with @reference.
  *Test:* test_documentation().
  *Done:* c0f3bd1f9. The example uses typed `@reference` literals, because an untyped one throws "under-typed" when it runs.
- [x] **L16-4** (Low, Correctness)
  State in both docstrings that the IoMap that make_iomap returns must hold the element (as its input), because the cache key is objectid, a number, and not a reference to the element. This is the smaller option and answers PAR-MODULE-DOCSTRING; the other option keeps the element in the cache entry and compares it with ===.
  *Test:* test_documentation().
  *Done:* 48d8971df.
- [x] **L17-23** (Low, Documentation) — after L17-6, L17-10, L17-13, L17-16
  Correct each false statement: the fragment table; 'every structural projection uses the engine' (four *ToSyntax files hold hand-written printers); ':terminal' to :structural; drop '(nodes; WIP)'; correct line 794 and lines 466-469; correct the export claim of the pure printer.
  *Test:* test_documentation().
  *Done:* 5c9270493. `ChildrenContainer.jl` stays (L17-16 is a decision); its header says that it holds no code.
- [x] **L17-24** (Low, Documentation)
  Delete the history at ProjectionTemplate.jl:265-275 and keep its constraint in the present tense. Name F1, F2 and F3 in words (a nested sub-node, a reactive child list, an as= override). Delete 'from day one' and the plan-phase citations at ProjectionTemplate.jl:228 and ProjectionInterface.jl:150-153.
  *Test:* test_documentation().
  *Done:* 5c9270493.
- [x] **L17-25** (Low, Documentation)
  Describe the contract only: remove the names of higher packages and consumers (PointReferenceStep, map_operation_position, the render stage, PaneToWidget, FocusingProjection, Clipboard, the editor loop), write 'stage' where the text calls a pipeline stage a layer, and delete the second copy of the comment at ProjectionTemplate.jl:1374-1380.
  *Test:* test_documentation().
  *Done:* 5c9270493.
- [x] **L17-26** (Low, Documentation)
  Show the 4-argument read_intent in the Example, with a gesture that needs geometry. Say that a 4-argument reader returns an Intent, and correct 'Leaf projections therefore keep their 3-arg methods'. Give map_reference_backward, print_child, PrinterContext, make_child_context and read_routed_intent a 'Use it to' paragraph, an Example and 'See also'. Move the older paragraph of the Projection docstring above 'See also'.
  *Test:* test_documentation().
  *Done:* 5c9270493.
- [x] **L18-28** (Low, Documentation)
  Delete the history comments (DefaultTools.jl:285-288 and :228-229; DeclaredApiTest.jl:110, :160 and :513-518) and rename the testset in SearchQueryTest.jl:157. Drop the two PAR-PER-EDITOR-STATE citations. State the contracts of Tool.jl:229-232, the ApiEntry docstring and the declare_api! example in the terms of this layer. Remove the personification at DefaultTools.jl:169 and ToolModule.jl:25.
  *Test:* test_documentation(), test_declared_api() and test_search_query().
  *Done:* 3563bad0d. The private names of omnet-julia (`run_simulations_in_conversation`, `stop_simulations`, `CampaignVerbsModule`) left Documentation.jl too, as the finding asks; the `declare_api!` example uses kernel modules only.
- [x] **L19-8** (Low, Documentation)
  Name the kind of value in place of a provider or a higher layer (a provider-specific tool list, a caller that runs tools), say what the code does (a `Tool` holds no wire format), and wrap LlmMessage.jl:110 under 90 characters.
  *Test:* None; the change is text only.
  *Done:* 9ca69096e.
- [x] **L20-12** (Low, Documentation)
  Describe the contract without the layer above, keep one statement of the two halves (in the module docstring), write 'the loop streams, runs the tools, and stops when the model asks for no tool', add a Throws line to `run_turn!` (it throws what `stream_turn`, `messages` and `on_event` throw), and wrap AgentLoop.jl:45 and :87.
  *Test:* None; the change is text only.
  *Done:* 5875f6bdf.
- [x] **L22-29** (Low, Documentation)
  Update the sections: all 17 fields of `Editor`; the recognizer makes a `MousePress` after its `MouseUp` and recognizes no chord today; the three backends with `WebBackend`; the nine files of the layer; the full list of downward edges; the tests with WaitTest.jl, the feed test and the safe-mode test.
  *Test:* None; the change is text only.
  *Done:* 6257fc7c2. test_kernel 3901 and 2 broken, test_mcp_tools 158, test_search_scale 45; the documentation and naming guards find nothing.
- [x] **L22-30** (Low, Documentation)
  Remove the consumer names and the rule citation, repair the `print!` sentence, name all five keywords in the header of the `run_editor!` docstring, describe the barrier and the repairs in the `evaluate!` docstring, say that `insert_elements!` runs on the editor task, make each fragment header one line under 90 characters, and wrap the long lines.
  *Test:* None; the change is text only.
  *Done:* 35c200dbb. The export line of EditorModule.jl:54 (101 characters) stays for export-block-rule.md.

## Phase 7 — The decided questions

The owner decided 37 questions of the table below between 2026-09-30 and 2026-10-01, and asked on 2026-10-03 to implement them. The other questions stay open.

**Where:** branch `kernel-audit-decisions`, worktree `projectured-julia-kernel-audit-decisions`, on main `599cee558`. omnet-julia and inet-julia get a branch of the same name when a step reaches them. One commit for each step.

**Already done by another plan:** L07-1, L22-23 and the `_zoom_operation` part of L22-27 (plan/done/zoom-and-theme-controls.md).

**Sealed files.** A step that changes a sealed file waits for the permission of the owner for that file. The files: `fault/FaultCascade.jl`, `fault/FaultStore.jl`, `fault/FaultRecord.jl`, `fault/FaultBarrier.jl`, `performance/PerformanceModule.jl`, `performance/PerformanceCounter.jl`, `selection/SelectionModule.jl`, `selection/SelectionInterface.jl`, `selection/SelectionDefaults.jl`, `backend/BackendModule.jl`, `backend/BackendDefaults.jl`, `iomap/IoMapModule.jl`, `reference/ReferenceInterface.jl`, `reference/ReferenceSearch.jl` (the owner allowed its docstring for L10-10).

**L09-15 in part:** the two device generics are renamed now. `write_image` and `record_video` wait for L09-3, because its option C moves them out of the kernel under new names.

**Baseline:** the suites of the three repositories at the base commits, in `/var/tmp/kad-baseline/`.

- [x] **D1. The law and the rules, text only.** PAR-NO-NESTED-CELL (L10-13); the carve-outs of PAR-PURE-THUNK and PAR-NO-WRITE-IN-THUNK (L01-17); PAR-AI-SAME-GUARANTEES and its accepted exception (L18-27); system-anatomy.md (L14-6); code-quality-rules.md §5 (L06-10); the rows `describe_` (L06-12) and `run_` (L22-13), and the class of structural operations (L13-15, L14-2) in naming-rules.md.
  *Done:* the text of the new cell of L17-15 goes with its code in D6, and the sentence of PAR-ONE-BASED-INDEXING (L11-25) with its code in D9, so that the law never names code that does not exist yet.
- [x] **D2. POLICY-1 outside the fault layer.** L10-10 (`walk_document` takes `on_error`), L11-5 (the three reference walkers), L18-10 (the code tool acts as the Julia REPL), and every other catch-all arm of the kernel that does not ask `is_passthrough_exception`. PAR-REPORT-NEVER-THROWS states the rule and its one exception.
  *Done:* `walk_document` wraps the predicate in a private `_GuardedPredicate`, so the recursion keeps its signature. The code tool answers an exception of model code through `_is_passthrough_for_model_code`: a stop exception that is not an interrupt or a stack overflow goes on, and `_summarize_value` follows the same rule, because a `summary` method can be model code. 14 other arms of the kernel got the test: AgentLoop.jl (1), EditorLoop.jl (the quit after a failed build), Description.jl (2), PathChain.jl (3), ProjectionDefaults.jl (2), Documentation.jl (2), RelevanceSearch.jl (2), SearchQuery.jl (1), and MeaningSearch.jl (5, the one that reads EOF already rethrows). Three arms keep the exception and need no test: the shutdown loop returns its first exception, the build of the editor rethrows, and the editor task puts the exception into a channel for its caller. The modules name the fault module bare (`using ..FaultModule`), because the layering guard rejects a name list on a `using` (PAR-QUALIFIED-EXTENSION). Tests: DocumentWalk 39, ReferenceEvaluation 108, Code execution 50; test_kernel: 4145 pass and 2 broken; its 6 failures in MeaningSearchTest come from a second run in one process, because the meaning store keeps the models of the first run (the first run passed it).
  - **L11-5 in part.** Only the stop exceptions pass now. The `MethodError` half waits for the owner: the docstring of `TypeReferenceStep` promises that `get_valid_reference_prefix` cuts a path at an unfolded type token, which has no `evaluate_reference_step` on purpose, and `TypeReferenceTest.jl:68` asserts it. Option B would make that token a fault of the program.
- [x] **D3. POLICY-1 in the fault layer** (L01-8). Sealed: FaultCascade.jl, FaultStore.jl, FaultRecord.jl.
  *Done:* the owner allowed the unsealing on 2026-10-04. Ten arms of the report path ask `is_passthrough_exception` first: six in FaultCascade.jl (the depth, the leave, tier 5, the console, the sound, the line for a refused target), two in FaultStore.jl (the wake, the target of the drain) and two in FaultRecord.jl (the message and the traceback). The docstrings say "never throws an ordinary exception", and PAR-REPORT-NEVER-THROWS says that "a report never throws" is about an ordinary exception. The three files are ⬜ in SEALING.md until they are audited again. Tests: one for each kind of arm; the report cascade 20, the fault store 37, the fault record 7, test_kernel 4161 pass and 2 broken.
- [x] **D4. Every default fault policy is strict** (L01-5), with the programs that a person starts in the three repositories.
  *Done:* `make_editor` and `build_editor` default to `make_strict_fault_policy()`, so `run_editor!(document, projection)` is strict too; `Editor` already was. The code changed after the audit: `build_editor` (EditorBuild.jl) is the form that the programs use now. Programs that a person starts pass `FaultPolicy()`: the display of a value in an editor window (EditorDisplay.jl), the helper of the gallery that every example uses (`_make_window_scene_editor`) and the console run of the gallery, the docstring example of `make_fault_tolerant_projection`; omnet-julia the campaign window and the Qtenv window (9900237d). The application passes the policy of its settings, which the command line can make strict, so the first print runs under it already. `record_application_video` passes the policy of its settings too, as the application does: its settings read the editor (`is_read_from_targets`) and apply no policy to it, so with the strict build the paint fault of `ApplicationVideoTest.jl:291` ended the take; the sweep against main found it. The video tools build `Editor(...)` and were strict already. A fact the plan did not have: inet-julia `example/watch/mac_fsm_sdl.jl` calls `run_editor!(SdlBackend(), projection, screen; on_start)`, a form that projectured-julia does not define; that example is broken on main already. The law, the Editor docstring, the two docstrings of FaultPolicy.jl, fault.md and editor.md say it. Tests: test_kernel, test_platform, test_referenced_document_editor, test_history_sweep, test_application, test_dataframes 542.
- [x] **D5. One pair registers an operation that carries a path** (L13-8).
  *Done:* the catch-all `reroot_operation` reroots the reference that `operation_reference` reports, through `retarget_operation`. The methods for `ReplaceReferencedValueOperation` (kernel), the two primitive edits, `OpenTooltipOperation` and `OpenContextMenuOperation` go, because their pair already gives the same result; `ReplaceTextRangeOperation` gets the pair in place of its method, so the default reader now maps it back too. The kernel changed after the audit: the family `ReplacePathOperation` registers through `get_operation_path` and `make_path_operation`, and keeps its one method, as `CompoundOperation` and `WrappingOperation` do; the law names that family. The four packages import only the names that they still extend. Tests: Rerooting 56, the text tests, test_platform 86942 pass and 8 broken.
- [x] **D6. The template walk reads the blueprint with `peek`** (L17-15).
  *Done:* nine reads of a blueprint cell in ProjectionTemplate.jl became `peek`: `_carries_marker`, `_has_fixed_children`, `_find_tokens`, `_find_sections`, `_find_collection`, `_find_fixed_children`, `_scan_atomic!`, and the two reads of the inline print (its sample and its children computation). The reads of the IoMap cells and of the child lists stay tracked, because those are the dependencies of the output. PAR-NO-WRITE-IN-THUNK has the carve-out for a new cell. Tests: test_julia 518, test_math 180, test_fsm 159, test_process 309, test_rst 84, test_platform 86942 pass and 8 broken.
- [x] **D7. `ChildrenContainer.jl` goes** (L17-16), with its line and a new sentence in SEALING.md.
  *Done:* the file, its include, its line in the fragment table of ProjectionModule.jl and in architecture.md, and its line in SEALING.md. The banner of the seam in ProjectionInterface.jl names no file, so it stays. The kernel layering guard passes (10).
- [x] **D8. A kernel docstring shows kernel names only** (L11-17). Sealed: the docstrings of ReferenceInterface.jl and ReferenceSearch.jl.
  *Done in part:* the unsealed files. ReferenceBuilder.jl (the `@reference` docstring now builds a toy `Point` and calls `evaluate_reference`), ReferencedDocument.jl (the referenced document, `DocumentLocator`, `find_referenced_document`, `get_parent`), ReferenceEvaluation.jl and ReferenceModule.jl (a hot path and a caller, not a simulator, the UI or the editor); ReferenceStep.jl needed no change. The pane package shows the window calls: `find_pane` gets a `get_parent` line, and pane.md gets `get_parent` and `DocumentLocator` with `find_referenced_document`. code-quality-rules.md §1 has the sentence. Each new kernel example was run against the kernel.
  - **The owner allowed the unsealing on 2026-10-04.** The two docstrings take the proposed text below; both files are ⬜ in SEALING.md until they are audited again. The proposed text, as applied: The proposed text: in ReferenceInterface.jl (`Reference`), "a selection, the target of an edit, the tab a verb opened" becomes "a selection, or the target of an edit", and the example `value = get_referenced_value(editor, place)` becomes `value = evaluate_reference(document, place)`. In ReferenceSearch.jl (`search_references`), `search_references(editor.document, "Alice")` becomes `search_references(document, "Alice")`, and the example over `editor.document` and `JsonString` becomes a toy `@document struct Note` with `text::String`, searched for "TODO" and read with `evaluate_reference`.
- [x] **D9. `reference_pattern"…"`, 1-based, and `first_index`** (L11-24, L11-25), with omnet-julia.
  *Done:* `@ref_str` is `@reference_pattern_str`, and the two arm readers of `@reference_case` and `@reference_rules` know the new macro name. `parse_reference_pattern(text; first_index = 1)` shifts an index from `first_index` to 1; the macro is always 1-based. The tests of the string spelling count from 1 and also check `first_index = 0`. PAR-ONE-BASED-INDEXING states the boundary rule; reference.md and the module docstrings follow, and the guide no longer says "0-based indices". omnet-julia passes `first_index = 0` in the INI reader and the two trim-routing tools (281ad857). Tests: ReferenceRules 1509, ReferenceEvaluation, the kernel layering guard, the naming guard.
- [x] **D10. The protocol methods of copy and sync take no default values** (L10-8), with omnet-julia.
  *Done:* the four kind methods of `copy_document` and the two methods of `sync_document!` (kernel and ListNode.jl) take `policy` and `depth` with no default; `copy_document(K, value)` and `sync_document!(shadow, source)` are methods of their own. The private `_copy_shadow_element` keeps its defaults, because the element sync calls it with two arguments. omnet-julia `Configuration.jl` (the sweep method, 4a410593). A fact the plan did not have: inet-julia `PacketEnvelope.jl` called `copy_document(ReactiveCell, pk, LivePacketPolicy())` with three arguments through the default depth, and `LivePacketPolicy` is no `SyncPolicy`; it now passes the depth 0 (b370905). Tests: test_kernel and test_platform, no new failure.
- [x] **D11. `Tool` takes keywords** (L18-3).
  *Done:* `Tool(name; description, parameters, handler, result_mime_type)`. 21 calls changed: DefaultTools.jl (6), UndoDocument.jl (2), FaultExamples.jl (1), and 12 in 8 test files; each call names one keyword on each line, aligned under the name. omnet-julia and inet-julia call `Tool` only in their precompile assets. Tests: test_declared_api, test_search_answer, test_agent_loop, test_llm_defaults, test_code_execution, test_mcp 452. The Ollama, Anthropic and umbrella tests that build a tool run in the final sweep, with no network.
- [x] **D12. The renames**, one commit each, with `workspace/bin/julia-rename.jl`: the builders with a 1-based index (L13-9); `is_self_contained_operation` (L13-15); the three stages (L22-13); the counters (L02-5, L22-27); `make_similar_cell` (L03-10); the two device generics (L09-15); the gesture getters, the file, `with_free_axis` and the word `template` (L15-12, L17-21); the reconcilers (L16-8); `set_selection!` and `@selected` (L12-3); `GesturePatternTest.jl` (L06-10).
  *Done so far:* the six renames that touch no sealed file, by a refactoring agent, one commit each: `is_self_contained_operation` (L13-15, also omnet 18ee7ba2), `make_similar_cell` (L03-10), `collect_document_gesture_bindings`, `compute_applicable_gesture_bindings` and `ProjectionGestureBindings.jl` (L15-12), `with_free_axis`, `TemplateIoMap` and `print_template_document` (L17-21, also omnet 3bcfdc65 and inet 28eba68), `_log_performance_counters!` (L22-27), `GesturePatternTest.jl` with `test_gesture_pattern` (L06-10). The rename tool misses a doubly qualified name such as `A.B.RuleIoMap`; the agent found about 450 such lines in the precompile assets of omnet-julia and inet-julia and changed them by hand. The decision records in plan/pending/kernel-audit* keep the old names, as plan/done does. Then L13-9 by hand: `make_insert_elements_operation`, `make_delete_elements_operation` and `make_replace_document_operation`, and the two element builders take the 1-based index of an element; the 17 calls changed their index (the clipboard helper `_elements_index` answers a 1-based index, and the text edit names the element and the boundary apart). Tests: test_kernel 4155 pass and 2 broken in a fresh process (the base has 4140 and 2), test_platform, test_chart, test_json, test_xml, test_julia, test_math, test_document_insertion.
  - The wrap pass: the lines that the renames pushed past 90 characters are wrapped (projectured 203515f86, omnet 1f0dc493); Markdown tables, one-line paragraphs and plan records keep their style.
  - With the owner's permission of 2026-10-04, the renames in the sealed layers, one commit each: the three stages `run_read_stage!`, `run_evaluate_stage!`, `run_print_stage!` (L22-13; e56dff902, omnet 6d4e1bfb, inet 8b6bf98); `run_with_performance_counters` (L02-5; ae1c80369); `take_from_devices!` and `write_to_devices!` (L09-15, the two device generics; ca726fd68, omnet b5bbec6f, inet 285ccfd); `make_reconciled_child_iomaps_cell` and `make_reconciled_child_iomap_cell` (L16-8; 416aeebb9, omnet ba6a432f, inet 1becbf6); and L12-3: `set_selection!` answers its document, `with_selection` is gone, and the macro is `@selected` (7cf85ae26). The sealed files that changed are ⬜ in SEALING.md: FaultBarrier.jl, PerformanceModule.jl, PerformanceCounter.jl, BackendModule.jl, SelectionModule.jl, SelectionInterface.jl, SelectionDefaults.jl, IoMapModule.jl; BackendDefaults.jl did not change and stays sealed. Tests after the five: test_kernel 4161 pass and 2 broken, test_platform 86942 pass and 8 broken, no failure.
  - Still open: `write_image` and `record_video` wait for L09-3.
- [x] **D13. The arguments** (POLICY-3): §4 of code-quality-rules.md, the guard, the count markers out, an `# @optional:` marker or a change for each definition that breaks the optional clause, in the three repositories.
  *Done:* §4 states the count as advice and the optional clause as a recommendation with the marker `# @optional: <reason>` (fc0843490). The guard checks the clause on every public definition outside a port, reports a leftover `# @positional:` marker, and takes the root of another repository: `julia test/suite/arguments.jl <root>`; `--report` prints the counts. A refactoring agent removed the 80 markers of projectured-julia (one kept fact: the compile count of the walk in DocumentWalk.jl) and 19 of omnet-julia, and added `# @optional:` markers with a reason to every definition that breaks the clause: 19 in projectured-julia, 30 in omnet-julia (the 4 old markers of ForceDirectedParameters.jl took the new word), 3 in inet-julia. No signature changed (projectured d599451e8 and 6603e0d6d, omnet b84be571 and 7a588ebc, inet da7e634). The guard passes for the three roots.
  - Open for the owner: omnet-julia and inet-julia do not run the guard by themselves. Each can run it with its root as above; a test that includes `test/suite/arguments.jl` of projectured-julia by path would tie their suites to the layout of this repository, and a copy, as omnet-julia keeps of the naming guard, would be a second guard to keep.
- [x] **D14. The test sweep** against the baseline in the three repositories, the precompile assets, and the guides that name a renamed name.
  *Done:* the branch merged main (projectured 43a7c1718, omnet 282f17a2, inet a7c211c) and was compared with the merge parents of main (projectured 759a7ce2a, omnet f72ccd5c, inet ee71036), suite by suite, one side after the other on the same lane, with no network; full table in /var/tmp/kad-main/comparison.md. Result: no failure of the branch that main does not have, after three checks:
  - `ApplicationVideoTest.jl:291` was the branch's: the take of the application built its editor strict (L01-5). Fixed in 2aeb6d47b; test_video is then 78 pass and 2 fail, as main.
  - inet-julia `t1s_byte_identity.jl` (6 failures) fails on main too, with identical differing lines; the sweep's worktree of main had no `inet-cpp` beside it, so the test was skipped there. The same missing folders explain the 7 and 5 skips that looked like broken tests turning into passes.
  - omnet-julia `WatchExampleTest.jl:426` depends on timing: run alone five times, it fails five times on main (the event count stops at 9223373 before the pause).
  - Guards: the branch resolves the 5 failures of `test_arguments`; `test_exports` and `test_documentation` show the same findings as main.
  - The precompile assets keep some old names inside generated closure names; the precompile step skips such an entry, and the next recording replaces them.
  - The video suites ran in their own processes with a hard limit; no hang this time.

## Items that wait for a decision

These items need no decision of their own, but a decision on another finding can make them moot.
Do each one after its decision, if it still applies.

- **L11-22** (Low) waits for L11-10. Split ReferenceCase.jl into the lowering, the compiled matcher and the macro, and ReferenceRules.jl into the interpreter, the display and the quoting. Split `_gen_path_match`, `_parse_ref_path!`, `_consume` and `_gen_above_match` under 60 lines. Wrap the lines over 90 characters.
- **L23-2** (Medium) waits for L23-5. Take `start` after the first `print!`, and when an entry fires late, move the times of the later entries by that delay. The docstring says that `hold` is 'the dwell after the entry' and that 'each resulting state is visible'.
- **L23-3** (Medium) waits for L23-5. Give an event entry to the recognizer through `pop_gesture!(editor.recognizer, ...)` with a reader that answers the event once, stamped with the time it fires (a copy with the time field replaced), so that the docstring's 'the same path live input takes' holds.
- **L23-6** (Medium) waits for L23-5. Add test/kernel/playback/PlaybackTest.jl with `HeadlessBackend` and a short timeline (an event, an operation, an await, then `QuitEditorOperation()`); check the order of the entries and the rerooting.
- **L23-7** (Low) waits for L23-5. Log a skipped entry with its index (`@warn`), throw `ArgumentError` for a `hold` under 0 when the schedule is built, and read `time_ns()` for the schedule.
- **L23-8** (Low) waits for L23-5. Use `read_rooted_operation(editor, op_prefix, op)` in place of `reroot_operation`, so the readers between the root and the content lift the operation (PAR-DELEGATE-AND-LIFT).
- **L23-9** (Low) waits for L23-5. Replace `_path_to_steps(op_prefix)` with `Tuple(get_reference_steps(op_prefix))` and delete `_path_to_steps`.
- **L23-10** (Low) waits for L23-5. Rename `_timeline_operation` to `_make_timeline_operation` and the keyword `op_prefix` to `operation_prefix` (the full word; one caller, example/backend/sdl/LiveExamples.jl:138), and the locals `op`, `acc`, `cur`, `n`. `_path_to_steps` goes with L23-9.
- **L23-11** (Low) waits for L23-5. Remove the consumer names from Playback.jl, correct the claim of 'the same path live input takes' (or fix it with L23-3), name `op_prefix` in the header of the bootstrap docstring, give editor.md the real signature, folder and use of `OperationModule`, delete the stale 'Known remaining instance' sentence of architecture-invariants.md, and wrap the six long lines.

## Faults that the classification found

The classifiers and the implementers found faults that the audit does not hold:

- [x] **N-1** (Medium, Correctness) — omnet-julia and inet-julia
  `KeyDown(:enter)` names a key that no backend reports: the name of the key is `:return`. Write
  `:return` in omnet-julia `source/tool/record_precompile.jl:111` and in inet-julia
  `source/tool/repl/record/driver.jl:56`.
  *Test:* the two record scripts run, and the recorded trace holds the key.
  *Done:* omnet-julia c66d24a6, inet-julia bed5ad6. The record scripts were not run. The two statements that name `MSelectionDocument` are removed from the omnet-julia asset files (ecfbb8a2); inet-julia has none. test_kernel 3901 and 2 broken, test_substrate 86907 and the 8 known, test_mcp_tools 158, test_assistant_mvp 127 and 4 known, test_anthropic 38 and 1 broken, test_ollama 101, test_search_scale 45.
- [x] **N-4** (Medium, Correctness) — found in step 2.1
  `Sdl.jl` defines `map_reference_forward` and `map_reference_backward` for
  `GraphicsCanvasToImageFile` with no import, so they are new functions of ProjecturedSdl and
  do not extend the functions of the projection layer. Qualify them
  (`ProjectionModule.map_reference_forward(...) = ...`), as PAR-QUALIFIED-EXTENSION asks.
  *Test:* `ProjecturedSdl` has no own `map_reference_forward`, and `test_sdl()` passes.
  *Done:* lane A, c75569085. ProjecturedSdl binds no name `ProjectionModule`, so the methods name `ProjecturedKernel.ProjectionModule.map_reference_*`.
- [x] **N-5** (Medium, Correctness, Suspected) — found in step 2.4
  The undo of an element overwrite on a reactive `CellVector` can put back the new value:
  `get_slot_at` answers the slot cell, and `setindex!` writes the new value into that same cell,
  so the inverse holds a cell that already has the new value. First prove it with a run (an
  overwrite of one element of a reactive `CellVector`, then its inverse). If it holds, make the
  inverse keep the old value, not the cell, as `make_inverse_operation` promises.
  *Test:* `test_inversion()`: the inverse of an overwrite puts back the old value.
  *Done:* lane B, 0f0ccf25a. A run on the old code proved it: `CellVector(["a","b"])`, overwrite the second element with "z", apply the inverse, and it still read ["a","z"]. The inverse of one element keeps `parent[index]`, the value; a splice still keeps the slot cells.
- [x] **N-6** (High, Correctness) — found in step 3.9
  `play_live!` throws `UndefVarError` for `read!` on every call on Julia 1.13, because
  `EditorModule` and `Base` both export `read!` (L22-13 proved). So every live example of
  playback fails. Call `EditorModule.read!` by its qualified name in Playback.jl. The name of
  `read!` stays the decision of L22-13.
  *Test:* `test_playback()`: its `@test_broken` for this call becomes a `@test` and passes.
  *Done:* lane A, eb1c4ece9. test_kernel 3260 pass and 2 broken (644 checks of the corpus on M paths); test_substrate 86866 and the 7 known failures; test_mcp_tools 152; test_julia 407; test_json 194; test_xml 73.
- [x] **N-8** (Medium, Correctness) — found in step 6.1
  The SDL backend names `\` as `:backslash`, but `convert_web_key_to_symbol` answers `:char`, so
  Ctrl+\ can never fire in the browser. Name it `:backslash` in the web backend, as SDL does, and
  correct the comment and the docstring of Web.jl that say the two tables mirror each other.
  *Test:* `test_web_backend()`: the key `\` gives `:backslash`.
  *Done:* 4fae78eab, with PAR-BACKEND-SEAM, which named the difference. test_web_backend 101; test_kernel 3901 and 2 broken; test_mcp_tools 158; test_search_scale 45; the guards find nothing. Also corrected: fault.md, architecture-rules.md, the index row of PAR-STORE-THEN-DRAIN (0ee7362a0) and a history comment of WidgetToGraphics.jl (fd12c4dc0). **Still stale, outside the items:** division-terminology.md:78 names "base/visual" packages; architecture-rules.md:110-120 gives old paths and "twenty-eight" (package-rules.md says 29); CodeExecution.jl:102 names `PaneSplit`; the `@document_preset` docstring holds a history paragraph.
- [x] **N-9** (Medium, Correctness) — found by the review
  L11-3 made the matchers, the copy, the fold and the selection walk take either step layout, but
  `_write_slot!` (Operations.jl) and `_make_slot_inverse` (Inversion.jl) take only the C layout,
  so `ReplaceReferencedValueOperation(leaf, Reference(MFieldReferenceStep("value")), 2)` throws
  `MethodError`. Dispatch on the layout family, as L11-3 does.
  *Test:* `test_inversion()`: a write and its inverse through an `M…` step.
  *Done:* 957396802. The review found it. Also from the review (ed76c017d to 7e5b277d4): `@reference_step a.b` and `x...` raise again, as before L11-21 (a regression of L11-21); the way back of an overwrite with a cell puts the old slot back (N-5); the first exception of the loop or of its end goes on to the caller (L22-10); the test of a failing feed ends when the feed barrier regresses (L21-2); `drain_faults!` refuses a policy that is not a `FaultPolicy` (L01-10); the sentinel is `_NO_MATCH` (L11-23); and text and line fixes. test_kernel 3920 and 2 broken; the other suites at their counts.
- [x] **N-10** (Low, Correctness) — found by the fix of L22-10
  The `catch` of `make_editor` calls `quit_backend!`, which can hide the error of the build, as
  the end of `run_editor!` did before L22-10. Let the first exception go on, as L22-10 does.
  The fix of L22-10 has two costs: when the loop has thrown, an exception of a cleanup step is
  dropped and not recorded; after a normal quit, the exception of a step is thrown again from
  the `finally`, so its stack trace starts there.
  *Test:* `test_editor_inbox()`: a build that throws, and a `quit_backend!` that throws; the
  *Done:* 240e0a2dd. The quit runs inside its own `try`, and the build error goes on; the exception of the quit is dropped, as in L22-10. test_kernel 3922 and 2 broken.
  caller sees the build error.
- **N-2** (Medium, needs a decision): Ctrl+, (`KeyDownPattern(:comma)` in
  `source/platform/projection/generic/Focusing.jl:70`) can never fire, because `:comma` is in no key
  vocabulary and no backend names it. A new key name is a decision: see the table below.
- **N-3** (Low, outside the kernel): the argument guard also reports `Application.jl:631` and
  `TextMeasure.jl:223`. They ask the same question as L18-3 and L22-1.

## Not in this plan: the decisions of the owner

The 131 open questions stand in 12 groups, by the kind of decision. A group with a policy has its policy first: an answer to the policy settles the questions that point to it. In each group the main questions come first, then the others by severity.

Each question shows its options and my recommendation, marked **Recommended (mine)**. I prepared them on 2026-09-30, with five review agents, from the audit reports and the code on main at `2886cb86e`. A recommendation is advice: the decision is yours. Where the answer has a real cost or risk, a line **Risk** says so. The report of each finding in `kernel-audit/` holds the evidence.

| # | Group | Questions | Main question |
| ---: | --- | ---: | --- |
| 1 | [The rules (law and process)](#group-1) | 14 | POLICY-1; L01-8 |
| 2 | [Names that no rule fixes](#group-2) | 16 | — |
| 3 | [The rule of three positional arguments](#group-3) | 3 | POLICY-3 |
| 4 | [The public surface](#group-4) | 22 | POLICY-4 |
| 5 | [The reactive engine and the document model](#group-5) | 16 | L03-1, L03-2 |
| 6 | [Time bounds, the inbox and the loop](#group-6) | 11 | POLICY-6-time, POLICY-6-inbox; L20-1, L21-5 |
| 7 | [Many editors in one process](#group-7) | 7 | POLICY-7; L21-1 |
| 8 | [Caret and range semantics](#group-8) | 11 | L12-1, L11-8 |
| 9 | [Editing and fault semantics](#group-9) | 12 | L13-1, L01-1 |
| 10 | [Devices, keys and backends](#group-10) | 10 | L07-1 |
| 11 | [The scope of the kernel](#group-11) | 5 | POLICY-11; L11-10, L23-5 |
| 12 | [Measurements and tests](#group-12) | 4 | — |

### Group 1

**The rules (law and process)** (14 questions). What a PAR rule requires, and the rules of SEALING.md and of the file structure. POLICY-1, one rule for each catch-all arm, answers L01-8, L10-10, L11-5 and L18-10.

#### POLICY-1

- **A:** One rule for each catch-all arm in every layer: the arm asks is_passthrough_exception first and rethrows when it answers true. The law names each exception to this rule. The only exception that this file proposes is the model code of the code tool (L18-10).
- **B:** Each layer decides for its own arms, and the law lists each layer that catches an exception that means stop.
- **Recommended (mine): A.** The seam is in layer 1 (FaultInterface.jl), so every layer can ask it with no new dependency. The barrier, the inbox and the agent loop already ask it (FaultBarrier.jl:56, FaultBarriers.jl:114, Inbox.jl:110, AgentLoop.jl:92). A catch-all arm that does not ask it loses a Ctrl+C of the person, as L01-8, L10-10, L11-5 and L18-10 show in four layers.
- **Decided by the owner, 2026-09-30: A.** The permission for the sealed files of the fault layer is asked when the work starts.
- Settles: L01-8, L10-10, L11-5, L18-10.
- Cost: S for each arm. The three sealed files of the fault layer need permission (L01-8). The other arms are in files that are not sealed.

**L01-8** (Low, main question): Which sentence of PAR-REPORT-NEVER-THROWS wins in the report path: 'a report never throws' or 'an exception that means stop is never caught'?

- **A:** The pass-through sentence wins. Each catch arm of the report path (about ten arms in FaultCascade.jl, FaultStore.jl and FaultRecord.jl) rethrows when is_passthrough_exception answers true. The law says that 'a report never throws' is about an ordinary exception.
- **B:** 'A report never throws' wins. The arms stay as they are, and the law states that the report path also catches an exception that means stop.
- **Recommended (mine): A.** Each sentence has its own purpose. 'Never throws' keeps one broken frame from a dead editor. An exception that means stop asks for a stopped editor, so to let it pass does not break the first purpose. An InterruptException that arrives while the frame writes a console line is a Ctrl+C of the person, and B loses it. The seam is in the same layer, so the change adds no import.
- **Decided by the owner, 2026-09-30: A**, by POLICY-1.
- Settles: L10-10, L11-5, L18-10.
- Cost: S. Three sealed files need permission: FaultCascade.jl, FaultStore.jl, FaultRecord.jl. One sentence of PAR-REPORT-NEVER-THROWS. One test for each kind of arm (the cascade, the drain, the format).

**L01-5** (Medium): Tests reach `make_editor`, which catches by default: must these tests pass the strict policy, or does the second half of PAR-REPORT-NEVER-THROWS change?

- **A:** Keep the tolerant default of make_editor (the plan of 2026-09-23). The law names Editor(…) as the strict entry of a test, in place of 'wherever a test can reach it'. The three tests that call make_editor with its default pass make_strict_fault_policy().
- **B:** Make every default strict: the kernel and screen forms of make_editor and the one-call run_editor!(backend, …) take make_strict_fault_policy(). Each program that a person starts passes FaultPolicy() on purpose. The requirement sentence of the law stays as it is.
- **C:** Keep the default and the law. The tests stay tolerant, and each test that calls make_editor asserts at its end that the fault store of its editor is empty.
- **Recommended (mine): B.** The law gives its own reason: a barrier that is on under test turns a real bug into a passing run. With B, a forgotten keyword gives a loud failure: a program stops at its first fault. With A or C, a forgotten keyword in a new test gives a silent pass. The tolerant default was safe on run_editor!, because no test called it (plan/done/the-editor-survives-a-fault.md, step 1). make_editor took that default, and tests call make_editor now (ApplicationTest.jl:445, ReferencedDocumentEditorTest.jl:14, WaitTest.jl:230).
- **Decided by the owner, 2026-09-30: B.**
- Cost: M for B. The defaults in EditorLoop.jl and WindowScene.jl. About 12 call sites that a person starts (some in docstring examples) get fault_policy = FaultPolicy(): Application.jl, Gallery.jl (2), FaultLogOverlay.jl, WindowChrome.jl, ApplicationVideo.jl, two tool/video scripts; omnet-julia CampaignWindow.jl and QtenvWindowScene.jl; inet-julia example/watch/mac_fsm_sdl.jl. fault.md, editor.md, the Editor docstring and one sentence of the law. No sealed file. A is S: three test files and the law text.
- **Risk:** Every program that a person starts must pass `FaultPolicy()` on purpose; a program that forgets stops at its first fault.

**L10-10** (Medium): Does the walk rethrow the exceptions that mean stop from a predicate, although its docstring says that an exception from the predicate counts as no match?

- **A:** Rethrow an exception that means stop. An ordinary exception from the predicate still counts as no match. The docstring says both.
- **B:** Rethrow an exception that means stop, and let an ordinary exception from the predicate go to the caller (no catch).
- **C:** Keep the catch-all arm and state an exception to PAR-REPORT-NEVER-THROWS.
- **Recommended (mine): A.** The walk visits objects of every type, so a predicate that reads a field of one type throws on the others. 'Counts as no match' is what makes such a predicate usable, and search_documents gives it to the model. An interrupt or a stack overflow is not a fault of the predicate. is_passthrough_exception is in layer 1, below the document layer.
- POLICY-1 (A) leaves out C: A or B remains.
- **Decided by the owner, 2026-09-30: A, with a keyword.** `walk_document` takes `on_error`, a function `(object, exception) -> Bool` that runs when the predicate throws an ordinary exception; its answer is the match of that object. The default `(object, exception) -> false` keeps "counts as no match"; `on_error = (object, exception) -> throw(exception)` gives option B. An exception that means stop goes through first and never reaches `on_error`, as everywhere under POLICY-1. `search_documents` and `search_references` pass the keyword on. The owner allows the docstring of `search_references` in the sealed `ReferenceSearch.jl` to name it.
- Depends on: L01-8.
- Cost: S. DocumentWalk.jl and DocumentModule.jl (using ..FaultModule). Both files are not sealed now (SEALING.md). One test: a predicate that throws InterruptException ends the walk.

**L10-13 (part)** (Medium): Does PAR-NO-NESTED-CELL keep its `MethodError` for a nested cell, so that the code changes, or does the rule text say that a cell of any type passes through as the cell of the field?

- **A:** The rule text follows the code: a cell of any type passes through as the cell of the field. The reactive layout checks no declared type. The kind layouts (`ImmutableCell`, `MutableCell`) check a raw value and a write against the declared type.
- **B:** The code follows the rule in part: the constructor throws when a passed cell can not hold the declared type (a ReactiveCell{String} into a field of Int), and lets a ReactiveCell{Any} through.
- **C:** The code follows the rule text: only a cell of the cell type of the field passes, so each Cell(x) that the machinery makes must carry its type.
- **Recommended (mine): A.** The loose bound is a written design (DocumentMacro.jl:96-99): the machinery makes an untyped Cell(x), a ReactiveCell{Any}, and stores it in typed fields. The owner holds that a reactive cell stores Any and that a read narrows to the declared type. C breaks that machinery. B adds a check that a later write to the same Any cell does not make anyway.
- **Decided by the owner, 2026-09-30: A, for now.** The law states what the code does today. An example on main showed the facts:
  - `Person` (the reactive layout): a raw `"thirty"`, `Cell("thirty")`, `ReactiveCell{String}("thirty")` and the write `q.age = "thirty"` into `age::Int` all give `"thirty"`.
  - `MCPerson` and `ICPerson` (the kind layouts): a raw `"thirty"` throws `MethodError`, and so does the write `m.age = "thirty"`. `Cell("thirty")` and `MutableCell{String}("thirty")` pass and give `"thirty"`.
  - The new text of the rule: "A cell that a constructor gets becomes the cell of the field, whatever type of value it holds. The declared type of a field is the type that the field holds at rest. The reactive layout does not enforce it, because an edit passes through intermediate values, such as a text to parse or a document of another domain that a projection gives meaning to. The kind layouts (`ImmutableCell`, `MutableCell`) check a raw value and a write against the declared type."
  - The owner wants strict types later, with a boundary type for each intermediate state. That is its own plan: [strict-document-types.md](strict-document-types.md). When it lands, this rule changes again.
- Cost: S. PAR-NO-NESTED-CELL in architecture-invariants.md, one sentence. No code.

**L11-17** (Medium): For the names that the pane window declares to the assistant (`@reference`, DocumentLocator, get_parent, get_edited_document), does the Use-it-to rule (an example that runs in the window) win over PAR-NO-CONSUMER-DOCS in a kernel docstring?

- **A:** PAR-NO-CONSUMER-DOCS wins in a kernel file. The Example of a kernel docstring uses kernel names only. The package that declares the name to a window (the pane package) shows the call in the window, in its own docstrings or guide. code-quality-rules.md §1 says this in one sentence.
- **B:** The Use-it-to rule wins for a declared name: a kernel docstring may show a call in the window, as a stated exception to PAR-NO-CONSUMER-DOCS.
- **Recommended (mine): A.** PAR-NO-CONSUMER-DOCS is an architecture invariant, and more than one window can declare the same kernel name, so an example of the pane window is wrong for another window. The pane package declares these names (PaneProgram.jl:99-101) and its docstrings already name them (PaneProgram.jl:298, :953), so a search finds a window example there. A kernel example still shows the model the shape of the call.
- **Decided by the owner, 2026-09-30: A.** PAR-NO-CONSUMER-DOCS wins in a kernel file. The pane package shows the calls in the window.
- Cost: S to M. ReferenceBuilder.jl, ReferencedDocument.jl, ReferenceEvaluation.jl, ReferenceModule.jl and ReferenceStep.jl (not sealed). ReferenceInterface.jl and ReferenceSearch.jl are sealed and need permission. The pane docstrings or a pane guide take the window examples. code-quality-rules.md §1, one sentence.

**L11-5** (Medium): Do `try_evaluate_reference`, `get_valid_reference_prefix` and `annotate_reference_types` rethrow the exceptions that mean stop and a missing step method, although `try_evaluate_reference` promises a default instead of a throw?

- **A:** Rethrow an exception that means stop. Answer the default for every other exception.
- **B:** Rethrow an exception that means stop, and a MethodError whose function is evaluate_reference_step itself (a step type with no method). Answer the default for every other exception. The docstring of try_evaluate_reference says so.
- **C:** Keep the catch-all arms and state the exception in the law.
- **Recommended (mine): B.** Every method of evaluate_reference_step takes an untyped document (ReferenceStep.jl, ProjectionReferenceStep.jl, and the steps of the text, graphics, chart and focus packages). So a MethodError of that function comes only from a step type with no method, which is a fault of the program and not a path that does not resolve. A stale path throws other errors (BoundsError, a field that does not exist, ReferenceTypeMismatchException), and those still give the default. The promise of the docstring is for a path that does not resolve, so B keeps the promise and corrects its words.
- POLICY-1 (A) leaves out C: A or B remains.
- Depends on: L01-8.
- **Decided by the owner, 2026-09-30: B.**
- Cost: S. ReferenceEvaluation.jl and ReferenceModule.jl (not sealed). Tests of the three walkers.

**L13-8** (Medium): Does one pair (operation_reference, retarget_operation) register a new path-bearing operation, which changes the meaning of PAR-REGISTER-NEW-OPERATION?

- **A:** One pair registers an operation that carries a path: the catch-all reroot_operation retargets through operation_reference and retarget_operation when the operation reports a reference. The law, the comment of Rerooting.jl and operation.md say so. The methods of reroot_operation for single types in the primitive and text packages go.
- **B:** Keep three methods (reroot_operation and the pair), and correct the law so that it names all three.
- **Recommended (mine): A.** The default read_intent already reaches an operation of a higher package only through the pair (ProjectionDefaults.jl:178-187). The second paragraph of the same rule already lets a wrapper register once through two generics. ReplaceTextRangeOperation shows how three methods fail: it has only reroot_operation (TextDocument.jl:1176), so the default reader drops it with no error.
- **Decided by the owner, 2026-09-30: A.**
- Cost: S. Rerooting.jl (not sealed); PrimitiveDocument.jl (two methods go); TextDocument.jl (add the pair, remove the reroot method); architecture-invariants.md; operation.md. CollectedIntentsOperation keeps its own method.

**L18-10** (Medium): Does execute_julia_code let the pass-through exceptions pass, or turn an interrupt of model code into an answer as a stated exception to PAR-REPORT-NEVER-THROWS?

- **A:** Every pass-through exception passes: each catch of the tool layer rethrows first. A Ctrl+C in model code then ends the editor loop.
- **B:** A stated exception for an interrupt only: an InterruptException raised in model code ends that call, and its text is the answer. A quit, a stack overflow and an out-of-memory error pass.
- **C:** The code tool acts as the Julia REPL: an exception raised in model code is the answer of the call, also an interrupt and a stack overflow. A QuitEditorException and an OutOfMemoryError pass. The law states the exception.
- **Recommended (mine): C.** The code tool is a REPL for the model. In the Julia REPL and in a notebook kernel, an interrupt ends the evaluation and the session goes on, and a stack overflow of user code is an error message. With A, an endless loop or a deep recursion that the model wrote ends the whole editor. A quit is a request to stop, and a heap that ran out is a state that the call can not repair, so both pass. In every option, _notify_evaluation and the arms of MeaningSearch.jl rethrow each pass-through exception, because they run no model code.
- POLICY-1 (A) makes this the one exception that the law can name: A, B or C remains.
- **Decided by the owner, 2026-09-30: C.** It is the one exception to POLICY-1 that the law names.
- Depends on: L01-8, L18-9, L20-2.
- Cost: S. ToolModule.jl (using ..FaultModule), CodeExecution.jl, MeaningSearch.jl (not sealed). One sentence of PAR-REPORT-NEVER-THROWS. test_code_execution: an interrupt sent into a long evaluation gives an answer, and a QuitEditorException passes.
- **Risk:** Option C is wider than the question: B lets only an interrupt of model code become the answer.

**L01-17** (Low): The count of the fault store grows at each write: which property qualifies a collector for the carve-out of PAR-NO-WRITE-IN-THUNK?

- **A:** Name the properties that the store has: no cell depends on it, and no computation reads it. A count in it may then grow at each run. Reword the carve-outs of PAR-NO-WRITE-IN-THUNK and PAR-PURE-THUNK to match.
- **B:** Keep 'idempotent' and make the write idempotent: a second run of one computation must not add to the count. The store has no run identity for this, so it is a new mechanism.
- **C:** Keep 'idempotent' for the record, and state that the count is a statistic that can count a second run of one computation.
- **Recommended (mine): A.** The sealed FaultStore docstring already names the two properties that make the write safe: the store has no dependents, so a write invalidates nothing, and the answer of the computation does not depend on the store. The count reaches a person only through the drain, outside every computation. So the law is wrong, not the code. The key keeps the store small (the capacity counts keys); it does not keep the cache right.
- **Decided by the owner, 2026-09-30: A.**
- Cost: S. architecture-invariants.md, the two carve-out paragraphs. No sealed file, because the FaultStore docstring already says the same.

**L11-25** (Low): Does PAR-ONE-BASED-INDEXING name the 0-based index of `ref"…"`, which reference-pattern-vocabulary.md step 9 decided, as an exception?

- **A:** Yes. PAR-ONE-BASED-INDEXING states the rule of the boundary: a string in the syntax of an outside format keeps the count of that format, and its parser converts to the 1-based count at the boundary. ref"…" is the spelling of a configuration key, and such a key counts from 0.
- **B:** No exception. ref"…" becomes 1-based as @reference is, and the reader of a configuration file converts the index itself.
- **Recommended (mine): A.** The owner decided the shift in step 9 of plan/done/reference-pattern-vocabulary.md, and the law must say what the code does (PAR-HONEST-DOCS). The shift is at a boundary between two counts, where the rule already asks for an explicit conversion. B reverses a recorded decision and moves the conversion into the configuration reader of omnet-julia.
- **D (the owner's correction):** The string spelling is 1-based by default, as `@reference` is. `parse_reference_pattern(text; first_index = 1)` takes the first index of the text as a keyword (the name `first_index` is my proposal), and the string macro is always 1-based. The INI reader of omnet-julia (IniConfiguration.jl:200) and the two trim-routing tools (tool/trim-routing/entry.jl:244, entry_parallel.jl:148) pass `first_index = 0`. PAR-ONE-BASED-INDEXING gets no exception, only one sentence: a parser of an outside format takes the first index of that format as a keyword, with the default 1, and converts at the boundary.
- **Decided by the owner, 2026-09-30: D.** The owner first chose A, then corrected it: "the ref"" syntax comes from omnet, it should not use a different indexing mechanism by default, it's ok to have a parameter in the parser so omnet can use it". This reverses the default of step 9 of plan/done/reference-pattern-vocabulary.md, which keeps its history.
- Cost of D: S to M. ReferencePatternString.jl (`_pattern_index_value` shifts only by the keyword; the header comment and the docstring), the arms that read a string pattern (ReferenceCase.jl:529, ReferenceRules.jl:837) stay 1-based, ReferenceRulesTest.jl (the string patterns with an index change their numbers), omnet-julia IniConfiguration.jl and the two tools. No sealed file.
- Depends on: L11-10, L11-24.
- Cost: S. One sentence in architecture-invariants.md. No code.

**L14-6** (Low): Does a module with one fragment keep its code in the module file (four kernel modules, two sealed), or does system-anatomy.md drop that rule?

- **A:** The module file of a module with one fragment holds the code. Merge Intent.jl, Clock.jl, GestureRecognizer.jl and Playback.jl into their module files, and change code-quality-rules.md §1.
- **B:** system-anatomy.md drops the sentence. Every module file holds only the head and __init__, as code-quality-rules.md §1 says.
- **Recommended (mine): B.** code-quality-rules.md §1 says that a module file 'holds no other code', and all 78 *Module.jl files under source/ keep only the head and __init__. Seven of them include one fragment, four in the kernel. No file follows the sentence of system-anatomy.md, which also counts 15 kernel head files where the kernel has 23.
- **Decided by the owner, 2026-09-30: B.** Fact after the merge of gesture-type (2026-10-01): `GestureRecognizerModule.jl` and `GestureRecognizer.jl` are gone, so option A had one module less; the decision stands.
- Cost: S. system-anatomy.md only. No sealed file and no change of SEALING.md. A would change four sealed files (ClockModule.jl, Clock.jl, GestureRecognizerModule.jl, GestureRecognizer.jl) and remove lines of SEALING.md (see L17-16).

**L17-15** (Low): Does PAR-NO-WRITE-IN-THUNK get a carve-out for the fresh cells that a nested template walk writes inside the computation of its parent?

- **A:** Carve-out: a computation may write a cell that the same run made, before it hands the cell out, and it reads such a cell only with peek. The template walk reads the blueprint with peek, so the cell has no dependent at the write.
- **B:** No carve-out: the template walk builds each output node with its final values (a new node through its wrapper) and writes no cell inside a computation.
- **C:** Carve-out in the text only, with no change of the code.
- **Recommended (mine): A.** The write completes the construction of a node that no cell reads yet. With peek it invalidates nothing, which is the one harm that the rule prevents. B rewrites the patch steps of ProjectionTemplate.jl (1516 lines, seven setproperty! calls). C keeps the edge from a fresh cell to the parent computation that the report found.
- **Decided by the owner, 2026-09-30: A.** The words follow L01-17: a new cell with no dependent and no tracked reader.
- Depends on: L01-17.
- Cost: S. ProjectionTemplate.jl (not sealed): the tracked reads of the blueprint become peek (_carries_marker, the _find_ helpers, the children computation of the inline print). architecture-invariants.md, one paragraph. The suites of the template users: test_julia, test_math, test_fsm, test_process, test_substrate.
- **Risk:** The carve-out does not cover the rerun of nested thunk child lists that step 1.4 recorded.

**L17-16** (Low): May `ChildrenContainer.jl`, an empty fragment, be deleted, which removes its line from SEALING.md?

- **A:** Delete ChildrenContainer.jl, its include and its line in SEALING.md. Add one sentence to the conventions of SEALING.md: the line of a deleted file goes out in the commit that deletes the file. The conventions do not say this today; they say only "Do not remove entries or reorder the list."
- **B:** Keep the empty file with its header that says that it holds no code (the state after 5c9270493).
- **C:** Give the file content: a default method of the children-container seam, if L17-17 gives the seam one.
- **Recommended (mine): A.** SEALING.md is the ordered inventory of source/kernel/ in load order, and the include order of ProjecturedKernel.jl is the authority. A line for a file that does not exist makes the inventory false. The rule 'do not remove entries' keeps the audit order of files that exist. The file is not sealed, and PAR-PROJECTION-PLACEMENT says that no orphan shapes the structure.
- **Decided by the owner, 2026-09-30: A**, with the new sentence in the conventions of SEALING.md.
- Settles: L14-6, L11-10, L23-5.
- Cost: S. ChildrenContainer.jl, ProjectionModule.jl (the include and the fragment table), ProjectionInterface.jl (the banner), SEALING.md (one line and one sentence of the conventions). No sealed file.

**L18-27** (Low): Does the text of PAR-AI-SAME-GUARANTEES state the exception that D22 accepted?

- **A:** Yes. The rule states the accepted exception: the code tool runs any code with the editor bound, so a direct write stays possible. The editor discourages it, and the tool tells the model that such a write gets no undo, no check and no transform.
- **B:** No exception: the code tool refuses a direct write, so that the rule holds as it is written.
- **Recommended (mine): A.** The owner accepted the direct write on 2026-09-26 (D22 of plan/pending/the-assistant-reaches-a-referenced-document.md), and the law must say what is true (PAR-HONEST-DOCS). B reverses that decision and needs a new mechanism (a guard on writes).
- **Decided by the owner, 2026-09-30: A.** The paragraph also names the Julia function `execute_julia_code!`; the tool name stays `execute_julia_code`.
- Cost: S. architecture-invariants.md, one paragraph. No code.

### Group 2

**Names that no rule fixes** (16 questions). A name for each item that the naming rules do not fix. Each question proposes one name, checked against naming-rules.md and against the names of the three repositories. Decide these together: L02-5 with L22-27, L13-15 with L14-2, L15-12 with L17-21, and L06-10 with the three splits.

**L12-3** (Medium): What replaces with_selection and @with_selection, which change their argument although with_<stem> means a copy?

- **A:** `set_selection!` returns its document. `with_selection` goes, and its callers call `set_selection!`. The macro becomes `@selected`, for example `@selected JsonString("") value{0}`.
- **B:** Add a `!`: `with_selection!` and `@with_selection!`. The change of the argument shows, but `with_` still means a copy.
- **C:** Make `with_selection` a true copy: copy the document, then select in the copy.
- **D:** Keep the names. The macro refuses a symbol as its first argument, so it always selects in a new document. The function goes.
- **Recommended (mine): A.** `set_selection!` is already the writer for 'a document that nothing holds yet' (PAR-REPLACE-SELECTION), and that is the construct-and-select case. It only needs to return the document, and a mutating function that returns its subject is a Julia habit (`push!`). C adds a copy of cells to each insertion literal for no reader. `@selected` is a declarative word, as the rules ask of a macro: 'this document, selected at this path'. I checked: `@selected` is free.
- **Decided by the owner, 2026-09-30: A.** The permission for the three sealed files of the selection layer is asked when the work starts.
- Cost: M. Sealed (permission needed): SelectionInterface.jl, SelectionDefaults.jl, SelectionModule.jl. projectured-julia: `with_selection` 41 uses in 15 code files, `@with_selection` 46 uses in 12 files (JsonDocument.jl, YamlDocument.jl, FsmDocument.jl, XmlDocument.jl, ProcessDocument.jl, Domain.jl, JuliaInsertionToSyntax.jl and others). SelectionTest.jl:51 asserts `with_selection(leaf, path) === leaf`. naming-rules.md removes `with_selection` from its example list of derived copies. No use in omnet-julia or inet-julia.

**L13-9** (Medium): Do the builders get make_ names, and do the builders (0-based) and the editor verbs (1-based) keep two count bases?

- **A:** Rename the builders to `make_insert_elements_operation`, `make_delete_elements_operation` and `make_replace_document_operation`. The two element builders take the 1-based element index of the editor verbs, and convert it to the 0-based boundary of their `RangeReferenceStep`.
- **B:** Rename the builders as in A, but keep the 0-based index, and name the argument `boundary`.
- **C:** Keep the names and the two bases. Correct only the docstrings.
- **Recommended (mine): A.** PAR-ONE-BASED-INDEXING says that elements are 1-based and boundaries 0-based, and the builders take the index of an element: the first to delete, or the place of the first new one. 12 of the 17 calls in source/ subtract 1 before the call (PaneSurgery.jl 6, ChartDocument.jl 3, TextDocument.jl 2, VersioningToAny.jl 1). Domain.jl builds `ElementReferenceStep(n + 1)` and passes `n` to the builder in the same function, and ClipboardCollectionToAny.jl keeps a helper only to make a 0-based index. The builders return an operation, and `make_` is the verb for a new object. When the base and the name change in one step, no call keeps the old base under the old name. I checked: the three new names are free.
- **Decided by the owner, 2026-09-30: A.**
- Cost: M. projectured-julia: `insert_elements` 20 uses in 11 code files, `delete_elements` 22 in 11, `replace_document` 32 in 11. Each call of an element builder needs a check of its index. omnet-julia: no call of the builders (1 call of `insert_elements!`, which does not change; text in 2 plans). inet-julia: none. No sealed file. Prose: PAR-PREFER-REPLACE-VALUE in architecture-invariants.md, operation.md.

**L14-2** (Medium): Does CollectedIntentsOperation get a verb-first name, or a second structural exception in naming-rules.md?

- **A:** Keep the name, as a member of the class of structural operations that L13-15 writes into naming-rules.md.
- **B:** Rename it to a verb-first phrase, for example `CarryIntentsOperation` or `OfferIntentsOperation`.
- **C:** Name it alone as a second exception in naming-rules.md.
- **Recommended (mine): A.** Its evaluation does nothing: it is a carrier, and its docstring takes `CompoundOperation` as its model. It is the answer to the payload `CollectIntents`, which is a verb-first request, and 'collected intents' reads as the answer to 'collect intents'. A verb-first name reads as a second request and claims an action that the evaluation does not do.
- **Decided by the owner, 2026-09-30: A**, with L13-15.
- Depends on: L13-15.
- Cost: S for A: text in naming-rules.md only. B: M (41 uses in 16 code files of projectured-julia, operation.md, system-anatomy.md; no use in omnet-julia or inet-julia).

**L22-13** (Medium): Does the read stage get a new name, or become a method of `Base.read!`?

- **A:** Rename the stage to `read_input!(editor)`.
- **B:** Make the stage a method of `Base.read!` (`Base.read!(editor::Editor)`), and export no own `read!`.
- **C:** Keep the name, but stop its export. Callers write `EditorModule.read!`.
- **Recommended (mine): A.** The clash is real: N-6 showed that `play_live!` threw `UndefVarError` on Julia 1.13, because `EditorModule` and `Base` both export `read!`. `Base.read!` reads binary data from a stream into an array, so a method for an Editor (B) gives one function two meanings. `read_input!` keeps the verb of the read-evaluate-print loop and names the unit that flows in, as the protocol names do. `evaluate!` and `print!` do not clash, so they stay. I checked: only a local function in a test uses `read_input`, and `read_input!` is free.
- **D (the owner's request for one scheme):** Name the three stages as one family under `run_frame!`: `run_read_stage!`, `run_evaluate_stage!`, `run_print_stage!`. The verbs read, evaluate and print stay in the names. The verb table of naming-rules.md gets the row "`run_` — it runs a unit of work: a loop, a frame, a stage or a barrier", which `run_editor!`, `run_frame!`, `run_fault_barrier!` and `run_on_editor_task!` already use. The scheme 'verb + the unit that flows in' (`read_input!`, `evaluate_operation!`, `print_document!`) was set aside: `f!` reads as the in-place form of `f`, and `evaluate_operation` and `print_document` already exist with other contracts.
- **Decided by the owner, 2026-09-30: D.** "These names sound good, consistent and meaningful."
- Cost of D: M. projectured-julia: about 60 code uses (`read!` 18, `evaluate!` 17, `print!` 25) in EditorModule.jl (the export), EditorLoop.jl, ReadEvaluatePrint.jl, Playback.jl, PerformanceCounter.jl, FaultBarrier.jl, tool/precompile/recording-driver.jl and the tests; about 9 guides. omnet-julia: 14 uses in 3 files (source/tool/record_precompile.jl, demo/catalog/notebook_drive.jl, test/proof/risk/RISK-STARTUP-LATENCY/ui_window.jl). inet-julia: 6 uses in source/tool/repl/record/driver.jl. No sealed file. The names are free in the three repositories.
- Cost: S. 18 code uses in 8 files: EditorModule.jl (the export), EditorLoop.jl, ReadEvaluatePrint.jl, Playback.jl (its qualified call from N-6 goes), EscapeQuitTest.jl, FaultBarriersTest.jl, ConsoleBackendTest.jl, and the import in package/ProjecturedPlatformTest. About 15 mentions in comments and docstrings (Sdl.jl, VideoBackend.jl, Inbox.jl, Feeds.jl, EditorLoop.jl, PlaybackModule.jl, FrameDrainTest.jl, FaultSafeModeTest.jl, WaitWakeTest.jl); editor.md. naming-rules.md needs no change: its sentence on the verbs read, evaluate and print stays true, and `read_input!` follows its rule 'verb + the unit that flows in'. omnet-julia and inet-julia do not call it. No sealed file.

**L02-5** (Low): Which verb-first name replaces `with_performance_counters`, which binds a scope and makes no copy?

- **A:** Rename it to `run_with_performance_counters(f)`. The verb says that the function runs `f`.
- **B:** Rename it to `measure_performance(f)`. The verb is in the verb table, but the function returns the value of `f`, not a measure.
- **C:** Keep the name, and write it in naming-rules.md as an exception to the `with_<stem>` rule.
- **Recommended (mine): A.** The function binds a scope and runs `f`. It makes no copy, so `with_` does not apply. The repository already uses this shape: `run_with_window_tools(run)` in the shell package, and the fault plan chose `run_fault_barrier!` over `with_fault_barrier` for the same reason. The name takes no `!`, because the function changes no state outside the new store. I checked: no name `run_with_performance_counters` exists in the three repositories.
- **Decided by the owner, 2026-09-30: A.** The name uses the `run_` row of the verb table from L22-13. The permission for the two sealed files of the performance layer is asked when the work starts.
- Settles: L22-27.
- Cost: S. 17 uses in 6 code files of projectured-julia: EditorLoop.jl, 3 test files and the two sealed files PerformanceCounter.jl and PerformanceModule.jl (permission needed). No code use in omnet-julia or inet-julia (1 plan text in omnet-julia). Prose: cell.md, editor.md, system-anatomy.md, architecture-invariants.md, plan/pending/font-zoom-per-editor.md.

**L03-10** (Low): Which `make_` name replaces `copy_cell_as`?

- **A:** `make_similar_cell(c, v)`. It follows the Julia word `similar`, which makes a new object of the same kind with other contents.
- **B:** `make_same_kind_cell(c, v)`. It names the kept property, but it reads less well.
- **C:** `make_cell_like(c, v)`. It reads well, but it ends in a preposition, which the rules drop.
- **Recommended (mine): A.** The function makes a new cell with the kind and the value type of `c`. It copies neither the value nor the computation of `c`. `make_` is the verb for a new object, and the word for the thing made (`cell`) goes last. `similar` is the Julia word for this relation (`similar(array)`), so a Julia reader can guess the name. I checked: the name is free.
- **Decided by the owner, 2026-09-30: A.** The permission for the three sealed files of the cell layer is asked when the work starts.
- Cost: S. 23 uses in 8 code files of projectured-julia. Sealed (permission needed): CellInterface.jl, CellDefaults.jl, CellModule.jl. Other files: DocumentDefaults.jl, DocumentCopy.jl, CellVector.jl, FileCut.jl, CellTest.jl; prose in cell.md. No use in omnet-julia or inet-julia.

**L06-10** (Low): Do you want EventPattern.jl (521 lines) split into two fragments now, and what is the name of the new fragment?

- **A:** Split now. `EventPattern.jl` keeps the reified pattern and its text. A new fragment `EventCase.jl` takes the parser and `@event_case`.
- **B:** Split now, but name the new fragment `EventPatternParser.jl` (for the parser that `@gestures` also uses), and rename `EventCaseTest.jl` to match it.
- **C:** Split when the event layer changes next (the chord pattern of plan/pending/key-chords-from-bindings.md adds to this file).
- **D:** Keep one file, and write an exception to the budget of 500 lines.
- **Recommended (mine): A.** The file has 540 lines now (the fixes added 19), and its two parts serve two kinds of reader. `EventCase.jl` holds `@event_case` as `ReferenceCase.jl` holds `@reference_case` in the reference layer. The test file `EventCaseTest.jl` then names a real file; step 4.6 of the fixes plan held the rename of that test for this decision. A move with no other change is easy to review while the audit is fresh, and the next change of the layer (a chord pattern) makes the file larger. I checked: no file `EventCase.jl` exists.
- **Decided by the owner, 2026-09-30: D, and the rule is relaxed.** "The rule should be relaxed, don't split unless there's a good boundary." EventPattern.jl stays one file. code-quality-rules.md §5 changes: 500 lines is a reason to look for a boundary, not a limit. Split a file only at a good boundary, a part with its own concept and its own readers and a small interface to the rest; where no such boundary exists, the file stays whole. The sentence "Do not sweep them. When you next work in one, take one section out into its own fragment" goes. The budget of 60 lines for a function does not change.
  - Consequence: `EventCaseTest.jl` tests `EventPattern.jl`, so the rule of test names (`<Thing>Test.jl`, naming-rules.md) makes it `EventPatternTest.jl`. The rename that step 4.6 held for this decision can go ahead.
  - Fact after the merge of gesture-type (2026-10-01): `EventPattern.jl` is now `source/kernel/gesture/GesturePattern.jl` (551 lines, not sealed), and its test is `test/kernel/gesture/GestureCaseTest.jl`. The decision stands for the new file, and the test-name rule makes the test `GesturePatternTest.jl`.
  - The scheme of fragment names (`<Concept><Part>.jl`) is not decided. A split at a good boundary names its fragment when it happens.
- Settles: L10-21, L17-19, L18-23 (parts).
- Cost: S. Sealed (permission needed): EventPattern.jl and EventModule.jl (the include list). No name changes, so no caller changes. Prose that names EventPattern.jl for the parser: event.md and the header comment of binding/Gestures.jl.

**L06-12** (Low): Does describe_event_pattern take the verb format_, which the verb table gives for a function that makes text?

- **A:** Rename it to `format_event_pattern`, as the verb table gives for a function that makes text.
- **B:** Rename all 10 `describe_` functions (`describe_operation`, `describe_document`, `describe_value`, `describe_gesture` and the others) to `format_`.
- **C:** Keep `describe_event_pattern`, and add a row for `describe_` to the verb table: it makes words for a person that say what a thing is or does. `format_` stays for a value in a fixed text form (`format_tick`).
- **Recommended (mine): C.** `describe_` is an established family of 10 functions: 168 uses in 32 code files here and 42 uses in 10 files of omnet-julia. A splits the family, and B is a large change for a name that reads as English. The rules say that English wins where a rule gives a phrase that nobody says: a person describes an operation and formats a number. The text of these functions ('Ctrl+x', 'zoom in') is a description for a person, not a format.
- **Decided by the owner, 2026-09-30: C.** The row: `describe_` makes words for a person that say what a thing is or does; `format_` puts the fields of a thing into a fixed text form (`format_tick`, `format_fault_label`). Fact after the merge of gesture-type (2026-10-01): the function is now `describe_gesture_pattern` in the gesture layer; the decision stands.
- Cost: S for C: one row in naming-rules.md and no code change. A: S (13 uses in 8 files; sealed EventPattern.jl and EventModule.jl). B: L (168 uses in 32 files here and 42 in 10 files of omnet-julia).

**L09-15** (Low): Do the four backend generics with an external effect take a !, and which name does read_from_devices take?

- **A:** All four take a `!`: `take_from_devices!`, `write_to_devices!`, `write_image!`, `record_video!`.
- **B:** Keep the verb `read`: `read_from_devices!`, `write_to_devices!`, `write_image!`, `record_video!`.
- **C:** Only the two device generics take a `!`. The two file writers keep their names, as Base `write` does.
- **D:** Keep the four names, and write the exception in naming-rules.md.
- **Recommended (mine): A.** The rule is explicit: 'An external side effect takes `!`', and a function that consumes a queue is a `pop_` or a `take_`. `read_from_devices` takes the event out of the queue of the backend: SDL clears `pending_input`, the web backend calls `take!`, the headless backend calls `popfirst!`. `take_from_devices!` keeps the pair with `write_to_devices!`, and `take` is the Julia word for a removal from a queue. L18-25 applied the same rule (`execute_julia_code!`). `render_canvas` and `decode_image` change nothing outside, so they keep their names. I checked: the four new names are free.
- **Decided by the owner, 2026-09-30: A.** If L09-3 takes its option C (the file writers leave the kernel under new names), only the two device generics are renamed here. The permission for the three sealed files of the backend layer is asked when the work starts.
- Depends on: L09-3.
- Cost: L by breadth, but mechanical with workspace/bin/julia-rename.jl. projectured-julia: `read_from_devices` 88 uses in 20 code files, `write_to_devices` 55 in 21, `write_image` 46 in 18, `record_video` 52 in 17. omnet-julia: 1, 1, 9 (7 files) and 2 uses. inet-julia: only the precompile asset. Sealed (permission needed): BackendInterface.jl, BackendModule.jl, BackendDefaults.jl. PAR-BACKEND-SEAM names two of them. The precompile assets of the three repositories take the new names at their next record.

**L10-21, L17-19, L18-23 (parts)** (Low): May `DocumentMacro.jl`, `ProjectionTemplate.jl` and `Documentation.jl` split into new fragment files, and under which names (decide with L06-10)?

- **A:** Split all three now. A new fragment takes the name of its concept and a noun for its part (`<Concept><Part>.jl`), and the part with the public entry keeps the old name. DocumentMacro.jl keeps `@document`, `@document_preset`, the layout list, the schema names, the selection field and the registry; DocumentVariants.jl takes the emitters of the stem, the variants, their aliases and their constructors. ProjectionTemplate.jl keeps the marker words, the markers, `@projection_template` and its sugar; ProjectionTemplatePrinter.jl takes the IoMap, the wiring and the walk printer of each node shape; ProjectionTemplateMapper.jl takes the data-driven reference mappers; ProjectionTemplateReader.jl takes the readers. Documentation.jl keeps the readers (`list_functions`, `read_function_documentation`); DocumentationGuide.jl takes the guide roots, the guide index, `read_guide_section` and the reads of a resource by its URI; DocumentationReflection.jl takes the reflection over the loaded package; DocumentationSearch.jl takes the index, the rank, `search_guides` and `search_api`.
- **B:** Split now only the two files that are three times over the budget (ProjectionTemplate.jl, Documentation.jl). Split DocumentMacro.jl when it changes next.
- **C:** Split each file when it changes next (the advice of the audit for ProjectionTemplate.jl).
- **D:** Keep the files, and write an exception to the budget of 500 lines for an engine file.
- **Recommended (mine): A.** Two files are three times over the budget (1516 and 1546 lines), and the third has 793 lines. None of the three is sealed, so a split needs no permission. A split that only moves code keeps every name, so no caller changes. The scheme `<Concept><Part>.jl` puts the parts of one engine side by side in a file list and in a stack trace, and the part with the public entry keeps the old name, so the links of the guides still land. EventCase.jl (L06-10) is the one exception: it takes the name of the macro that it holds, as ReferenceCase.jl does. I checked: none of the proposed file names exists.
- **Decided by the owner, 2026-09-30: D**, with L06-10: the three files stay whole, and the relaxed rule of §5 has no exception for an engine file. The splits of L11-22 follow the same rule.
- Depends on: L06-10.
- Cost: M. Three unsealed files and their module files (DocumentModule.jl, ProjectionModule.jl, ToolModule.jl) for the include lists; the export blocks follow plan/pending/export-block-rule.md. No name changes, so no caller in projectured-julia, omnet-julia or inet-julia changes. The guides that link to a moved function by file and line change.

**L11-24** (Low): Does the string spelling `ref"…"`, which reference-pattern-vocabulary.md chose, take the full word as the naming rules require, or stay as a stated exception?

- **A:** Rename it to `reference_pattern"…"` (`@reference_pattern_str`), the pair of the runtime function `parse_reference_pattern`.
- **B:** Rename it to `reference"…"` (`@reference_str`).
- **C:** Keep `ref"…"` as a stated exception for a string-literal prefix, as Base has `r"…"` and `b"…"`. Write the reason in naming-rules.md and in the guard of test/suite/naming.jl.
- **Recommended (mine): A.** The rules put a meaningful name before a short one, and the guard already lists `ref` as a forbidden short form. The macro makes a pattern (a `Vector{PatStep}`), not a `Reference`, so with B a reader expects a Reference. `reference_pattern"…"` says what it makes and pairs with `parse_reference_pattern`. Julia also has long prefixes (`dateformat"…"`). The cost is small: only the kernel and one test file use the macro. I checked: `@reference_pattern_str` is free.
- **Decided by the owner, 2026-09-30: A.** With L11-25 (D), `reference_pattern"…"` is 1-based.
- Cost: S. projectured-julia: ReferencePatternString.jl (the macro and its text), ReferenceCase.jl (1 use), ReferenceModule.jl (the docstring), ReferenceRulesTest.jl (10 uses). No code use in omnet-julia or inet-julia: their hits are the text 'ref', not the macro. No sealed file. plan/done/reference-pattern-vocabulary.md keeps its history.

**L13-15** (Low): Which names replace operation_travels_unchanged and WrappingOperation, and does naming-rules.md get a second structural exception?

- **A:** `operation_travels_unchanged` becomes the predicate `is_self_contained_operation`. `WrappingOperation` keeps its name, and naming-rules.md replaces 'the one structural exception' with a class: a structural operation holds other operations and names no edit of its own (`CompoundOperation`, `WrappingOperation`, `CollectedIntentsOperation`).
- **B:** The predicate as in A, and naming-rules.md adds only `WrappingOperation` by name as a second exception.
- **C:** Rename `WrappingOperation` to a verb-first phrase (for example `WrapOperation`), and add no exception.
- **Recommended (mine): A.** An abstract supertype and a container name a structure, not an edit, so a verb claims an action that they do not do. A class rule answers `WrappingOperation` and `CollectedIntentsOperation` (L14-2) with one sentence, and it answers the next container too, where a list of names only grows. `operation_travels_unchanged(op)` is a predicate that starts with a noun. `is_self_contained_operation` names the property that its docstring gives: the operation names its subject, not a place. I checked: the name is free.
- **Decided by the owner, 2026-09-30: A.** It settles L14-2 as A. L13-3 decides only whether the "next hole" operation extends the predicate.
- Depends on: L13-3. Settles: L14-2.
- Cost: M. `operation_travels_unchanged`: 30 uses in 18 code files of projectured-julia (12 files extend it) and 6 uses in 2 files of omnet-julia. `WrappingOperation`: no rename. naming-rules.md gets the class rule. No sealed file.

**L15-12** (Low): Do the two getters and the layer-17 file get new names, and which ones?

- **A:** `get_document_gesture_bindings` becomes `collect_document_gesture_bindings`. `get_applicable_gesture_bindings` becomes `compute_applicable_gesture_bindings`. `get_document_gesture_bindings_own` keeps its name. The layer-17 file becomes `ProjectionGestureBindings.jl`.
- **B:** Only the file name changes. The two getters keep their names, and the verb table says that a short walk is a trivial computation.
- **C:** No change.
- **Recommended (mine): A.** The first function walks the supertype chain and gathers the table of each level, which is the row of `collect_` ('it gathers from several places'). The second filters a list with a predicate, which is a loop, so `compute_`. `find_` does not fit, because the answer is a list and never `nothing`. `_own` reads one table at a known place, so it keeps `get_`. The layer-17 file defines `read_projection_gesture` and the default of `get_projection_gesture_bindings`, so `ProjectionGestureBindings.jl` names it, and it no longer differs from binding/GestureBinding.jl by one letter. I checked: the three names are free.
- **Decided by the owner, 2026-09-30: A**, with L17-21.
- Settles: L17-21.
- Cost: M. `get_document_gesture_bindings` 32 uses in 8 code files, `get_applicable_gesture_bindings` 7 in 4. No code use in omnet-julia or inet-julia (their precompile assets hold `_own`, which does not change). The file rename changes the include in ProjectionModule.jl and the prose that names the file (34 lines in 14 files, most of them in plan/done, which keeps its history). naming-rules.md uses the pair as its example of a qualifier suffix, so that example changes. No sealed file.

**L16-8** (Low): Do the two reconcilers get make_ names, and which ones?

- **A:** `make_reconciled_child_iomaps_cell` and `make_reconciled_child_iomap_cell`.
- **B:** `make_child_iomaps_cell` and `make_child_iomap_cell` (the example of the audit).
- **C:** Keep the `reconcile_` names, and let the docstring say that the call makes the cell that reconciles.
- **Recommended (mine): A.** Each call makes a new `Cell`, and the cell does the reconcile at each computation, so `make_` with `cell` last says what the caller gets. The word `reconciled` keeps the reason to call these functions and not a plain `Cell(@computation ...)`: the reuse of each child IoMap. It also matches the file name IoMapReconcile.jl. I checked: the names are free.
- **Decided by the owner, 2026-09-30: A.** The permission for the sealed IoMapModule.jl is asked when the work starts.
- Cost: M. projectured-julia: `reconcile_child_iomaps` 24 uses in 14 code files, `reconcile_child_iomap` 33 in 15. omnet-julia: 3 uses in 2 files. inet-julia: no code use. The precompile assets of the three repositories (about 200 lines each) take the new names at their next record. Sealed (permission needed): IoMapModule.jl, for the export. Prose: the guides that name the two functions.

**L17-21** (Low): Which names does the layer take for the file GestureBindings.jl, for withhold_offer, and for the engine word (template or rule)?

- **A:** The file becomes `ProjectionGestureBindings.jl` (as in L15-12). `withhold_offer` becomes `with_free_axis(ctx, axis)`. The engine word is `template`: `RuleIoMap` becomes `TemplateIoMap`, and `print_template_rule` becomes `print_template_document`.
- **B:** As A, but `withhold_offer` becomes `with_withheld_offer`, which keeps the word 'offer' of the layout text.
- **C:** The engine word is `rule`: `@projection_template` becomes `@projection_rule`, and the other template names follow.
- **Recommended (mine): A.** `withhold_offer` returns a copy of the context, and the rules name a copy `with_<stem>`. The copy has one axis free (no minimum and no maximum), so `with_free_axis` stands beside `with_exact_size` and `with_bounded_size`. The public macro, the file and its plan use `template`, and `rule` is the word of the first version of the engine (the branch `projection-rule-macro`). So `template` changes the fewer names and the less visible ones. `print_template_document` follows the protocol shape of `print_document`. I checked: the new names are free.
- **Decided by the owner, 2026-09-30: A**, with L15-12. The engine word is `template`.
- Cost: M. `withhold_offer`: 22 uses in 6 code files (the callers in layout and widget). `RuleIoMap`: 50 uses in 10 code files of projectured-julia and 3 uses in 2 files of omnet-julia (legacy NED and INI); the precompile assets of the three repositories. `print_template_rule`: 8 uses in 3 files (RstToSyntax.jl among them). No sealed file.

**L22-27** (Low): Which names replace `perf!` and `_zoom_operation` (decide with L02-5, the other name of the counters)?

- **A:** `perf!` becomes `_log_performance_counters!`. `_zoom_operation` goes, because L22-23 moves the zoom keys into a binding table.
- **B:** `perf!` becomes `_log_performance_counters!`. `_zoom_operation` becomes `_find_zoom_operation`, because it can return `nothing`.
- **C:** Keep both names.
- **Recommended (mine): A.** I recommend A if L22-23 takes its option C, and B if the function stays. `perf!` writes the counters to the log, which is an external effect, so the name takes a verb, the full word `performance` and a `!`. It is not exported, so it takes the leading underscore of a private name, as L10-23 gave to the private helpers of the document layer. With L02-5, the counter family reads `run_with_performance_counters`, `get_performance_counters` and `_log_performance_counters!`. I checked: both new names are free.
- **Decided by the owner, 2026-09-30:** `perf!` becomes `_log_performance_counters!`. `_zoom_operation` follows L22-23: it goes if the zoom keys move into a binding table (A), and it becomes `_find_zoom_operation` if the function stays (B).
- Depends on: L02-5, L22-23.
- Cost: S. `perf!`: 8 uses in 4 code files (EditorLoop.jl and comments in test/kernel/editor/), PAR-PROFILE-WITH-COUNTERS in architecture-invariants.md, editor.md, plan/pending/a-present-that-is-a-timeout.md. `_zoom_operation`: 3 uses in ReadEvaluatePrint.jl. No sealed file. omnet-julia: text in 1 plan.

### Group 3

**The rule of three positional arguments** (3 questions). One answer for three signatures: POLICY-3.

#### POLICY-3

- **A:** No new kind of exception; §4 keeps its four kinds. A public definition names each argument after the third, and the subject (the editor, the document) counts. A method that a kind or a type adds to a generic of a protocol keeps the arity of the protocol, but it takes no optional positional argument: its short form is a method of its own. A constructor takes what the thing is and names the rest, as Resource does.
- **B:** A fifth kind of exception: an editor verb that mirrors an operation builder may put the editor before the arguments of the builder. A marker may also excuse optional positional arguments.
- **C:** No policy: decide each signature alone.
- **Recommended (mine): A.** Each question of the group has an answer inside §4 as it is written. Tool is a constructor, and Resource in the same file already has the keyword shape. The editor verbs can name their index. copy_document and sync_document! are already on the protocol list of test/suite/arguments.jl, so only their defaults break §4. Each of the four kinds of today has a structural reason (a protocol, a tuple, a port, a table of painters); a kind for two verbs weakens a rule that a guard checks.
- **Decided by the owner, 2026-09-30: A, then changed the same day: the count rule is relaxed.** "Relax the rule, these argument count rules are not that strict." The new §4 of code-quality-rules.md:
  - The count is advice. Prefer at most three positional arguments; a fourth is fine when the name of the function implies it. §4 no longer lists kinds of exception.
  - These clauses stay rules: a `Bool` is never positional; two arguments of one type that a caller could swap take a name; more than five keywords means a type is missing.
  - "At most one optional positional argument, and never one beside a keyword argument" is a recommendation, not a hard rule: "I can easily imagine exception, those should be marked". An exception carries a marker.
  - `test_arguments()` no longer fails on the count; `julia test/suite/arguments.jl --report` still prints the picture. The `# @positional:` markers of the count go: 57 in 21 files of projectured-julia, 23 in omnet-julia.
  - **Decided by the owner, 2026-10-01: the marker is `# @optional: <reason>`.** The guard reads only the new word, and it reports a `# @positional:` marker that is left, so the removal of the count markers is complete when the guard passes. The 4 markers of omnet-julia ForceDirectedParameters.jl that cover the optional clause take the new word.
  - **Decided by the owner, 2026-10-01: the guard checks the optional clause.** `test_arguments()` fails on a public definition that breaks the clause and has no marker. Today 57 public definitions do so with no marker (24 projectured-julia, 30 omnet-julia, 3 inet-julia); each gets a marker with one line of reason, or a change where a change is better. omnet-julia and inet-julia have no guard of their own; how they run it is a question of the work.
- Settles: L18-3, L22-1, L10-8.
- Cost: S to M in total: the three items below, and the two sites of N-3 (outside the questions) that the guard also reports.

**L18-3** (High): Does Tool take a signature with keywords, or a # @positional: marker for its four positional arguments?

- **A:** Tool(name; description, parameters, handler, result_mime_type = "text/plain"), the shape of Resource.
- **B:** Tool(handler, name; description, parameters, result_mime_type), so that a do block writes the handler.
- **C:** A # @positional: marker for the four positional arguments. §4 then needs a new kind of exception, because a constructor of four fields is none of the four kinds.
- **Recommended (mine): A.** Resource, the next type of Tool.jl, has the shape Resource(uri, name; description, provider, mime_type) from plan/done/keyword-arguments.md, and call_tool took keywords in the same plan. One shape then serves the types of the file. The Tool constructor came in commit 2224b9d8, after that plan closed.
- **Decided by the owner, 2026-09-30: A.** It stands under the relaxed §4: `name` and `description` are two strings that a caller can swap, and `Resource` in the same file has the keyword form.
- Depends on: POLICY-3.
- Cost: S. Tool.jl, DefaultTools.jl (6 calls), UndoDocument.jl (2), FaultExamples.jl (1), and about 14 calls in 8 test files. No call in omnet-julia or inet-julia.

**L22-1** (High): Do `insert_elements!` and `delete_elements!` take the index as a keyword, or does code-quality-rules.md section 4 get a new kind of exception for them?

- **A:** The index is a keyword in both verbs: insert_elements!(editor, collection, values; index) and delete_elements!(editor, collection; index, count = 1).
- **B:** Only insert takes the index as a keyword: insert_elements!(editor, collection, values; index), and delete_elements!(editor, collection, index; count = 1), which mirrors the builder delete_elements(path, index; count).
- **C:** §4 gets a new kind of exception for an editor verb that mirrors a builder, and the shape of D24 stays.
- **Recommended (mine): A.** The editor is the subject, so each verb has room for two more positional arguments, and the collection and the values are what the verbs name. The keyword at the call also marks the 1-based element index apart from the 0-based position of the builders insert_elements and delete_elements (the question of L13-9). One shape for the pair is simpler for a model to learn. D24 approved the verbs and their 1-based index; a keyword keeps both.
- **Decided by the owner, 2026-09-30: no change.** Under the relaxed §4 (POLICY-3), `insert_elements!(editor, collection, index, values)` and `delete_elements!(editor, collection, index, count = 1)` keep their signatures.
- Depends on: POLICY-3.
- Cost: S. DocumentEdits.jl, the tool text in DefaultTools.jl:32-33, Application.jl (3 calls), orientation.md (4), editor.md, ReferencedDocumentEditorTest.jl (5), DeclaredApiTest.jl, ApplicationVideoTest.jl. omnet-julia SearchContextCorpus.jl names only the verb, so it does not change.
- **Risk:** The choice is close: option B, where `delete_elements!` keeps its index positional, also follows §4.

**L10-8** (Medium): Do the kind copy and `sync_document!` take `policy` and `depth` as keywords, or keep two optional positional arguments with a marker?

- **A:** Keywords: copy_document(K, value; policy = nothing, depth = 0) and sync_document!(shadow, source; policy = nothing, depth = 0). Each method that a kind adds takes the two keywords.
- **B:** Keep the four-argument protocol method with no default: copy_document(K, value, policy, depth) and sync_document!(shadow, source, policy, depth) are the methods that a kind adds. The short forms copy_document(K, value) and sync_document!(shadow, source) are methods of their own.
- **C:** Keep two optional positional arguments with a marker, and change §4 so that a marker also excuses the clause on optional arguments.
- **D:** One walk value: copy_document(K, value, bound), where a new type holds the policy and the depth.
- **Recommended (mine): B.** §4 already excuses the count of a protocol method, and both names are on the protocol list of the guard. Only the defaults break the clause 'at most one optional positional argument'. B removes them, keeps dispatch on positional arguments, and keeps each extension signature except its '= nothing' and '= 0' (ListNode.jl, omnet-julia's ASweep; CellVector.jl has no default already). The three-argument sugar of BoundedSync.jl stays legal. A reaches about 50 calls in the three repositories. D adds a type for two values.
- **Decided by the owner, 2026-10-01: B.** Under the relaxed §4 the optional clause is a recommendation with marked exceptions, and B needs no marker: the short forms are methods of their own. After the fold, ListNode.jl is source/platform/collection/ListNode.jl.
- Depends on: POLICY-3.
- Cost: S. DocumentCopy.jl, DocumentSync.jl, DocumentInterface.jl (the docstring names the two entries and the protocol method), ListNode.jl (the defaults of sync_document!), omnet-julia source/simulator/configuration/Configuration.jl (the defaults of the ASweep method). No sealed file.

### Group 4

**The public surface** (22 questions). Keep, export or remove a name, and where a seam lives. POLICY-4 states one rule for the public surface, and each question applies it.

#### POLICY-4

- **A:** One rule for the whole surface: the export list is the API (R1). An exported name stays only for a listed reason (R2). A private name that another module reaches becomes public, or the reach goes (R3). A test reaches only the private names of its own layer, and only by qualification (R4). A seam lives in its interface file (R5). A macro splices objects (R6). A removal counts users in three repositories first (R7).
- **B:** As A, and add the Julia `public` keyword (Julia 1.11, the compat of the packages) as a second tier: a supported name that a caller reaches by qualification, and that `using Projectured` does not bring into scope.
- **C:** No rule for the group. Decide each name alone, as the audit found them.
- **Recommended (mine): A.** PAR-MODULE-BOUNDARY-IS-API already makes the export list the API, and the guards (test_exports, private_import_errors, qualified_reference_errors) key on it. One tier keeps one check. The 21 questions of the group repeat five cases: a name with test users only, a name with no user, a private name that another package or repository reaches, a seam outside its interface file, and a macro that splices a bare name. One rule answers each case the same way.
- Settles: L03-8, L06-7, L06-8, L09-7, L09-8, L09-11, L10-21, L11-9, L12-6, L13-13, L15-9, L16-5, L16-6, L17-8, L17-9, L17-17, L18-11, L18-19, L18-22, L20-9, L22-24, L22-31.
- Cost: Text: PAR-MODULE-BOUNDARY-IS-API in architecture-invariants.md, and code-quality-rules.md sections 1 and 4 (S). Guards (M): let qualified_reference_errors also check the test folders (R4) and a qualification across packages (R3), and let test_exports() refuse an exported name with a leading underscore (R1). No sealed file. Today 23 exported names start with an underscore in projectured-julia (10 in source and package files, 13 in test suites) and 4 in omnet-julia; inet-julia has none.

**L09-7** (Medium): Does the offscreen renderer of ProjecturedSdl become public API (names without an underscore), or a declared seam that the video package uses?

- **A:** Make the offscreen renderer public API of ProjecturedSdl: remove the underscore of its seven names (open, close, emit frames, make the paint state, partial render, frame with overlay, picture with overlay) and export them. Export encode_frames_to_video! from ProjecturedVideo in the same way.
- **B:** Declare an offscreen renderer seam (an abstract renderer type and its generics) in a package below both. SDL implements it, and the video package calls only the seam.
- **C:** Move the video code into ProjecturedSdl, as a fragment or as a package extension on FFMPEG, so that the names stay private.
- **Recommended (mine): A.** R3(3) and R1. The renderer has one implementer (SDL) and callers in other modules: ProjecturedVideo, and omnet-julia tool/video/record_study_take.jl for _encode_frames_to_video!. Its signatures hold an SDL renderer and surface. A seam with one implementer is an abstraction that nothing else uses. C brings FFMPEG back to the SDL users, which the split into ProjecturedVideo prevents.
- Under POLICY-4 R3(3).
- Cost: M. source/backend/sdl/SdlBackend.jl, package/ProjecturedSDL, package/ProjecturedVideo, source/backend/video/VideoRecording.jl and VideoBackend.jl, example/backend/sdl/ApplicationVideo.jl, two SDL tests (LaidOutCanvasTest.jl, TreeRenderTest.jl), GraphicsModule and ProjecturedWeb for the bounds helpers; omnet-julia tool/video/record_study_take.jl. No sealed file. inet-julia has no user.

**L09-8** (Medium): Does render_canvas stay as a seam for a later renderer, or go?

- **A:** Remove render_canvas (the generic, its export and the SDL method), the stub render_sdl_canvas, the `render` keyword of GraphicsCaching, and `render=render_canvas` in the gallery example.
- **B:** Keep the seam and implement render_sdl_canvas: put the pixels of the canvas into a GraphicsImage, and let GraphicsCaching use it.
- **C:** Keep the declaration only and remove the stub, so that a call raises MethodError.
- **Recommended (mine): A.** R5 and PAR-NO-TEST-DOUBLES-IN-MAIN: the one method fabricates an empty image (Sdl.jl:2939), and its one consumer does not read it (the GraphicsCaching docstring: 'nothing reads it yet'). No code in omnet-julia or inet-julia names render_canvas, and no pending plan implements it: cairo-glfw-backend.md:259 names it as a maybe, and feature-video-screenplays.md only lists it in a table of the backend methods.
- Under POLICY-4 R5.
- Cost: S. BackendInterface.jl and BackendModule.jl (sealed: permission needed for each), source/backend/sdl/SdlBackend.jl, source/platform/graphics/GraphicsCaching.jl, example/projectured/GalleryWrapperProjectionExample.jl, the export of ProjecturedExample, devices-and-backends.md. Users: projectured-julia only (5 source lines and 1 example line).

**L11-9** (Medium): Does the pattern AST become exported API after its rename, or does omnet-julia get an exported query surface while the AST stays private?

- **A:** Export the pattern AST after its rename to full words (naming-rule-violations.md question 21: PatStep to PatternStep, and so on), with docstrings that state it as the data form of a parsed pattern.
- **B:** Keep the AST private, and export a query: a match of a parsed pattern against a plain path of names and indices, which omnet-julia calls in place of its own matcher.
- **C:** Keep the AST private, and let omnet-julia own a parser of its own for INI keys.
- **Recommended (mine): A.** R2(d): parse_reference_pattern is exported and answers Vector{PatStep}, so the AST is already the result type of a public function. B puts OMNeT++ rules into the kernel: the omnet-julia matcher lets a bare * take the index that follows it, and keeps the text of a literal for a hot loop (IniConfiguration.jl:253-360). C gives the INI keys a second parser that can go out of step with the kernel form.
- Under POLICY-4 R2(d). Depends on: L11-10.
- Cost: M. ReferenceCase.jl (22 types), ReferenceRules.jl, ReferencePatternString.jl, ReferenceModule.jl (none sealed), reference.md; omnet-julia source/legacy/ini/IniConfiguration.jl and 3 recorded precompile statements. inet-julia has no user.

**L17-8** (Medium): How do code outside the layer and omnet-julia reach the template markers, and what replaces the AtomicWiring test in ReaderDefaults.jl?

- **A:** Export the five marker words again, and let the DSL exemption of naming-rules.md cover exported words.
- **B:** Keep the words private. The kernel exports one macro that applies make_template_builder to a helper function, and omnet-julia writes its helpers with it.
- **C:** Keep the words private. omnet-julia writes its own macro of two lines over the exported make_template_builder, as RstToSyntax.jl does for @rst_flat and @rst_indented.
- **D:** Keep the words private, and put each helper inside the template bodies.
- **Recommended (mine): C.** projection-layer-is-one-module.md (stage 3, done) took the words off the export list, because ordinary code uses them as local names; A reverses that recorded decision. make_template_builder is exported for this use, and RstToSyntax.jl is the precedent. D copies _ini_kv_children into two templates. For the AtomicWiring test in ReaderDefaults.jl (all options): export a predicate is_opaque_template_leaf(iomap::RuleIoMap) -> Bool, so the type stays private (R3(2)).
- Under POLICY-4 R3(1), R3(2). Settles: L17-8.
- Cost: S. ProjectionTemplate.jl and ProjectionModule.jl (not sealed) for the predicate, source/platform/projection/ReaderDefaults.jl, test/platform/projection/ProjectionTemplateTest.jl:56 (it imports bound with no need); omnet-julia source/legacy/ned/presentation/NedToSyntax.jl, ini/presentation/IniToSyntax.jl and testfile/presentation/TestToSyntax.jl. inet-julia has no user.

**L17-9** (Medium): Does the pure printer pair stay in the projection contract?

- **A:** Delete print_document_pure, print_child_pure and print_pure, with their methods in Chaining.jl, Recursive.jl and TypeDispatching.jl, their exports, and their entry in the argument guard.
- **B:** Keep the pair, record the exception to PAR-FOUR-FUNCTIONS in architecture-invariants.md, and give it a caller (a batch export) and a test.
- **Recommended (mine): A.** R2: nothing calls print_pure or print_child_pure, and only its own methods call print_document_pure. Its docstring now says that an export prints through print_document. Each concrete projection falls back to a snapshot of print_document, so the pure path is slower than the reactive one and gives no gain. omnet-julia and inet-julia have no user.
- Under POLICY-4 R2. Settles: L17-9.
- Cost: S. ProjectionInterface.jl, ProjectionDefaults.jl, ProjectionModule.jl (not sealed), three files in source/platform/projection/higherorder/, ProjectionAlgebraModule.jl, test/suite/arguments.jl, projection-system.md, naming-rule-renames.md. Users: projectured-julia only (14 source lines, 1 test line).

**L18-11** (Medium): Which exported calls replace the private reaches into the tool layer from Notebook.jl, Evaluator.jl, SearchScaleMeasurement.jl and the tests?

- **A:** Export the private names as they are, with no underscore.
- **B:** Export narrow calls: bind_scratch_name!(set, name, value), which makes the scratch module when it is absent and keeps the name across a new declare_api!; a folder field of MeaningModel in place of the global _MEANING_FOLDER; an `observers` keyword of the ToolSet constructor for Evaluator.jl; and one read of the search index for a measurement and a test.
- **C:** Move the callers into the tool layer. This is not possible for omnet-julia and the examples.
- **Recommended (mine): B.** R3(2) and R4. The reaches read a representation (the scratch module, the index, the store) or write a process-wide global, so A makes the representation public. A test that writes _MEANING_FOLDER[] moves the vector files of each editor in the process; a field of the model keeps the value with the model. B also removes a fault: declare_api! sets set.scratch = nothing, so it drops the names that install_notebook! bound, with no error.
- Under POLICY-4 R3(2), R4. Depends on: L18-13.
- Cost: M. CodeExecution.jl, Tool.jl, ToolSet.jl, MeaningSearch.jl, Documentation.jl (not sealed); source/platform/conversation/Evaluator.jl; example/kernel/SearchScaleMeasurement.jl, SearchCorpus.jl, SearchRanking.jl; three umbrella tests (SearchCorpusTest.jl, SearchScaleTest.jl, McpTest.jl); omnet-julia source/presentation/page/Notebook.jl, tool/search/measure_rankings.jl and three test files (CampaignAssistantTest.jl, MeaningSearchMeasurementTest.jl, SearchScaleTest.jl). inet-julia has no user.

**L03-8** (Low): Does the cell layer get a public read of the stored value, so that persistence stops reading private fields?

- **A:** Declare a new generic get_cell_stored_value(cell) in CellInterface.jl, with a method for each cell kind, and let the two serializers call it.
- **B:** Use the exported names that exist: a serializer asks is_computed_cell(c) first, then reads peek(c), which records no dependency and, for a cell with no computation, answers the stored value as it is. PAR-PERSISTENCE-BY-VALUE names these two in place of getfield(c, :value).
- **C:** Keep the field read, and state the field `value` of the three kinds as part of the contract, in their docstrings and in the rule.
- **Recommended (mine): B.** R3(1): exported names already meet the need. For a cell with no computation, Base.peek(c::ReactiveCell) returns c.value and records no dependency (ReactiveCell.jl:309), and peek of a MutableCell or an ImmutableCell is c[]. is_computed_cell answers what omnet-julia reads from c.computation (CheckpointSerializer.jl:94). So B needs no new name and no sealed file.
- Under POLICY-4 R3(1). Settles: L03-6.
- Cost: S. source/platform/serialization/BinarySerialization.jl, PAR-PERSISTENCE-BY-VALUE in architecture-invariants.md, omnet-julia source/simulator/checkpoint/CheckpointSerializer.jl (the methods of the three kinds). No sealed file. inet-julia has no user.

**L06-7** (Low): Do the eight exported event names with no user (has_shift_, has_alt_, has_meta_modifier_key, KeyUpPattern, MouseDownPattern, MouseUpPattern, MouseEnterPattern, MouseLeavePattern) stay as part of a complete family with tests, or go?

- **A:** Keep the two families (the four modifier predicates, and one pattern constructor for each event type), and add the tests that are missing.
- **B:** Remove the eight names from the sealed event files.
- **C:** Remove only MouseEnterPattern and MouseLeavePattern, the two names with no test.
- **Recommended (mine): A.** R2(c). Each name is a member of a family that a reader guesses from one member: about 55 lines use KeyDownPattern, and has_ctrl_modifier_key has a caller (ProjectionConfiguring.jl:136). After L06-15, six of the eight names have a test in EventModuleTest.jl; MouseEnterPattern and MouseLeavePattern have none. A removal edits three sealed files and leaves a hole in each family.
- Under POLICY-4 R2(c). Settles: L06-15.
- Cost: S. test/kernel/event/EventModuleTest.jl only (a text test and a match test for MouseEnterPattern and MouseLeavePattern). No sealed file. Users: none of the eight names has a user outside the event layer and its test in the three repositories.
- **Check after the merge of gesture-type (2026-10-01): the question holds.** The four predicates are in `event/EventDefaults.jl`; the six pattern constructors are in `gesture/GesturePattern.jl`. No file of the two families is sealed now, so option B needs no permission. `MouseEnterPattern` and `MouseLeavePattern` still have no test; `has_ctrl_modifier_key` still has its one caller (`source/platform/widget/ProjectionConfiguring.jl:137`).

**L06-8** (Low): Does the event layer export a predicate that tells whether a rule binds a field, so that Gestures.jl stops its test of object identity?

- **A:** Export a predicate has_bound_event_fields(rule::EventPatternRule) -> Bool from EventPattern.jl, and let Gestures.jl call it in place of `bound_body !== escaped_body`.
- **B:** Keep the identity test. The docstring of build_event_field_bindings promises that the result is `body` itself when the rule binds no field, so the test uses a documented contract. Make the comment shorter.
- **C:** Export the field pattern types (FieldPattern, BoundField, LiteralField, ExpressionField), and let the binding layer read rule.fields.
- **Recommended (mine): A.** R3(2): the consumer asks the fact itself, not a side effect of object identity. If build_event_field_bindings ever wraps a body that binds no field, the identity test becomes true with no error, and each named command loses its name (Gestures.jl:127). C exports a representation.
- Under POLICY-4 R3(2).
- Cost: S. EventPattern.jl and EventModule.jl (both sealed: permission needed for each), source/kernel/binding/Gestures.jl, EventModuleTest.jl. No user in omnet-julia or inet-julia.
- **Check after the merge of gesture-type (2026-10-01): the question holds, with new names.** The rule is `GesturePatternRule`, the builder is `build_gesture_field_bindings`, and the identity test is `reads_event = bound_body !== escaped_body` at `source/kernel/binding/Gestures.jl:118`. The predicate of option A becomes `has_bound_gesture_fields`. `GesturePattern.jl` and `GestureModule.jl` are not sealed, so no permission is needed.

**L09-11** (Low): Does the devices argument of the three per-frame generics stay, now that configure_devices! gives the Display to SDL and no backend reads the argument?

- **A:** Remove the `devices` argument from read_from_devices, write_to_devices and wait_for_input. A backend keeps the devices that configure_devices! gave it.
- **B:** Keep the argument, and state what a backend must do with it (for example, write only to the Display devices in it).
- **C:** Keep the argument, and state in the docstrings that a backend may ignore it.
- **Recommended (mine): A.** configure_devices! already gives a backend the devices of its editor once, before the first print, and no method of the five backends reads the argument of a frame. A backend serves one editor (PAR-PER-EDITOR-STATE), so a change of the devices of an editor is a new configure_devices! call, not an argument of each frame. A contract parameter that no implementer reads misleads each new backend.
- Under POLICY-4 R5.
- Cost: M. BackendInterface.jl and BackendDefaults.jl (sealed: permission needed for each); the five backends (Sdl.jl, Web.jl, Console.jl, VideoBackend.jl, example/kernel/BackendHeadless.jl); three calls in the editor layer; example/platform/fault/FaultExamples.jl and example/projectured/Gallery.jl; 10 test files with about 107 lines; omnet-julia test/ide/IdeWindowWrapTest.jl (two methods); the recorded precompile statement of write_to_devices in each of the three repositories; the text of sdl-per-editor-state.md, feature-video-screenplays.md and cairo-glfw-backend.md.

**L10-21** (Low): Does the private seam `_declared_value_types`, which every `@document` expansion extends, become a public exported name, or stay private with a stated exception?

- **A:** Make it a public seam: declare get_document_field_value_types with no body in DocumentInterface.jl, export it, keep the default (nothing) in DocumentDefaults.jl, let the macro extend it by object, and let the test call it by its public name.
- **B:** Keep _declared_value_types private, and state the exception in PAR-MODULE-BOUNDARY-IS-API and in its comment.
- **Recommended (mine): A.** R5: each @document expansion adds a method to it in the module of the caller, so it is a seam, and it sits in DocumentCopy.jl, outside the interface file. It also answers a real need: select-a-widget-and-paste-it-into-a-tab.md records that the clipboard wanted the declared field types and did not open the private name. The name uses get_ because the value sits at a known place (a generated method), and it follows its siblings get_document_cell_type and get_document_native_type.
- Under POLICY-4 R5. Settles: L10-21.
- Cost: S. DocumentInterface.jl, DocumentDefaults.jl, DocumentCopy.jl, DocumentMacro.jl, DocumentModule.jl (none sealed), DocumentMacroTest.jl, the document guide. Users: projectured-julia only (7 source lines, 2 test lines); omnet-julia and inet-julia have none.

**L12-6** (Low): How does a painter that holds a stored selection value read its path and its live flag?

- **A:** Export the two value readers of the selection layer under public names.
- **B:** Add methods of get_stored_selection and is_live_selection on SelectionDocument.
- **C:** Put two exported value readers next to SelectionDocument and unwrap_selection in the document layer, and let the selection layer and the painters call them.
- **D:** No new name: each painter holds the document, so it calls the exported get_stored_selection(document) and is_live_selection(document) in its computation. Delete the copies.
- **Recommended (mine): D.** R3(1). Both painters hold the document: TextToGraphics.jl:296 reads getfield(styled, :selection), and PaneToWidget.jl:151 reads getfield(source, :selection). The exported readers take the document and read the same cell with [], so each computation keeps the same dependency. B gives get_stored_selection two meanings on a SelectionDocument, which is itself a document.
- Under POLICY-4 R3(1). Settles: L12-6.
- Cost: S. source/platform/text/TextToGraphics.jl and source/platform/pane/PaneToWidget.jl. No sealed file: the private readers in SelectionDefaults.jl are fragments of their own module and stay. No user in omnet-julia or inet-julia.

**L13-13** (Low): May reroot_reference, an exported name with users in four packages, move from the operation layer to the reference layer?

- **A:** Move reroot_reference to ReferencePath.jl beside concat_references, write it as a use of concat_references, and export it from ReferenceModule.
- **B:** Keep it in the operation layer, and only write its body with concat_references.
- **C:** Delete it, and let the call sites write concat_references(Reference(steps...), reference).
- **Recommended (mine): A.** It works on references only, and a thing lives with its concept (architecture-rules.md). Each caller slice (primitive, text, widget) already has `using ..ReferenceModule`, and the umbrella exports both modules, so no call site changes. Only ReferenceEvaluationTest.jl imports it from OperationModule. C removes the pair of reroot_operation.
- Under POLICY-4 R2(a). Settles: L13-13.
- Cost: S. Rerooting.jl, OperationModule.jl, ReferencePath.jl, ReferenceModule.jl (none sealed), ReferenceEvaluationTest.jl, operation.md and reference.md. Users: projectured-julia only (the kernel, primitive, text, widget, and two tests); omnet-julia and inet-julia have none.

**L15-9** (Low): Do fire_named_gesture_binding, get_applicable_gesture_bindings and @gesture_set stay as supported API although only tests use them?

- **A:** Keep all three as supported API, each with its test and a docstring that says what it is for.
- **B:** Keep get_applicable_gesture_bindings and @gesture_set, which plans name, and move fire_named_gesture_binding into a test package.
- **C:** Stop the export of all three.
- **Recommended (mine): A.** R2. get_applicable_gesture_bindings is the menu of legal gestures that live-example-construction.md (in progress) calls (R2(f)). @gesture_set is the shared-set form of the @gestures DSL, and key-chords-from-bindings.md extends both macros (R2(c)). fire_named_gesture_binding is the pair of fire_gesture_bindings (fire by name, fire by event), and three test files in two packages use it to run a command (R2(c)). Each has a test.
- Under POLICY-4 R2(c), R2(f). Settles: L15-9.
- Cost: S. Docstrings in GestureBinding.jl and Gestures.jl (not sealed). Users: projectured-julia only; omnet-julia and inet-julia have none.

**L16-5** (Low): Are the three field names the IoMap contract, or must the readers go through the three accessors?

- **A:** The three fields projection, input and output are the contract: the docstrings of IoMap and @iomap say so. The accessors stay as plain getters, for a caller that passes a function, and their text 'overrides this' goes.
- **B:** Each reader goes through the accessors: change about 940 field reads here, 63 in omnet-julia and 9 in inet-julia, and add a guard.
- **C:** Remove the three accessors, and let each caller read the fields.
- **Recommended (mine): A.** R3, last sentence: a field is part of the contract when the docstring of its type names it. Each IoMap struct in the three repositories has the three fields (93 @iomap structs here, 5 in omnet-julia, 1 in inet-julia), and no method overrides an accessor. C changes about 190 accessor calls (78 here, 91 in omnet-julia, 17 in inet-julia) for no gain.
- Under POLICY-4 R3. Settles: L16-5.
- Cost: S. IoMapInterface.jl (sealed: text only, permission needed), IoMapDefaults.jl, the iomap guide. No code change, and no change in omnet-julia or inet-julia.

**L16-6** (Low): Do the macros that inject a default supertype put the type object into the expansion, instead of a bare name that the calling module must have in scope?

- **A:** Yes: @iomap, @projection and @document put the object (IoMap, Projection, Document) into the expansion, and macros.md says so.
- **B:** No: keep the bare names, and keep the requirement in macros.md that the calling module has them in scope.
- **Recommended (mine): A.** R6 and PAR-QUALIFIED-EXTENSION, which names the object form for a macro. @gestures and the cell parameters of @document already use it. A bare name gives UndefVarError in a module without the name, and the wrong supertype in a module that has a name of its own. The bare names are at IoMapDefaults.jl:33, ProjectionMacro.jl:37, DocumentMacro.jl:574 and DocumentMacro.jl:414 (items::Document...).
- Under POLICY-4 R6. Settles: L16-6.
- Cost: S. IoMapDefaults.jl, ProjectionMacro.jl, DocumentMacro.jl (none sealed), macros.md. No call site changes in the three repositories.

**L17-17** (Low): Does the children-container seam dispatch on the output node, so that each output domain registers its own container?

- **A:** Key both on the type of the output: make_children_container(output_type, cells_or_thunk) and get_children_container_type(output_type). ProjecturedCollection registers CellVector as the default for each output, and an output domain adds a more specific method.
- **B:** Remove the seam: the engine builds the container from the declared type of the children field of the output node.
- **C:** Keep the seam with no argument, and state in its docstring that one package registers it for each process.
- **Recommended (mine): A.** R5 and PAR-FRAMEWORKS-SINK: a generic with no argument holds one method, so a second registrant overwrites the first, and Julia refuses a method overwrite during precompilation. Each call site already holds the output node or its type (`out` in ProjectionTemplate.jl:487-743, `w.outtype` at :876), so the key needs no new data.
- Under POLICY-4 R5.
- Cost: S. ProjectionInterface.jl and ProjectionTemplate.jl (not sealed: 6 calls of the make_ form and 1 of the get_ form), source/platform/collection/CellVector.jl. Users: projectured-julia only; omnet-julia and inet-julia register no method.

**L18-19** (Low): Does read_function_documentation drop type_name, or use it to pick the docstring of one method?

- **A:** Drop type_name from the tool, the scratch helper and the function.
- **B:** Use type_name as list_functions does: answer the docstrings of the methods whose signature names the type, and when no method does, answer all of them with a line that says so.
- **C:** Drop type_name, and make the second argument a real signature that picks the method.
- **Recommended (mine): B.** The tool promises it ('Optional type, when the function is documented per type'), and list_functions already filters on the same argument with the same test (occursin on the signature of each method, Documentation.jl). The code has docstrings per method (for example write_to_devices for the Console, SDL, Web and Video backends), so a model that finds a method by its type can read the text of that method.
- Under POLICY-4 (no rule: a behaviour promise). Settles: L18-19.
- Cost: S. source/kernel/tool/Documentation.jl and a test in test/kernel/tool/. The tool declaration and the scratch helper stay. No sealed file. omnet-julia calls the function with a module and a name only (CampaignVerbsTest.jl:183), so it does not change.

**L18-22** (Low): Do api_entry_bindings, api_source_name, register_resource!, find_resource, read_value_documentation, SearchTerm and KeywordQuery stay exported?

- **A:** Keep all seven exported, and add a test for each one that has none.
- **B:** Keep five and stop the export of two. Keep register_resource! and find_resource (the resource family with Resource, list_resources and read_resource; register_resource! is how a package adds a resource, as register_tool! adds a tool), read_value_documentation (the family of the four read_..._documentation readers), and KeywordQuery and SearchTerm (the types of the exported parse_keyword_query and is_keyword_match). Stop the export of get_api_entry_bindings and get_api_source_name.
- **C:** Stop the export of all seven.
- **Recommended (mine): B.** R2(b), (c) and (d) hold for five names. get_api_entry_bindings and get_api_source_name are helpers of the declaration machinery: only fragments of ToolModule call them in the three repositories, and get_api_entry_names already gives a caller the names of an entry (omnet-julia uses it).
- Under POLICY-4 R2(b), R2(c), R2(d). Settles: L18-22.
- Cost: S. ToolModule.jl (the export list); tests in test/kernel/tool/ for register_resource!, find_resource and read_value_documentation. No sealed file. None of the seven has a user outside the tool layer in the three repositories.

**L20-9** (Low): Does `AgentEvent` stay as a supertype, or go?

- **A:** Keep AgentEvent, state in run_turn! that on_event takes an LlmEvent or an AgentEvent, and add a test that dispatches on it.
- **B:** Remove AgentEvent. AgentToolResult stays alone until a second event of the loop comes.
- **Recommended (mine): B.** R2: AgentEvent has one subtype, and no method in the three repositories dispatches on it; the consumers dispatch on LlmEvent and AgentToolResult (AssistantTurn.jl:757, 788; omnet-julia AssistantSessionTest.jl:201). An abstract type with one subtype and no user is an orphan that shapes the structure.
- Under POLICY-4 R2. Depends on: L20-1, L20-2. Settles: L20-9.
- Cost: S. Agent.jl and AgentModule.jl (not sealed). Users: projectured-julia only (4 source lines); omnet-julia and inet-julia have none.

**L22-24** (Low): Which of the ten names stay exported?

- **A:** Keep all ten exported, and give each a docstring that says why.
- **B:** Keep six and stop the export of four. Keep wake_editor! (the documented wake of a producer), drain_feeds! and read! (steps of the loop, with run_frame!, evaluate!, print! and drain_operations!), and is_editor_in_safe_mode, is_editor_degraded and get_consecutive_fault_limit (read-only queries of the fault state). Stop the export of enter_safe_mode!, leave_safe_mode!, report_frame_faults! and InboxFeed.
- **C:** Keep wake_editor! only, and stop the export of the other nine.
- **Recommended (mine): B.** R2(c) and (e). A test must see the fault state with no private reach, so the three queries stay (the fault test package reads two of them, the editor tests the third). The steps of the loop are one family, and PAR-MODULE-BOUNDARY-IS-API named their export as the fix for the reach of PlaybackModule; four test files in other packages call drain_feeds!. The editor decides safe mode by its own rule (a print fails, a print succeeds), so no caller must enter or leave it, and report_frame_faults! and InboxFeed are parts of the loop that no caller outside the editor layer names.
- Under POLICY-4 R2(c), R2(e). Depends on: L22-13. Settles: L22-24.
- Cost: S. EditorModule.jl (the export list) and FeedsTest.jl (it names EditorModule.InboxFeed under R4). No sealed file. No user in omnet-julia or inet-julia. One recorded precompile statement names InboxFeed by its full path, so it does not change.

**L22-31** (Low): Do the four private names that the tests use become public, or do the tests stop naming them?

- **A:** Export the four names.
- **B:** Keep the four private. The tests of the editor layer (test/kernel/editor/) name them qualified (EditorModule.MAX_OPERATIONS_PER_FRAME) and do not import them. ValueViewerTest.jl of the umbrella suite stops its reach.
- **C:** As B, but export compute_wait_timeout, the read-only query of how long the next wait may block, because a test in another package reads it.
- **Recommended (mine): C.** R4 and R2(e). RunFunctionOperation, MAX_OPERATIONS_PER_FRAME and FRAME_INTERVAL have users only in the tests of their own layer, so they stay private and the tests qualify them. compute_wait_timeout has a user in another package (test/projectured/editor/ValueViewerTest.jl:81, 87), which checks that a live value makes the editor poll and then sleep: a contract of the loop that a test outside the layer must see.
- Under POLICY-4 R4, R2(e). Settles: L22-31.
- Cost: S. EditorModule.jl (one export), FaultBarriersTest.jl, InboxTest.jl, FrameDrainTest.jl, WaitTest.jl and ValueViewerTest.jl. No sealed file. No user in omnet-julia or inet-julia.

### Group 5

**The reactive engine and the document model** (16 questions). New states and mechanisms of the sealed engine, and the document model. L03-1 and L03-2 come first: one state of a cell answers L03-1, L03-2, L03-3 and L05-1.

**L03-1** (High, main question): Which form does a failed computation take in a cell?

- **A:** Keep a failed computation as the result of the cell. The cell stores the exception, becomes valid, and each read throws that exception again until a write invalidates the cell. An exception that means stop (is_passthrough_exception) is not stored, and the cell stays invalid as now.
- **B:** Keep the failed cell invalid, but also mark the reader that caught the failure as invalid, so that each read of the reader runs the failed computation again.
- **C:** Change no engine code. A barrier that catches must not keep its result, so Catching.jl reads again on each frame.
- **Recommended (mine): A.** The header of Catching.jl promises two things: the failed computation does not run again on each frame, and the real output comes back when the input changes. Only A gives both, because a stored failure is a valid state, and the walk of a later write goes through it to the reader. B and C run the failed computation on each frame, which is the repeated fault that the barrier exists to stop. A also restores PAR-MONOTONE-INVALIDATION: no invalid cell has a valid reader.
- Settles: L03-12, L03-13.
- Cost: ReactiveCell.jl 🔒 and CellModule.jl 🔒. The cell layer then imports is_passthrough_exception from the fault layer, which is layer 1, so the layer rules allow it. CellTest.jl: the @test_broken of L03-1 becomes a @test. FaultCatchingTest.jl: a recovery test. cell.md: the invariant for a failed computation (the open part of L03-12). One more field costs 8 bytes for each reactive cell (56 to 64 bytes). The two serializers (BinarySerialization.jl, omnet-julia CheckpointSerializer.jl) read only value and computation, so they need no change. Size M.
- **Risk:** A stored failure stays after Revise corrects a method, until an input changes; today a failed cell under the frame barrier recovers in the next frame. Each reactive cell grows by 8 bytes.

**L03-2** (Medium, main question): Does the engine get a state for a cell that computes now, so that a write during a computation is not lost?

- **A:** Give a cell the state 'computes now'. When the walk of a write meets a dependent in that state, it marks the dependent stale, and _recompute! leaves that cell invalid at its end, so the next read computes it again.
- **B:** Change no engine code. cell.md and PAR-NO-WRITE-IN-THUNK state that a computation must not yield and must not write, and another task (the wall-clock heartbeat) writes only through a store that the editor drains between frames.
- **C:** A, and a check in setindex! and set_cell_computation! that throws for a write to a cell with readers while the stack of computations of the task is not empty.
- **Recommended (mine): A.** A write at a yield inside a computation is a real path today: the wall-clock heartbeat writes at each yield of its thread (Clock.jl). Without the state, one such write leaves a reader stale for good, with no error. The state costs no memory when it replaces valid::Bool, and L03-3 needs the same state to find a cycle.
- Settles: L05-1.
- Cost: ReactiveCell.jl 🔒. CellTest.jl: the @test_broken of L03-2 becomes a @test. cell.md: the thread contract (one thread; another task writes through a store). architecture-invariants.md: PAR-PER-EDITOR-STATE and PAR-NO-WRITE-IN-THUNK. No code outside the cell layer reads the valid field. Size S to M.

**L10-3** (High): How does the sync treat a mutable container in a leaf: copy it (a cost for a large buffer, and a throw for unassigned slots), copy it only for some types, or keep the reference and invalidate by another signal?

- **A:** Copy each mutable container of a leaf into the shadow (the saved patch /var/tmp/kernel-fixes/a/L10-3-sync-copy.patch). The shadow owns its value. Each sync copies and compares the whole container, and a vector with unassigned slots throws.
- **B:** Sync a container by the shape of its shadow slot. A Vector field whose shadow slot is a collection document (L10-6) syncs element by element, as sync_vector_result! of omnet-julia does by hand. Any other mutable container gets the copy of A. A field that no view reads leaves the sync through a new document trait (a new seam), and omnet-julia leaves out ParallelEngine.green_buf.
- **C:** Keep the reference, and write the cell of a mutable container on each sync with no compare: no copy, but each reader computes again on each sync.
- **D:** Keep the reference. The docstring says that a mutable leaf is shared and never invalidates, and a caller syncs such a field by hand.
- **Recommended (mine): B.** The shadow exists so that the reactive side owns its values and shows no intermediate state (the header of DocumentSync.jl). C and D keep the alias, so a reader of the shadow sees the source while it changes, also while the worker threads of the parallel engine write it. A is correct, but it copies and compares one million slots of green_buf in each slice, and it throws on the unassigned slots. B keeps the ownership, makes an append cost one element, and takes green_buf out of the sync; no view reads it (its shadow has a buffer of capacity 1).
- Depends on: L10-6.
- Cost: DocumentSync.jl and DocumentInterface.jl (the trait and the docstrings); a test in DocumentContractTest.jl or BoundedSyncTest.jl. The compare of a copied container must skip unassigned slots. omnet-julia: one trait method for ParallelEngine; sync_vector_result! can go. No sealed file. The name of the trait is a decision. Size M.
- **Risk:** It depends on L10-6, and a new document trait keeps a buffer such as `green_buf` out of the sync.

**L03-3** (Medium): Shall the engine detect a cycle and throw an ordinary exception that a barrier can record?

- **A:** Find a re-entry: a read of a cell in the state 'computes now' throws an ordinary exception that names the cell (for example CellCycleException). A barrier records it. Under L03-1, each cell of the cycle stores it until a write breaks the cycle.
- **B:** Keep the stack overflow, and state in cell.md and PAR-ACYCLIC-CELLS that a cycle, a direct self-read too, stops the editor.
- **C:** Find the cycle only in a build with the counters switch on.
- **Recommended (mine): A.** A StackOverflowError is a passthrough exception (FaultDefaults.jl), so one cyclic printer stops the whole editor, and no barrier can record it. The check costs one compare, and only on the path that already finds an invalid cell. The formula slice guards a cycle with a process-wide Set (_EVALUATING, FormulaDocument.jl:311); with A it can drop that global and catch the exception to answer #CYCLE!.
- Depends on: L03-2.
- Cost: ReactiveCell.jl 🔒 and CellModule.jl 🔒 (the export of the new exception type); cell.md and PAR-ACYCLIC-CELLS in architecture-invariants.md; FormulaDocument.jl; CellTest.jl (a cycle and a direct self-read). The name of the exception is a decision; CellCycleException ends in Exception, as naming-rules.md requires. Size S.

**L05-1** (Medium): As L03-2: does the engine get a state for a cell that computes now?

- **A:** The engine fix of L03-2: a reader that computes when the heartbeat writes stays invalid after its computation, so the next frame computes it again.
- **B:** Change no engine code. Keep the sentence in the docstring of start_wall_clock! (done in 40496d8b8): a computation that reads the clock must not yield.
- **C:** The heartbeat does not write the clock cell at a yield. It puts the time into a store, and the owner writes the cell between frames.
- **Recommended (mine): A.** It is the same fault as L03-2, so one engine fix answers both. C moves the write away from the yield for the clock only; any other task that writes a cell at a yield still meets the fault.
- Depends on: L03-2.
- Cost: No work of its own after L03-2. The sentence 'must not yield' in Clock.jl 🔒 can then go, if you want. Size S.

**L10-11** (Medium): Does the `@document` expansion ask its seams at run time, or stay at expansion time with a guard on the load order?

- **A:** Emit the substitution as a call at run time: the generated code asks get_cell_layout_field_type when it runs.
- **B:** Stay at expansion time, and fix the order: CellVector.jl registers the Val{:Vector} method before its own @document declaration, spells its own storage so that the substitution skips it, and a test checks the order.
- **Recommended (mine): B.** A call at run time does not remove the order problem. The aliases and the struct types are fixed when the module that declares them loads, so a schema in a package that loads before the collection package keeps the plain type with either option. The Revise case of CellVector itself also needs its own storage to skip the substitution with either option. B fixes that case, and a test holds the order that 3bdf2eb2 checked by hand.
- Depends on: L10-6.
- Cost: CellVector.jl (the order, and how it writes the type of its elements field); a test of the order; the docstring of get_cell_layout_field_type says that a package that does not load the collection package gets no substitution. DocumentMacro.jl does not change. Size S.

**L10-6** (Medium): Does a field declared `Vector{T}` become a `CellVector` in every constructor and copy of the cell layout, as commit 3bdf2eb2 and the docstring say, or does the substitution go?

- **A:** Make the substitution real. The bare constructor, ICFoo, MCFoo, the kind copy and the sync turn a raw AbstractVector of a field declared Vector{T} into the registered collection (CellVector) in the cell layout. The native layout keeps the plain Vector.
- **B:** Remove the substitution: delete get_cell_layout_field_type, its method in CellVector.jl, _cell_value_types and the claim in the docstring. A schema that wants one cell for each element declares CellVector.
- **Recommended (mine): A.** The substitution is your own design (3bdf2eb2): a declaration states the plain type, and each layout gets what it needs. Today it works nowhere: ICFoo and MCFoo throw a MethodError for such a field, so no code that works depends on the present state. omnet-julia already builds by hand what A gives (lift_parameter_value in Parameters.jl:208, sync_vector_result! in VectorResult.jl), and L10-3 needs a shadow collection for its element sync.
- Settles: L10-3, L10-11.
- Cost: DocumentMacro.jl, DocumentCopy.jl, DocumentSync.jl and DocumentInterface.jl; tests. No sealed file. A rough count finds about 55 @document schemas with about 90 fields of type Vector{T} in the three repositories (17 schemas in projectured-julia, 37 in omnet-julia, 1 in inet-julia). Where code builds a cell layout of such a schema from raw values, the field then holds a CellVector, which is a Document and not an AbstractVector, so a reader that needs a plain Vector (a typed argument, sort!, resize!) breaks. Size L, with a sweep of omnet-julia.
- **Risk:** About 90 `Vector{T}` fields of about 55 schemas in the three repositories change their value, and a reader that needs a plain `Vector` breaks, because a `CellVector` is not an `AbstractVector`. Sweep the readers first; if many break, drop the substitution instead.

**L10-7** (Medium): What must a plain copy, a kind copy and a sync do at a back-link: throw a DocumentCopyException, or share or skip the node?

- **A:** In all three walks, throw DocumentCopyException when a node comes back inside its own copy or sync, as DuplicatePolicy does. A document kind with real back-links adds its own copy and sync, as ListNode does.
- **B:** Share: at a back-link, the copy keeps the original node, so the copy points into the source tree.
- **C:** Skip: at a back-link, the slot gets a placeholder (the placeholder of the policy, or nothing).
- **D:** Copy the graph in two phases, and point the back-link of the copy at the copy of its owner, as deepcopy does.
- **Recommended (mine): A.** DuplicatePolicy already throws at a back-link (DocumentCopy.jl:99), so A gives one rule for every walk. B puts an alias of the source into the copy, the same fault as L10-3. D can not write a back-link into an ImmutableCell slot. A StackOverflowError goes through every barrier, and a DocumentCopyException does not. ListNode.jl shows the extension for a kind that needs its back-links.
- Cost: DocumentCopy.jl and DocumentSync.jl: a chain of the nodes in progress (a vector, searched by identity, with a push and a pop for each node). It finds every cycle, because a cycle always comes back to a node on the current path. DocumentInterface.jl: the docstrings. Tests with a toy back-link. No sealed file. Size S.

**L10-9** (Medium): How does the walk keep out of closures, types and the undo history: new walk leaves and an opaque history container, or a default `descend` that follows `get_edited_field`?

- **A:** New walk leaves (Function, Type, Module, Task), and an opaque history container: the undo package keeps its entries in a type with is_walk_opaque.
- **B:** A default descend that follows get_edited_field: at a node that names an edited field, the walk enters that field and no other.
- **C:** Both: the leaves of A for values that are never content, and the default descend of B for a wrapper, limited to its document children, so that a scalar field such as the title of a tab still matches.
- **Recommended (mine): C.** The two parts answer two faults. A closure, a type, a module and a task are never document content, so a fixed rule of the walk fits them, with no seam. A history, a stored copy and a bar are not on the screen, and get_edited_field already names the field that is: its docstring says that a walk follows these fields, and six types answer it. B alone still enters a closure that a document holds; A alone makes each wrapper package add a container type.
- Cost: DocumentWalk.jl (not sealed; you keep its re-seal for your own review) and DocumentInterface.jl; DocumentWalkTest.jl. is_pane_search_step and _is_draft_search_step can then get smaller. search_documents and search_references no longer find nodes in an undo history or in a clipboard copy. Size S to M.

**L11-11** (Medium): Do the step types keep `@document [C, M]` as the ruling of 2026-08-24 says, or drop the injected selection field and use an immutable value layout, and do the `type` and `head` cells of a path node become immutable?

- **A:** Keep @document [C, M] as you decided on 2026-08-24, and change nothing.
- **B:** Keep the [C, M] families, but declare each step with an explicit last field selection::ImmutableCell{Nothing}, and make the type and head cells of a path node immutable cells. Only tail, start and stop stay reactive, because the selection writer writes them in place.
- **C:** B, and an immutable value layout [C, I] in place of M. The M... step names become I... names.
- **D:** Build the steps with a layout list of the struct layer and not with @document (a new mechanism).
- **Recommended (mine): B.** B keeps your decision of 2026-08-24 and removes only what that decision does not name. No code writes the type or the head cell of a path node in place, and nothing selects inside a step, so these cells only add dependency edges and memory. The selection writer writes tail, start and stop in place (SelectionDefaults.jl), so those stay reactive.
- Cost: ReferenceStep.jl and ReferencePath.jl (not sealed); a test that a computation that reads a path records no edge to its head or type cell. C also renames 148 uses of the five M... step names in 34 files of omnet-julia. Size S for B; M for C.

**L16-1** (Medium): May the sealed cell layer get a primitive that runs a function with no dependency record, so that the reconcilers build a child IoMap outside the list computation?

- **A:** Add a primitive to the cell layer that runs a function with an empty stack of computations (for example run_untracked(f)), and let the reconcilers call make_iomap inside it.
- **B:** No new primitive: build each new child IoMap in a cell of its own and read it with peek, so that the reads of the child printer go to that cell.
- **C:** Change no code, and state that the list cell depends on the reads of each new child printer.
- **Recommended (mine): A.** An untracked scope is the usual primitive of reactive libraries (untrack in Solid, untracked in MobX), and cell.md already compares peek with it. peek covers one cell, and a child printer reads many. B makes a cell for each new child that nothing keeps; its weak edges stay in the dependents of each cell that it read until the collector runs, so has_dependent_cells answers true for a while. C keeps the extra computations of item 1 of the finding.
- Cost: ReactiveCell.jl 🔒 and CellModule.jl 🔒 (the primitive and its export), cell.md; IoMapReconcile.jl; CellTest.jl and a test that the child list does not depend on a cell that only a child printer reads. The name is a decision; run_untracked starts with a verb. Size S.

**L04-2** (Low): Must the generated setter refuse a cell as a value, at the cost of one type test on each write?

- **A:** The generated setter throws an ArgumentError when the value is a cell, and the message points to getfield for a shared cell. The setter that @document generates (_emit_accessors) gets the same check.
- **B:** Keep the setter as it is, and state in PAR-NO-NESTED-CELL that a write through the setter can store a cell as a value.
- **C:** A write of a cell of the type of the field puts that cell in place of the cell of the field, as the constructor does.
- **Recommended (mine): A.** PAR-NO-NESTED-CELL says that a field never holds a cell as its value, and the constructor of the same struct already refuses it. The type test costs nothing where the compiler knows the type of the value, because it removes the test; only a write through a dynamic dispatch pays one type compare. C is not possible for an immutable struct, which every @document cell layout is, and it would change which cell the readers depend on.
- Cost: CellStruct.jl 🔒 (the generated setter) and DocumentMacro.jl (_emit_accessors); CellStructTest.jl (the set that L04-10 left for this decision). Every struct of cells gets the check, so a run of the suites and of omnet-julia must show that no writer stores a cell through the setter. Size S.

**L04-3** (Low): What does a Computation argument give to a type parameter?

- **A:** A Computation gives Any: add get_cell_struct_argument_type(::Computation) = Any. A bounded parameter (A<:Real) then throws a TypeError.
- **B:** A Computation throws an ArgumentError that asks for the explicit form T{A}(...).
- **C:** A Computation, and a cell whose value type is Any, give the parameter its declared bound (Any when it has none).
- **Recommended (mine): C.** The value type of a computation is not known before it runs, so the widest type that the declaration allows is the true answer. A Cell argument has the same fault today: Cell(1) gives Any, and a parameter A<:Real then throws a TypeError. C answers both with one rule, and for a parameter with no bound it is the same as A.
- Cost: CellStruct.jl 🔒 (the constructor that infers the parameters, and get_cell_struct_argument_type); DocumentMacro.jl (its own such constructor calls the same function); CellStructTest.jl. No caller in the three repositories passes a Computation to a parametric struct today (SequentialEvent{A} of omnet-julia uses ImmutableCell, which refuses a Computation). Size S.

**L04-4** (Low): Does the sync ask for the kind of each field, or does a struct of mixed kinds never reach the sync?

- **A:** Export a query of the kind of one field (for example get_cell_struct_field_kind(x, name)), and let every walk ask each slot.
- **B:** Keep get_cell_struct_kind as it is. The field walk already takes the kind from the cell of each slot (L10-17). The collection walk and the list sync take the kind of the first field, and their docstrings say so.
- **C:** Refuse a struct of mixed kinds in the sync with a clear error.
- **Recommended (mine): B.** Since L10-17, _sync_fields! reads the kind of each slot (_get_slot_kind in DocumentSync.jl), so a record of mixed kinds syncs correctly now. Only _sync_elements! and _sync_list_tail! (ListNode.jl) use one kind, and for a collection the kind of its element container is the right kind for a new element. The docstring of get_cell_struct_kind already says that it reads the first field.
- Cost: Text only: DocumentSync.jl and the sync_document! docstring in DocumentInterface.jl; no sealed file. A test in DocumentContractTest.jl with a DC layout of mixed kinds. Size S.

**L04-5** (Low): Does @cell_struct apply Rule Y, as macros.md says, or only @document?

- **A:** build_cell_struct_exprs calls the builder of the positional constructors, so @cell_struct, @iomap and @projection apply Rule Y, after a check that no generated method collides with a hand-written one.
- **B:** Only @document applies Rule Y. Correct macros.md:48, and say it in the docstring of build_cell_struct_positional_constructors.
- **Recommended (mine): B.** A method that Rule Y generates and that has the signature of a hand-written outer constructor is a fatal method overwrite during precompilation. The work on @document met this several times (a widened guard, and the order of the fields). Every @iomap and @projection struct of three repositories would take that risk, for a small gain: the keyword constructor already covers a field with a default.
- Cost: B: macros.md, and one sentence in a docstring of CellStruct.jl 🔒 if you want it there. A: CellStruct.jl 🔒, and a load of every package of the three repositories with --warn-overwrite=yes. B is size S; A is size M.

**L04-6** (Low): Shall the generated methods point to the declaration of the struct, with a new source argument on the exported builders?

- **A:** build_cell_struct_exprs takes a keyword source (default nothing) and puts it in place of the line nodes of the parts that it generates. @cell_struct, @document, @iomap and @projection pass __source__.
- **B:** Keep the kernel file as the location of the generated methods.
- **C:** Remove the line nodes from the generated parts, so that a method has no file location.
- **Recommended (mine): A.** A stack trace, methods(T) and the hint of a MethodError must send the reader to the declaration of the struct, not to the kernel file. A keyword with a default keeps every caller of the exported builder as it is, and a keyword keeps the rule of three positional arguments.
- Cost: CellStruct.jl 🔒 (the keyword and one private helper that replaces the line nodes); DocumentMacro.jl, IoMapDefaults.jl and ProjectionMacro.jl pass __source__. A test that functionloc of a generated constructor names the test file. Size S.

### Group 6

**Time bounds, the inbox and the loop** (11 questions). The value of each time bound, what happens when it runs out, and a full inbox. POLICY-6-time and POLICY-6-inbox answer most of the group.

#### POLICY-6-inbox

- **A:** Three states and two queues: a bounded inbox for other tasks, a queue with no bound for the editor task and for posts before the loop, and a close of both at the end of the loop.
- **B:** Code on the editor task applies an operation at once and never posts; a feed drain calls a guarded apply (the report fix of L21-5).
- **C:** One inbox with no bound for every task.
- The rules of option A:
  - I1. An editor has three states: made (no loop yet), running, and ended.
  - I2. While the loop runs, a post from another task goes into the bounded inbox (64), and the producer waits when it is full. This keeps the backpressure that post_operation! promises.
  - I3. A post from the editor task (current_task() === editor.loop_task) goes into a second queue with no bound, which the next drain takes first. The post sets wake_pending, so the next frame runs at once. The editor task never waits on its own inbox, so the tooltip drain (TooltipRest.jl:99) and post_pane_operation! (PaneProgram.jl:839) stay as they are. Only the editor task fills this queue, so the work of one frame bounds it. The feed contract says that a drain may post.
  - I4. Before the loop starts, a post from any task goes into the second queue, because no task drains yet and the task that posts can be the task that later runs the loop. The queue is a Channel with no bound, so any task may put into it.
  - I5. At its end, run_editor! closes both queues before it answers the calls that wait. A later post throws, because nothing will ever apply it; omnet-julia sync_watch! then gets an exception in place of a hang. A put! that waits on a full inbox wakes with the same exception, because close(channel, exception) wakes every waiter. run_on_editor_task! catches it and runs the call at once on the task that calls, as for an editor with no loop: no frame runs, so nothing races. This also closes the window between its read of loop_task and its post.
  - I6. An editor runs its loop once. run_editor! on an ended editor throws an ArgumentError: the end quit the backend, and only make_editor starts a backend.
- **Recommended (mine): A.** A gives each producer what it needs: backpressure for another task, no wait on itself for the editor task, and a clear failure after the end. B can not serve post_pane_operation!, which posts on purpose so that one evaluation does not run inside another, and a direct apply from a drain passes the operation barrier and its repairs, which are private to the editor layer.
- Settles: L21-5, L22-4, L22-3, L20-1.
- Cost: editor/Inbox.jl, Editor.jl (a queue and the state), EditorLoop.jl (the close and the refusal of a second run), feed/FeedInterface.jl (docstring), InboxTest.jl; no sealed file; omnet-julia Watch.jl may catch the exception to stop its driver. M.

#### POLICY-6-time

- **A:** Bound each wait by what it waits for: a stream by its silence, a call by its wait in the queue, a tool by a stated budget. A round and a turn get no clock of their own. A person can cancel a turn.
- **B:** Give each round (and each turn) one wall-clock limit that the event wrapper of the loop checks, as the report of L20-1 proposes.
- **C:** A and B together.
- The rules of option A:
  - T0. The editor task never waits for a party that it does not own: no network read, no sleep for another task, no take! on a channel that another task fills. A frame ends because each drain and each read loop has a bound (done in L21-4, L22-2, L22-5).
  - T1 (L19-2). A silence bounds a stream, not its length. Each adapter sets connect_timeout and keeps its own watchdog: a Timer that the adapter resets at each chunk and that closes the connection when it fires. max_tokens of the request bounds the length. The adapter does not use the readtimeout of HTTP.jl for a stream: in HTTP.jl 1.11 timeoutlayer wraps streamlayer and try_with_timeout bounds the whole call, so a readtimeout cuts a long answer. When the watchdog fires, the adapter throws an error that names the bound ('the server sent nothing for 60 s'). The stream_turn docstring promises it: every stream ends with LlmTurnEnd or LlmFailure, or the call throws; an early end and a silence throw.
  - T2 (L20-1). A round and a turn get no clock of their own. A round is one stream (T1) and its tool calls (T3, T4); a turn is at most max_rounds rounds. When a stream throws, run_turn! throws, as its docstring says, and the assistant ends the turn with status :error and an 'Error: ...' part; the next submit works. The person ends a long turn with the cancel of L20-2.
  - T3 (L20-1, L22-3). run_on_editor_task! with wait = true takes a keyword timeout, 30 s by default, that bounds the wait until the editor STARTS the call. When it runs out first, the call is withdrawn (the editor skips it) and the caller gets an EditorCallTimeoutException. After the start, the caller waits for the end: Julia can not stop a task half way, and a half-applied write needs the repair of an operation fault. run_turn! and the MCP handler turn the exception into a tool result with is_error = true, so the model reads it and the turn goes on. After the end of the loop, POLICY-6-inbox applies.
  - T4 (L18-9). A Tool says where it runs; the default is the editor task. The searches and the resource reads read no editor state, so they run on the task that calls them, and their waits (the embed request, the wait for a vector build) never hold the editor. Model code stays on the editor task, because only that task writes a document that a running editor shows (PAR-STORE-THEN-DRAIN). Julia can not stop a task that does not yield, so model code gets a stated budget: the tool description says it, and the answer of a call that held the window longer carries a note that tells the model to start long work on a task of its own. The hard stop is the interrupt of the person (L18-10).
  - T5 (L22-7). wait_for_input runs in the :device barrier with a counter of its own, :device_wait, and the limit 8, as the two other halves of the device seam. In place of a wait that threw, the loop sleeps one poll slice of 0.01 s, so a wait that throws at once can not use all of a processor. Past the limit, the loop stops the call of the backend wait and polls in slices of 0.01 s, as the default wait of BackendDefaults.jl:20 does. The retry of a stopped half follows L22-9.
  - T6 (L22-12). The frame clock is a time of the backend, so its seam goes to the other backend seams.
- The values:
  - connect: 10 s for both adapters; Ollama /api/show gets connect 5 s and a total of 10 s (it has no bound today)
  - first chunk: Anthropic 60 s; Ollama 300 s (a local server loads the model and reads the whole prompt before its first line; 300 s is the readtimeout of its embed request)
  - between two chunks: 60 s for both adapters
  - wait of a call in the editor queue: 30 s
  - budget of model code: 10 s, stated and reported, not enforced
  - wait for a vector build: 30 s, as now, but off the editor task
  - pause after a failed loop wait: 0.01 s
  - limit of :device_wait: 8
- When a bound runs out:
  - stream: the adapter closes the connection and throws an error that names the bound
  - turn: run_turn! throws; the assistant shows the error part and sets status :error; a cancel ends the turn with :cancelled
  - call: withdrawn before its start; the caller gets EditorCallTimeoutException; the agent loop and the MCP handler answer a tool result with is_error = true
  - tool budget: the answer gets a note and the editor logs one warning line
  - loop wait: one pause of 0.01 s, then a poll past the limit
- **Recommended (mine): A.** Each wait gets one bound, at the side that waits, with a value that fits what it waits for. One clock on a round can not tell a slow answer from a dead server: a local model on a processor streams one answer for many minutes, and the on_event wrapper of B runs only when an event arrives, so it can not end a silent stream.
- Settles: L20-1, L19-2, L18-9, L22-3, L22-7, L22-12, L20-2.
- Cost: Agent layer, editor layer (Inbox.jl, EditorLoop.jl, FaultBarriers.jl), tool layer (Tool.jl, ToolSet.jl, DefaultTools.jl, CodeExecution.jl), LlmInterface.jl docstring, source/adapter/anthropic, source/adapter/ollama, source/adapter/mcp, source/platform/assistant; no sealed file except T6 (three backend files); omnet-julia only through the cancel keyword of L20-2. L in total, in S and M steps.

**L20-1** (High, main question): What time limit bounds a round, a tool call that waits for the editor, and a stream read, and what does the turn do when a limit runs out?

- **A:** POLICY-6-time: one bound for each wait (stream silence, queue wait of a call, stated tool budget), no clock for a round or a turn, and a cancel.
- **B:** A time limit per round in Agent that the on_event wrapper checks, a read timeout in the adapters, and a timeout keyword of run_on_editor_task! (the report).
- **C:** One clock for the whole turn.
- **Recommended (mine): A.** The on_event wrapper of B runs only when an event arrives, so it can not end the silent stream that the finding describes, and a clock on a round or a turn cuts the long answer of a slow local model. The race at the end of the loop goes away with the close of POLICY-6-inbox.
- Depends on: L19-2, L20-2.
- Cost: See POLICY-6-time. L in total.

**L21-5** (Medium, main question): How does code on the editor task apply an operation when the inbox can be full: apply it at once and never post from a drain, or post into a queue of the editor task with no bound?

- **A:** Apply the operation at once on the editor task, and never post from a drain (the report).
- **B:** Post into a queue of the editor task with no bound, which the next drain takes first (POLICY-6-inbox I3).
- **Recommended (mine): B.** See POLICY-6-inbox: A can not serve a post that must wait until the evaluation in progress ends (post_pane_operation!), and a direct apply from a drain passes the operation barrier and its repairs, which are private to the editor layer.
- Settles: L22-4.
- Cost: editor/Inbox.jl, feed/FeedInterface.jl (docstring); TooltipRest.jl stays as it is. S.

**L01-2** (High): Which layer stops the growth of the targets: the sealed store, with a detach when the safe mode ends, or the safe-mode projection above the kernel, with one log for each store?

- **A:** The sealed store gets detach_fault_target!, and the safe mode detaches what it attached when it ends.
- **B:** The safe-mode projection above the kernel keeps one log for each store and attaches no new one at each entry.
- **C:** The editor keeps the first safe-mode projection that it made and uses it again at each entry; the store already refuses a second attach of one target.
- **Recommended (mine): A.** Each attach then has its detach, so a log that nothing shows stops getting writes, and the safe mode owns what it attached. B needs a table keyed by store in ProjecturedFault, a process-wide table of per-editor state (PAR-PER-EDITOR-STATE), and C keeps a hidden log that each drain writes for the life of the editor.
- Depends on: L01-12.
- Cost: FaultStore.jl and FaultModule.jl (sealed); editor/SafeMode.jl; source/platform/fault/FaultSafeMode.jl; FaultStoreTest.jl, FaultSafeModeTest.jl. S.

**L18-4** (High): Does the code tool keep the process-wide swap of stdout and stderr, with a lock and a stated exception to PAR-PER-EDITOR-STATE, or capture each call with a new mechanism that does not touch the process streams?

- **A:** Keep the process-wide swap of stdout and stderr, hold one process lock around it, and state an exception to PAR-PER-EDITOR-STATE.
- **B:** Install once a stdout and a stderr that send each write to the capture of the call that the writing task belongs to (a scoped value that the tasks of the call inherit), else to the console; run each call under a logger that writes into the same capture.
- **C:** Capture nothing: the answer holds only the value of the last statement.
- **Recommended (mine): B.** With A, one code call holds every code call of the other editors for its length, and the output of every other task of the process goes into its answer; PR-MANY-EDITORS-ONE-PROCESS says that one editor must never slow another, and on a web server with one editor for each person A gives one person's output to the model of another. B needs no change of Julia: in 1.13 Base.stdout is a global of type IO, and the logger state and a scoped value follow each task that a call starts.
- Cost: tool/CodeExecution.jl, ToolModule.jl (docstring), a stated carve-out in architecture-invariants.md (the router is the same for every editor), CodeExecutionTest.jl. M.

**L18-9** (Medium): How does a tool call bound the time that it holds the editor task?

- **A:** Keep every tool call on the editor task; the meaning search answers 'not ready' there and does not wait; the description states a bound for model code (the report).
- **B:** A Tool says where it runs, the editor task by default; the searches and the resource reads run on the calling task; model code keeps a stated budget of 10 s and gets a note when it held the window longer (POLICY-6-time T4).
- **C:** Run model code on a task of its own, and send only its writes through run_on_editor_task!.
- **D:** A watchdog interrupts model code after a hard bound.
- **Recommended (mine): B.** The searches read no editor state, yet today the query vector (an HTTP request of up to 300 s) and the wait for a vector build (up to 30 s) run on the editor task, and A still keeps the request there. C lets a direct write of model code land inside a frame that yields, although PAR-STORE-THEN-DRAIN gives the write of a shown document to the editor task only, and D can not stop a loop that does not yield.
- Depends on: L18-10.
- Cost: tool/Tool.jl (a keyword of Tool), ToolSet.jl, DefaultTools.jl, CodeExecution.jl, agent/AgentLoop.jl, source/adapter/mcp/McpServer.jl. M.
- **Risk:** A keyword on `Tool` that says where it runs is close to the opt-in flag that you avoid.

**L19-2** (Medium): What read timeout do the adapters set on a stream, and does the `stream_turn` contract promise one?

- **A:** The adapters set the readtimeout of HTTP.jl on the stream request, and the contract promises it.
- **B:** Each adapter keeps its own watchdog, a bound for the first chunk and a bound between two chunks, reset at each chunk; the stream_turn contract promises that a silence longer than the bound throws.
- **C:** No read bound in the adapters; the loop bounds the round.
- **Recommended (mine): B.** In HTTP.jl 1.11 readtimeout bounds the whole request body (timeoutlayer wraps streamlayer, and try_with_timeout bounds the whole call), so A cuts a long answer that streams. Today neither stream request sets a bound, so a silent server holds the turn for ever.
- Settles: L20-1.
- Cost: LlmInterface.jl (docstring), source/adapter/anthropic/AnthropicLlm.jl, source/adapter/ollama/OllamaLlm.jl, one test in each adapter test package (a stub server that sends one chunk and then nothing). S-M.

**L20-2** (Medium): Can a person cancel an agent turn, and through what: a `cancel` keyword of `run_turn!` with a stop operation in the assistant?

- **A:** A cancel keyword of run_turn! (a flag), checked before each round, in the on_event wrapper and before each tool call; the stop reason :cancelled; a stop operation of the assistant sets the flag (the report).
- **B:** A, and stream_turn takes the same keyword: the watchdog of the adapter (POLICY-6-time T1) closes the connection when the flag is set.
- **C:** No cancel; the bounds of POLICY-6-time end a turn that hangs.
- **Recommended (mine): B.** With A alone a cancel waits for the next event, and a silent server sends none, so the person waits for the watchdog, up to 300 s for Ollama. A closed connection also stops a local server that generates for nobody.
- Depends on: L19-2.
- Cost: AgentLoop.jl, LlmInterface.jl (the keyword in the contract), agent.md, source/adapter/anthropic, source/adapter/ollama, example/kernel/LlmFake.jl and LlmScripted.jl, source/platform/assistant/AssistantTurn.jl (a CancelAgentTurnOperation and its key); omnet-julia tool/assistant/study_rehearsal.jl (WatchedLlm passes the keyword on). M.

**L22-12** (Medium): Does `get_frame_clock_time` move into the backend layer, as PAR-BACKEND-SEAM asks, with permission for three sealed files?

- **A:** Move the seam: declare it in BackendInterface.jl, its default in BackendDefaults.jl, export it from BackendModule.jl, and change the import of ProjecturedVideo.
- **B:** Keep it in the editor layer, and state in PAR-BACKEND-SEAM that a seam that only the loop calls may live there.
- **Recommended (mine): A.** PAR-BACKEND-SEAM declares every backend generic in BackendInterface.jl, and the one method of this seam is the method of a backend (VideoBackend).
- Cost: BackendInterface.jl, BackendDefaults.jl, BackendModule.jl (sealed, permission for each); editor/EditorLoop.jl, EditorModule.jl; ProjecturedVideo.jl, source/backend/video/VideoBackend.jl. S.

**L22-3** (Medium): What does a post or a call do after the loop of its editor ended, and may an editor run its loop a second time?

- **A:** Close the queues at the end; a later post throws; a call runs at once on its own task; an editor runs its loop once (POLICY-6-inbox I5, I6).
- **B:** Close the queues at the end; a later post and a later call both throw.
- **C:** Allow a second loop: the end closes the inbox, and a new run_editor! opens a new one and starts the backend again.
- **Recommended (mine): A.** A post after the end can never apply, so a throw tells the producer at once, while a call with no loop already runs at once by the contract of run_on_editor_task!, and no frame races it. A second loop needs initialize_backend! again, which only make_editor calls, and no caller in the three repositories runs one editor twice.
- Settles: L20-1.
- Cost: editor/Inbox.jl, EditorLoop.jl, InboxTest.jl; omnet-julia Watch.jl gets an exception in place of a hang. S-M.

**L22-4** (Medium): How does code on the editor task post when the inbox can be full (the same question as L21-5)?

- **A:** Apply at once on the editor task, and never post from a drain.
- **B:** Post into a queue of the editor task with no bound (POLICY-6-inbox I3).
- **Recommended (mine): B.** Same question as L21-5; see POLICY-6-inbox.
- Settles: L21-5.
- Cost: editor/Inbox.jl. S.

**L22-7** (Medium): When `wait_for_input` throws, which counter counts it, with what limit, and how does the loop pause in place of the wait?

- **A:** A counter of its own, :device_wait, with the limit 8; one pause of 0.01 s in place of a failed wait; past the limit, a poll in slices of 0.01 s (POLICY-6-time T5).
- **B:** Count it on :device_read, the input half.
- **C:** No barrier: a wait that throws ends the editor, as now.
- **Recommended (mine): A.** is_editor_degraded says that the halves of the device seam fail apart, so a shared counter lets a read that works reset the count of a wait that fails. A failed wait returns at once, so without a pause the loop uses a whole processor; the poll is what a backend with no wait of its own does (BackendDefaults.jl:20).
- Depends on: L22-9.
- Cost: editor/EditorLoop.jl, FaultBarriers.jl (device_wait = 8 in _CONSECUTIVE_FAULT_LIMITS), FaultBarriersTest.jl. S.

### Group 7

**Many editors in one process** (7 questions). Whether a thing belongs to one editor. POLICY-7 answers the group. L21-1 is its main case, and it matters most for many editors on the web backend.

#### POLICY-7

- **A:** Each editor owns its state and each document that it shows; the process keeps only a value that is the same for every editor and that no editor writes for the others.
- **B:** Shared session state stays where it is, with an identity or a lock, and each case is a stated exception.
- The rules of option A:
  - E1. A store, a feed and a target document serve one editor. What an editor attaches (a wake, a fault target), it detaches at its end.
  - E2. A logger, an output capture or a context that an editor binds follows the tasks that the editor starts. In Julia 1.13 the logger state and a scoped value live in the scope that a new task inherits (src/task.c: t->scope = ct->scope).
  - E3. The process keeps a value only when it is the same for every editor and no caller writes it for the others (the carve-out of PAR-PER-EDITOR-STATE): the guide index of one list of roots, the API index, the meaning vectors of one model, a method that a package defines at load.
  - E4. A printer derives each context from the one that it receives, so the clock, the fault store and the policy of the editor reach every subtree.
- **Recommended (mine): A.** The owner names the web backend as the case that matters: a server with one editor for each person. There, a process-wide log, stream or registry shows the work of one person to another, which is worse than a mix of numbers.
- Settles: L21-1, L22-14, L22-15, L17-11, L18-13, L18-24, L11-12, L18-4.
- Cost: See each question.

**L21-1** (High, main question): Does a feed belong to one editor, and do the session stores of the log and the statistics stay process-wide?

- **A:** A feed belongs to one editor: the contract says it, and the message log, the frame statistics and the fault log get a store and a target document for each editor by default; the session documents go.
- **B:** Keep one session log as an accepted carve-out; its store keeps one wake for each editor, and one editor drains it.
- **C:** A, and a process log document for the lines that no editor logs.
- **Recommended (mine): A.** Today one editor writes the session log, the fault log (_SESSION_FAULT_LOG) and the statistics from its task while another editor shows them (PAR-STORE-THEN-DRAIN), and on a web server with one editor for each person a shared log shows the operations, code and faults of one person to another. B keeps that leak.
- Depends on: L22-15. Settles: L22-14.
- Cost: feed/FeedInterface.jl (docstring); ProjecturedLog, ProjecturedStatistics, ProjecturedFault (FaultDocument.jl), ProjecturedShell (WindowChrome.jl); omnet-julia IdeWindow.jl uses run_with_window_tools. L.
- **Risk:** A tab that shows the log or the faults needs a new way to find the document of its editor: a new mechanism.

**L11-12** (Medium): Does a rules answer keep its compile into a process-wide method table, with a lock and a collision check, or does the interpreter evaluate the common answer shapes with no eval?

- **A:** Keep the compile into the method table of ReferenceModule; hold one lock around the cache, the check and the definition; keep the expression beside its key and compare it with == before reuse; state in the docstring that a rule set is code.
- **B:** The interpreter evaluates the common answer shapes (a bound name, a literal, a quoted value, a tuple or vector of these) with no eval, and compiles the rest as in A.
- **C:** Decide L11-10 first; if the pattern language leaves the kernel, this question moves with it.
- **Recommended (mine): A.** No code outside the kernel tests uses @reference_rules or apply_reference_rules (L11-10), so a small change is enough, and A removes the three real faults: the race, the key collision of repr, and a program that a file brings in silence.
- Depends on: L11-10.
- Cost: reference/ReferenceRules.jl, ReferenceRulesTest.jl; no sealed file. S (A) or M (B).

**L17-11** (Medium): Does a subtree that a printer prints with a context of its own (the fault log, the gesture log, the two inspectors) inherit the clock and the fault store of the editor?

- **A:** Yes: the fault log and the gesture log derive their context from the one they receive, with_exact_size(make_child_context(ctx, EmptyReference()); width = nothing, height = nothing), as the inspectors do; the PrinterContext docstring states the rule.
- **B:** No for the two logs: they print outside the barriers on purpose, and the exception is stated.
- **C:** A, and PrinterContext() with no parent is for the root of a print only (the editor and tests), with a guard.
- **Recommended (mine): A.** The clock and the fault store are per editor, and a new context drops them: an animation in the log stays at time 0, and a barrier in the log finds no store, so a fault in one log row breaks the whole print. With A the barrier keeps the fault in the log panel, and the count buckets of the store bound a fault that the log itself causes.
- Cost: source/platform/fault/FaultLogOverlay.jl, source/platform/gesturelog/GestureLogOverlay.jl, projection/PrinterContext.jl (docstring); the fault and gesture log tests. S.

**L18-13** (Medium): Do the guide roots belong to one ToolSet, or stay a process-wide registry?

- **A:** The guide roots belong to one ToolSet: register_guide_root!(set, directory; prefix), and one cached guide index for each distinct list of roots, under _INDEX_LOCK.
- **B:** Keep the process registry, and state it as an accepted carve-out (an application adds its guides at load, for every window).
- **C:** Both: the process list holds the guides that every editor has, and a ToolSet adds its own.
- **Recommended (mine): A.** The carve-out of PAR-PER-EDITOR-STATE covers a value that no caller writes, but here a package that loads later changes the guides of every editor that runs, and a server with editors of different applications gives each editor the guides of the others. One cached index for each list of roots keeps the shared work, so the carve-out still holds for the cache.
- Cost: tool/Documentation.jl, DefaultTools.jl, MeaningSearch.jl, ToolModule.jl (docstring); omnet-julia OmnetCampaignUi.jl (__init__) and CampaignWindow.jl (register on the tools of the editor that it makes). M.

**L22-14** (Medium): How does an ended editor let go of the wake that it gave to a shared feed store?

- **A:** A detach pair: the feed contract gets detach_wake_callback!(feed) with a default that does nothing, the fault store gets its wake cleared, and the end of run_editor! calls both.
- **B:** attach_wake_callback!(feed, nothing) means detach; no new generic.
- **C:** The wake holds the editor through a weak reference, so a store that keeps the wake does not keep the editor.
- **Recommended (mine): A.** With L21-1 each store belongs to one editor, but a caller can still give one store to two feeds; then the contract says that a feed and its store serve one editor, a second attach throws in place of an overwrite, and the end detaches. A pair of names keeps the vocabulary symmetric, as detach_fault_target! of L01-2 does, and C hides the fault that two editors share one store.
- Depends on: L21-1, L01-2.
- Cost: feed/FeedInterface.jl, FeedDefaults.jl, FeedModule.jl (export), editor/EditorLoop.jl (_end_editor_loop!), source/platform/log/MessageLogFeed.jl, MessageLogStore.jl. S.

**L22-15** (Medium): Does each editor log under its own logger, or with an identity in the shared log?

- **A:** Each editor logs under its own logger: run_editor! runs its loop under with_logger, and the logger writes each line into the store of the editor and forwards it to the process logger with an editor keyword.
- **B:** One shared log in which each line carries an editor identity, and each view filters by it.
- **C:** As now.
- **Recommended (mine): A.** In Julia 1.13 the logger state is a scoped value and a new task inherits the scope, so the lines of the turns and the tool calls that an editor starts reach the log of that editor. B still sends the lines of every editor to every log store, and a filter is one more thing that a view can forget.
- Depends on: L21-1.
- Cost: editor/Editor.jl (a logger keyword and an identity), EditorLoop.jl (with_logger around the loop), source/platform/log/MessageLogCapture.jl (a logger for one store), source/platform/shell/WindowChrome.jl. M.

**L18-24** (Low): Does a ToolSet keep what a turn builds until the declaration or the model changes, and does the code tool log the length of an answer in place of its text?

- **A:** Yes to both: a ToolSet keeps its default tools, resources and meaning vectors until an input changes (the declaration, the meaning model, the guide roots); the code tool logs the length of an answer at @info and its text at @debug.
- **B:** Keep the rebuild at each turn, and log only the length.
- **C:** Keep both as now.
- **Recommended (mine): A.** Each turn walks the guide tree on disk, reflects over each module and gathers about 1.04 million characters for the vectors again, with no change of input. A log line with the whole answer floods the message log, and with a shared log it puts the data of one person into the log of another (POLICY-7).
- Depends on: L20-4, L18-13.
- Cost: tool/DefaultTools.jl, ToolSet.jl, MeaningSearch.jl (start the vectors only when the model name or the declaration changes), Documentation.jl (keep the guide list with the index), CodeExecution.jl (two log lines). S-M.

### Group 8

**Caret and range semantics** (11 questions). What a caret or a range between elements is. L12-1 with L11-8 comes first. L11-13 and L12-2 are one question.

**L12-1** (Medium, main question): What does the selection walk store for a caret {k} and for a range [i, j] between the documents of a collection?

- **A:** The walk stops at the collection for a caret and for a range of more than one item: the collection stores the step, and no document inside it gets a selection. An element step [i] goes into element i, as now.
- **B:** A caret stays on the collection. A range [i, j] writes a whole-element selection (the empty path) into each element from i to j.
- **C:** Keep the walk (a caret selects element k+1 as a whole, and a range marks only element i), and document it.
- **Recommended (mine): A.** Each node stores the rest of one path, so one selection has one branch; B needs several branches. The reference layer already reads a caret as a place that lands on no child (Position). With L11-8, a range also evaluates to a value on the collection and not to its first item, so the two layers read one step the same way. The printer of the collection draws the caret or the range from its own selection.
- Depends on: L11-8. Settles: L17-2.
- Cost: SelectionDefaults.jl 🔒: _selection_child goes into a child only for an element step. SelectionTest.jl. The printers of collections that draw a caret or a range between documents (JSON arrays and objects, syntax nodes) can need to read their own step. First, a run must confirm the fault (the finding is Suspected). Size M.
- **Risk:** The finding is Suspected: prove it by a run first.

**L11-8** (Medium, main question): What does a range step `{s:e}` with s < e evaluate to: its first item as now, a new span value beside Position, or the (start, stop) tuple of the text steps?

- **A:** Keep the first item. Document it, and correct the two literals of InsertionToSyntax.jl so that they record the type of the item.
- **B:** A new value beside Position, for example PositionRange(start, stop). A range that is not empty evaluates to it, annotate_reference_types records it, and the three text steps answer it in place of their tuple.
- **C:** The (start, stop) tuple of the text steps, for the kernel range step too.
- **Recommended (mine): B.** A caret already evaluates to a value that says where it is (Position), because a place between items is not a node. A range is not a node either. The first item hides the stop of the range, and a tuple has no type of its own for a checkpoint (PAR-FOLDED-CHECKPOINTS). One value for the kernel step and the text steps ends the two conventions.
- Cost: ReferenceStep.jl, ReferenceEvaluation.jl, ReferenceModule.jl (an export); TextRangeReferenceStep.jl, TextSpanReferenceStep.jl, TextColumnReferenceStep.jl; InsertionToSyntax.jl:107 and :126; reference.md; a search for callers that read the value of a range step. The name is a decision: PositionRange pairs with Position, and 'span' is already a word of the text domain. Size M.

**L11-13** (Medium): Which layer copies the range step of the caller: `strip_reference_types` in the reference layer, or `_matched_selection` in the selection layer?

- **A:** strip_reference_types answers fresh range steps, as copy_reference does, because it already builds a new node for each step (reference layer, not sealed).
- **B:** _matched_selection copies the path with copy_reference before it stores it (selection layer, SelectionDefaults.jl 🔒).
- **C:** Change no code, and keep the copy by hand at each caller.
- **Recommended (mine): A.** Every selection writer goes through _matched_selection, which calls strip_reference_types, so A closes the way in for every caller. strip already builds one new node for each step, so A adds only one step object for each range step, while B builds the whole path a second time. The reference layer already holds the rule that a range step is the one step that changes in place (_copy_reference_step). A changes no sealed file.
- Settles: L12-2.
- Cost: ReferenceEvaluation.jl: strip_reference_types calls _copy_reference_step, and its docstring says that the result shares no step that changes in place. A test that the path of a caller keeps its numbers after a caret move. Size S.

**L11-2** (Medium): On a `nothing` input, does a catch-all arm (`__ =>`, `rest... =>`) answer its result, as the compiled matcher does, or `nothing`, as the normative interpreter does?

- **A:** A catch-all arm answers its result for a nothing input, as the compiled matcher does; the interpreter changes.
- **B:** A nothing input matches no arm, and the case answers nothing, as the normative interpreter does; the compiled matcher changes.
- **C:** A new arm word matches only nothing, so that a case can say what 'no selection' answers; a catch-all matches only a path.
- **Recommended (mine): B.** nothing means 'no selection', which is not a path, so no path pattern can match it. The done plan reference-pattern-vocabulary.md makes the interpreter the normative matcher. A scan of the 33 '__ =>' arms and the 4 'rest... =>' arms in source/, and of the 2 arms in inet-julia, finds that each arm with an answer other than nothing is behind a 'reference === nothing && return' guard, or gets a Reference from its caller (the reference of a printer context is never nothing). So B changes no known result.
- Cost: ReferenceCase.jl: the compiled catch-all and the bare rest arm test for a Reference. The nothing rows of the corpus in ReferenceRulesTest.jl (L11-19 left them for this decision). A run of the suites must confirm the scan. Size S.

**L11-6** (Medium): Does `search_references` on a ReferencedDocument answer paths from the root (its reference prepended) or from its document, as D5 lifts `search_documents`?

- **A:** Paths from the root: search_references(x::ReferencedDocument, ...) searches get_document(x) and puts get_reference(x) in front of each path.
- **B:** Paths from its document: the lift of D5 passes get_document(x), as it does for search_documents.
- **Recommended (mine): A.** D1 defines the reference of a referenced document as the complete reference from the root, and each read through one already extends that reference (ReferencedDocument.jl:85 and :102). A path from the root goes straight into replace_referenced_value!, a selection write and ReplaceReferencedValueOperation, which all start at the root (one selection, written at the root). A path from the document fails there, as the finding shows. The lift of search_documents answers nodes and not paths, so it sets no rule for a path.
- Cost: ReferencedDocument.jl: one method beside the lift of search_documents (ReferenceSearch.jl 🔒 does not change). ReferencedDocumentTest.jl. One line in plan/pending/the-assistant-reaches-a-referenced-document.md, whose step 3 is in progress. Size S.
- **Risk:** The lifted `evaluate_reference` takes paths relative to the document, but the search answers paths from the root, so the pair can mislead a caller.

**L12-2** (Medium): Which layer copies a range step that a caller passes in: the selection writer, or strip_reference_types for every caller?

- **A:** strip_reference_types answers fresh range steps for every caller (reference layer, not sealed).
- **B:** The selection writer copies the path with copy_reference in _matched_selection (SelectionDefaults.jl 🔒).
- **Recommended (mine): A.** It is the same question as L11-13, with the same answer. Every writer goes through _matched_selection, which calls strip_reference_types, so a fresh step there closes the way in for every caller. The cost is one step object for each range step, and no sealed file changes.
- Settles: L11-13.
- Cost: See L11-13. Size S.

**L13-6** (Medium): Must a document-rooted write check the type checkpoints of its path and throw on a mismatch?

- **A:** Walk to the parent with the typed path. A node whose type changed throws ReferenceTypeMismatchException, the barrier records it, and nothing is written. The inverse walks the same way. A reader that makes wrong types gets a fix.
- **B:** Keep the strip. A document-rooted write goes to the node that stands at the place now, and the docstring says so.
- **C:** Check the types first with get_valid_reference_prefix, and refuse a stale path with an error that names the first node that does not match.
- **Recommended (mine): A.** An operation can wait (in the inbox, in a playback, or from an agent that built it against an older tree), and a stale path then writes into another node with no error. PAR-FOLDED-CHECKPOINTS tells a replay to go through the typed walk. evaluate_reference already throws on a typed mismatch, and a node with no recorded type still passes, so only a path with a wrong type throws.
- Cost: Operations.jl (the split of the terminal step must keep the types) and Inversion.jl; InversionTest.jl and a test with a stale operation. A run of the suites shows which readers make wrong types. A carried root (a widget, a projection parameter) stays as it is. Size S to M.
- **Risk:** It can show readers that build wrong types; a first pass can warn in place of a throw.

**L17-2** (Medium): What does a template mapper answer for a caret or a range on a collection: nothing, or the same range on the output?

- **A:** A template mapper answers nothing for a caret or a range on a collection; only an element step maps.
- **B:** Map a caret as a caret and a range as a range where the output child list holds one child for each element, in order. Answer nothing where it does not (separators, extra children, a bound index).
- **C:** Keep the start of the step, as now.
- **Recommended (mine): B.** Your decision on the one selection (2026-09-17) says that a range follows the same rule as a caret, and that only a range that a projection can not map in a simple way declines. Where the template builds one output child for each element, the map keeps the same index, so a caret between two items stays visible on the screen. C is wrong in both directions: a caret {2} maps to the element [3].
- Depends on: L12-1, L11-8.
- Cost: ProjectionTemplate.jl (about ten places that read after.head.start); ProjectionTemplateTest.jl with a caret and a range on a template collection. No sealed file. No producer of such a path through a template exists today (the finding is Suspected for the effect). Size M.

**L11-20** (Low): Does `@reference(document, path)` throw when a step does not resolve, and does `is_fully_typed_reference(nothing)` answer false, although the code comment calls `nothing` 'not our concern'?

- **A:** @reference(document, path) throws an ArgumentError that names the first step that does not resolve, as the one-argument form throws for a path that is not fully typed. is_fully_typed_reference(nothing) answers false.
- **B:** No throw: the docstring says that the rest of the path stays untyped after a step that does not resolve. is_fully_typed_reference(nothing) answers false.
- **C:** Keep both as they are, and delete the claim 'correct by construction' from the docstring.
- **Recommended (mine): A.** The two forms of one macro then keep one contract, and 'correct by construction' in the docstring becomes true. PaneProgram.jl builds the same check again by hand (_refuse_stale), which shows that a caller needs it. For nothing, a predicate that answers true for 'no path' states a false thing, and each caller today tests nothing before the call (ProjectionDefaults.jl:66, ProjectionTemplate.jl:767), so false changes no result.
- Cost: ReferenceBuilder.jl (a check after annotate_reference_types in the two-argument form); ReferenceEvaluation.jl (one line and its comment); PaneProgram.jl can keep its message or drop _refuse_stale; tests. A scan of the 39 two-argument calls in the three repositories must show that none names a slot that does not exist yet. Size S.

**L13-12** (Low): How does an undo put back 'no selection': may ReplaceSelectionOperation hold nothing?

- **A:** ReplaceSelectionOperation holds Union{Nothing, Reference}. nothing clears the selection from the root, and the inverse of a move from 'no selection' is ReplaceSelectionOperation(nothing).
- **B:** A new operation type for a clear, for example ClearSelectionOperation, with its rerooting and its route.
- **C:** Keep DoNothingOperation as the inverse, so that an undo leaves the caret where the move put it.
- **Recommended (mine): A.** replace_selection!(document, nothing) already clears (_matched_selection lets nothing through), so the operation only has to carry it. One operation type for each selection write needs no new registration (PAR-REGISTER-NEW-OPERATION). C breaks PAR-INVERTIBLE-OPERATIONS. nothing (no selection) stays apart from the empty path (the whole element).
- Settles: L22-22.
- Cost: Operations.jl (the field type), Inversion.jl (_make_selection_inverse), Rerooting.jl (a clear reroots to a clear, and its route is the root), Description.jl (a text for a clear); InversionTest.jl. A reader that matches ReplaceSelectionOperation and reads op.path must accept nothing, so a scan of the read_intent methods is necessary (MarkdownToSyntax.jl already tests 'path isa ConcreteReference'). Size S.

**L22-22** (Low): Does the selection repair go through an operation, and which one?

- **A:** The repair evaluates ReplaceSelectionOperation(nothing) through evaluate_operation, in the same barrier.
- **B:** A new operation type for a clear (ClearSelectionOperation).
- **C:** Keep the direct write, and state in PAR-ONE-WAY-TO-EDIT that a repair of the editor is not an edit.
- **Recommended (mine): A.** PAR-ONE-WAY-TO-EDIT names evaluate_operation as the one way to change the document, and a log or a playback then sees the repair. With L13-12, the one selection operation carries a clear, so no new type is necessary. The write still starts at the root, so PAR-SELECTION-WRITTEN-AT-ROOT holds.
- Depends on: L13-12.
- Cost: FaultBarriers.jl (not sealed); a test in the editor suite that a failed operation leaves a clear of the selection. Size S.

### Group 9

**Editing and fault semantics** (12 questions). Behaviour that a person sees. L13-1 and L01-1 are High.

**L13-1** (High, main question): Where does a number text that does not parse yet, such as '-' or '1e', live while the person types?

- **A:** The number field holds the text as a String until it parses; splice_number answers the text, and each number field admits a String (the report).
- **B:** A typed transient value: splice_number answers an UnparsedNumber(text) when the text does not parse; each number field admits it; printers show its text; a writer or a computation that needs a number refuses it by dispatch.
- **C:** The text stays in the state of the text layer or the IoMap, and the field changes only when the text parses.
- **D:** An unparsed number turns into the insertion document of its domain, and back into a number when its text parses.
- **Recommended (mine): B.** PAR-WIDE-FIELD-TYPES and PAR-DOMAIN-OWNS-EDITS put the intermediate state in the document, so the undo, the selection and every view see it (C keeps it outside), and a typed value keeps 'a number, or a number that the person still types' apart from a String, which a consumer of A can not tell from a string value without a parse. D swaps the node type at each key that crosses from parse to no parse, which changes the type checkpoints of the selection path, and the kernel splice knows no domain insertion.
- **Decided by the owner, 2026-10-05: D**, through S-5 of [strict-document-types.md](strict-document-types.md): an incomplete number becomes the insertion of its domain, if the domain has one. The work belongs to that plan. The primitive domain does D already in its reader (`make_number_edit_operation`), not in the kernel splice, so the kernel splice needs no domain insertion.
- Cost: kernel/operation/Operations.jl and OperationModule.jl; source/platform/primitive/PrimitiveDocument.jl; the number fields and printers of each domain (JsonNumber and others); source/platform/projection/ReaderDefaults.jl:61; source/platform/clipboard/Clipboard.jl:309; the writers. No sealed file. M-L.

**L01-1** (High, main question): How must a fault that the full store drops reach a person?

- **A:** The drain answers the growth of dropped since the last drain, and the frame reports it once for each count bucket ('12 faults dropped, the store is full') (the report).
- **B:** A drop counts into one overflow record with a reserved key, which the drain hands to the targets and to the console as any record, with the count buckets.
- **C:** B, and the store makes room: when it is full, it forgets the oldest key that the drain already handed over; the overflow record counts only when every key still waits for the drain.
- **D:** The fault log gets a clear that empties the store (clear_fault_store! went in 5ec9c35b).
- **Recommended (mine): C.** A and B tell the person that faults were lost but never which ones, and since nothing empties the store, a long session (a web editor runs for days) fills it once and then turns every new kind of fault into a number. With C each fault reaches the log and the console at least once, as PAR-REPORT-NEVER-THROWS asks ('no fault is lost'), and the capacity still bounds the memory.
- Cost: FaultStore.jl (sealed), FaultModule.jl (sealed) only if a name is exported; FaultStoreTest.jl; fault.md. M.
- **Risk:** It reverses the rule of the store "keep the first faults"; a forgotten fault is reported again when it comes back.

**L13-3** (Medium): Must 'next hole' search only the document that holds the selection, and may the exported seam child_reference_steps go?

- **A:** The operation carries the path of the document to search, and the reroot prefixes it on the way up; search it with search_references and maxdepth (the report).
- **B:** The domain gives a scope predicate with the hole predicate (for Julia, a node of the Julia domain); the operation searches the outermost node on the selection path for which the scope holds, with search_references and maxdepth, and still travels unchanged.
- **C:** Keep the walk from the root, and add only a depth bound.
- **Recommended (mine): B.** The reader that makes the operation sits at the hole (_julia_ins_tab) and knows no path of the file, so A needs a reader higher up that fills the path in as the operation passes, a new channel through the projection chain; B needs none. Yes, child_reference_steps and its CellVector method can go, because search_references walks the one step layout that evaluate_reference walks and already has maxdepth (PAR-SEARCH-DONT-WALK).
- Settles: L13-11.
- Cost: kernel/operation/Operations.jl, OperationInterface.jl, OperationModule.jl (an export goes); source/domain/julia/JuliaInsertionToSyntax.jl; source/platform/collection/CellVector.jl, CollectionModule.jl; TraversalTest.jl. No user outside projectured-julia. S-M.

**L13-5** (Medium): How does a wrapper that holds a CompoundOperation give its way back, and how does a wrapper with state of its own keep its own inversion?

- **A:** Add evaluate_invertible_operation!(editor, op::WrappingOperation), which inverts the held operation when the wrapper has no make_inverse_operation method of its own (the report; a test of the method table).
- **B:** Add the same method with no test of the method table: it evaluates the held operation through evaluate_invertible_operation! and rewraps its inverse with rewrap_operation; a wrapper with state of its own adds its own evaluate_invertible_operation! method beside its make_inverse_operation.
- **C:** A wrapper constructor pushes itself into a CompoundOperation, so each member inverts alone.
- **Recommended (mine): B.** The rule is then one sentence of dispatch: a wrapper whose evaluation is the evaluation of what it holds (ReplaceViewStateOperation) inverts through it, and a wrapper with state of its own (RecordUndoOperation) says its own way back with a method. A test of the method table breaks when a method moves, and C can not serve RecordUndoOperation, which records one step for the whole compound.
- Cost: kernel/operation/Inversion.jl, OperationInterface.jl (docstring of make_inverse_operation); source/platform/undo/UndoDocument.jl (one method); test_inversion. S.

**L13-7** (Medium): What does a splice into a plain Vector field do: refuse, or write the field cell after the change?

- **A:** Refuse: a splice or an overwrite into a container that is not a document collection throws an ArgumentError that names the field.
- **B:** Write the field cell after the change: build a new vector with the splice, write it into the field that holds the vector, and let the way back write the old vector back.
- **C:** Change the vector in place, as now, and then write the same vector into its field cell again.
- **Recommended (mine): B.** A plain Vector in a cell is a value, and a cell write is the change that makes the readers of a field compute again (PAR-FIELDS-ARE-CELLS), while a refusal closes such a field to insert_elements! and delete_elements!, which a model uses on any collection that a document shows. C loses the old value, so its way back must copy the removed items, and the value changes without a cell write.
- Depends on: L10-6.
- Cost: kernel/operation/Operations.jl (_write_slot! and the overwrite need the owner and the field of the vector), Inversion.jl; InversionTest.jl. S.

**L15-4** (Medium): Is sel in scope in a rule body, or do the texts say that a body has only doc and the pattern variables?

- **A:** Bind sel in the body: the operation closure takes the selection that applicable got, (doc, sel, event) -> body, and each fire passes it; the texts then hold, except the promise of event.
- **B:** Correct the three texts and the guide: a body has doc and the pattern variables, and reads the selection with get_selection(doc).
- **C:** The macro binds sel = get_selection(doc) inside the body, with no change of the GestureBinding contract.
- **Recommended (mine): A.** The precondition gets a selection that a caller passes for a target with none of its own (WidgetToGraphics.jl:9174, GestureBindings.jl:28), and get_selection(doc) can not give that selection in a body; with A the precondition and the body see the same sel. C gives a different sel in exactly those cases.
- Cost: kernel/binding/GestureBinding.jl (three calls), Gestures.jl (two closures), GestureBindingInterface.jl; the bindings that code builds by hand (Focusing.jl, UndoBufferToAny.jl, Domain.jl, VersioningToAny.jl, FileSystemToWidget.jl and others); devices-and-backends.md. None in omnet-julia or inet-julia. M.
- **Risk:** It changes the contract of `GestureBinding` and about 12 hand-written bindings.

**L18-12** (Medium): Who owns the sentence that names the editing verbs: the tool layer, or the layers that define the verbs?

- **A:** The tool layer keeps the sentence, and a guard test compares each named verb with a function that exists.
- **B:** The owners write the sentence into the ToolSet or the declaration, and the tool layer prints it (the report).
- **C:** A seam of the tool layer that the owner of a verb extends beside the verb (is_editing_verb(::typeof(insert_elements!)) = true); the tool layer names each declared verb for which it holds, with the signature line of its docstring.
- **Recommended (mine): C.** With C the text follows the function: a rename changes the printed name, and a new argument changes the signature line that the author of the verb updates with the code, while B keeps a second copy of the text that julia-rename.jl does not change, because it skips strings. C is the seam pattern of PAR-FRAMEWORKS-SINK, and its method table is the same for every editor.
- Cost: tool/DefaultTools.jl and a seam declaration in the tool layer; editor/DocumentEdits.jl (two methods); source/platform/pane/PaneProgram.jl (one method); DeclaredApiTest.jl. S-M.

**L20-4** (Medium): Who registers the default tools of a `ToolSet`, and how do their descriptions follow `declare_api!`?

- **A:** The ToolSet fills its defaults once, at its first read, only for the names that it does not hold; each call that changes an input of a default tool (declare_api!, register_guide_root! on the set, set_meaning_model!) refreshes the defaults that are still defaults; run_turn!, the MCP server and the assistant stop the registration.
- **B:** run_turn! registers only the default names that the set does not hold, and declare_api! refreshes the descriptions.
- **C:** Keep the registration at each turn, and state that a default name is reserved.
- **Recommended (mine): A.** The set registers once and the input that changes a description refreshes it, so a caller's tool of a default name stays and no turn repeats the work (L18-24). The write then happens where the set changes, not on the task of a turn, which AgentInterface.jl forbids for a write from another task.
- Depends on: L18-13. Settles: L18-24.
- Cost: tool/ToolSet.jl, Tool.jl, DefaultTools.jl, agent/AgentLoop.jl, source/adapter/mcp/McpServer.jl, source/platform/assistant/AssistantTurn.jl; the omnet-julia tests that call register_default_tools! still work. M.

**L01-12** (Low): Does the seam `make_safe_mode_projection` move from the fault layer to the editor layer?

- **A:** Move the seam to the editor layer: declare make_safe_mode_projection next to enter_safe_mode!, and FaultViewModule extends EditorModule.make_safe_mode_projection.
- **B:** Keep it in the fault layer, and state the reason in fault.md.
- **Recommended (mine): A.** The fault layer never calls the seam, and the seam names a projection (layer 17) and the safe mode (layer 22); PAR-NO-CONSUMER-DOCS puts a seam in the lowest layer where every concept that it names exists, which is the editor layer.
- Depends on: L01-2.
- Cost: FaultInterface.jl, FaultDefaults.jl, FaultModule.jl (sealed); editor/SafeMode.jl, EditorModule.jl; source/platform/fault/FaultSafeMode.jl; FaultDefaultsTest.jl; fault.md. No user in omnet-julia or inet-julia. S.

**L15-10** (Low): Does Intent.gesture keep a second meaning for a collected intent, or does the pattern get a field of its own?

- **A:** State the second meaning in the Intent docstring.
- **B:** A collected entry gets a type of its own (pattern, operation, description, domain), and CollectedIntentsOperation holds those; Intent keeps one meaning.
- **C:** Intent gets a field pattern that only a collected intent fills.
- **Recommended (mine): B.** Two meanings for one field are a defect even when each one is clear (the owner's rule: mint a word, do not overload one), and a collected entry is a line of a list of what is available, not a change that travels with its input, so the invariant of Intent does not apply to it. C adds a field that most intents leave empty.
- Depends on: L14-2.
- Cost: kernel/intent/Intent.jl (the type and the reroot at line 158), kernel/binding/GestureBinding.jl (collect_binding_intents); about 30 uses of CollectedIntentsOperation in projectured-julia and the lists that read .gesture. M.

**L18-17** (Low): Does a short String with a line break reach the model as prose, or keep the escaped REPL form?

- **A:** Show a String that holds a line break as its lines, at any length, as a long String is shown now.
- **B:** Keep the REPL form for a short String, and say so in the comment and the description.
- **Recommended (mine): A.** repr of a String never holds a line break, so the check !occursin('\n', text) at CodeExecution.jl can only mean the line breaks of the string, and A is what the code means; a long String already comes as its lines. A model that reads a short program as one escaped line spends rounds.
- Cost: tool/CodeExecution.jl (_describe_value_for_model), CodeExecutionTest.jl. S.

**L22-19** (Low): Does `find_rooted_operation` try the root last, or refuse an edit that no reader carries?

- **A:** Try the root last: an edit that no reader carries applies at the root.
- **B:** Refuse, and say it: the docstring says that an edit that no reader carries is refused, and the error names the reader that must learn the route.
- **Recommended (mine): B.** A write at the root passes every reader between the root and the part, so a history that holds the part does not record it and a projection that refuses or transforms the edit is never asked; PAR-AI-SAME-GUARANTEES asks for the path of an edit of the person.
- Cost: editor/DocumentEdits.jl (docstring and message). S.

### Group 10

**Devices, keys and backends** (10 questions). The seams of the backends. L07-1, the zoom in the kernel, comes first, and L22-23 follows it.

**L07-1** (Medium, main question): Do you reopen the decision of plan/done/device-layer-audit.md and let the kernel step the zoom of the Display, so that the web backend can zoom too?

- **A:** Keep the decision of plan/done/device-layer-audit.md: only the SDL package evaluates the zoom. The Display docstring and PAR-BACKEND-SEAM say that the other backends do not zoom.
- **B:** Reopen it. The kernel editor evaluates `AdjustZoomOperation`: it steps the `zoom` of the `Display` in `editor.devices`, then calls a new backend generic with a no-op default (for example `follow_display_ratio!(backend, editor, old_ratio)`). SDL answers it with its reflow and its full repaint; the web backend sends the ratio to the page.
- **C:** Reopen it, and follow the browser model. The kernel steps the `zoom` of the `Display`. At its next output, each backend follows the new ratio: it keeps the device size of each window, repaints in full, and reports the new logical size as a `WindowResize`. No new backend generic.
- **Recommended (mine): B.** Since the device audit, the zoom is a field of the kernel's `Display` (D1 put it there 'so any backend can read it'). The one method that evaluates the kernel's `AdjustZoomOperation` is in Sdl.jl and tests `editor.backend isa SdlBackend`, so a second backend can not add its own method without an overwrite. In the browser the zoom is dead twice: asset/web/client.js calls `preventDefault` on every Ctrl key and every wheel event, so Ctrl+= zooms neither the page nor the editor. The web backend is where the owner wants many editors. B keeps the reflow inside the evaluation, as SDL does it now and as the live-window check of the device audit tested. The fact that moves me to C: if a backend generic that gets the editor and writes the window sizes is not acceptable, C has no new sealed generic and changes the document only through a reader. The cost of C is one frame at the new ratio before the reflow.
- Settles: L22-23.
- Cost: M. The kernel can not call `step_zoom`, because the style package depends on the kernel. So `step_zoom` and its table move into the device layer, and the style package imports them for the font zoom. Sealed (permission needed): DeviceModule.jl and Display.jl (its docstring says that only SDL reads the Display); for B also BackendInterface.jl, BackendDefaults.jl and BackendModule.jl. Unsealed: an editor-layer or operation-layer file for the evaluation, Sdl.jl, Web.jl and asset/web/client.js (the page scales its canvas by the zoom, and divides the pointer position and its size by it), tests with two editors and with the web backend. omnet-julia and inet-julia: no change.
- **Settled by the owner on 2026-10-01 in plan/done/zoom-and-theme-controls.md (D24 to D26, section 4.6).** The kernel has no zoom: `_zoom_operation` and the kernel forms of `AdjustZoomOperation` and `AdjustFontZoomOperation` go. The zoom lives in the `Appearance` of a new wrapper package and is copied into the `Display`. SDL follows the new pixel ratio when it draws (its `evaluate_operation` methods go), and the web client applies the zoom that the update message carries. This is the browser model of option C, with the zoom outside the kernel. The work belongs to that plan.

**L07-2** (Medium): Is the size of the display a property of the Display device, or only the answer of get_display_size(backend)?

- **A:** Remove `width` and `height` from `Display`, and their write in the SDL `configure_devices!`. `get_display_size(backend)` is the one source, with one default value for the size.
- **B:** The `Display` holds the size. `get_display_size(backend)` answers the size of the `Display` that the backend holds, and the backend fills it (SDL holds a `Display` from its constructor).
- **C:** Keep both, and let the docstring say that the fields are a copy.
- **Recommended (mine): A.** No code reads the two fields. The size is needed before an editor and its devices exist: the `make_editor` of the screen package asks `get_display_size(backend)` before it calls the kernel's `make_editor`. The usable size depends on the monitor and on the work area, which a live query answers and a stored copy does not. The default is now in three places: (1280, 800) in `Display()`, (1280, 800) in BackendDefaults.jl, and (1280, 720) in `get_sdl_display_size`. The fact that moves me to B: if the owner wants one `Display` for each monitor (the placement of a window on a monitor, a scale for each monitor), then the size belongs on that device. That is B with a list of Displays, and a larger design.
- Cost: S. Sealed (permission needed): Display.jl (the fields and the positional constructor) and BackendDefaults.jl (the one default). Sdl.jl (the write and its fallback), DeviceModuleTest.jl (4 lines). omnet-julia: CampaignPrecompile.jl builds `Display()` with no size and needs no change. inet-julia: none.
- **Check after the merge of gesture-type (2026-10-01): the question holds.** `Display(; width = 1280, height = 800, …)` keeps the two fields; only `source/backend/sdl/SdlBackend.jl:4322` writes them, and no code reads them. The default is still in three places. The owner approved the unseal of `Display.jl` for step N1 of zoom-and-theme-controls.md (`scale` → `density`), so a change of L07-2 can go in the same step.

**L09-3** (Medium): How does a package answer write_image, record_video, render_canvas and decode_image, so that a second implementer does not overwrite the first?

- **A:** A symbol-keyed factory makes a value that the package owns: `make_image_renderer(:sdl)` returns an `SdlImageRenderer`, and `write_image`, `render_canvas` and `decode_image` dispatch on that value. The kernel default for an unknown key names the package to load.
- **B:** A `Val` seam behind a keyword: `write_image(document, projection, filename; renderer = :sdl)` calls `write_image(Val(renderer), ...)`, so each call of today stays valid. A predicate (for example `is_image_decoder_loaded(:sdl)`) lets a caller ask before it decodes.
- **C:** Move each generic out of the kernel into the package that implements it (for example `write_sdl_image`, as `measure_sdl_text`), and let each caller call that package.
- **Recommended (mine): B.** PAR-OPT-IN-DEPENDENCY already names this shape ('a symbol-keyed `Val` factory … the `record_video` seam'), so B adds no new mechanism: a second implementer (plan/pending/cairo-glfw-backend.md plans one) adds methods for its own key and overwrites nothing. A keyword with the implementer of today as its default keeps the 46 calls of `write_image` in projectured-julia and the 9 in omnet-julia as they are. The predicate lets MarkdownToSyntax.jl, BookToSyntax.jl and RstToSyntax.jl stop the catch of every exception, which now hides a missing decoder and a broken file in the same way. The fact that moves me to A: if the kernel must not name `:sdl` as a default, then each call names or receives its renderer, at the cost of a change at each call.
- Settles: L09-15.
- Cost: M. Sealed (permission needed): BackendInterface.jl, BackendDefaults.jl, BackendModule.jl. Sdl.jl, Video.jl, the three domain calls of `decode_image`, omnet-julia ModuleAppearanceToGraphics.jl (`decode_image`). With B, the calls of `write_image` (18 files here, 7 in omnet-julia) and `record_video` (17 here, 2 in omnet-julia) need no change; with A they all change. inet-julia: none.

**L09-4** (Medium): Does a video show every window of the screen (tooltips, popups, dialogs), or only the main window?

- **A:** Compose every visible window at its `x` and `y` onto the frame, in the order of the windows of the `ScreenDocument`. The frame is the screen of the video backend (its width and its height).
- **B:** Keep one window, and write the limit in the docstring and in PAR-MANY-WINDOWS.
- **C:** Write one video for each window.
- **Recommended (mine): A.** A take shows the editor in use, and a tooltip, a popup or a dialog is a part of what the person sees; a screen recording shows them too. The video backend already treats its frame as the screen: `get_display_size` of the backend answers the frame size, and the backend draws the main window at the origin of the frame. PAR-MANY-WINDOWS asks each backend to show every window or to say plainly that it can not. A keeps the rule with no exception.
- Cost: S to M. VideoBackend.jl (`_select_window`, the full render and the partial render), the video suite. No sealed file. No use in omnet-julia or inet-julia.

**L09-5** (Medium): Where does the console map a plain Home to the selection of the root, when the backend stops its remap to Ctrl+Alt+Home?

- **A:** The console reports a plain Home. A table of editor bindings that fires after the pipeline declines a gesture (see L22-23) gets a row from the console package: a plain Home that no reader takes reads as Ctrl+Alt+Home.
- **B:** The console reports a plain Home, and a reader of the console projection binds it. That reader reads first (the output end reads first), so it takes a plain Home from every inner reader, as the remap does now.
- **C:** No map. The console reports each key as it comes. A terminal sends Ctrl+Alt+Home as `ESC [1;7H`, which Console.jl already decodes with its modifiers, so the selection of the root works with the same keys as in SDL.
- **D:** Keep the remap, and write the exception in PAR-BACKEND-SEAM.
- **Recommended (mine): C.** The contract says that a device reports only what happened. A backend that gives a key a meaning for one reader breaks every other reader: ChartDocument binds a plain Home to 'Select the first part', which the console can never deliver now. Console.jl already decodes the xterm modifier parameter, so Ctrl+Alt+Home reaches the reader when the terminal sends it. C adds no mechanism, and the console runs the same bindings as SDL. The fact that moves me to A: a terminal in use that can not send Ctrl+Alt+Home (the Linux virtual console can send no modifier for Home), or a wish of the owner for a one-key start of the structural navigation in the console. A comes after L22-23, and it needs a way for a row to read one gesture in the place of another, which is a new mechanism.
- Cost: S for C: Console.jl (`_home_event` goes), ConsoleBackendTest.jl, the console guide (it tells the person to press Ctrl+Alt+Home). No sealed file. No use in omnet-julia or inet-julia.

**N-2** (Medium): Does the key vocabulary get `:comma`, so that Ctrl+, can fire, or does the binding take another key?

- **A:** Add `:comma` to the key vocabulary: SDL keysym 44, the web key ',', and the list in the `KeyDown` docstring.
- **B:** Name every key of the base US layout that has no name now: `:comma`, `:semicolon`, `:apostrophe`, `:grave`, `:left_bracket`, `:right_bracket`, and the digits `:one` to `:nine` beside `:zero`, in every backend. `:char` stays for a key outside the table.
- **C:** Bind focus-out to another key that the vocabulary has.
- **Recommended (mine): B.** The vocabulary grew one key at a time, for the bindings that needed one (`:period` for Ctrl+., `:zero` for Ctrl+0, `:backslash` for Ctrl+\), and each new binding found a missing key: N-2 now, N-8 before it. L09-1 gave every letter a name in every backend; the same step for the punctuation and the digits ends the class of fault, not only this case. Ctrl+, and Ctrl+. are a pair (focus out, focus in), so another key (C) breaks the pair.
- Cost: S to M. Sealed (permission needed): KeyboardEvent.jl (the list in the docstring). Sdl.jl (the keysym table), Web.jl (`convert_web_key_to_symbol`), Console.jl (the bytes that it can read), the backend tests. Focusing.jl needs no change. No use in omnet-julia or inet-julia (their `:comma` is a token kind of the NED parser).

**L08-1** (Low): While a chord waits for its next key, does another input (a key up, a character, a click, a key of another window) wait behind the kept keys, or does it break the chord?

- **A:** Input that belongs to the kept keys (their `KeyUp`, the `KeyPress` of a chord step, a modifier key) waits behind them, in order. Any other input (a click, a key of another window, a window event) breaks the chord: the kept keys go out first as ordinary keys, then that input. The `KeyUp` and the `KeyPress` of a key that a complete chord takes go with the chord.
- **B:** Every input waits behind the kept keys until the chord completes or breaks.
- **C:** Every input other than the next `KeyDown` breaks the chord, a key up too.
- **D:** No rule now. Decide it with plan/pending/key-chords-from-bindings.md.
- **Recommended (mine): A.** The recognizer promises that 'the reader sees the order of the input', and today a `KeyUp` can reach the reader before its own `KeyDown`. A key up and the text of a chord step are parts of the same key press, so they stay with it. A click or a key of another window is a new act of the person, so it ends the chord; a chord then belongs to one window, as a click does. In Emacs and in VS Code, the key of a chord step also types no text.
- Cost: S. Sealed (permission needed): GestureRecognizer.jl. GestureRecognizerTest.jl. No use in omnet-julia or inet-julia.
- **Check after the merge of gesture-type (2026-10-01): the question holds, in a new file.** The recognizer is gone; `gesture/ChordRecognition.jl` (not sealed) keeps the keys of a chord. An input that is not a `KeyDown` (a key up, a character, a click) passes on at once while keys are kept, so the reader can still see a `KeyUp` before its `KeyDown`. `_is_chord_prefix` compares the key and the modifiers but not the window, so a key of another window can continue a chord. Cost now: ChordRecognition.jl and test/kernel/gesture/GestureRecognitionTest.jl; no permission.

**L09-10** (Low): Does get_pointer_position answer nothing for an unknown position, in place of (-1, -1), which is also a real position on a monitor to the left of or above the primary one?

- **A:** Answer `nothing` when the backend can not report the position. The callers test it: the tooltip and hover probes skip, and the SDL placement uses its fallback.
- **B:** Keep `(-1, -1)`, and let the callers compare with it.
- **C:** Keep the tuple, and add a predicate `has_pointer_position(backend)`.
- **Recommended (mine): A.** `(-1, -1)` is a real position on a monitor to the left of or above the primary one, so an in-band value can not mean 'unknown'. `nothing` is the Julia answer for a value that is not known. A caller that forgets the test then fails at once, where today it puts a tooltip in the center of the screen. The name keeps `get_`, because the value sits at a known place when it exists and the function does not search.
- Cost: S. Sealed (permission needed): BackendInterface.jl, BackendDefaults.jl. VideoBackend.jl, TooltipProbe.jl, HoverProbe.jl, Sdl.jl (`compute_window_place`). omnet-julia: source/ide/IdeWindow.jl passes the answer on in `_make_window_pointer`, so its callers must accept `nothing`. inet-julia: none.

**L09-12** (Low): Does the kernel give one answer for an output of the wrong type, one window id for an input with no window, and one helper for the gated wait?

- **A:** All three. A kernel default method of `write_to_devices` throws an error that names the backend and the output type, as the web and console backends do now. One exported constant in the event layer means 'no window'; every backend uses it, and no window may take it as its id. One exported helper in the backend layer does the gated wait.
- **B:** The error and the helper only. Each backend keeps its own id for 'no window'.
- **C:** Keep the differences, and write them in PAR-BACKEND-SEAM.
- **Recommended (mine): A.** PAR-BACKEND-SEAM asks for one contract for all backends. The error: two of the four backends already raise an error that names the fix, while SDL and video give a `MethodError` in each frame. The `run_editor!` docstring says that such output goes 'unrendered', which no backend does, so that text changes too. The id: no code outside the backends tests for 'no window' today, so one constant costs little, and a window of the document can not take it by mistake. The wait: `_wait_for_gate` is the same function, word for word, in Console.jl and Web.jl.
- Cost: S. Sealed (permission needed): BackendDefaults.jl and BackendModule.jl (the error and the helper), WindowInput.jl and EventModule.jl (the constant). Sdl.jl, Web.jl, Console.jl (`:console` becomes the constant), VideoBackend.jl, the docstring in EditorLoop.jl. No use in omnet-julia or inet-julia.

**L22-23** (Low): Where are the zoom keys bound: in a binding set of the backend or screen package, through a backend generic, or with the zoom stepped in the kernel (L07-1)?

- **A:** A gesture binding set that the backend package or the screen package gives.
- **B:** A backend generic that answers the zoom for each backend.
- **C:** With L07-1 (the kernel steps the zoom), the keys stay in the kernel editor, but as a table of `GestureBinding` rows that the editor fires after the pipeline declines a gesture. The bare Escape of the quit goes into the same table. `_zoom_operation` and `_is_quit_gesture` go.
- **D:** Keep the function in the loop.
- **Recommended (mine): C.** When the kernel evaluates the zoom for every backend (L07-1), the keys belong to the editor, not to one backend package. A table of the existing `GestureBinding` type shows the keys to the help projection and to the command palette, where the function now hides them. It fires in the same place as now, after the pipeline, so a projection that binds the keys still wins. The rows follow the exact modifier match, so Ctrl and Ctrl+Shift need a row each (Ctrl++ is Ctrl+Shift+=). The fact that moves me to A: if L07-1 keeps the zoom in SDL, then the SDL package gives the rows, and the kernel loop names no zoom key.
- Depends on: L07-1. Settles: L22-27.
- Cost: S to M. ReadEvaluatePrint.jl, a new private table in the editor layer, FaultBarriersTest.jl (it reads the zoom operations through `read!`), the help tests. No sealed file. No use in omnet-julia or inet-julia.
- **Settled by the owner on 2026-10-01 in plan/done/zoom-and-theme-controls.md (D25, sections 4.6 and 4.7).** The zoom keys are bindings of the appearance wrapper, so F1 and the palette list them, and `_zoom_operation` goes. That settles the `_zoom_operation` part of L22-27: the function goes. The bare Escape of the quit (`_is_quit_gesture` in `read!`) stays as it is; that plan does not touch it.

### Group 11

**The scope of the kernel** (5 questions). Whether a feature stays in the kernel. POLICY-11 states the rule of the scope. L11-10 and L23-5 unblock the 10 items that wait.

#### POLICY-11

- **A:** The kernel holds what the editor loop needs, what a kernel contract needs, and machinery that names only kernel API and that two or more packages above share. architecture-rules.md states the three tests.
- **B:** The kernel holds only what the editor loop needs, as the membership test of architecture-rules.md says. Other machinery moves to a substrate package, one for each distinct set of consumers (PAR-PACKAGE-CHAIN).
- **Recommended (mine): A.** PAR-LOWEST-PACKAGE puts code in the lowest package whose API it names, and the kernel already holds machinery that the loop does not call: run_turn! of the agent layer, which only the assistant package and a fault example call. With B, that layer would move too. A states the practice, so L11-10 and L23-5 get one answer.
- Settles: L11-10, L23-5, L23-4.
- Cost: S. architecture-rules.md, one paragraph.

**L11-10** (Medium, main question): Does the pattern language (the rules DSL, the string spelling, the glob matcher and the interpreter) stay in the kernel?

- **A:** Keep the whole pattern language in the kernel, and state the scope rule of POLICY-11 in architecture-rules.md.
- **B:** Move the two front ends that no kernel code calls to a substrate package that omnet-julia uses: the rules value DSL (@reference_rules, ReferenceRules, apply_reference_rules, their display and quote code) and the string spelling (ref"…", parse_reference_pattern), about 700 lines. The interpreter and the glob matcher stay in the kernel.
- **C:** Delete the rules value DSL, which no code uses. Keep the string spelling and the glob matcher for the INI reader of omnet-julia.
- **Recommended (mine): A.** The interpreter and the glob matcher are part of @reference_case: it gives the interpreter each arm with a gap, an alternation or any(…) (ReferenceCase.jl:395-427), and it calls glob_matches for glob"…" (ReferenceCase.jl:607). So they can not leave while @reference_case, which 44 files use, stays. Only the two front ends could move. The rules value DSL has a planned consumer: omnet-julia plan/pending/ned-ini-to-anatomy.md, Phase 3, builds ParameterRules over the kernel's ReferenceRules. The INI reader of omnet-julia uses parse_reference_pattern and glob_matches today.
- Depends on: POLICY-11. Settles: L11-22, L11-2.
- Cost: S for A: architecture-rules.md, one paragraph. In every option, each extension step (.proj, .point, .row, .sample) gets a match_reference_step_value method, or the text says that it can not stand in a rules pattern. B is M: a new substrate package with its test and example packages, the package table, the corpus tests, and the imports of omnet-julia. C is M and reverses two done plans (reference-rules-macro.md, reference-pattern-vocabulary.md).
- The items that wait, by option:
  - A: apply: L11-22, L11-2 (parts).
  - B: apply: L11-2 (parts); change: L11-22 (the display and quote part moves to the new package).
  - C: apply: L11-22 (without the display and quote part), L11-2 (parts, without the one arm parser); moot: L11-22 (display and quote part), L11-2 (one arm parser for both macros).

**L23-5** (Medium, main question): Does playback stay in the kernel with its own loop, or become a source of input around `run_editor!`, as `VideoBackend` does, and in which package?

- **A:** Keep the loop of play_live! in the kernel, and copy into it the steps of run_editor! (the clock, drain_feeds!, run_frame!, and a wait bounded by the next entry).
- **B:** Replace the loop with a source of input around run_editor!, in the playback layer of the kernel: a backend that wraps the live backend, forwards the backend generics to it, answers due event entries from read_from_devices with the time at which they fire, and gives operation entries to the editor task. The scheduler and the entry kinds serve VideoBackend too.
- **C:** As B, but the source and the entry kinds live outside the kernel: in a new substrate package that ProjecturedVideo and ProjecturedSdlExample use, or in ProjecturedVideo. The kernel loses layer 23.
- **D:** Delete play_live!. A person watches a scripted session as a video (VideoBackend).
- **Recommended (mine): B.** One loop gives one behaviour: the loop of play_live! lacks nine steps of run_editor! (L23-1), and each later step of run_editor! would need one more copy. VideoBackend proves the shape: a backend whose read_from_devices answers due entries plays a timeline through the real loop and the gesture recognizer. The source names only kernel API and has two consumers (ProjecturedVideo and ProjecturedSdlExample), so under POLICY-11 it stays in the kernel.
- Depends on: POLICY-11. Settles: L23-1, L23-4.
- Cost: M. Playback.jl and PlaybackModule.jl (not sealed): a backend wrapper that forwards about ten backend generics, and a scheduler; example/backend/sdl/LiveExamples.jl; PlaybackTest.jl; editor.md. VideoBackend.jl can then use the scheduler. C also needs the sealed ProjecturedKernel.jl (the layer list), SEALING.md (L17-16), KernelSuite.jl, system-anatomy.md and package-rules.md.
- The items that wait, by option:
  - A: apply: L23-2, L23-3, L23-6, L23-7, L23-8, L23-9, L23-10, L23-11.
  - B: change: L23-6, L23-7, L23-8, L23-10, L23-11; moot: L23-2, L23-3, L23-9.
  - C: change: L23-6, L23-7, L23-8, L23-10, L23-11; moot: L23-2, L23-3, L23-9.
  - D: change: L23-11; moot: L23-2, L23-3, L23-6, L23-7, L23-8, L23-9, L23-10.

**L23-1** (High): Does `play_live!` drain the feeds, which reverses the recorded design that a scripted timeline must not apply foreign posts, or does L23-5 replace the loop?

- **A:** play_live! drains the feeds in its own loop. This reverses the sentence of plan/done/the-editor-waits-for-events.md §3.2 that a scripted timeline must not apply foreign posts.
- **B:** L23-5 replaces the loop with a source of input around run_editor!, which drains the feeds. The recorded sentence then applies only to a harness that calls run_frame! directly, and it stays true.
- **C:** Keep the loop without feeds, and make post_operation! refuse a post (in place of a block after 64 posts) while a playback runs. The text says that a menu command does nothing under playback.
- **Recommended (mine): B.** play_live! is a live session: a person watches, clicks and types in the window, and the window stays live after the last entry. A menu command posts its pane edit through the inbox, so a loop with no drain loses it, and the poster blocks after 64 posts. VideoBackend already plays a timeline through run_editor!, which drains the feeds, and its recordings carry every tool (example/backend/sdl/ApplicationVideo.jl:4-9).
- Depends on: L23-5.
- Cost: No cost of its own: the work is part of L23-5.

**L02-1** (Medium): How does the counter switch reach the package cache: a preference, with a new dependency of the kernel, or a written rebuild step?

- **A:** A compile-time preference, read with Preferences.jl. The package cache tracks it, and the kernel gets its first dependency.
- **B:** A run-time switch for each editor: the counters are always compiled in, and a frame binds a store only when the switch of its editor is on.
- **C:** A written rebuild step (--compiled-modules=no, or a delete of the kernel image), and a message at load that names the state of the switch.
- **Recommended (mine): A.** The package cache tracks a preference, so a change of the switch rebuilds the kernel image and a stale image can not occur. Preferences.jl is already in the tree (ProjecturedRepl, ProjecturedBuilder), and ProjecturedBuilder already writes baked preferences, so one mechanism serves every compile-time switch. C keeps the trap and asks each person to know it. B adds a check to each cell read, and its cost needs a measurement of time on an idle machine with the owner's approval.
- Cost: S to M. PerformanceCounter.jl (sealed, permission); package/ProjecturedKernel/Project.toml; package-rules.md ('The kernel depends on nothing' changes); PAR-PROFILE-WITH-COUNTERS; cell.md; editor.md. The counted tests of L02-3 can set the preference in a child process.
- **Risk:** The kernel gets its first dependency, against "the kernel depends on nothing" in package-rules.md.

**L23-4** (Medium): Which package declares the timeline entry kinds, and what does `await` mean: a predicate of the editor, or of the document?

- **A:** The kernel declares the entry kinds in its playback layer, beside the source of input of L23-5: an event entry, an operation entry and an await entry, each with its hold. await is a predicate of the editor.
- **B:** The package that holds the playback source declares them (a new substrate package, or ProjecturedVideo), if L23-5 moves playback out of the kernel. await is a predicate of the editor.
- **C:** No type: one docstring states the NamedTuple format, and each interpreter reads its keys. await stays a predicate of the document for record_video and of the editor for VideoBackend.
- **Recommended (mine): A.** PAR-FRAMEWORKS-SINK asks for one format below its users, and the lowest interpreter decides the home. await must be a predicate of the editor, because the timelines of today read the editor: ApplicationVideoTest.jl:95 reads editor.clock, and tool/video/check_assistant_undo.jl and record_assistant_window.jl wait for a turn of the assistant. A predicate of the document is one line in that form: editor -> p(editor.document).
- Depends on: L23-5, POLICY-11.
- Cost: M. The playback layer (the types); source/backend/video/VideoRecording.jl and VideoBackend.jl read the types; example/backend/sdl/LiveExamples.jl (timed_event, timed_operation and timed_await make the types, and timed_await takes a predicate of the editor); ApplicationVideo.jl; the tool/video scripts; the video tests. record_video has no Editor: it passes the stand-in that it has, or it runs on VideoBackend and run_editor! as record_application_video does.

### Group 12

**Measurements and tests** (4 questions). Two questions need a check or a timing run, which needs your approval. The other two are questions of the tests.

**L03-9** (Low): May the walk take @nospecialize, and may the timing run (it needs an idle machine and your approval)?

- **A:** Yes to both: add @nospecialize to _invalidate_dependents! (sealed ReactiveCell.jl, permission), and measure the time of the walk before and after on an idle machine, with the owner's approval.
- **B:** Check first with no clock: @code_typed of the walk and the trim verifier of an ahead-of-time build show whether the call of the walk to itself is a dispatch at run time. Add @nospecialize only if it is. Measure time only if the owner wants a number for the speed.
- **C:** No change: no rule asks for it, and the report only suspects the cost.
- **Recommended (mine): B.** The comment of the same file gives the reason for @nospecialize on the two edge helpers: an ahead-of-time build can not resolve a body that is specialized on T. That is a static fact that the trim verifier checks with no clock. A measurement of time needs an idle machine and the owner's word, and a static check needs neither. The walk runs on every write, so a confirmed dispatch is worth the permission for the sealed file.
- Cost: S. ReactiveCell.jl (sealed, permission), one line. The check is one short process.

**L06-11** (Low): Do you change the public type EventPattern for speed before a measurement shows a cost?

- **A:** No: measure first. Count the allocations of fire_gesture_bindings and of one @event_case (a count, not a measurement of time), and read @code_warntype of matches_event_pattern. Change the type only if the count or a measurement shows a cost.
- **B:** Yes: EventPattern{E,F<:NamedTuple} now, with an inner constructor that infers F, and one sentinel at module level for @event_case.
- **C:** Split: the private sentinel of @event_case now, as L11-23 did for the reference matcher (_NO_MATCH), and the public type only after a measurement.
- **Recommended (mine): A.** The matcher runs once for each binding on the path of one event. By estimate, a dynamic test of a field there costs microseconds in a frame of milliseconds. An allocation count needs no approval, so the fact is cheap to get. The public type is in a sealed file, and a new parameter changes what EventPattern{KeyDown} means (a UnionAll over F).
- Cost: S for the count. B: EventPattern.jl (sealed, permission); GestureLogDocument.jl:164 keeps its call through the inner constructor.
- **Check after the merge of gesture-type (2026-10-01): the question holds.** The type is now `GesturePattern{E<:Union{Event,Gesture}}` with `fields::NamedTuple` in `gesture/GesturePattern.jl` (not sealed), and the sentinel of the case macro is `_nomatch`. If the private sentinel changes, its name follows L11-23 (`_NO_MATCH`).

**L22-31 (part 2)** (Low): May `walk_repl_loop` drive each example through a real `Editor` and `run_frame!`, where an Escape that no reader takes quits and the zoom keys and the click pairing change what each example reports?

- **A:** Yes: walk_repl_loop drives each example through a real Editor (HeadlessBackend) and run_frame!. The event list sends a click as a press and a release, the walk records a quit on Escape as a pass and goes on, and the zoom keys stay. The broken registries get a new baseline from a diff against main.
- **B:** No: keep the stand-in sweep for the reader contract, and add a small test of the real loop for a few examples, one for each domain.
- **C:** Both sweeps over every example.
- **Recommended (mine): A.** The stand-in prints a fresh IoMap after each event, so it hides the faults of IoMap reuse, which the owner's notes record as a class that only the real loop shows (a type-to-replace that kept a stale IoMap, a drag that lost its state). Escape, the zoom keys and the pair of press and release are what a person meets, so the new reports are the true ones. C doubles the slowest sweep.
- Cost: M. ReplTest.jl (walk_repl_loop, test_repl), ExampleSweeps.jl and its broken registry, CatalogTest.jl, MathToGraphicsTest.jl, MarkdownImageLeafTest.jl. One run of test_repls() on main and one on the branch for the baseline diff; each is a long run, so it runs as a user service.
- **Risk:** The REPL sweep of every example gives new results: an Escape that no reader takes quits, and the zoom keys and the click pairing change what each example reports.

**N-7** (Low): omnet-julia example/ide/SearchUntunedCorpus.jl:76-77 asks a question whose answer is now the private `_get_cell_struct_trailing_default_count` (L04-7), which a search can never find: does the question go, or get another answer? Either changes the corpus of 60 questions.

- **A:** Drop the question. The corpus has 59 questions, and the short group has 19.
- **B:** Draw one new answer of the short group at random, by the method of the file header (a question from code alone, with no word of four or more letters of its answer), and keep 60 questions.
- **C:** Keep the question and give get_cell_struct_required_count as its answer.
- **Recommended (mine): B.** The corpus is a measurement with a random draw of 20 answers for each amount of documentation. A dropped question changes the size of one group, and an answer that a person picks breaks the draw. The question describes the trailing count, not the required count, so C gives a wrong answer.
- Cost: S. One question in omnet-julia example/ide/SearchUntunedCorpus.jl. The results of the untuned search are then for a changed corpus; a rerun loads a model, so check the free memory first.

## Not in this plan: the findings that other plans hold

| ID | Severity | The plan that holds it |
| --- | --- | --- |
| L01-4 | Medium | a-fault-is-easy-to-see-and-stays-small.md |
| L01-11 | Low | export-block-rule.md |
| L02-4 | Low | export-block-rule.md |
| L08-2 | Low | key-chords-from-bindings.md |
| L17-19 | Low | export-block-rule.md (the export block). The other parts: an item above (part), and the split, which needs a decision. |
| L18-23 | Low | export-block-rule.md (the export block). The other parts: an item above (part), and the split, which needs a decision. |
| L19-4 | Low | export-block-rule.md |
| L20-10 | Low | export-block-rule.md (the export block). The order of the `using` lines is an item above (part). |
| L22-8 | Medium | a-fault-is-easy-to-see-and-stays-small.md |
| L22-9 | Medium | a-fault-is-easy-to-see-and-stays-small.md (P3, D5). The retry interval of a stopped input half needs a decision. |
| L22-21 | Low | a-fault-is-easy-to-see-and-stays-small.md |
| L22-26 | Low | export-block-rule.md (the export block). The other parts: an item above (part), and the server options, which need a decision. |
