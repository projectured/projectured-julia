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
  *Done:* lane B, fa1c8c02. `_find_conditional` reads the children cell with `peek`, so that the computation that prints the parent does not depend on the child list; the state cell holds the tracked read. Both regression tests fail on the old code. Suites: test_julia 410 (+3), test_substrate 86839 (+9), the others at their baseline. A remaining risk, for L17-15: the walk in the state cell strips the `bound` markers of the vector that it reads, so a second run on the same cached vector would make a bound leaf an introduced slot. No rule of today reruns it. The macros guide does not describe the thunk child list (for L17-23).

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
  *Test:* A new testset in test/anthropic/AnthropicTest.jl (ProjecturedAnthropicTest) sends a recorded SSE body (message_start, one text block, message_delta) through `_drain_sse_events!`. It asserts no throw, the text events, and an `LlmTurnEnd` that carries the input count of message_start.
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
  Sort the using lines by module name. Delete the trailing comments of the includes. Make count of delete_elements a keyword (count = 1) and change the one positional call at source/text/TextDocument.jl:1310. Wrap the lines over 90 characters. Shorten the five fragment headers to one line.
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
  Replace the one `Ref` with a `Dict` keyed by `(models_url, api_key)` under a lock, so each key and URL gets its own answer. The report gives two ways; the keyed cache is the smaller, and it keeps the documented ask once in a process (llm.md), where a cache on the instance asks once per backend.
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

- [ ] **L21-2** (Medium, Correctness) — same fault as L22-6
  In `drain_feeds!`, run each `drain_changes!` in its own `_run_barrier(editor, :evaluate; origin = typeof(feed), fallback = 0)`, in place of the one barrier at EditorLoop.jl:179-181. Write in the `drain_changes!` docstring that a drain that throws is recorded and the next feed still drains.
  *Test:* test_editor_feeds(): two feeds under `FaultPolicy()`, and the first throws in `drain_changes!`; assert that the second drains in the same frame and that one fault record has the type of the first as its origin.
- [ ] **L21-3** (Medium, Correctness) — same fault as L22-7
  In `compute_wait_timeout`, compute each `compute_wake_deadline` inside `_run_barrier(editor, :evaluate; origin = typeof(feed), fallback = nothing)`, so a feed that throws counts as no deadline, and say so in the docstring. Of the two ways of the report, only the barrier keeps the editor alive, as plan/done/the-editor-survives-a-fault.md requires ('must not stop the editor'); a sentence in the contract alone does not.
  *Test:* test_editor_wait(): a feed whose deadline throws, under `FaultPolicy()`; assert that `compute_wait_timeout` answers the other bounds and that a fault record exists.
- [ ] **L21-4** (Medium, Correctness) — same fault as L22-5
  As L22-5: `drain_operations!` takes at most the operations that were ready when the drain started (at most `INBOX_CAPACITY`) and sets `editor.wake_pending` when some remain. Write in the `drain_changes!` docstring that a drain moves what the store held when the drain started.
  *Test:* test_editor_inbox(): a task posts in a loop while the editor drains; assert that one drain answers at most the count that was ready, and that `wake_pending[]` is true after it.
- [ ] **L22-2** (Medium, Correctness)
  In `run_frame!`, when the read loop ends at the cap, at a read that threw (give the read barrier the fallback `_BARRIER_FAILED` to tell it from no input), or at a dropped IoMap, set `editor.wake_pending[] = true`, so the next turn of `run_editor!` skips the wait. EditorLoop.jl:34 already says 'whatever is left waits for the next frame'.
  *Test:* test_editor_frame_drain(): a reader that throws on a `MouseUp` under `FaultPolicy()`; after `run_frame!`, assert `editor.wake_pending[]`. The same after a frame that reaches `MAX_OPERATIONS_PER_FRAME`.
- [ ] **L22-5** (Medium, Correctness) — same fault as L21-4
  In `drain_operations!`, take at most the operations that were ready when the drain started, and set `editor.wake_pending` when some remain. In `run_editor!`, call `yield()` once in a frame whose wait was skipped: the `run_editor!` docstring (EditorLoop.jl:119-121) says that the wait is where cooperative tasks get their turn.
  *Test:* test_editor_inbox(): a task that posts in a loop does not hold one drain for ever; after the drain, `wake_pending[]` is true.
- [ ] **L22-6** (Medium, Correctness) — same fault as L21-2
  Move the barrier and the repairs of `evaluate!` into one private function that applies one operation, with no log line and no write of `editor.operation`. Call it from `evaluate!` and for each posted operation in `drain_operations!`. Put one barrier around each `drain_changes!` (L21-2).
  *Test:* test_editor_frame_drain(): under `FaultPolicy()`, a posted operation that fails half way is taken back by its inverse, and the next posted operation applies in the same drain; a feed that throws does not stop the next feed.
- [ ] **L22-7** (part) (Medium, Correctness)
  Wrap `get_frame_clock_time` in `_run_barrier(editor, :device; ...)` with the wall time as the fallback. The deadline part is L21-3; the wait and its counter wait for their decision.
  *Test:* `test_editor_fault_barriers()` (L22-17): a clock that throws gives the wall time.
- [ ] **L22-10** (Medium, Correctness)
  In the `finally` of `run_editor!`, nest the three steps in `try ... finally` so that each runs when an earlier one throws, and let the first exception go on. The docstring says that the loop quits its backend 'also when it throws'.
  *Test:* test_editor_inbox(): a call posted with `wait = false` that throws `InterruptException` is still in the inbox when the loop ends; assert that `run_editor!` throws it and that a backend stub saw `quit_backend!`.
- [ ] **L22-11** (Medium, Architecture)
  In `_make_operation_inverse`, the inverse block of `_repair_after_operation_fault!` and `_repair_selection!`: `catch exception`, then `is_passthrough_exception(exception) && rethrow()`, then `record_fault!(editor.faults, :evaluate; origin = <the operation type or the repair>, exception, traceback = catch_backtrace())`.
  *Test:* FaultBarriersTest.jl (L22-17): under `FaultPolicy()`, an operation whose `make_inverse_operation` throws leaves one fault record; an `InterruptException` from the inverse goes through the repair.
- [ ] **L22-16** (Medium, Types/performance)
  Log `describe_operation(operation)` in place of the interpolated operation, still at `@info`, so the `evaluate!` docstring ('Logs the operation') stays true. The report's `@debug` or switch changes what the message log shows, so it is left out.
  *Test:* test_escape_quit() or a new testset: `@test_logs` sees an info line with the `describe_operation` text of a `ReplaceSelectionOperation` that `evaluate!` applies.
- [ ] **L22-18** (Low, Correctness)
  In `read!`, when `leave_safe_mode!(editor)` answers true, clear `editor.operation`, set `editor.wake_pending`, and return `false`, so that `run_frame!` paints before it reads on. In `run_editor!(editor)`, print once in the `:print` barrier before the first frame when `editor.iomap === nothing`.
  *Test:* test_fault_safe_mode(): in the safe mode, Escape and a key in one read; assert that the key applies on the next frame. test_editor_wait(): an `Editor(...)` with a queued key applies it in its first frame.
- [ ] **L22-20** (Low, Correctness)
  Read `time_ns()` for `t_start` and `frame_started`, and convert the differences to seconds.
  *Test:* test_editor_wait() as a regression run; no test can step the system clock.
- [ ] **L22-25** (Low, Shape)
  Move `evaluate!` and `print!` into ReadEvaluatePrint.jl and keep the barrier helpers in FaultBarriers.jl; move `get_fault_store(editor)` into Editor.jl; correct the header of EditorLoop.jl to name `get_frame_clock_time` and `make_editor`. The other way, headers that list what each file holds now, makes the headers longer than the budget of L22-30.
  *Test:* test_kernel() as a regression run; the fragments share one namespace, so no caller changes.
- [ ] **L22-26** (part) (Low, Shape)
  Sort the 18 `using` lines of EditorModule.jl by module name, put a comment above `import ..FeedModule: drain_changes!` that says the module extends it, and list the fragments in the module docstring. The server options wait for their decision; the export block is in export-block-rule.md.
  *Test:* The layering guard passes.

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
  *Done:* lane A, f0ba5e65. `drain_faults!(store; policy = FaultPolicy())`; FaultBarriers.jl passes `editor.fault_policy`.
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
- [ ] **L04-9** (Low, Documentation) — 🔒 `CellStructPlan.jl`, `CellStruct.jl`; after L04-7, L04-8
  Add a 'Use it to' paragraph and an example, with the goal of a macro writer, to the fifteen names that have neither.
  *Test:* test_documentation().

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

