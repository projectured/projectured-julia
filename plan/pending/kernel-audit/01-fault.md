# Layer 01 — fault (`source/kernel/fault/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (8 of 8).

## Verdict

The fault layer is cohesive and imports nothing. It holds no process-global mutable state, and no source file changed after the seal of 2026-09-24 (f5140f4b).
The store and the policy are per editor, and that is correct.
Two findings are High. A new fault past the 64-key capacity of the store gets no report on any tier, so a barrier loses it in silence. The store also has no way to detach a target, so each entry into the safe mode leaves one more log attached for the life of the editor.
One drain reports a fault once for each count bucket that it crossed, so one fault can give four identical console blocks.
The design text and the law say that `run_editor!` turns the barriers on, but since 31f71539 `run_editor!` keeps the policy of the editor.
The plan `plan/pending/a-fault-is-easy-to-see-and-stays-small.md` covers only the cut traceback (L01-4). L01-1, L01-3, L01-7 and L01-8 change the same three sealed files that its step D1 asks to open.

## Shape

- Purpose: the record of one fault, the per-editor store that a reactive computation may write, the policy, the barrier around one stage of work, and the report cascade (tiers 3 to 5).
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `FaultModule.jl` | 55 | 🔒 | module head: docstring, 5 export statements, 7 includes |
  | `FaultInterface.jl` | 106 | 🔒 | 5 open seams, declarations only |
  | `FaultDefaults.jl` | 30 | 🔒 | the default method of each seam; the BEL sound |
  | `FaultRecord.jl` | 150 | 🔒 | `FaultRecord`, the key, the format of message and traceback, `make_fault_record` |
  | `FaultStore.jl` | 248 | 🔒 | `FaultStore`, `record_fault!`, `drain_faults!`, targets, wake, consecutive counts |
  | `FaultPolicy.jl` | 50 | 🔒 | `FaultPolicy` (3 switches), `make_strict_fault_policy` |
  | `FaultCascade.jl` | 105 | 🔒 | `report_fault!` and tiers 3 to 5 |
  | `FaultBarrier.jl` | 74 | 🔒 | `run_fault_barrier` |