- [ ] **L06-1** (Medium, Shape) — 🔒 `KeyboardEvent.jl`; same fault as L09-1
  Restore the documented vocabulary. The KeyDown docstring states that each letter key has the name of its lower-case letter, :a to :z, and every backend follows it (L09-1). No new table, function or type goes into the event layer.
  *Test:* No test for the docstring. The backend tests of L09-1 assert :a to :z on SDL, the web and the console.
- [ ] **L06-2** (Medium, Documentation) — 🔒 `MouseEvent.jl`
  The MouseScroll docstring states that a positive dy is a turn of the wheel away from the user, which scrolls up, and that a positive dx is a scroll to the right, as SDL and the web page send them.
  *Test:* No test for the docstring. L09-18 adds a test that SDL and the web give dy > 0 for a turn away from the user.
- [ ] **L06-3** (Low, Correctness) — 🔒 `EventPattern.jl`
  _build_modifier_test reads the modifiers through get_modifier_keys, with the function put into the expression as a value, so that the expansion resolves in any module.
  *Test:* test_event_case(): the rule WindowResize(; ctrl) on a WindowResize event gives no error and no match.
- [ ] **L06-4** (Low, Correctness) — 🔒 `EventPattern.jl`
  build_event_field_bindings returns body at once when rule.type === nothing, as its docstring promises.
  *Test:* test_event_module(): through a small test macro, the rule _ => 1 gives the body back and no MethodError.
- [ ] **L06-5** (Low, Correctness) — 🔒 `EventPattern.jl`
  The first option of the report: an inner constructor of EventPattern checks that each modifier flag is :ctrl, :shift, :alt or :meta, and throws an ArgumentError that names the flag, as the macro path does. The field type stays Vector{Symbol}, as the docstring states.
  *Test:* test_event_module(): KeyDownPattern(:s; modifiers = [:control]) throws an ArgumentError.
- [ ] **L06-6** (Low, Correctness) — 🔒 `EventPattern.jl`
  _describe of MouseDown and MouseUp gives 'Left button down' and 'Left button up' (and 'button down', 'button up' with no button), after the prefix of the modifiers.
  *Test:* test_event_module(): describe_event_pattern(MouseDownPattern(:left)) is 'Left button down', and MouseUpPattern(:right; modifiers = [:ctrl]) gives 'Ctrl+Right button up'.
- [ ] **L06-9** (Low, Shape) — 🔒 `KeyboardEvent.jl`, `ModifierKeys.jl`, `MouseEvent.jl`
  Apply the rule 'A Bool is never positional': the short KeyDown form takes repeat as a keyword, KeyDown(key, modifiers; repeat = false, time). The docstrings of ModifierKeys and MouseButtons show only the keyword and name forms. The callers in source/ (Sdl.jl:403, Web.jl:597, Console.jl _with_alt_modifier, Web.jl:539, Console.jl:429, sdl_modifiers) and the tests use keywords.
  *Test:* test_event_module(): KeyDown(:a, ModifierKeys(); repeat = true, time = 0.0).repeat is true; then test_sdl_keysym(), test_web_backend(), test_console_backend() and test_gesture_recognizer() pass.
- [ ] **L06-13** (Low, Documentation) — 🔒 `MouseEvent.jl`, `WindowEvent.jl`, `EventInterface.jl`
  The MouseButtons example uses time = 0.0. MouseDown, MouseMove and WindowResize say 'logical pixels'. The header of EventInterface.jl says that the body of get_event_time is in EventDefaults.jl.
  *Test:* No test (docstring text). The corrected example gives true in a session.

### Step 3.7: The device layer

Sealed files: `Display.jl`, `ProjecturedKernel.jl`.

- [ ] **L07-3** (Low, Correctness) — 🔒 `Display.jl`
  An inner constructor of Display requires scale > 0 and zoom > 0 and throws an ArgumentError for any other value (NaN too). The docstring states the limit.
  *Test:* test_device_module(): Display(scale = 0) and Display(zoom = -1.0) throw an ArgumentError (with L07-5).
- [ ] **L07-4** (Low, Documentation) — 🔒 `Display.jl`, `ProjecturedKernel.jl`
  The Display docstring says that the SDL backend draws each logical pixel as get_device_pixel_ratio(display) device pixels, and that the web, console and video backends do not read the Display. The layer diagram says 'layer 7 - the devices and their physical properties'.
  *Test:* No test (docstring text).

### Step 3.8: The gesture layer

Sealed files: `GestureRecognizer.jl`.

- [ ] **L08-3** (Low, Documentation) — 🔒 `GestureRecognizer.jl`
  In pop_gesture!, replace the sentences that name the editor and the tests with 'source answers the next input, or nothing'. The recognizer calls get_event_time(event) in place of event.time (lines 97, 101, 158), as its docstring says. editor.md:48-50, :206-210 and :499-501 say that the chord table of an editor is empty, and the list of events that a reader gets adds WindowClose, WindowResize and WindowDefocus.
  *Test:* test_gesture_recognizer() passes with the same count.

### Step 3.9: The backend layer

Sealed files: `BackendDefaults.jl`, `BackendInterface.jl`, `BackendModule.jl`, `MouseEvent.jl`, `ProjecturedKernel.jl`.

- [ ] **L09-2** (High, Correctness) — 🔒 `MouseEvent.jl`
  The first option of the report: a backend drops a button that the vocabulary does not name. SDL: _sdl_button_sym gives :right only for 3 and nothing for 4 and more, and the poll makes no MouseDown or MouseUp for it. Web: buttonSym in client.js gives left only for 0 and null for 3 and more, and the page sends nothing; Web.jl drops a button name other than left, middle and right. The MouseDown docstring states the rule.
  *Test:* test_input_coalescing(): an SDL button 4 makes no mouse event; test_web_backend(): a mousedown message with an unknown button makes no event.
- [ ] **L09-6** (Medium, Architecture) — 🔒 `BackendInterface.jl`, `BackendDefaults.jl`
  Remove the keyword display of get_display_size, which no caller outside a test passes: the interface, the default, SDL (always display 0, now Sdl.jl:4183), VideoBackend.jl:217 and FaultExamples.jl:144. The docstring says 'the usable size in logical pixels'.
  *Test:* test_headless_backend(): get_display_size(b) is (1280, 800); remove the line with display = 2.
- [ ] **L09-13** (Low, Shape) — 🔒 `BackendInterface.jl`
  The Backend docstring states the order initialize_backend!, configure_devices!, open_native_windows!, as make_editor calls them, and what configure_devices! promises (it fills the devices of the editor in place; a backend that draws with a device keeps that device). initialize_backend! stops saying that it creates windows. play_live! calls configure_devices!(backend, devices) before open_native_windows!.
  *Test:* A playback test with a small backend that records its calls: play_live! calls initialize_backend!, configure_devices! and open_native_windows! in that order.
- [ ] **L09-14** (Low, Shape) — 🔒 `BackendModule.jl`
  Remove the two comments on the include lines, which repeat the docstring (PAR-TIGHT-COMMENTS).
  *Test:* No test; the export guard for the planned part.
- [ ] **L09-16** (Low, Documentation) — 🔒 `BackendModule.jl`, `BackendInterface.jl`
  BackendModule: remove 'measure text', write 'is not' and 'initialize', and say where the backends are (opt-in packages, the console in the substrate, the headless double in an example package). BackendInterface.jl: remove 'may' for a possibility, 'e.g.', 'HiDPI', the objects that act as persons, and the names of callers (the editor loop, a feed flush, the follower window); state timeout_seconds > 0 for wait_for_input.
  *Test:* No test (docstring text); the documentation and naming guards pass.
- [ ] **L09-17** (Low, Documentation) — 🔒 `ProjecturedKernel.jl`; after L09-1
  Write the backend part of devices-and-backends.md again from the table in the Shape section of 09-backend.md (four backends and the headless double, open_native_windows!, wait_for_input and wake_backend!, no tooltip in the browser, read! in ReadEvaluatePrint.jl). Correct editor.md:404-407, system-anatomy.md:320-322, :374 and :495-498, the record_video example in ProjecturedVideo.jl:18, the _emit_frames! sentence in ProjecturedSdl.jl:12, and the layer 9 text in ProjecturedKernel.jl:36.
  *Test:* test_documentation() passes.

### Step 3.10: The sealed files of the document layer

Sealed files: `DocumentSearch.jl`, `ForwardProtocol.jl`.

- [ ] **L10-20** (Low, Correctness) — 🔒 `ForwardProtocol.jl`
  In `_forward_defs`, make the forwarded `push!`, `insert!`, `deleteat!` and `setindex!` return `x`, the wrapper. Emit `Base.length` over the field in `@adapt_map_protocol`.
  *Test:* test_document_contract(): push!(wrapper, v) === wrapper; length and collect work on a toy type under @adapt_map_protocol.
- [ ] **L10-25** (Low, Documentation) — 🔒 `DocumentSearch.jl`
  Name concepts, not functions or types of higher layers. Rewrite the personified sentences with the mechanism as the subject. Merge the fifth paragraph of the `Document` docstring. Give the reason for the place of SelectionDocument without the count: the macro splices the type as an object, so the type must be at or below this layer.
  *Test:* test_documentation(); no code change.

### Step 3.11: The sealed files of the reference layer

Sealed files: `ReferenceInterface.jl`, `ReferenceSearch.jl`, `SelectionDefaults.jl`.

- [ ] **L11-3** (Medium, Correctness) — 🔒 `SelectionDefaults.jl`
  Chosen option: test the layout family (`AFieldReferenceStep`, `ARangeReferenceStep`, `ATypeReferenceStep`) in each `isa` of the two matchers, of strip and fold, of `_copy_reference_step` (an M step copies to an M step) and of `_selection_child` in SelectionDefaults.jl.
  *Test:* test_reference_rules(): each corpus row matches the same on a path of M steps; test_reference_evaluation(): copy_reference copies an M range step.
- [ ] **L11-7** (Medium, Correctness) — 🔒 `ReferenceInterface.jl`
  Add a `Base.hash` that agrees with `==` to the seven step types. Change the fallback `==(::ReferenceStep, ::ReferenceStep)` to `a === b`. State in the `ReferenceStep` docstring that a step type defines `==` and a consistent `hash`.
  *Test:* test_reference_evaluation(): a toy step type with no `==` equals itself; test_text(): two equal paths with a text-range step have equal hashes and give one element in a Set.
- [ ] **L11-14** (Medium, Types/performance) — 🔒 `ReferenceSearch.jl`
  In `_PATH_WALK`, carry the location as a cheap reversed chain of steps (for example nested tuples), and build a `Reference` for each result only, in `search_references`.
  *Test:* test_document_walk() and test_referenced_document() answers unchanged; an allocation count of search_references on a deep toy tree drops.
- [ ] **L11-16** (Medium, Documentation) — 🔒 `ReferenceInterface.jl`, `ReferenceSearch.jl`
  Correct each of the twelve items in place so that the text matches the code. Items 5 and 6 also change the sealed ReferenceInterface.jl and ReferenceSearch.jl, and item 6 about twelve comments in other packages.
  *Test:* test_documentation(); no code change.
- [ ] **L11-25** (part) (Low, Documentation) — 🔒 `ReferenceInterface.jl`
  Delete the history comments, move each misplaced comment to its code, and correct the header of ReferenceInterface.jl so that it names where the seam defaults are. The rule text waits for its decision.
  *Test:* Documentation only.

### Step 3.12: The selection layer

Sealed files: `SelectionDefaults.jl`, `SelectionInterface.jl`, `SelectionModule.jl`.

- [ ] **L12-4** (Medium, Documentation) — 🔒 `SelectionInterface.jl`
  Move the goals 'move the caret after an edit' and 'select what a search found' to a new 'Use it to' paragraph of replace_selection!, with an example that writes at the root document. Keep only 'build a document that nothing holds yet' for set_selection!.
  *Test:* test_documentation().
- [ ] **L12-6** (part) (Low, Documentation) — 🔒 `SelectionModule.jl`
  Say in the module docstring of `SelectionModule` that a document extends `has_dormant_selection`, and that no other generic of the layer has a method outside it. The value readers wait for their decision.
  *Test:* Documentation only.
- [ ] **L12-7** (Low, Shape) — 🔒 `SelectionModule.jl`, `SelectionInterface.jl`, `SelectionDefaults.jl`
  Wrap the eight lines over 90 characters. Shorten the fragment headers of SelectionInterface.jl and SelectionDefaults.jl to one line each.
  *Test:* test_kernel_layering() and test_document_contract(); no behaviour changes.
- [ ] **L12-8** (Low, Documentation) — 🔒 `SelectionInterface.jl`
  clear_selection!: say that it clears the selection along the path that the document holds; delete 'the whole document' and 'all its children'. replace_selection!: say that a caret move in a leaf writes the selection cell of the leaf once and writes no ancestor cell; the start/stop write in place applies only where the path starts with the range step.
  *Test:* test_documentation().
- [ ] **L12-9** (Low, Documentation) — 🔒 `SelectionDefaults.jl`
  Replace the comment with: 'At a divergence the old branch is cleared, or kept and marked dormant when a document on it asks to keep it. Marking walks the same path as a clear and writes a flag.' Then correct code-quality-rules.md section 2, which names this line as the history comment that waits for permission.
  *Test:* The grep of code-quality-rules.md section 2 finds no match in source/kernel/selection/.
- [ ] **L12-10** (Low, Documentation) — 🔒 `SelectionInterface.jl`, `SelectionDefaults.jl`, `SelectionModule.jl`
  Correct the headers: the interface declares nine generics; the defaults header is one line (L12-7); the module docstring names the dormant generics and map_selection_forward. Replace 'a tab group', 'a pane group', 'a tabbed pane' and 'CellVector' with the concept. In selection.md: the layers are 11 and 10; link SelectionMismatchException to its own section; delete the fallback sentence at lines 319-321.
  *Test:* test_documentation().

### Step 3.13: The sealed files of the iomap layer

Sealed files: `IoMapInterface.jl`.

- [ ] **L16-9** (Low, Documentation) — 🔒 `IoMapInterface.jl`
  Remove the idiom and the personification in IoMapInterface.jl; drop ChainingIoMap; add the optional cell kind to the @iomap signature; replace 'unminimal', the string example and 'crucially'; make the fragment header one line; wrap line 95; add IoMapReconcile.jl and the reconcilers to architecture.md and system-anatomy.md; say in PAR-STABLE-IOMAP-IDENTITY that the key is the identity and the index.
  *Test:* test_documentation().

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

- [ ] **L06-15** (Low, Tests) — after L06-3, L06-4, L06-5, L06-6
  Add the missing cases: the four has_*_modifier_key functions, get_modifier_keys of a KeyChord and of a window event, get_event_time of an event type of another module, the text of KeyUp, MouseDown, MouseUp and KeyChord patterns, and the cases of L06-3 to L06-5. The tests of the eight unused names wait for L06-7, and the rename of EventCaseTest.jl waits for L06-10.
  *Test:* test_event_module() and test_event_case() pass with the new cases.

### Step 4.7: Tests of the device layer

- [ ] **L07-5** (Low, Tests) — after L07-3
  Add a test of the values that L07-3 rejects, and rename the test 'a backend writes the properties in place' to 'each device is mutable'.
  *Test:* test_device_module() passes with the new test.

### Step 4.8: Tests of the gesture layer

- [ ] **L08-4** (Low, Tests)
  Add a double click whose second click is in another window (count 1), and the limits of the click windows (a release at 5 px or after 0.3 s is no click, because the test is a strict <). Remove sleep(0.35) and keep the two event times. The two chord cases (another event between the keys, keys of two windows) go with L08-1.
  *Test:* test_gesture_recognizer(): the new cases pass, and the run is 0.35 s shorter.

### Step 4.9: Tests of the backend layer

- [ ] **L09-18** (Low, Tests) — after L09-1, L09-2
  Put one table of inputs into each of the three existing backend tests: the letters a to z (L09-1), the three buttons and a side button (L09-2), and a wheel turn away from the user, dy > 0 (L06-2); through sdl_to_keydown and the SDL poll, _decode_and_enqueue! of the web backend, and _next_event! of the console. Add kernel tests of the defaults of get_pointer_position and open_native_windows!. Correct the docstring of HeadlessBackendTest.jl (no measure).
  *Test:* test_sdl_keysym(), test_input_coalescing(), test_web_backend(), test_console_backend() and test_headless_backend() pass with the new cases.

### Step 4.10: Tests of the document layer

- [ ] **L10-15** (Medium, Tests) — after L10-1, L10-2, L10-3, L10-4, L10-5
  Add one test case for each fixed finding, in the commit of its fix. Add a kernel test of SelectionDocument and unwrap_selection with a toy document, of `get_edited_field` and `replace_wrapped_document!`, and direct tests of `@forward_protocol` and `@adapt_map_protocol`.
  *Test:* test_document_contract(), test_document_macro(), test_document_walk(), test_bounded_sync().
- [ ] **L10-26** (Low, Tests) — after L12-5
  Declare DmValueSel at the top level with the other fixtures. Move the four selection testsets into the kernel selection test file that L12-5 adds. Delete the history phrases.
  *Test:* test_document_macro() prints no world-age warning; the moved cases pass in the kernel selection test.

### Step 4.11: Tests of the reference layer