- Imports: none. Imported by, in the kernel: `OperationModule` (layer 13, extends `is_passthrough_exception`), `AgentModule` (20), `EditorModule` (22, extends `get_fault_store`). Outside the kernel: `FaultViewModule` (extends `append_fault!` and `make_safe_mode_projection`), `ScreenModule`, `ShellModule`, `AssistantModule`, `ProjecturedMcp`. Note outside the layer: [ProjecturedMcp.jl:23](../../../package/ProjecturedMcp/src/ProjecturedMcp.jl#L23) writes `import ProjecturedKernel.FaultModule: record_fault!`, but [Mcp.jl:94](../../../source/adapter/mcp/McpServer.jl#L94) and [Mcp.jl:166](../../../source/adapter/mcp/McpServer.jl#L166) only call it. PAR-QUALIFIED-EXTENSION reserves `import` for a name that the file extends. The guard reads only relative imports, so it does not see this one.
- Public surface: 19 exported names. 12 have a user in code outside the kernel: `append_fault!`, `get_fault_store`, `make_safe_mode_projection`, `is_passthrough_exception`, `FaultRecord`, `make_fault_record`, `FaultStore`, `record_fault!`, `get_fault_records`, `attach_fault_target!`, `FaultPolicy`, `make_strict_fault_policy`. 7 have users only in the kernel: `play_fault_sound!` (only its own default method exists; no backend adds one), `drain_faults!`, `attach_fault_wake!`, `get_consecutive_fault_count`, `reset_consecutive_fault_count!`, `report_fault!`, `run_fault_barrier`. Every name has a user. `omnet-julia` and `inet-julia` use no name of this layer.
- State: `Editor` makes one `FaultStore` and holds one `FaultPolicy` ([Editor.jl:84](../../../source/kernel/editor/Editor.jl#L84)), so the store and the policy are per editor. That is correct for PAR-PER-EDITOR-STATE. The layer holds no mutable global: `_BELL` is an immutable constant, and `_get_fault_sound_stream` reads `Base.stderr` at each call. The store has no lock. Its docstring requires that all writers run on the thread of the editor task. Each writer in the tree runs there: the frame, `run_on_editor_task!` bodies, and the `@async` task of [AssistantTurn.jl:242](../../../source/platform/assistant/AssistantTurn.jl#L242), which runs on the thread of its parent. `capacity` limits `records` and `order`, and `capacity` times the count buckets limits `undrained`. `targets` has no bound (L01-2). Note outside the layer: [FaultDocument.jl:169](../../../source/platform/fault/FaultDocument.jl#L169) holds `_SESSION_FAULT_LOG`, one process-global log. [WindowChrome.jl:226](../../../source/platform/shell/WindowChrome.jl#L226) attaches it to the store of every window editor. Two editors in one process therefore write one log document from two tasks, and each shows the faults of the other. Its comment says "because there is one editor". That breaks PAR-PER-EDITOR-STATE in `ProjecturedFault`, not in this layer.
- Shape notes: the layer has the Module, Interface and Defaults triad. The store repeats the store, drain and wake shape of the feed layer (`attach_fault_wake!` next to `attach_wake_callback!`). It can not be a `Feed`, because the feed layer is layer 21. The drain runs at the top of `run_frame!`, so a driver that steps frames also reports.
- Tests: `test/kernel/fault/`, 4 files, 5 test functions, 61 passes on the baseline (defaults 10, record 3, store 25, report 5, barrier 18). `test/platform/fault/` checks the store through `FaultLog`. The tests cover the key, the capacity count, the count buckets, the wake, a target that throws, the strict policy and the passthrough of an interrupt. No test checks which tier `report_fault!` answers, the nested report, the traceback cut, the dedupe of `attach_fault_target!`, or a report of a dropped fault. One test checks a wrong result as correct (L01-3).

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 2 | 4 |
| Architecture | 0 | 0 | 1 |
| Shape | 0 | 0 | 2 |
| State | 1 | 0 | 0 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 1 | 3 |
| Tests | 0 | 1 | 1 |
| **Total** | **2** | **4** | **12** |

## Findings

### L01-1 A new fault past the capacity of the store gets no report on any tier

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: no code reads `dropped`, and no function clears the store.
- Where: [FaultStore.jl:167](../../../source/kernel/fault/FaultStore.jl#L167) 🔒, [FaultBarrier.jl:60](../../../source/kernel/fault/FaultBarrier.jl#L60) 🔒
- Evidence: when the store holds `capacity` keys (64 by default), `record_fault!` counts a new key and returns:

  ```julia
  if length(store.order) >= store.capacity
      store.dropped += 1
      return nothing
  end
  ```

  The key never enters `undrained`, so the drain never shows it, and the wake does not run. `run_fault_barrier` reports for itself only when `store === nothing` (lines 63-66), so it returns the fallback with no console line and no log line. Only the tests read `dropped` ([FaultStoreTest.jl:45](../../../test/kernel/fault/FaultStoreTest.jl#L45), [:69](../../../test/kernel/fault/FaultStoreTest.jl#L69)). No getter exports it, and no code shows it. No function clears the store (5ec9c35b removed `clear_fault_store!`). Scenario: in a long session the application collects 64 distinct keys (site, origin, exception type); each tool name and each operation type is its own origin. After that, the repair takes back a new operation fault, and no tier reports it. The design plan assumes that the log shows "a count of what it dropped" ([the-editor-survives-a-fault.md:303](../../../plan/done/the-editor-survives-a-fault.md#L303)). No code shows that count. The constructor also takes `FaultStore(capacity = 0)`, and that store drops every fault.
- Rule: PAR-REPORT-NEVER-THROWS ("a barrier never swallows a fault in silence"; "A barrier that catches must record, so no fault is lost").
- Fix: make the drop visible. `drain_faults!` answers the growth of `dropped` since the last drain, and the frame reports it once per count bucket, for example "12 faults dropped, the store is full". Also reject `capacity < 1`, as `FrameMeasurementStore` does.
- Reach: `FaultStore.jl` 🔒, `FaultCascade.jl` 🔒 (a line for the drop), `editor/FaultBarriers.jl` (`report_frame_faults!`), `FaultStoreTest.jl`, `fault.md`.

### L01-2 A fault target stays attached for the life of the store, and each safe-mode entry attaches one more

- Category: State · Severity: High · Confidence: Confirmed
- Where: [FaultStore.jl:81](../../../source/kernel/fault/FaultStore.jl#L81) 🔒, [FaultStore.jl:209](../../../source/kernel/fault/FaultStore.jl#L209) 🔒
- Evidence: the layer has `attach_fault_target!` and no function that detaches a target. [FaultSafeMode.jl:60-66](../../../source/platform/fault/FaultSafeMode.jl#L60) answers `make_safe_mode_projection(store)` with a new `FaultLog` and calls `attach_fault_target!(store, log)` each time. [SafeMode.jl:29](../../../source/kernel/editor/SafeMode.jl#L29) calls it at each entry, and `leave_safe_mode!` ([SafeMode.jl:46-53](../../../source/kernel/editor/SafeMode.jl#L46)) removes nothing. Scenario: a projection fails on 4 frames, the editor enters the safe mode, and the person presses Escape. The projection fails again, and the cycle repeats. Each cycle leaves one more `FaultLog` (up to 50 entries each) in `store.targets`. Nothing shows the old logs, and each later drain writes the cells of all of them. The growth is permanent for the life of the editor.
- Rule: bug (unbounded growth); PAR-STORE-THEN-DRAIN (a store feeds the documents that an editor shows while its loop runs).
- Fix: add `detach_fault_target!(store, target)` and call it when the safe mode ends. Alternatively, keep one safe-mode log for each store in the safe-mode projection above the kernel and do not attach a new one at each entry.
- Reach: `FaultStore.jl` 🔒, `FaultModule.jl` 🔒 (export), `editor/SafeMode.jl`, `source/platform/fault/FaultSafeMode.jl`, `FaultStoreTest.jl`, `FaultSafeModeTest.jl`.

### L01-3 One drain hands a record over once for each count bucket that it crossed

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [FaultStore.jl:159-163](../../../source/kernel/fault/FaultStore.jl#L159) 🔒, [FaultStore.jl:203](../../../source/kernel/fault/FaultStore.jl#L203) 🔒
- Evidence: `record_fault!` pushes the key onto `undrained` at count 1, 10, 100 and 1000, also when the key is already in the vector. `drain_faults!` copies `undrained` with no dedupe and emits the same record (with the last count) once per entry. The test expects this result: [FaultStoreTest.jl:79-81](../../../test/kernel/fault/FaultStoreTest.jl#L79) records 3000 faults and expects `length(drain_faults!(store)) == 4` and 4 hand-overs. Scenario: one projection bug fails at 3000 nodes in one print. This is the case that the design names. The next frame calls `report_fault!` four times for one record ([FaultBarriers.jl:34-37](../../../source/kernel/editor/FaultBarriers.jl#L34)). The console then shows four identical `[fault]` blocks with `count = 3000`, and the drain writes the log cells four times. The docstring of `append_fault!` says "once per new record, per target".
- Rule: bug; the contract in [FaultInterface.jl:11-12](../../../source/kernel/fault/FaultInterface.jl#L11) 🔒.
- Fix: in `record_fault!`, do not push a key that `undrained` already holds (the count in `records` is already the latest), or `unique!` the copy in `drain_faults!`. Change the test to expect one hand-over.
- Reach: `FaultStore.jl` 🔒, `FaultStoreTest.jl`. The plan does not cover it; its step D1 opens the same file.

### L01-4 The first report of a fault keeps 12 lines, and the console logger cuts it again

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [FaultRecord.jl:96-106](../../../source/kernel/fault/FaultRecord.jl#L96) 🔒, [FaultCascade.jl:76-79](../../../source/kernel/fault/FaultCascade.jl#L76) 🔒
- Evidence: `_format_fault_traceback` keeps the first 12 lines of `showerror(io, exception, traceback)`. Those lines start with the message, so a long message (a `MethodError` with its list of candidates) leaves no stack frame. `_report_on_console` passes the text as the keyword value `traceback = record.traceback`, and the console logger cuts a long keyword value again ("⋯ 630 bytes ⋯" in take 7). The message is also cut at 400 characters ([FaultRecord.jl:77](../../../source/kernel/fault/FaultRecord.jl#L77)).
- Rule: bug (a first report that a person can not read in full); problem P6 of the plan.
- Fix: step D1 of the plan: keep the whole text for a new key and print it once as part of the message.
- Reach: `FaultRecord.jl` 🔒, `FaultStore.jl` 🔒, `FaultCascade.jl` 🔒, tests.
- Planned: plan/pending/a-fault-is-easy-to-see-and-stays-small.md (P6, D1).

### L01-5 The design text and the law say that run_editor! turns the barriers on, and the code does not

- Category: Documentation · Severity: Medium · Confidence: Confirmed
- Where: [fault.md:31-35](../../../documentation/package/platform/fault/fault.md#L31), [architecture-invariants.md:970-973](../../../documentation/rule/architecture-invariants.md#L970), [Editor.jl:35-37](../../../source/kernel/editor/Editor.jl#L35), [FaultBarriers.jl:7-8](../../../source/kernel/editor/FaultBarriers.jl#L7)
- Evidence: fault.md says "`run_editor!` defaults to `FaultPolicy()`" and shows `run_editor!(editor)  # barriers on`. The law says "`run_editor!` is what turns the barriers on, because every test in the tree builds an `Editor` directly and none of them calls `run_editor!`". Since 31f71539 (2026-09-23), `run_editor!` takes `fault_policy::FaultPolicy=editor.fault_policy` ([EditorLoop.jl:137](../../../source/kernel/editor/EditorLoop.jl#L137)). So `run_editor!(Editor(…))` runs with every barrier off, and `make_editor` is what turns them on (`fault_policy = FaultPolicy()`, [EditorLoop.jl:211](../../../source/kernel/editor/EditorLoop.jl#L211); [WindowScene.jl:134](../../../source/platform/screen/WindowScene.jl#L134)). Tests do call `run_editor!` ([InboxTest.jl:132](../../../test/kernel/editor/InboxTest.jl#L132), [WaitTest.jl:153](../../../test/kernel/editor/WaitTest.jl#L153)). Tests also reach `make_editor` with its default, so their barriers are on ([WaitTest.jl:147](../../../test/kernel/editor/WaitTest.jl#L147), [ApplicationTest.jl:445](../../../test/projectured/editor/ApplicationTest.jl#L445)). That is against the second half of PAR-REPORT-NEVER-THROWS ("must default to catching nothing wherever a test can reach it"). The sealed files of this layer say only "an editor that a test makes has it false", which stays true.
- Rule: PAR-HONEST-DOCS, PAR-UPDATE-THE-GUIDE; PAR-REPORT-NEVER-THROWS (second half).
- Fix: correct the four texts to say that `make_editor` turns the barriers on and `run_editor!` keeps the policy of the editor. The owner must decide whether the tests that use `make_editor` must pass the strict policy.
- Reach: `fault.md`, `architecture-invariants.md`, `editor/Editor.jl`, `editor/FaultBarriers.jl`. No sealed file; optionally `WaitTest.jl` and `ApplicationTest.jl`.

### L01-6 No test checks which tier report_fault! answers

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [FaultStoreTest.jl:136-156](../../../test/kernel/fault/FaultStoreTest.jl#L136), for [FaultCascade.jl:42-61](../../../source/kernel/fault/FaultCascade.jl#L42) 🔒
- Evidence: the only test of the cascade checks `:swallowed` twice, `isa Symbol` once, and `store.depth == 0`. No test checks `:console` with the console on, `:sound` with the console off, the extra sound for a `:device` record, or the nested call (`depth > 1`). A change that stops the sound tier, or that answers `:swallowed` where the console worked, passes every test.
- Rule: PAR-NEW-CODE-SHIPS-TESTS; PAR-REPORT-NEVER-THROWS ("Tests assert both").
- Fix: one test set per tier. Use a test logger (`Test.TestLogger`) for the console and a backend that counts its sounds.
- Reach: tests only (a new `FaultCascadeTest.jl`, see L01-18).

### L01-7 A store that throws makes report_fault! skip the console tier

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [FaultCascade.jl:44](../../../source/kernel/fault/FaultCascade.jl#L44) 🔒
- Evidence: `_enter_fault_report!(store)` is the first call in the outer `try`. A store that throws there jumps to the outer `catch`, which answers `:swallowed`. The console tier is not tried, also when it works. The test checks this result as correct: [FaultStoreTest.jl:145-146](../../../test/kernel/fault/FaultStoreTest.jl#L145) passes `AngryStore()` with `FaultPolicy()`, where the console is on, and expects `:swallowed`. No real caller passes such a store today (the frame passes a `FaultStore`).
- Rule: PAR-REPORT-NEVER-THROWS ("It reports at the first tier that works").
- Fix: guard `_enter_fault_report!` in its own `try`, count a failure as depth 1, and go on to the console. Expect `:console` in the test.
- Reach: `FaultCascade.jl` 🔒, `FaultStoreTest.jl`.

### L01-8 The report path catches the exceptions that mean stop

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [FaultCascade.jl:57](../../../source/kernel/fault/FaultCascade.jl#L57) 🔒, [FaultStore.jl:106-109](../../../source/kernel/fault/FaultStore.jl#L106) 🔒, [FaultStore.jl:212](../../../source/kernel/fault/FaultStore.jl#L212) 🔒, [FaultRecord.jl:78-82](../../../source/kernel/fault/FaultRecord.jl#L78) 🔒, [FaultRecord.jl:98-102](../../../source/kernel/fault/FaultRecord.jl#L98) 🔒
- Evidence: these arms catch every exception and never ask `is_passthrough_exception`. An `InterruptException` that arrives while the frame writes a console line, runs a target or formats a message is caught, and the loop goes on. The same section of the law says: "An exception that means the program is to stop or can not go on is never caught" ([architecture-invariants.md:977](../../../documentation/rule/architecture-invariants.md#L977)). The two sentences of PAR-REPORT-NEVER-THROWS conflict here, and the code follows "never throws".
- Rule: PAR-REPORT-NEVER-THROWS (the passthrough paragraph).
- Fix: the owner decides which sentence wins. To follow the passthrough rule, add `is_passthrough_exception(exception) && rethrow()` to each arm. Otherwise, state the exception in the law.
- Reach: `FaultCascade.jl` 🔒, `FaultStore.jl` 🔒, `FaultRecord.jl` 🔒, or `architecture-invariants.md`.

### L01-9 An origin that is a Union type makes the barrier throw a MethodError

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [FaultRecord.jl:141](../../../source/kernel/fault/FaultRecord.jl#L141) 🔒, [FaultBarrier.jl:59-64](../../../source/kernel/fault/FaultBarrier.jl#L59) 🔒
- Evidence: `_get_fault_origin_name(origin::Type) = nameof(origin)`. For a type, Julia 1.13 defines `nameof` only on `DataType` and `UnionAll` (`base/runtime_internals.jl:431-432`), so `origin = Union{A, B}` or `Union{}` raises a `MethodError`. `record_fault!` and `make_fault_record` run in the `catch` arm of `run_fault_barrier` with no guard, so this new error leaves the barrier in place of the fallback. Today every caller passes `typeof(x)`, an object or a `Symbol`, so no caller hits it.
- Rule: bug; the docstring of `record_fault!` says that it is safe to call from inside a computation.
- Fix: `_get_fault_origin_name(origin::Type) = origin isa DataType || origin isa UnionAll ? nameof(origin) : Symbol(string(origin))`.
- Reach: `FaultRecord.jl` 🔒.

### L01-10 The drain writes a target failure to the console whatever the policy says

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [FaultCascade.jl:98-105](../../../source/kernel/fault/FaultCascade.jl#L98) 🔒, [FaultStore.jl:201](../../../source/kernel/fault/FaultStore.jl#L201) 🔒
- Evidence: `drain_faults!(store)` takes no policy, so `_log_fault_report_failure` always calls `@error`. A policy with `is_console_enabled = false` does not stop the line. The baseline log of `test_kernel()` shows the line ("[fault] a fault target refused a record", in the baseline run of `test_kernel()`) from [FaultStoreTest.jl:96-104](../../../test/kernel/fault/FaultStoreTest.jl#L96).
- Rule: the contract of `FaultPolicy.is_console_enabled` ([FaultPolicy.jl:14](../../../source/kernel/fault/FaultPolicy.jl#L14) 🔒).
- Fix: give `drain_faults!` a `policy` keyword, or return the failures to the caller, which then reports them under its policy.
- Reach: `FaultStore.jl` 🔒, `FaultCascade.jl` 🔒, `editor/FaultBarriers.jl`, `FaultStoreTest.jl`.

### L01-11 The export block of FaultModule does not follow the rule of one statement for each fragment

- Category: Architecture · Severity: Low · Confidence: Confirmed
- Where: [FaultModule.jl:41-45](../../../source/kernel/fault/FaultModule.jl#L41) 🔒
- Evidence: the statement for `FaultStore.jl` lists `record_fault!` and `drain_faults!` before `get_fault_records`, `attach_fault_target!` and `attach_fault_wake!`, which the fragment defines first. The last statement names two fragments (`report_fault!` from `FaultCascade.jl`, `run_fault_barrier` from `FaultBarrier.jl`). [exports.jl:57](../../../test/suite/exports.jl#L57) lists the file in `EXPORT_UNMIGRATED`.
- Rule: code-quality-rules.md §1 (the export block).
- Fix: reorder the store statement and split the last one.
- Reach: `FaultModule.jl` 🔒, `test/suite/exports.jl`.
- Planned: plan/pending/export-block-rule.md (line 78: 2 violations, sealed).

### L01-12 The safe-mode seam sits in layer 1, but only the editor layer calls it and it answers a projection

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [FaultInterface.jl:65-84](../../../source/kernel/fault/FaultInterface.jl#L65) 🔒, [FaultDefaults.jl:22](../../../source/kernel/fault/FaultDefaults.jl#L22) 🔒
- Evidence: `make_safe_mode_projection(store)` is the one seam of the layer that the layer never calls. Its only caller is `enter_safe_mode!` in the editor layer ([SafeMode.jl:29-30](../../../source/kernel/editor/SafeMode.jl#L29)), which checks `projection isa Projection`, a concept of layer 17. "Safe mode" is a concept of the editor layer too. This layer calls the other four seams (`append_fault!` by the drain, `play_fault_sound!` by the cascade, `is_passthrough_exception` by the barrier, `get_fault_store` names only the store).
- Rule: PAR-NO-CONSUMER-DOCS ("Prefer redistributing the seam to the lowest layer where every concept it names is already introduced"); architecture-rules.md (a thing lives in the layer that uses it).
- Fix: declare the seam in the editor layer next to `enter_safe_mode!`, and let `FaultViewModule` extend `EditorModule.make_safe_mode_projection`.
- Reach: `FaultInterface.jl` 🔒, `FaultDefaults.jl` 🔒, `FaultModule.jl` 🔒, `editor/SafeMode.jl`, `editor/EditorModule.jl`, `source/platform/fault/FaultSafeMode.jl`, `FaultDefaultsTest.jl`, `fault.md`.

### L01-13 Two paths of the cascade have no caller outside the tests

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [FaultCascade.jl:63](../../../source/kernel/fault/FaultCascade.jl#L63) 🔒, [FaultCascade.jl:46](../../../source/kernel/fault/FaultCascade.jl#L46) 🔒
- Evidence: `report_fault!(store, ::Nothing; …)` has one caller, [FaultStoreTest.jl:151](../../../test/kernel/fault/FaultStoreTest.jl#L151). The frame passes drained records ([FaultBarriers.jl:35](../../../source/kernel/editor/FaultBarriers.jl#L35)), and the barrier passes the record that it made on the line before ([FaultBarrier.jl:64-65](../../../source/kernel/fault/FaultBarrier.jl#L64)). The `depth > 1` arm runs only when `report_fault!` calls itself again through the logger or the backend. No code does that, and no test covers it.
- Rule: code-quality-rules.md (dead code); the Shape category.
- Fix: remove the `::Nothing` method, or keep it and name the case that needs it. Cover the nested arm with a test (L01-6) or remove the depth.
- Reach: `FaultCascade.jl` 🔒, `FaultStore.jl` 🔒 (the `depth` field), `FaultStoreTest.jl`.

### L01-14 run_fault_barrier changes the store and its name has no `!`

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [FaultBarrier.jl:48](../../../source/kernel/fault/FaultBarrier.jl#L48) 🔒
- Evidence: the function resets the count ([:54](../../../source/kernel/fault/FaultBarrier.jl#L54)), adds to it ([:59](../../../source/kernel/fault/FaultBarrier.jl#L59)) and records a fault ([:60](../../../source/kernel/fault/FaultBarrier.jl#L60)) in the store that it gets. Its siblings `run_editor!`, `run_frame!` and `run_on_editor_task!` carry the `!`. The plan that chose the name compared only `run_` with `with_` ([the-editor-survives-a-fault.md:810](../../../plan/done/the-editor-survives-a-fault.md#L810)).
- Rule: naming-rules.md ("Mutating functions end with `!`").
- Fix: rename to `run_fault_barrier!` with `workspace/bin/julia-rename.jl`, then update the prose. The accepted exception for seven keywords follows the new name.
- Reach: `FaultBarrier.jl` 🔒, `FaultModule.jl` 🔒, `editor/FaultBarriers.jl`, `FaultBarrierTest.jl`, `fault.md`, `system-anatomy.md`, `architecture.md`.

### L01-15 The layer says "thunk", where the cell layer says "computation"

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [FaultStore.jl:11-23](../../../source/kernel/fault/FaultStore.jl#L11) 🔒 (5 lines), [FaultStore.jl:101](../../../source/kernel/fault/FaultStore.jl#L101) 🔒, [FaultStore.jl:131](../../../source/kernel/fault/FaultStore.jl#L131) 🔒, [FaultInterface.jl:13](../../../source/kernel/fault/FaultInterface.jl#L13) 🔒
- Evidence: commit 22b3ded0 (2026-09-24 18:09) made "computation" the one word of the cell layer. `source/kernel/cell/` and `cell.md` now hold no "thunk". The owner sealed this layer at 14:20 the same day. The layer still uses the word 9 times on 8 lines. The law also uses both words: the index row of PAR-NO-WRITE-IN-THUNK ([architecture-invariants.md:67](../../../documentation/rule/architecture-invariants.md#L67)) says "A thunk must never write", and its section says "A computation must never write".
- Rule: writing-rules.md ("Use one word for one thing").
- Fix: replace "thunk" with "computation" in the docstrings and comments. The rule ID `PAR-NO-WRITE-IN-THUNK` stays, because an ID is permanent.
- Reach: `FaultStore.jl` 🔒, `FaultInterface.jl` 🔒; outside the layer `editor/Editor.jl`, `editor/EditorLoop.jl`, `editor/Inbox.jl`, `editor/FaultBarriers.jl`, `architecture-invariants.md`.

### L01-16 Docstrings and comments name callers above the layer, and the include comments repeat the docstring

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [FaultStore.jl:22-24](../../../source/kernel/fault/FaultStore.jl#L22) 🔒, [FaultBarrier.jl:11-13](../../../source/kernel/fault/FaultBarrier.jl#L11) 🔒, [FaultCascade.jl:4-15](../../../source/kernel/fault/FaultCascade.jl#L4) 🔒, [FaultModule.jl:47-53](../../../source/kernel/fault/FaultModule.jl#L47) 🔒
- Evidence: "The editor loop then calls `drain_faults!` once per frame" names a caller. "It is not what a projection uses — a projection must answer a substitute document and so carries its own catch, and calls `record_fault!` directly" explains the code of a higher layer. The cascade header names "the barrier projection, above" and what it "already did". These files are not seam files, so the carve-out for seams does not apply. The seven include comments of `FaultModule.jl` repeat the fragment list of the docstring at lines 22-34. `CellModule.jl`, the model that code-quality-rules.md names, has no include comments.
- Rule: PAR-NO-CONSUMER-DOCS; PAR-TIGHT-COMMENTS ("Two comments saying the same thing … is one comment too many").
- Fix: state the contract for any caller ("Call it once per frame, outside every computation"), and remove the include comments.
- Reach: `FaultStore.jl` 🔒, `FaultBarrier.jl` 🔒, `FaultCascade.jl` 🔒, `FaultModule.jl` 🔒.

### L01-17 Three texts of the law and the kernel guide describe this layer inexactly

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [architecture-invariants.md:221-235](../../../documentation/rule/architecture-invariants.md#L221), [architecture-invariants.md:956-958](../../../documentation/rule/architecture-invariants.md#L956), [architecture.md:160-181](../../../documentation/package/kernel/architecture.md#L160)
- Evidence: the carve-out of PAR-NO-WRITE-IN-THUNK names the fault store as its case and requires that "its write is **idempotent**". `record_fault!` adds one to the count at each run ([FaultStore.jl:151-154](../../../source/kernel/fault/FaultStore.jl#L151) 🔒), and the count reaches the log through the drain. PAR-PURE-THUNK forbids "a counter that grows on every run". The cached values stay correct, because no computation reads the store. So the property that makes the store safe is "keyed, and no computation reads it", not idempotence. PAR-REPORT-NEVER-THROWS stands under the title "Package, layer, slice, and module structure". The index lists it under "Editor, devices, and backends" (line 143). The folder table of `architecture.md` has no row for `fault/`, but its layer list (line 36) names it.
- Rule: PAR-HONEST-DOCS.
- Fix: reword the carve-out, move the section under the title that the index gives it, and add the `fault/` row.
- Reach: `architecture-invariants.md`, `architecture.md`. No sealed file.

### L01-18 The cascade test lives in the store test file, and the tests write real error blocks into the log

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: [FaultStoreTest.jl:136-156](../../../test/kernel/fault/FaultStoreTest.jl#L136), [FaultStoreTest.jl:147](../../../test/kernel/fault/FaultStoreTest.jl#L147)
- Evidence: `test_fault_report` tests `FaultCascade.jl`, but it sits in `FaultStoreTest.jl`. Lines 50, 51, 57, 58, 77, 107 and 131 of that file are 92 to 102 characters long. Line 147 runs the console tier with `FaultPolicy()`. The baseline log therefore holds an `Error: [fault] device in AngryBackend` block (lines 53-57) beside the block of L01-10. A person who reads a test log must step over it.
- Rule: naming-rules.md ("A test is named for the file it tests"); code-quality-rules.md §5 (90 characters).
- Fix: move `test_fault_report` to `FaultCascadeTest.jl`, wrap the long lines, and send the console tier to a test logger.
- Reach: tests only, and `ProjecturedKernelTest.jl` (the include list).

## Accepted before, not raised again

- `run_fault_barrier` takes seven keyword arguments. The owner accepted it on 2026-09-24 (seal commits d4fc522c and f5140f4b).
- The limits of the breakers live in the editor layer, and `FaultPolicy` keeps three switches. `format_fault_message` is private (plan/done/fault-policy-limits.md).
- The store is outside the reactive graph and is the named carve-out of PAR-NO-WRITE-IN-THUNK and PAR-PURE-THUNK. The key holds no reference and no message. The layer is at position 1. The barrier projection is opt-in. The names `FaultStore`, `play_fault_sound!`, `run_fault_barrier` (not `with_fault_barrier`) and `FaultCascade.jl` are the choices of plan/done/the-editor-survives-a-fault.md. L01-14 raises only the `!`, which that plan did not discuss.
- The `Any` fields `FaultRecord.first_reference`, `FaultStore.targets` and `FaultStore.wake`: the layer can not name a reference, a log or an editor, because each is above it.

## Checked and clean

- Seal: no file of `source/kernel/fault/` changed after f5140f4b. The last source change is 313186d9, the commit before the seal.
- PAR-INTERFACE-DECLARES-ONLY: `FaultInterface.jl` holds only docstrings and `function f end`, and the module exports all 5 names.
- PAR-MODULE-BOUNDARY-IS-API and PAR-QUALIFIED-EXTENSION inside the kernel: the layer imports nothing. Code above imports each name that it extends (`FaultViewModule`) or qualifies it (`Operations.jl:74`, `ReadEvaluatePrint.jl:143`, `FaultSafeMode.jl:60`).
- PAR-PER-EDITOR-STATE: one store and one policy per editor; no mutable global in the layer.
- PAR-NO-WRITE-IN-THUNK: `record_fault!` writes no cell. Only the drain writes cells, on the editor task.
- PAR-STORE-THEN-DRAIN: the drain runs at the top of `run_frame!`, before `read!`.
- PAR-REPORT-NEVER-THROWS, first half: `report_fault!` has an outer `catch`, and the drain survives a target that throws. See L01-7 and L01-8 for the edges.
- PAR-MODULE-DOCSTRING and the fragment headers: the module file opens with a docstring, and each fragment opens with a comment that names `FaultModule`.
- History comments: none (the grep of code-quality-rules.md §2 finds no history word).
- PAR-CITE-EXCEPTIONS-ONLY: the three citations mark the carve-out and an empty `catch`.
- Code-quality §4: no definition takes more than three positional arguments; no `Bool` is positional in a written signature.
- Size: every file is under 500 lines, and no source line is over 90 characters.
- Naming: every exported function starts with a verb; no banned abbreviation; the file names follow `<Concept>Module.jl`, `…Interface.jl`, `…Defaults.jl`.
- 1-based indexes: `order`, `undrained` and the line cut of the traceback use `1:maximum_lines`, which is correct. The message cut counts characters, not bytes (tested).