- [ ] **L11-19** (Medium, Tests) — after L11-1, L11-3, L11-4, L11-7
  Add toy-document tests to ReferenceEvalTest.jl for get_valid_reference_prefix, is_valid_reference, try_evaluate_reference, copy_reference, concat_references, extend_reference, fold_reference_types and search_references. Add the multi-byte, M-step, `nothing` and arm-word rows with their fixes. Rewrite TypeReferenceTest.jl on toy documents in the folded form in the kernel suite.
  *Test:* test_reference_evaluation(), test_reference_rules().

### Step 4.12: Tests of the selection layer

- [ ] **L12-5** (Medium, Tests)
  Add test/kernel/selection/SelectionTest.jl with test_selection() and test-local @document types: a mismatch throws SelectionMismatchException and keeps the cell; replace_selection! clears the divergent branch; a caret move writes no ancestor selection cell; a keeper marks a branch dormant and a later write makes it live; map_selection_forward carries the dormant state; @with_selection builds a typed path. Register it in KernelSuite.jl and ProjecturedKernelTest.jl.
  *Test:* test_selection().

### Step 4.13: Tests of the operation and intent layers

- [ ] **L13-11** (Medium, Tests)
  Add testsets for: the 'next hole' evaluation; describe_operation of each kernel type and the (operation, root) form; splice_string, splice_number and splice_value!; the reroot of a document-rooted ReplaceReferencedValueOperation; the defaults of operation_reference, retarget_operation and operation_travels_unchanged. Make the ToyList override in TraversalTest.jl use .items[i].
  *Test:* test_rerooting(), test_inversion(), test_traversal(), and a new test_description().
- [ ] **L14-3** (Medium, Tests)
  Add test/kernel/intent/IntentTest.jl with test_intent(): a route that starts with the steps, one that does not, a route of nothing, the labels that each constructor keeps, and ClaimedGesture. Move the two testsets of CollectedIntentsOperation and merge_collected_intents from RerootingTest.jl. Register it in KernelSuite.jl and ProjecturedKernelTest.jl.
  *Test:* test_intent() and test_rerooting().

### Step 4.14: Tests of the binding layer

- [ ] **L15-6** (Medium, Tests) — after L15-1, L15-8
  Add testsets: claimed with and without override; get_instance_gesture_bindings and the order instance before type; the three-argument read_bound_gesture; a [DC], an [M] and an [I] document; an operation that returns nothing so that a later rule fires.
  *Test:* test_gesture_binding().
- [ ] **L15-14** (Low, Tests)
  Delete the four testsets of matches_event_pattern and describe_event_pattern after a check that EventModuleTest.jl asserts the same cases; move a case that it lacks there. Delete 'old hand-written' from the header.
  *Test:* test_gesture_binding() and test_event_module().

### Step 4.15: Tests of the iomap layer

- [ ] **L16-3** (Medium, Tests)
  Add test/kernel/iomap/IoMapReconcileTest.jl and IoMapDefaultsTest.jl (test_iomap_reconcile(), test_iomap_defaults()): a delete and a front insert make the later children again; an element that goes away leaves the cache; one object at two indexes gets two child IoMaps; a make_iomap that returns nothing; reconcile_child_iomap with the same and with a new object; the supertype and the kind argument of @iomap; the three accessors. Register both in KernelSuite.jl and ProjecturedKernelTest.jl.
  *Test:* test_iomap_reconcile() and test_iomap_defaults().

### Step 4.16: Tests of the projection layer

- [ ] **L17-12** (Medium, Tests) — after L17-1
  Add kernel tests with fixture documents for with_inner_size, with_size_range, get_property, the typed make_child_context, the default mappers, the branches of the default reader, the bridge, read_routed_intent, ProjectionReferenceStep (==, show, the .proj DSL), @projection and read_projection_gesture. Add substrate tests for each wiring kind (tokens, sections, mixed, conditional) with an edit through the same IoMap.
  *Test:* The new test functions, each run alone: for example test_projection_defaults() in test/kernel/projection/ and test_projection_template_wirings() in test/substrate/projection/.

### Step 4.17: Tests of the tool layer

- [ ] **L18-14** (Medium, Tests)
  Make the four assertions exact: compare the answer of string(Cell) with the quoted name, or also assert that the answer holds no UndefVarError.
  *Test:* test_declared_api().
- [ ] **L18-15** (Medium, Tests) — after L18-1, L18-2, L18-5, L18-6, L18-7, L18-8
  Add kernel cases for an observer that throws, call_tool with an unknown name, the replacement in register_tool!, and register_guide_root!, and move the observe_evaluations! case down from EvaluatorToplevelTest.jl. The cases of L18-1, L18-2, L18-5, L18-6, L18-7 and L18-8 come with those fixes.
  *Test:* test_declared_api() and test_code_execution().

### Step 4.18: Tests of the llm and agent layers

- [ ] **L19-9** (Low, Tests)
  Add test/kernel/llm/LlmDefaultsTest.jl with `FakeLlm`: the error of `make_llm` and `default_llm_model` for a kind that no package answers, the answer of `get_llm_backend_names()`, `is_walk_opaque(::Llm)`, and the conversions of the `LlmRequest` and `LlmMessage` constructors. Register it in the kernel test package and suite.
  *Test:* test_llm_defaults() in ProjecturedKernelTest.
- [ ] **L20-7** (Medium, Tests)
  Add test/kernel/agent/AgentLoopTest.jl with `ScriptedLlm` and a NamedTuple target: the round cap and its answer, `LlmFailure` gives `:error`, a tool that throws (the fault record and `is_error`), a tool name that no tool answers, a stream with no terminal event, and the order of the `AgentToolResult` events. Rename AgentSeamTest.jl to AgentDefaultsTest.jl and `test_agent_seam` to `test_agent_defaults`.
  *Test:* test_agent_loop() and test_agent_defaults() in ProjecturedKernelTest.

### Step 4.19: Tests of the feed and editor layers

- [ ] **L21-7** (Low, Tests) — after L21-2, L21-3
  Move test/kernel/feed/FeedTest.jl to test/kernel/editor/FeedsTest.jl (it tests editor/Feeds.jl). Add a drain that throws (L21-2) and a deadline that throws (L21-3).
  *Test:* test_editor_feeds() from its new file, with the two new cases.
- [ ] **L22-17** (Medium, Tests) — after L22-6, L22-11
  Add test/kernel/editor/FaultBarriersTest.jl with a backend that throws on demand in `read_from_devices` and `write_to_devices` (in the test file or ProjecturedKernelExample) and an operation that fails half way. Cover repairs 0 to 2, the two breakers at their limits, a reader that throws in `run_frame!`, a feed that throws in the drain, a queued call that throws in `_answer_waiting_calls!`, and the zoom keys.
  *Test:* test_editor_fault_barriers() in ProjecturedKernelTest.
- [ ] **L22-31** (part) (Low, Tests)
  Add a kernel test of `find_rooted_operation` with a stand-in projection that follows a route, and drive `walk_repl_loop` through a real `Editor` and `run_frame!`. The private names that the tests use wait for their decision.
  *Test:* The two new test sets pass.

## Phase 5 — The renames

Each rename changes a public name. Run the tool with `--report` first, and read `--show-other`. Then correct the prose, which the tool skips. The renames of `run_fault_barrier`, `get_cell_struct_trailing_default_count` and `build_cell_struct_positional_ctors` change sealed files: they need the permission of phase 3. The renames that reach omnet-julia or inet-julia need a worktree there, and the three branches land together.

### Step 5.1: The renames, with `workspace/bin/julia-rename.jl`

- [ ] **L01-14** (Low, Naming) — 🔒 `FaultBarrier.jl`, `FaultModule.jl`, `FaultCascade.jl`, `FaultStore.jl`, `FaultPolicy.jl`, `FaultInterface.jl`
  Rename `run_fault_barrier` to `run_fault_barrier!` with workspace/bin/julia-rename.jl, then correct the prose in the docstrings, fault.md and system-anatomy.md.
  *Test:* test_fault_barrier(); test_naming(); a grep finds no `run_fault_barrier(` without `!`.
- [ ] **L04-7** (Low, Shape) — 🔒 `CellStructPlan.jl`, `CellStructModule.jl`
  Remove `get_cell_struct_trailing_default_count` from the export block, rename it to `_get_cell_struct_trailing_default_count` with workspace/bin/julia-rename.jl, test it through `get_cell_struct_required_count`, and remove it from the public list in cell.md.
  *Test:* test_cell_struct_plan: get_cell_struct_required_count is right for no, one and all trailing defaults; test_exports(); test_naming().
- [ ] **L04-8** (Low, Naming) — 🔒 `CellStruct.jl`, `CellStructModule.jl`
  Rename `build_cell_struct_positional_ctors` to `build_cell_struct_positional_constructors` with workspace/bin/julia-rename.jl, and make `parameters` of `build_cell_struct_keyword_constructor` a keyword.
  *Test:* test_cell_struct(); test_cell_struct_plan(); test_document_macro(); test_arguments().
- [ ] **L10-23** (Low, Naming)
  Rename `sync_element_limit` to `compute_sync_element_limit` with workspace/bin/julia-rename.jl, and give the private helpers `is_same_document_type`, `copy_shadow_element` and `is_walk_leaf` a leading underscore. Update the prose that names them and the protocol list in test/suite/arguments.jl.
  *Test:* test_naming(), test_arguments(), test_bounded_sync(), test_document_reflection().
- [ ] **L11-24** (part) (Low, Naming)
  Rename `ReferenceEvalTest.jl` to `ReferenceEvaluationTest.jl` and its testset "ReferenceEval" to "ReferenceEvaluation". The name of `ref"…"` waits for its decision.
  *Test:* `test_kernel()` runs the file under its new name.
- [ ] **L18-25** (Low, Naming)
  Rename with workspace/bin/julia-rename.jl: api_entry_bindings to get_api_entry_bindings, api_source_name to get_api_source_name, execute_julia_code to execute_julia_code!, execute_julia_expression to execute_julia_expression!. Keep the MCP tool name "execute_julia_code", a wire string.
  *Test:* test_naming(), test_code_execution() and test_declared_api(); then Pkg.precompile and the assistant tests in omnet-julia.
- [ ] **L19-6** (Low, Naming) — after L19-3
  Rename `default_llm_model` to `get_default_llm_model` with workspace/bin/julia-rename.jl (a value at a known place takes `get_`). Then correct the prose in agent.md and llm.md.
  *Test:* test_anthropic_model() and test_ollama_backend() with the new name; the naming guard.

## Phase 6 — The text

Text only. The documentation guards must pass after each step.

### Step 6.1: The law and the architecture guide

Each item corrects a fact about the code. No item changes what a rule requires.

- [ ] **L01-5** (part) (Medium, Documentation)
  Say in fault.md, the `Editor` docstring and the header of FaultBarriers.jl that `make_editor` turns the barriers on and that `run_editor!` keeps the policy of its editor (decision 3 of plan/done/an-editor-is-made-before-its-loop-runs.md). The policy of the tests waits for its decision.
  *Test:* Documentation only; the documentation guards pass.
- [ ] **L01-17** (part) (Low, Documentation)
  Move the section PAR-REPORT-NEVER-THROWS under the title that the index gives it, and add a `fault/` row to the folder table of architecture.md. The wording of the carve-out waits for its decision.
  *Test:* Documentation only; the documentation guards pass.
- [ ] **L02-6** (Low, Documentation)
  Say that the counters live in the scope of one frame of one editor, remove the history sentence, say that `perf!` logs only with the switch on and an applied operation, point the link of `run_editor!` to EditorLoop.jl, name the frame measurement store in the folder row, and call PerformanceModule a layer.
  *Test:* test_documentation().
- [ ] **L05-3** (Low, Documentation)
  Add one sentence to PAR-STORE-THEN-DRAIN: the heartbeat of a wall clock is the accepted exception, on the thread of the task that reads the clock.
  *Test:* test_documentation().
- [ ] **L06-14** (Low, Documentation)
  Write the event part of devices-and-backends.md again from the EventModule docstring: nine fragments, EventPattern.jl, get_event_time, the current names (matches_event_pattern, describe_event_pattern, parse_event_pattern_rule, build_event_pattern_expr, build_event_field_bindings), a type resolves in the module of the pattern, and WindowQuit is a request to quit. Correct system-anatomy.md:369-371 and architecture.md:107 and :167.
  *Test:* test_documentation() passes.
- [ ] **L10-13** (Medium, Documentation) — after L10-1
  Rewrite the file tree, the selection paragraph and the contract surface of document.md, and replace the example of a private program. Correct the selection union in macros.md. In architecture-invariants.md correct the stale fact of PAR-DOCUMENT-IDENTITY: the cell layout is an immutable struct. The text of PAR-NO-NESTED-CELL waits for its decision (L10-13, decision part).
  *Test:* test_documentation(); no code change.
- [ ] **L17-27** (Low, Documentation)
  Correct each statement: projection-system.md (the editor calls the 4-argument print; Intent has five fields, and route is one; no pipeline uses the pure pair), macros.md (18 files use @projection_template, and hand-written printers remain), naming-rules.md:384-385 (the marker words are not exported), architecture.md:111 (ProjectionModule is layer 17).
  *Test:* test_documentation().
- [ ] **L22-28** (Low, Documentation) — same fault as L01-5
  Say that `make_editor` turns the barriers on and `run_editor!` keeps the policy of its editor, and drop the stale claim that no test calls `run_editor!`.
  *Test:* None; the change is text only.

### Step 6.2: The design documents and guides

- [ ] **L11-15** (Medium, Documentation)
  Write `__ =>` in the three examples, and `children[i].rest...` in the example of projection-system.md.
  *Test:* test_documentation(); each corrected snippet expands with no LoadError.
- [ ] **L13-10** (Medium, Documentation)
  Rewrite the comment above the catch-all: a reader that declines returns nothing; the catch-all accepts any value that is not an Operation, so a stray value does no harm. Correct operation.md:298 the same way.
  *Test:* test_documentation().
- [ ] **L13-16** (Low, Documentation)
  Module docstring: six fragments, OperationInterface.jl, four open seams, and describe_reference. Correct the headers of Operations.jl and OperationInterface.jl. Point AdjustZoomOperation to OperationDefaults.jl. Replace StringReplaceRangeOperation at Description.jl:43 with a real name. Correct the Operation example and the insert_elements signature. Give QuitEditorException a docstring. Drop 'the collection package' and 'the editor loop'. Rewrite the layer section of operation.md from the six files.
  *Test:* test_documentation().
- [ ] **L14-8** (Low, Documentation)
  IntentModule.jl: say that the types sit in layer 14, above the operation layer, and drop 'the binding layer above'. ClaimedGesture: describe it by concepts; drop JSON, XML, fire_gesture_bindings, 'the generic reader bridge', ProjectionModule and '(now)'. CollectIntents: delete 'ClaimedGesture is the precedent'. Intent: show five fields in the signature line, and say that WindowInput is an event of the event layer. projection-system.md: link Intent.jl and show five fields.
  *Test:* test_documentation().
- [ ] **L15-5** (Medium, Documentation)
  Correct the signatures of fire_gesture_bindings (565) and fire_named_gesture_binding (598). Add GestureBindingInterface.jl with read_gesture to the tree (552-557). Correct the downward edges (630-633): EventModule once, add IntentModule, drop DocumentModule: Document. Write move_to_field(doc; from, to) at 606 and engineer-tour.md:191. Put the command palette in the gesturehelp package (625).
  *Test:* test_documentation().
- [ ] **L17-14** (Low, Correctness)
  Say in the docstring of print_document(projection, input) that the form is for a leaf or a wrapped pipeline, because it passes recursion = nothing. Correct projection-system.md:110-112: the editor calls the 4-argument form.
  *Test:* test_documentation().
- [ ] **L17-22** (Low, Documentation)
  Correct each path and name: documentation/testing.md to the testing guide, package/kernel/doc/... to documentation/package/kernel/..., 'Sequential' to ChainingProjection, and `[_with_selection](@ref)` to plain text. Delete the citations of plan/pending/cell-kind-documents.md with L17-24.
  *Test:* test_documentation().
- [ ] **L18-26** (Low, Documentation) — after L18-1
  Name each process-global value of the layer, and why it is there, in the ToolModule docstring and agent.md:59. Correct the empty-API sentences (Tool.jl:189, Documentation.jl:1262, agent.md:362, mcp-guide.md:50) after L18-1. Delete the remark about the wall clock at Documentation.jl:876.
  *Test:* test_documentation().
- [ ] **L18-29** (Low, Documentation)
  Show the api keyword in the docstring signatures of list_modules, read_module_documentation, read_type_documentation and read_function_documentation. Drop 'tips and tricks' (also in DefaultTools.jl:291). Move each comment above the function that it describes. Say in _is_interface_name that the prefix I means immutable. Name ApiEntry and observe_evaluations! in the ToolModule docstring and agent.md:30.
  *Test:* test_documentation().
- [ ] **L19-3** (Low, Shape)
  Keep the generic and correct its docstring: it answers the model that the backend falls back to, and a backend can choose another model for an empty name (the Anthropic adapter asks the Models API first). Correct agent.md:287 to match.
  *Test:* None; the change is text only.
- [ ] **L19-7** (Low, Documentation)
  List the five fragments in the LlmModule docstring (the seams in LlmInterface.jl, the fallbacks in LlmDefaults.jl). Correct agent.md:213-217 and :282 (`get_llm_backend_names` is in Llm.jl). Write ProjecturedAnthropic and ProjecturedOllama for the package `Llm`/`llm` in the three rule and design documents.
  *Test:* None; the change is text only.
- [ ] **L20-11** (Low, Documentation)
  Say in the module docstring that the module holds both halves. Name AgentInterface.jl as the file of the seam and add AgentDefaults.jl in system-anatomy.md and agent.md; write one AgentModule in place of the two.
  *Test:* None; the change is text only.
- [ ] **L21-6** (Low, Documentation)
  Name kinds in place of consumers (a feed that holds a queue of operations, the read step of a frame); write 'the default does nothing, for a feed whose producers never wake the editor'; add `TooltipFeed` to the table of editor.md and drop 'so far'; state the fault store and the tick cadence in the present tense.
  *Test:* None; the change is text only.

### Step 6.3: The docstrings and comments of files that are not sealed

- [ ] **L10-12** (Medium, Documentation)
  Correct the six statements: the injected field is `Union{Nothing, Reference, SelectionDocument}`, and an explicit `selection` field is accepted when it is last; the kind constructors are `ICFoo`/`MCFoo`; the bare constructor builds `DCFoo`; the layout codes include `I`; the file has eight emitters; the comment at line 593 gives the current union.
  *Test:* test_documentation(); no behaviour change.
- [ ] **L10-24** (Low, Documentation)
  Delete each history phrase. Keep a constraint that the code can not show in one sentence in the present tense.
  *Test:* test_documentation(); no code change.
- [ ] **L15-13** (Low, Documentation)
  Correct 'below' at GestureBindingInterface.jl:20; add override to the signature at GestureBinding.jl:16; name the three fragments, get_instance_gesture_bindings, fire_named_gesture_binding and CollectIntents in the module docstring; remove the consumer names, 'layer' for a pipeline stage, and the idioms; delete the repeat of the grammar at Gestures.jl:6-28; wrap the ten lines over 90 characters.
  *Test:* test_documentation().
- [ ] **L16-2** (Medium, Documentation)
  Rewrite the compound printer example: child_iomaps = reconcile_child_iomaps(...); the mappers read iomap.child_iomaps (no []); build the reference with @reference.
  *Test:* test_documentation().
- [ ] **L16-4** (Low, Correctness)
  State in both docstrings that the IoMap that make_iomap returns must hold the element (as its input), because the cache key is objectid, a number, and not a reference to the element. This is the smaller option and answers PAR-MODULE-DOCSTRING; the other option keeps the element in the cache entry and compares it with ===.
  *Test:* test_documentation().
- [ ] **L17-23** (Low, Documentation) — after L17-6, L17-10, L17-13, L17-16
  Correct each false statement: the fragment table; 'every structural projection uses the engine' (four *ToSyntax files hold hand-written printers); ':terminal' to :structural; drop '(nodes; WIP)'; correct line 794 and lines 466-469; correct the export claim of the pure printer.
  *Test:* test_documentation().
- [ ] **L17-24** (Low, Documentation)
  Delete the history at ProjectionTemplate.jl:265-275 and keep its constraint in the present tense. Name F1, F2 and F3 in words (a nested sub-node, a reactive child list, an as= override). Delete 'from day one' and the plan-phase citations at ProjectionTemplate.jl:228 and ProjectionInterface.jl:150-153.
  *Test:* test_documentation().
- [ ] **L17-25** (Low, Documentation)
  Describe the contract only: remove the names of higher packages and consumers (PointReferenceStep, map_operation_position, the render stage, PaneToWidget, FocusingProjection, Clipboard, the editor loop), write 'stage' where the text calls a pipeline stage a layer, and delete the second copy of the comment at ProjectionTemplate.jl:1374-1380.
  *Test:* test_documentation().
- [ ] **L17-26** (Low, Documentation)
  Show the 4-argument read_intent in the Example, with a gesture that needs geometry. Say that a 4-argument reader returns an Intent, and correct 'Leaf projections therefore keep their 3-arg methods'. Give map_reference_backward, print_child, PrinterContext, make_child_context and read_routed_intent a 'Use it to' paragraph, an Example and 'See also'. Move the older paragraph of the Projection docstring above 'See also'.
  *Test:* test_documentation().
- [ ] **L18-28** (Low, Documentation)
  Delete the history comments (DefaultTools.jl:285-288 and :228-229; DeclaredApiTest.jl:110, :160 and :513-518) and rename the testset in SearchQueryTest.jl:157. Drop the two PAR-PER-EDITOR-STATE citations. State the contracts of Tool.jl:229-232, the ApiEntry docstring and the declare_api! example in the terms of this layer. Remove the personification at DefaultTools.jl:169 and ToolModule.jl:25.
  *Test:* test_documentation(), test_declared_api() and test_search_query().
- [ ] **L19-8** (Low, Documentation)
  Name the kind of value in place of a provider or a higher layer (a provider-specific tool list, a caller that runs tools), say what the code does (a `Tool` holds no wire format), and wrap LlmMessage.jl:110 under 90 characters.
  *Test:* None; the change is text only.
- [ ] **L20-12** (Low, Documentation)
  Describe the contract without the layer above, keep one statement of the two halves (in the module docstring), write 'the loop streams, runs the tools, and stops when the model asks for no tool', add a Throws line to `run_turn!` (it throws what `stream_turn`, `messages` and `on_event` throw), and wrap AgentLoop.jl:45 and :87.
  *Test:* None; the change is text only.
- [ ] **L22-29** (Low, Documentation)
  Update the sections: all 17 fields of `Editor`; the recognizer makes a `MousePress` after its `MouseUp` and recognizes no chord today; the three backends with `WebBackend`; the nine files of the layer; the full list of downward edges; the tests with WaitTest.jl, the feed test and the safe-mode test.
  *Test:* None; the change is text only.
- [ ] **L22-30** (Low, Documentation)
  Remove the consumer names and the rule citation, repair the `print!` sentence, name all five keywords in the header of the `run_editor!` docstring, describe the barrier and the repairs in the `evaluate!` docstring, say that `insert_elements!` runs on the editor task, make each fragment header one line under 90 characters, and wrap the long lines.
  *Test:* None; the change is text only.

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
- **L23-10** (Low) waits for L23-5. Rename `_timeline_operation` to `_make_timeline_operation` and the keyword `op_prefix` to `operation_prefix` (the full word; one caller, example/sdl/LiveExamples.jl:138), and the locals `op`, `acc`, `cur`, `n`. `_path_to_steps` goes with L23-9.
- **L23-11** (Low) waits for L23-5. Remove the consumer names from Playback.jl, correct the claim of 'the same path live input takes' (or fix it with L23-3), name `op_prefix` in the header of the bootstrap docstring, give editor.md the real signature, folder and use of `OperationModule`, delete the stale 'Known remaining instance' sentence of architecture-invariants.md, and wrap the six long lines.

## Faults that the classification found

The classifiers and the implementers found faults that the audit does not hold:

- [ ] **N-1** (Medium, Correctness) — omnet-julia and inet-julia
  `KeyDown(:enter)` names a key that no backend reports: the name of the key is `:return`. Write
  `:return` in omnet-julia `source/tool/record_precompile.jl:111` and in inet-julia
  `source/tool/repl/record/driver.jl:56`.
  *Test:* the two record scripts run, and the recorded trace holds the key.
- [ ] **N-4** (Medium, Correctness) — found in step 2.1
  `Sdl.jl` defines `map_reference_forward` and `map_reference_backward` for
  `GraphicsCanvasToImageFile` with no import, so they are new functions of ProjecturedSdl and
  do not extend the functions of the projection layer. Qualify them
  (`ProjectionModule.map_reference_forward(...) = ...`), as PAR-QUALIFIED-EXTENSION asks.
  *Test:* `ProjecturedSdl` has no own `map_reference_forward`, and `test_sdl()` passes.
- [ ] **N-5** (Medium, Correctness, Suspected) — found in step 2.4
  The undo of an element overwrite on a reactive `CellVector` can put back the new value:
  `get_slot_at` answers the slot cell, and `setindex!` writes the new value into that same cell,
  so the inverse holds a cell that already has the new value. First prove it with a run (an
  overwrite of one element of a reactive `CellVector`, then its inverse). If it holds, make the
  inverse keep the old value, not the cell, as `make_inverse_operation` promises.
  *Test:* `test_inversion()`: the inverse of an overwrite puts back the old value.
- **N-2** (Medium, needs a decision): Ctrl+, (`KeyDownPattern(:comma)` in
  `source/projection/generic/Focusing.jl:70`) can never fire, because `:comma` is in no key
  vocabulary and no backend names it. A new key name is a decision: see the table below.
- **N-3** (Low, outside the kernel): the argument guard also reports `Application.jl:631` and
  `TextMeasure.jl:223`. They ask the same question as L18-3 and L22-1.

## Not in this plan: the decisions of the owner

Each row is one question. The report of the layer gives the options. A part of some of these
findings is already an item above, marked "(part)".

| ID | Severity | The question |
| --- | --- | --- |
| L01-1 | High | How must a fault that the full store drops reach a person? |
| L01-2 | High | Which layer stops the growth of the targets: the sealed store, with a detach when the safe mode ends, or the safe-mode projection above the kernel, with one log for each store? |
| L01-5 | Medium | Tests reach `make_editor`, which catches by default: must these tests pass the strict policy, or does the second half of PAR-REPORT-NEVER-THROWS change? |
| L01-8 | Low | Which sentence of PAR-REPORT-NEVER-THROWS wins in the report path: 'a report never throws' or 'an exception that means stop is never caught'? |
| L01-12 | Low | Does the seam `make_safe_mode_projection` move from the fault layer to the editor layer? |
| L01-17 | Low | The count of the fault store grows at each write: which property qualifies a collector for the carve-out of PAR-NO-WRITE-IN-THUNK? |
| L02-1 | Medium | How does the counter switch reach the package cache: a preference, with a new dependency of the kernel, or a written rebuild step? |
| L02-5 | Low | Which verb-first name replaces `with_performance_counters`, which binds a scope and makes no copy? |
| L03-1 | High | Which form does a failed computation take in a cell? |
| L03-2 | Medium | Does the engine get a state for a cell that computes now, so that a write during a computation is not lost? |
| L03-3 | Medium | Shall the engine detect a cycle and throw an ordinary exception that a barrier can record? |
| L03-8 | Low | Does the cell layer get a public read of the stored value, so that persistence stops reading private fields? |
| L03-9 | Low | May the walk take @nospecialize, and may the timing run (it needs an idle machine and your approval)? |
| L03-10 | Low | Which `make_` name replaces `copy_cell_as`? |
| L04-2 | Low | Must the generated setter refuse a cell as a value, at the cost of one type test on each write? |
| L04-3 | Low | What does a Computation argument give to a type parameter? |
| L04-4 | Low | Does the sync ask for the kind of each field, or does a struct of mixed kinds never reach the sync? |
| L04-5 | Low | Does @cell_struct apply Rule Y, as macros.md says, or only @document? |
| L04-6 | Low | Shall the generated methods point to the declaration of the struct, with a new source argument on the exported builders? |
| L05-1 | Medium | As L03-2: does the engine get a state for a cell that computes now? |
| L06-7 | Low | Do the eight exported event names with no user (has_shift_, has_alt_, has_meta_modifier_key, KeyUpPattern, MouseDownPattern, MouseUpPattern, MouseEnterPattern, MouseLeavePattern) stay as part of a complete family with tests, or go? |
| L06-8 | Low | Does the event layer export a predicate that tells whether a rule binds a field, so that Gestures.jl stops its test of object identity? |
| L06-10 | Low | Do you want EventPattern.jl (521 lines) split into two fragments now, and what is the name of the new fragment? |
| L06-11 | Low | Do you change the public type EventPattern for speed before a measurement shows a cost? |
| L06-12 | Low | Does describe_event_pattern take the verb format_, which the verb table gives for a function that makes text? |
| L07-1 | Medium | Do you reopen the decision of plan/done/device-layer-audit.md and let the kernel step the zoom of the Display, so that the web backend can zoom too? |
| L07-2 | Medium | Is the size of the display a property of the Display device, or only the answer of get_display_size(backend)? |
| L08-1 | Low | While a chord waits for its next key, does another input (a key up, a character, a click, a key of another window) wait behind the kept keys, or does it break the chord? |
| L09-3 | Medium | How does a package answer write_image, record_video, render_canvas and decode_image, so that a second implementer does not overwrite the first? |
| L09-4 | Medium | Does a video show every window of the screen (tooltips, popups, dialogs), or only the main window? |
| L09-5 | Medium | Where does the console map a plain Home to the selection of the root, when the backend stops its remap to Ctrl+Alt+Home? |
| L09-7 | Medium | Does the offscreen renderer of ProjecturedSdl become public API (names without an underscore), or a declared seam that the video package uses? |
| L09-8 | Medium | Does render_canvas stay as a seam for a later renderer, or go? |
| L09-10 | Low | Does get_pointer_position answer nothing for an unknown position, in place of (-1, -1), which is also a real position on a monitor to the left of or above the primary one? |
| L09-11 | Low | Does the devices argument of the three per-frame generics stay, now that configure_devices! gives the Display to SDL and no backend reads the argument? |
| L09-12 | Low | Does the kernel give one answer for an output of the wrong type, one window id for an input with no window, and one helper for the gated wait? |
| L09-15 | Low | Do the four backend generics with an external effect take a !, and which name does read_from_devices take? |
| L10-3 | High | How does the sync treat a mutable container in a leaf: copy it (a cost for a large buffer, and a throw for unassigned slots), copy it only for some types, or keep the reference and invalidate by another signal? |
| L10-6 | Medium | Does a field declared `Vector{T}` become a `CellVector` in every constructor and copy of the cell layout, as commit 3bdf2eb2 and the docstring say, or does the substitution go? |
| L10-7 | Medium | What must a plain copy, a kind copy and a sync do at a back-link: throw a DocumentCopyException, or share or skip the node? |
| L10-8 | Medium | Do the kind copy and `sync_document!` take `policy` and `depth` as keywords, or keep two optional positional arguments with a marker? |
| L10-9 | Medium | How does the walk keep out of closures, types and the undo history: new walk leaves and an opaque history container, or a default `descend` that follows `get_edited_field`? |
| L10-10 | Medium | Does the walk rethrow the exceptions that mean stop from a predicate, although its docstring says that an exception from the predicate counts as no match? |
| L10-11 | Medium | Does the `@document` expansion ask its seams at run time, or stay at expansion time with a guard on the load order? |
| L10-21 | Low | Does the private seam `_declared_value_types`, which every `@document` expansion extends, become a public exported name, or stay private with a stated exception? |
| L11-2 | Medium | On a `nothing` input, does a catch-all arm (`__ =>`, `rest... =>`) answer its result, as the compiled matcher does, or `nothing`, as the normative interpreter does? |
| L11-5 | Medium | Do `try_evaluate_reference`, `get_valid_reference_prefix` and `annotate_reference_types` rethrow the exceptions that mean stop and a missing step method, although `try_evaluate_reference` promises a default instead of a throw? |
| L11-6 | Medium | Does `search_references` on a ReferencedDocument answer paths from the root (its reference prepended) or from its document, as D5 lifts `search_documents`? |
| L11-8 | Medium | What does a range step `{s:e}` with s < e evaluate to: its first item as now, a new span value beside Position, or the (start, stop) tuple of the text steps? |
| L11-9 | Medium | Does the pattern AST become exported API after its rename, or does omnet-julia get an exported query surface while the AST stays private? |
| L11-10 | Medium | Does the pattern language (the rules DSL, the string spelling, the glob matcher and the interpreter) stay in the kernel? |
| L11-11 | Medium | Do the step types keep `@document [C, M]` as the ruling of 2026-08-24 says, or drop the injected selection field and use an immutable value layout, and do the `type` and `head` cells of a path node become immutable? |
| L11-12 | Medium | Does a rules answer keep its compile into a process-wide method table, with a lock and a collision check, or does the interpreter evaluate the common answer shapes with no eval? |
| L11-13 | Medium | Which layer copies the range step of the caller: `strip_reference_types` in the reference layer, or `_matched_selection` in the selection layer? |
| L11-17 | Medium | For the names that the pane window declares to the assistant (`@reference`, DocumentLocator, get_parent, get_edited_document), does the Use-it-to rule (an example that runs in the window) win over PAR-NO-CONSUMER-DOCS in a kernel docstring? |
| L11-20 | Low | Does `@reference(document, path)` throw when a step does not resolve, and does `is_fully_typed_reference(nothing)` answer false, although the code comment calls `nothing` 'not our concern'? |
| L11-24 | Low | Does the string spelling `ref"…"`, which reference-pattern-vocabulary.md chose, take the full word as the naming rules require, or stay as a stated exception? |
| L11-25 | Low | Does PAR-ONE-BASED-INDEXING name the 0-based index of `ref"…"`, which reference-pattern-vocabulary.md step 9 decided, as an exception? |
| L12-1 | Medium | What does the selection walk store for a caret {k} and for a range [i, j] between the documents of a collection? |
| L12-2 | Medium | Which layer copies a range step that a caller passes in: the selection writer, or strip_reference_types for every caller? |
| L12-3 | Medium | What replaces with_selection and @with_selection, which change their argument although with_<stem> means a copy? |
| L12-6 | Low | How does a painter that holds a stored selection value read its path and its live flag? |
| L13-1 | High | Where does a number text that does not parse yet, such as '-' or '1e', live while the person types? |
| L13-3 | Medium | Must 'next hole' search only the document that holds the selection, and may the exported seam child_reference_steps go? |
| L13-5 | Medium | How does a wrapper that holds a CompoundOperation give its way back, and how does a wrapper with state of its own keep its own inversion? |
| L13-6 | Medium | Must a document-rooted write check the type checkpoints of its path and throw on a mismatch? |
| L13-7 | Medium | What does a splice into a plain Vector field do: refuse, or write the field cell after the change? |
| L13-8 | Medium | Does one pair (operation_reference, retarget_operation) register a new path-bearing operation, which changes the meaning of PAR-REGISTER-NEW-OPERATION? |
| L13-9 | Medium | Do the builders get make_ names, and do the builders (0-based) and the editor verbs (1-based) keep two count bases? |
| L13-12 | Low | How does an undo put back 'no selection': may ReplaceSelectionOperation hold nothing? |
| L13-13 | Low | May reroot_reference, an exported name with users in four packages, move from the operation layer to the reference layer? |
| L13-15 | Low | Which names replace operation_travels_unchanged and WrappingOperation, and does naming-rules.md get a second structural exception? |
| L14-2 | Medium | Does CollectedIntentsOperation get a verb-first name, or a second structural exception in naming-rules.md? |
| L14-6 | Low | Does a module with one fragment keep its code in the module file (four kernel modules, two sealed), or does system-anatomy.md drop that rule? |
| L15-4 | Medium | Is sel in scope in a rule body, or do the texts say that a body has only doc and the pattern variables? |
| L15-9 | Low | Do fire_named_gesture_binding, get_applicable_gesture_bindings and @gesture_set stay as supported API although only tests use them? |
| L15-10 | Low | Does Intent.gesture keep a second meaning for a collected intent, or does the pattern get a field of its own? |
| L15-12 | Low | Do the two getters and the layer-17 file get new names, and which ones? |
| L16-1 | Medium | May the sealed cell layer get a primitive that runs a function with no dependency record, so that the reconcilers build a child IoMap outside the list computation? |
| L16-5 | Low | Are the three field names the IoMap contract, or must the readers go through the three accessors? |
| L16-6 | Low | Do the macros that inject a default supertype put the type object into the expansion, instead of a bare name that the calling module must have in scope? |
| L16-8 | Low | Do the two reconcilers get make_ names, and which ones? |
| L17-2 | Medium | What does a template mapper answer for a caret or a range on a collection: nothing, or the same range on the output? |
| L17-8 | Medium | How do code outside the layer and omnet-julia reach the template markers, and what replaces the AtomicWiring test in ReaderDefaults.jl? |
| L17-9 | Medium | Does the pure printer pair stay in the projection contract? |
| L17-11 | Medium | Does a subtree that a printer prints with a context of its own (the fault log, the gesture log, the two inspectors) inherit the clock and the fault store of the editor? |
| L17-15 | Low | Does PAR-NO-WRITE-IN-THUNK get a carve-out for the fresh cells that a nested template walk writes inside the computation of its parent? |
| L17-16 | Low | May `ChildrenContainer.jl`, an empty fragment, be deleted, which removes its line from SEALING.md? |
| L17-17 | Low | Does the children-container seam dispatch on the output node, so that each output domain registers its own container? |
| L17-21 | Low | Which names does the layer take for the file GestureBindings.jl, for withhold_offer, and for the engine word (template or rule)? |
| L18-3 | High | Does Tool take a signature with keywords, or a # @positional: marker for its four positional arguments? |
| L18-4 | High | Does the code tool keep the process-wide swap of stdout and stderr, with a lock and a stated exception to PAR-PER-EDITOR-STATE, or capture each call with a new mechanism that does not touch the process streams? |
| L18-9 | Medium | How does a tool call bound the time that it holds the editor task? |
| L18-10 | Medium | Does execute_julia_code let the pass-through exceptions pass, or turn an interrupt of model code into an answer as a stated exception to PAR-REPORT-NEVER-THROWS? |
| L18-11 | Medium | Which exported calls replace the private reaches into the tool layer from Notebook.jl, Evaluator.jl, SearchScaleMeasurement.jl and the tests? |
| L18-12 | Medium | Who owns the sentence that names the editing verbs: the tool layer, or the layers that define the verbs? |
| L18-13 | Medium | Do the guide roots belong to one ToolSet, or stay a process-wide registry? |
| L18-17 | Low | Does a short String with a line break reach the model as prose, or keep the escaped REPL form? |
| L18-19 | Low | Does read_function_documentation drop type_name, or use it to pick the docstring of one method? |
| L18-22 | Low | Do api_entry_bindings, api_source_name, register_resource!, find_resource, read_value_documentation, SearchTerm and KeywordQuery stay exported? |
| L18-24 | Low | Does a ToolSet keep what a turn builds until the declaration or the model changes, and does the code tool log the length of an answer in place of its text? |
| L18-27 | Low | Does the text of PAR-AI-SAME-GUARANTEES state the exception that D22 accepted? |
| L19-2 | Medium | What read timeout do the adapters set on a stream, and does the `stream_turn` contract promise one? |
| L20-1 | High | What time limit bounds a round, a tool call that waits for the editor, and a stream read, and what does the turn do when a limit runs out? |
| L20-2 | Medium | Can a person cancel an agent turn, and through what: a `cancel` keyword of `run_turn!` with a stop operation in the assistant? |
| L20-4 | Medium | Who registers the default tools of a `ToolSet`, and how do their descriptions follow `declare_api!`? |
| L20-9 | Low | Does `AgentEvent` stay as a supertype, or go? |
| L21-1 | High | Does a feed belong to one editor, and do the session stores of the log and the statistics stay process-wide? |
| L21-5 | Medium | How does code on the editor task apply an operation when the inbox can be full: apply it at once and never post from a drain, or post into a queue of the editor task with no bound? |
| L22-1 | High | Do `insert_elements!` and `delete_elements!` take the index as a keyword, or does code-quality-rules.md section 4 get a new kind of exception for them? |
| L22-3 | Medium | What does a post or a call do after the loop of its editor ended, and may an editor run its loop a second time? |
| L22-4 | Medium | How does code on the editor task post when the inbox can be full (the same question as L21-5)? |
| L22-7 | Medium | When `wait_for_input` throws, which counter counts it, with what limit, and how does the loop pause in place of the wait? |
| L22-12 | Medium | Does `get_frame_clock_time` move into the backend layer, as PAR-BACKEND-SEAM asks, with permission for three sealed files? |
| L22-13 | Medium | Does the read stage get a new name, or become a method of `Base.read!`? |
| L22-14 | Medium | How does an ended editor let go of the wake that it gave to a shared feed store? |
| L22-15 | Medium | Does each editor log under its own logger, or with an identity in the shared log? |
| L22-19 | Low | Does `find_rooted_operation` try the root last, or refuse an edit that no reader carries? |
| L22-22 | Low | Does the selection repair go through an operation, and which one? |
| L22-23 | Low | Where are the zoom keys bound: in a binding set of the backend or screen package, through a backend generic, or with the zoom stepped in the kernel (L07-1)? |
| L22-24 | Low | Which of the ten names stay exported? |
| L22-27 | Low | Which names replace `perf!` and `_zoom_operation` (decide with L02-5, the other name of the counters)? |
| L22-31 | Low | Do the four private names that the tests use become public, or do the tests stop naming them? |
| L23-1 | High | Does `play_live!` drain the feeds, which reverses the recorded design that a scripted timeline must not apply foreign posts, or does L23-5 replace the loop? |
| L23-4 | Medium | Which package declares the timeline entry kinds, and what does `await` mean: a predicate of the editor, or of the document? |
| L23-5 | Medium | Does playback stay in the kernel with its own loop, or become a source of input around `run_editor!`, as `VideoBackend` does, and in which package? |
| L10-13 (part) | Medium | Does PAR-NO-NESTED-CELL keep its `MethodError` for a nested cell, so that the code changes, or does the rule text say that a cell of any type passes through as the cell of the field? |
| L10-21, L17-19, L18-23 (parts) | Low | May `DocumentMacro.jl`, `ProjectionTemplate.jl` and `Documentation.jl` split into new fragment files, and under which names (decide with L06-10)? |
| N-2 | Medium | Does the key vocabulary get `:comma`, so that Ctrl+, can fire, or does the binding take another key? |

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
