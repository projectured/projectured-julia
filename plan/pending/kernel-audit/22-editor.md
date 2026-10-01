# Layer 22 — editor (`source/kernel/editor/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 9 files).

## Verdict

The layer keeps all mutable state on the `Editor`, and its module-level values are constants, so the layer itself keeps PAR-PER-EDITOR-STATE.
The weak part is the edge of the loop: the inbox, the wait and the fault paths.
A click that the recognizer holds can wait for unrelated input, and the inbox stays open after the loop ends.
The calls between two frames run outside every barrier, three repair blocks catch every exception with no record, and no test drives the fault paths.
`insert_elements!` and `delete_elements!` break the rule that `test_arguments()` guards.
Three texts, the law among them, still say that `run_editor!` turns the barriers on; `make_editor` does.

## Shape

- Purpose: the read-eval-print loop of one editor. It holds the `Editor`, the inbox and the feeds that move data in, one frame (report faults, read, evaluate, print), the wait between frames, the fault barriers, the safe mode, and the verbs that edit a collection through the readers.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `EditorModule.jl` | 50 | ⬜ | docstring, 18 `using`, 1 `import`, one export statement, 8 includes |
  | `Editor.jl` | 121 | ⬜ | `Editor`, its constructor, `invalidate_projection!`, `get_parent` and `find_referenced_document` for an editor |
  | `Inbox.jl` | 136 | ⬜ | `post_operation!`, `wake_editor!`, `drain_operations!`, `RunFunctionOperation`, `run_on_editor_task!`, `_answer_waiting_calls!` |
  | `Feeds.jl` | 85 | ⬜ | `InboxFeed`, `FRAME_INTERVAL`, `compute_wait_timeout`, `record_frame_performance!`, `drain_feeds!` |
  | `ReadEvaluatePrint.jl` | 143 | ⬜ | `read!`, `read_rooted_operation`, the Escape and zoom keys, `get_fault_store` |
  | `DocumentEdits.jl` | 95 | ⬜ | `find_rooted_operation`, `insert_elements!`, `delete_elements!` |
  | `SafeMode.jl` | 59 | ⬜ | `is_editor_in_safe_mode`, `enter_safe_mode!`, `leave_safe_mode!` |
  | `FaultBarriers.jl` | 193 | ⬜ | `_run_barrier`, `report_frame_faults!`, the limits, `is_editor_degraded`, the repairs, `evaluate!`, `print!` |
  | `EditorLoop.jl` | 290 | ⬜ | `perf!`, `run_frame!`, `get_frame_clock_time`, the two `run_editor!` methods, `make_editor` |

- Imports: 18 of the 21 lower layers (all except struct, binding and llm). It extends `drain_changes!` by `import`, and six generics by qualification: `evaluate_operation`, `invalidate_projection!`, `run_on_editor_task!`, `get_fault_store`, `get_parent`, `find_referenced_document`. The layer has no interface file; it declares one seam of its own, `get_frame_clock_time` (L22-12).
- Imported by: `PlaybackModule` in the kernel; `ProjecturedScreen`, `ProjecturedPane`, `ProjecturedShell`, `ProjecturedTooltip` (module alias); `ProjecturedVideo` (`import … get_frame_clock_time`); `ProjecturedFaultTest`; the umbrella re-export; omnet-julia (`OmnetSimulator`, `OmnetPresentation`: `post_operation!`) and inet-julia examples.
- Public surface: 23 exported names.
  - 13 have users outside the kernel: `Editor`, `make_editor`, `run_editor!`, `read_rooted_operation`, `evaluate!`, `print!`, `run_frame!`, `find_rooted_operation`, `insert_elements!`, `delete_elements!`, `get_frame_clock_time`, `post_operation!`, `drain_operations!`.
  - 6 have users only in tests: `read!` (and `PlaybackModule`), `get_consecutive_fault_limit`, `is_editor_in_safe_mode`, `InboxFeed`, `wake_editor!`, `drain_feeds!`.
  - 4 have no user outside the layer: `is_editor_degraded`, `enter_safe_mode!`, `leave_safe_mode!`, `report_frame_faults!`.
- State: per editor, in `Editor`: the backend, document, projection, devices, clock, tool set, inbox, IoMap, last operation, recognizer, fault store, fault policy, the projection that the safe mode put aside, feeds, `wake_pending`, frame measurements and `loop_task`. Module level: four constants (`INBOX_CAPACITY = 64`, `FRAME_INTERVAL = 0.01`, `MAX_OPERATIONS_PER_FRAME = 32`, `_CONSECUTIVE_FAULT_LIMITS`) and the sentinel `_BARRIER_FAILED`; no mutable global. Across tasks: `wake_pending` is atomic, `inbox` is a `Channel`, and `loop_task` is a plain field that other tasks read. The layer writes to the process logger (`@info`, `@warn`).
- Tests: `test/kernel/editor/` holds 9 files (1293 lines). Four test this layer: `EscapeQuitTest`, `InboxTest`, `FrameDrainTest`, `WaitTest` (11, 28, 11 and 20 checks pass in the baseline). Five are generic drivers (`PrinterTest`, `ReaderTest`, `ReplTest`, `NavigationTest`, `ConstructTest`). `test/kernel/editor/FeedsTest.jl` tests `drain_feeds!` and the wake (16). The safe mode is tested in `test/platform/fault/FaultSafeModeTest.jl` (ProjecturedFaultTest), the verbs in `test/projectured/editor/ReferencedDocumentEditorTest.jl` (umbrella). No test drives the operation barrier and its repairs, the read barrier, the two device breakers, the drain barrier, the calls that the end of the loop answers, or the zoom keys.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 9 | 4 |
| Architecture | 0 | 3 | 1 |
| Shape | 1 | 0 | 4 |
| State | 0 | 2 | 0 |
| Types/performance | 0 | 1 | 0 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 3 |
| Tests | 0 | 1 | 1 |

## Findings

### L22-1 `insert_elements!` and `delete_elements!` take four positional arguments, and the argument guard reports them

- Category: Shape · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: A run of the argument guard: it reports `DocumentEdits.jl:56 insert_elements!` and `DocumentEdits.jl:77 delete_elements!`. The guard failure is confirmed.
- Where: [DocumentEdits.jl:73](../../../source/kernel/editor/DocumentEdits.jl#L73) ⬜, [DocumentEdits.jl:93](../../../source/kernel/editor/DocumentEdits.jl#L93) ⬜
- Evidence: `insert_elements!(editor::Editor, collection, index::Integer, values) =` and `delete_elements!(editor::Editor, collection, index::Integer, count::Integer = 1) =`. No `# @positional:` marker stands above either. `test/suite/arguments.jl` scans `source/`, finds a one-line definition inside a docstring, and reports a public definition with more than three positional arguments. Neither signature is one of the four kinds that code-quality-rules.md §4 excuses.
- Rule: code-quality-rules.md §4, "A function takes at most three positional arguments"; the guard is `test_arguments()`.
- Fix: name the fourth argument, for example `insert_elements!(editor, collection, values; index)` and `delete_elements!(editor, collection; index, count = 1)`. The owner approved the present shape in D24 of `plan/pending/the-assistant-reaches-a-referenced-document.md`, so the owner chooses between a new signature and a new kind of exception in §4.
- Reach: `DocumentEdits.jl`; the tool text in `source/kernel/tool/DefaultTools.jl:32-33`; `source/platform/application/Application.jl`; `documentation/guide/orientation.md`; `test/projectured/editor/ReferencedDocumentEditorTest.jl`; `test/kernel/tool/DeclaredApiTest.jl`.

### L22-2 A click that the recognizer holds waits for unrelated input after a frame ends early

- Category: Correctness · Severity: Medium · Confidence: Confirmed by the code; the delay was not measured.
- Where: [EditorLoop.jl:70-82](../../../source/kernel/editor/EditorLoop.jl#L70) ⬜, [EditorLoop.jl:165-167](../../../source/kernel/editor/EditorLoop.jl#L165) ⬜, [Feeds.jl:35](../../../source/kernel/editor/Feeds.jl#L35) ⬜
- Evidence: `recognize_gesture!` answers a `MouseUp` and puts its `MousePress` into `recognizer.pending` (`source/kernel/gesture/GestureRecognizer.jl:107`). `run_frame!` stops its reads on three conditions: the read barrier answers `false` because a reader threw, `editor.iomap === nothing && break`, and `MAX_OPERATIONS_PER_FRAME`. When the `MouseUp` is the last read of such a frame, the `MousePress` stays in the recognizer. The next turn of the loop then waits: `compute_wait_timeout` looks at the clock and the feeds, and `wait_for_input` looks at the backend queue, but nothing looks at the recognizer. With no animation and no feed deadline the timeout is `Inf`.
- Scenario: a reader throws on a `MouseUp` (the case P4 of the fault plan). The frame breaks, and the click of that press is read only when the pointer moves again, against a newer state.
- Rule: bug; the comment at EditorLoop.jl:34 says "whatever is left waits for the next frame".
- Fix: when the read loop of `run_frame!` ends for a reason other than "no input", set `editor.wake_pending`, so that the next turn skips the wait.
- Reach: `EditorLoop.jl`.

### L22-3 The inbox stays open after the loop ends, so a later post is lost and a caller that waits does not return

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the lost post; the race on `loop_task` is Suspected (needs a run with a caller on another thread or a full inbox).
- Where: [Inbox.jl:106-117](../../../source/kernel/editor/Inbox.jl#L106) ⬜, [Inbox.jl:123-136](../../../source/kernel/editor/Inbox.jl#L123) ⬜, [EditorLoop.jl:191-196](../../../source/kernel/editor/EditorLoop.jl#L191) ⬜
- Evidence:
  1. `_answer_waiting_calls!` drops every operation that is not a `RunFunctionOperation`. A producer that waits for its operation does not learn it. omnet-julia `sync_watch!` does `post_operation!(editor, SyncSimulationOperation(w, done)); wait(done)` (`omnet-julia/source/presentation/workbench/Watch.jl:323`), and that task waits for ever when the loop ends first.
  2. The loop does not close the inbox. A later `post_operation!` is never applied, and after 64 posts `put!` blocks for ever.
  3. `run_on_editor_task!` reads `editor.loop_task`, a plain field, and then posts. If the loop ends between the read and the `put!`, the call lands after `_answer_waiting_calls!`, and `take!(answer)` waits for ever. A full inbox or a caller on another thread opens that window.
- Rule: bug; PAR-STORE-THEN-DRAIN says a posted operation is "applied exactly once".
- Fix: close `editor.inbox` in the `finally` of `run_editor!`, before `_answer_waiting_calls!`. Let `post_operation!` throw on a closed inbox, and let `run_on_editor_task!` run the call on its own task when the inbox is closed.
- Reach: `Inbox.jl`, `EditorLoop.jl`; producers in omnet-julia and inet-julia get an exception in place of a hang.

### L22-4 A post from the editor task into a full inbox blocks the one task that drains it

- Category: Correctness · Severity: Medium · Confidence: Suspected (needs 64 posts from other tasks inside one frame; no current producer does that).
- Where: [Inbox.jl:26-27](../../../source/kernel/editor/Inbox.jl#L26) ⬜
- Evidence: `post_operation!` is `put!(editor.inbox, operation)` on a channel of 64. Code on the editor task posts too: `post_pane_operation!` (`source/platform/pane/PaneProgram.jl:839`; its docstring: "Code that runs while the editor evaluates another operation … uses it") and the drain of the tooltip feed (`source/tooltip/TooltipRest.jl:99`). When producers on other threads fill the inbox during a frame, such a post blocks the editor task, and no task drains the inbox again. The editor hangs.
- Rule: bug; the feed contract says "A feed must not block".
- Fix: when `current_task() === editor.loop_task`, put the operation into a queue of the editor with no bound, which the next drain takes first. Other tasks keep the backpressure.
- Reach: `Inbox.jl`.

### L22-5 A producer that posts as fast as the editor applies can hold off the paint and the other tasks of the thread

- Category: Correctness · Severity: Medium · Confidence: Suspected (needs a run with a producer on another thread).
- Where: [Inbox.jl:64](../../../source/kernel/editor/Inbox.jl#L64) ⬜, [EditorLoop.jl:165-171](../../../source/kernel/editor/EditorLoop.jl#L165) ⬜
- Evidence: `drain_operations!` loops `while isready(editor.inbox)` with no bound. The read loop has a bound, `MAX_OPERATIONS_PER_FRAME`, for this same reason (EditorLoop.jl:30-35). A producer on another thread that puts a new operation before each `isready` keeps the drain in one frame, and `print!` does not run. Also, the loop skips `wait_for_input` while `wake_pending` is set, and a frame has no `yield`. When each frame gets a wake, the cooperative tasks of the editor thread (the MCP server, an assistant turn) get no turn. EditorLoop.jl:119-121 says that the wait is where they get it.
- Rule: bug.
- Fix: drain at most the operations that were in the inbox when the drain started, and set `wake_pending` when some are left. Call `yield()` once in a frame when the wait was skipped.
- Reach: `Inbox.jl`, `EditorLoop.jl`.

### L22-6 A posted operation that fails gets no repair, and a feed that throws stops the feeds after it

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [EditorLoop.jl:179-181](../../../source/kernel/editor/EditorLoop.jl#L179) ⬜, [Inbox.jl:62-69](../../../source/kernel/editor/Inbox.jl#L62) ⬜, [Feeds.jl:79-85](../../../source/kernel/editor/Feeds.jl#L79) ⬜
- Evidence: one `:evaluate` barrier wraps all of `drain_feeds!`. `drain_operations!` calls `evaluate_operation` directly, so a posted operation that fails half way gets none of the three repairs of `evaluate!`: the inverse, the new print and the selection repair. The design table of `plan/done/the-editor-survives-a-fault.md` §3.1 puts the operation barrier on "`evaluate!` and `drain_operations!`". When one feed or one posted operation throws, the barrier leaves `drain_feeds!`. The operations behind it and every later feed wait for the next wake, which can be unrelated input. A feed that throws in every frame stops the feeds after it for good.
- Rule: bug; design §3.1 of `the-editor-survives-a-fault.md`.
- Fix: move the body of `evaluate!` into one function that applies an operation with the barrier and the repairs, and call it for each posted operation. Put one barrier around each `drain_changes!`.
- Reach: `Inbox.jl`, `Feeds.jl`, `FaultBarriers.jl`, `EditorLoop.jl`.

### L22-7 The calls between two frames run outside every barrier, so one throw there ends the editor

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [EditorLoop.jl:166-167](../../../source/kernel/editor/EditorLoop.jl#L166) ⬜, [EditorLoop.jl:176](../../../source/kernel/editor/EditorLoop.jl#L176) ⬜, [Feeds.jl:38](../../../source/kernel/editor/Feeds.jl#L38) ⬜
- Evidence: `compute_wait_timeout` calls `compute_wake_deadline(feed, editor)` of each feed. Then `wait_for_input(editor.backend, …)` runs, and then `set_clock_time!(editor.clock, get_frame_clock_time(editor.backend, …))`. None of these runs in a `_run_barrier`. A throw reaches `e isa QuitEditorException || rethrow()`, and the editor ends and quits its backend. A feed of another package or a backend wait that throws therefore ends the editor. The same fault in `write_to_devices` costs one frame. `the-editor-survives-a-fault.md` §3.1 puts a device barrier on "each `Backend` seam call".
- Rule: bug; design §3.1.
- Fix: compute the deadline of each feed in a barrier that answers `nothing`. Run `wait_for_input` and `get_frame_clock_time` in the `:device` barrier with a counter of their own.
- Reach: `EditorLoop.jl`, `Feeds.jl`, `FaultBarriers.jl` (a limit for the new counter).

### L22-8 A printer fault that surfaces in the device write counts as a device fault, so the safe mode does not start

- Category: Correctness · Severity: Medium · Confidence: Confirmed · Planned: plan/pending/a-fault-is-easy-to-see-and-stays-small.md (P2, D4)
- Where: [FaultBarriers.jl:173-193](../../../source/kernel/editor/FaultBarriers.jl#L173) ⬜, [EditorLoop.jl:85](../../../source/kernel/editor/EditorLoop.jl#L85) ⬜
- Evidence: `print_document` builds cells; the printer computations run when `write_to_devices` reads the output. `print!` runs that write in its own `:device` barrier with `counter = :device_write`, inside the `:print` barrier of `run_frame!`. The fault counts on `:device_write`, and the `:print` barrier sees a success and resets its count. `_consider_safe_mode!` does not fire, and after eight frames the editor stops the write and the window freezes (take 7 of screenplay S2).
- Rule: bug; step 3 of design §3.4 of `the-editor-survives-a-fault.md`.
- Fix: D4 of the plan; the owner decides.
- Reach: `FaultBarriers.jl`; the SDL and offscreen renderers for D4.

### L22-9 A stopped half of the device seam never starts again, and a stopped input half leaves no way to quit

- Category: Correctness · Severity: Medium · Confidence: Confirmed · Planned in part: plan/pending/a-fault-is-easy-to-see-and-stays-small.md (P3, D5)
- Where: [FaultBarriers.jl:79-85](../../../source/kernel/editor/FaultBarriers.jl#L79) ⬜, [FaultBarriers.jl:188](../../../source/kernel/editor/FaultBarriers.jl#L188) ⬜
- Evidence: `is_editor_degraded(editor, :device_read) && return nothing`, and the same for `:device_write`. A count resets only after a call that works, and after the limit no call is made. With the input half stopped, `read!` gets no `WindowQuit` and no Escape, and the loop runs until an interrupt or a posted quit. `the-editor-survives-a-fault.md` §3.5 says: "`read_from_devices` keeps running so the person can still quit". D5 tries a stopped half again after the next applied operation; with no input, no operation comes.
- Rule: bug; design §3.5 of `the-editor-survives-a-fault.md`.
- Fix: try a stopped half again after a delay (for example once a second), whether an operation came or not. Do it at least for the input half.
- Reach: `FaultBarriers.jl`.

### L22-10 The cleanup of `run_editor!` stops at the first throw, so the backend can stay open and the server can keep its port

- Category: Correctness · Severity: Medium · Confidence: Suspected (needs a pass-through exception from a queued call at the end of the loop, or a server whose stop throws).
- Where: [EditorLoop.jl:191-196](../../../source/kernel/editor/EditorLoop.jl#L191) ⬜
- Evidence: the `finally` block runs `_answer_waiting_calls!(editor)`, `stop_agent_server!(server)` and `quit_backend!(editor.backend)` in sequence with no guard. `_answer_waiting_calls!` rethrows a pass-through exception (Inbox.jl:130), and `evaluate_operation` of a `RunFunctionOperation` does the same (Inbox.jl:101). A throw in one of the first two skips `quit_backend!`. The window stays, and the MCP server keeps its port, so the next editor of the process can not start a server on it.
- Rule: bug; PAR-PER-EDITOR-STATE (PR-MANY-EDITORS-ONE-PROCESS: stopping one editor must have no effect on another).
- Fix: run each of the three steps in its own `try … finally`, and rethrow the first exception after the last step.
- Reach: `EditorLoop.jl`.

### L22-11 Three repair blocks catch every exception, the pass-through ones too, and record nothing

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [FaultBarriers.jl:90-97](../../../source/kernel/editor/FaultBarriers.jl#L90) ⬜, [FaultBarriers.jl:104-110](../../../source/kernel/editor/FaultBarriers.jl#L104) ⬜, [FaultBarriers.jl:121-133](../../../source/kernel/editor/FaultBarriers.jl#L121) ⬜
- Evidence: `_make_operation_inverse` is `try make_inverse_operation(…) catch; nothing end`. `_repair_after_operation_fault!` evaluates the inverse inside `try … catch end`. `_repair_selection!` has a bare `catch`. Each block catches an `InterruptException` or a `QuitEditorException`, and none calls `record_fault!`. A fault in `make_inverse_operation` is never seen: under the strict policy `evaluate!` takes no inverse, and under the loop the fault vanishes.
- Rule: PAR-REPORT-NEVER-THROWS: "a barrier never swallows a fault in silence", and a pass-through exception "is never caught".
- Fix: in each block, `is_passthrough_exception(exception) && rethrow()`, then `record_fault!(editor.faults, :evaluate; origin = …, exception, traceback = catch_backtrace())`.
- Reach: `FaultBarriers.jl`.

### L22-12 `get_frame_clock_time` is a backend seam that the editor layer declares

- Category: Architecture · Severity: Medium · Confidence: Confirmed
- Where: [EditorLoop.jl:92-101](../../../source/kernel/editor/EditorLoop.jl#L92) ⬜
- Evidence: `get_frame_clock_time(backend, wall_time) = wall_time` dispatches on the backend, and its docstring says "a backend answers it unless it keeps a time of its own". The one other method is `get_frame_clock_time(backend::VideoBackend, wall_time)` (`source/backend/video/VideoBackend.jl:154`), which `ProjecturedVideo` imports from `EditorModule` (`package/ProjecturedVideo/src/ProjecturedVideo.jl:43`). A backend package therefore extends the editor layer, not the backend layer.
- Rule: PAR-BACKEND-SEAM: the backend generics are "all declared in `BackendInterface.jl` and dispatched on the concrete backend".
- Fix: declare `get_frame_clock_time` in `BackendInterface.jl`, put the default in `BackendDefaults.jl`, export it from `BackendModule`, and change the import of `ProjecturedVideo`.
- Reach: `source/kernel/backend/BackendInterface.jl` 🔒, `BackendDefaults.jl` 🔒, `BackendModule.jl` 🔒 (each needs the owner's permission); `EditorLoop.jl`, `EditorModule.jl`; `package/ProjecturedVideo/src/ProjecturedVideo.jl`, `source/backend/video/VideoBackend.jl`.

### L22-13 `EditorModule` exports `read!`, a name that `Base` exports with another binding

- Category: Architecture · Severity: Medium · Confidence: Suspected (needs a check in a fresh session: `using Projectured; read!(IOBuffer(UInt8[1]), zeros(UInt8, 1))`).
- Where: [ReadEvaluatePrint.jl:26](../../../source/kernel/editor/ReadEvaluatePrint.jl#L26) ⬜, [EditorModule.jl:32](../../../source/kernel/editor/EditorModule.jl#L32) ⬜
- Evidence: `function read!(editor::Editor)` defines a new function of `EditorModule`, not a method of `Base.read!`, and the module exports it. The umbrella re-exports every export into `Projectured` (`source/projectured/Projectured.jl:44-49`). A module that does `using Projectured` then sees two exported bindings named `read!`. `ProjecturedFaultTest` adds `import ProjecturedKernel.EditorModule: read!` beside `using ProjecturedKernel.EditorModule` (`package/ProjecturedPlatformTest/src/ProjecturedPlatformTest.jl:40`), which is the usual answer to such a clash. `test_export_collisions` compares the packages, not `Base`. `plan/pending/naming-rule-renames.md` keeps the name under the naming law; that decision does not address the clash.
- Rule: PAR-QUALIFIED-EXTENSION: "no two modules may export the same name with different bindings".
- Fix: rename the stage (for example `read_input!`) with `workspace/bin/julia-rename.jl`.
- Reach: `ReadEvaluatePrint.jl`, `EditorModule.jl`, `source/kernel/playback/Playback.jl`, `test/kernel/editor/EscapeQuitTest.jl`, `ProjecturedFaultTest`, `editor.md`. omnet-julia and inet-julia do not call `read!`.

### L22-14 The editor attaches its wake to stores and never detaches it, so a process-global store keeps an ended editor alive

- Category: State · Severity: Medium · Confidence: Confirmed
- Where: [Editor.jl:98-105](../../../source/kernel/editor/Editor.jl#L98) ⬜
- Evidence: the constructor gives `() -> wake_editor!(editor)` to each feed (`attach_wake_callback!`) and to the fault store. Nothing detaches it when the loop ends, and the feed contract declares no detach. `MessageLogFeed()` uses the process-global `_SESSION_MESSAGE_LOG_STORE` (`source/platform/log/MessageLogStore.jl:81`), and the shell gives one to each window editor (`source/platform/shell/WindowChrome.jl:216`). `attach_message_log_wake!` overwrites the one `wake` slot (`MessageLogStore.jl:77`). The store therefore holds the last editor, with its document, IoMap and backend, after that editor ends, and every earlier editor loses its log wake.
- Rule: PAR-PER-EDITOR-STATE.
- Fix: in the `finally` of `run_editor!`, detach the wake from each feed and from the fault store. The feed contract needs a detach generic, or `attach_wake_callback!(feed, nothing)` must mean detach. The shared session store is a separate fault of `ProjecturedLog`.
- Reach: `EditorLoop.jl`; `source/kernel/feed/FeedInterface.jl`, `FeedDefaults.jl`; `source/platform/log/MessageLogFeed.jl`.

### L22-15 Each editor writes its operation, performance and fault lines to the one process logger, with no editor identity

- Category: State · Severity: Medium · Confidence: Confirmed
- Where: [FaultBarriers.jl:147](../../../source/kernel/editor/FaultBarriers.jl#L147) ⬜, [EditorLoop.jl:25](../../../source/kernel/editor/EditorLoop.jl#L25) ⬜, [SafeMode.jl:37](../../../source/kernel/editor/SafeMode.jl#L37) ⬜, [FaultBarriers.jl:127](../../../source/kernel/editor/FaultBarriers.jl#L127) ⬜
- Evidence: `@info "[operation] …"`, `@info "[perf] …"` and the two `@warn "[fault] …"` lines go to `global_logger()`. With two editors in one process the lines mix, and no line says which editor wrote it. With the message-log capture installed (`source/platform/log/MessageLogCapture.jl:64`), the lines go into the session store, and the frame of whichever editor drains first shows them. One editor's log then shows the operations of another.
- Rule: PAR-PER-EDITOR-STATE.
- Fix: add an editor identity to each line as a log keyword, and run the frame under a logger of the editor (`with_logger`) when the editor has one.
- Reach: `FaultBarriers.jl`, `EditorLoop.jl`, `SafeMode.jl`, `Editor.jl` (a logger keyword); `source/platform/log`.

### L22-16 Each live operation formats the whole operation into a log line and computes an inverse before it runs

- Category: Types/performance · Severity: Medium · Confidence: Suspected (needs a measurement of `evaluate!` on a large document).
- Where: [FaultBarriers.jl:147](../../../source/kernel/editor/FaultBarriers.jl#L147) ⬜, [FaultBarriers.jl:151](../../../source/kernel/editor/FaultBarriers.jl#L151) ⬜
- Evidence: `editor.operation !== nothing && @info "[operation] $(editor.operation)"`. No kernel operation has a `show` method, so the default `show` prints every field. `show(::Document)` limits the depth to 3 but not the width (`source/kernel/document/DocumentDefaults.jl:95-111`). An operation that carries a collection or a root prints every element, for each operation of each frame, hover writes too. The line also reaches the message-log store, whose wake runs one more frame after each frame with an operation. Under the loop, `evaluate!` also calls `make_inverse_operation`, which walks the reference once more.
- Rule: bug (cost on the hot path).
- Fix: log `describe_operation(operation)` (it exists in `source/kernel/operation/Description.jl`), and log it at `@debug` or behind a switch of the editor.
- Reach: `FaultBarriers.jl`.

### L22-17 No test drives the fault paths of the loop

- Category: Tests · Severity: Medium · Confidence: Confirmed (a search of `test/` for the functions and the counters)
- Where: [FaultBarriers.jl:79-193](../../../source/kernel/editor/FaultBarriers.jl#L79) ⬜, [EditorLoop.jl:60-90](../../../source/kernel/editor/EditorLoop.jl#L60) ⬜, [Inbox.jl:123-136](../../../source/kernel/editor/Inbox.jl#L123) ⬜
- Evidence: no test makes an operation throw under a policy that catches, so repair 0 (the inverse), repair 1 (the new print) and repair 2 (the selection) have no test. No test makes `read_from_devices` or `write_to_devices` throw eight times, so the breakers in `read!` and `print!` have no test. No test makes a reader throw inside `run_frame!`, a feed throw inside the drain, or a queued call throw in `_answer_waiting_calls!`. The zoom keys of `read!` have no test. `test/kernel/fault/FaultBarrierTest.jl` tests `run_fault_barrier` alone, and `test/platform/fault/FaultSafeModeTest.jl` tests the `:print` count alone.
- Rule: PAR-NEW-CODE-SHIPS-TESTS; PAR-REPORT-NEVER-THROWS ("Tests assert both").
- Fix: add `test/kernel/editor/FaultBarriersTest.jl` with a `HeadlessBackend` variant that throws on demand and an operation that fails half way.
- Reach: `test/kernel/editor/`, `package/ProjecturedKernelTest/src/ProjecturedKernelTest.jl`, `test/kernel/KernelSuite.jl`.

### L22-18 `read!` drops input while no IoMap exists, also inside one read

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [ReadEvaluatePrint.jl:36-37](../../../source/kernel/editor/ReadEvaluatePrint.jl#L36) ⬜, [ReadEvaluatePrint.jl:64](../../../source/kernel/editor/ReadEvaluatePrint.jl#L64) ⬜
- Evidence: `elseif editor.iomap === nothing; continue` drops each gesture. Two cases reach it beyond the accepted swap between frames. First, Escape in the safe mode runs `leave_safe_mode!(editor) && continue`, which drops the IoMap and reads on, so all input behind that Escape in the same read is lost. `run_frame!` ends a frame at a dropped IoMap for this reason (EditorLoop.jl:51-54). Second, an editor built with `Editor(…)` and run by `run_editor!` reads its first frame before its first print (the video backend works around it, `source/backend/video/VideoBackend.jl:170-178`).
- Rule: bug.
- Fix: after `leave_safe_mode!`, return `false` from `read!`. Let `run_editor!` print once before its first read when `editor.iomap === nothing`.
- Reach: `ReadEvaluatePrint.jl`, `EditorLoop.jl`.

### L22-19 `find_rooted_operation` never tries the root, so an editor with no reader that follows a route can not use the edit verbs

- Category: Correctness · Severity: Low · Confidence: Confirmed that the loop stops at depth 1; the failure for a JSON editor is Suspected (needs a run).
- Where: [DocumentEdits.jl:24](../../../source/kernel/editor/DocumentEdits.jl#L24) ⬜
- Evidence: `for depth in (length(steps) - 1):-1:1` tries each place from the deepest to depth 1. The docstring says the operation is rooted "at the deepest place on `reference` from which the readers of the editor carry it to the root". The root carries it at once (`read_rooted_operation` answers the operation for an empty place), but the loop never tries it. So `insert_elements!` on a collection that is the root, or in an editor whose readers follow no route, throws `ArgumentError("No reader of the editor takes an edit of …")`. The plan records that "the JSON projection follows no route".
- Rule: bug, or a decision that the docstring must state.
- Fix: the owner decides. Either try depth 0 last, or say in the docstring that an edit that no reader carries is refused.
- Reach: `DocumentEdits.jl`.

### L22-20 The clock of the loop reads the wall clock

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [EditorLoop.jl:158](../../../source/kernel/editor/EditorLoop.jl#L158) ⬜, [EditorLoop.jl:174](../../../source/kernel/editor/EditorLoop.jl#L174) ⬜
- Evidence: `t_start = Base.time()` and `frame_started = Base.time()`. `Base.time()` follows the system clock, so a step of that clock moves the animation time of the editor back or forward, and it corrupts the frame time that `record_frame_performance!` records.
- Rule: bug.
- Fix: use `time_ns()` for both values, converted to seconds.
- Reach: `EditorLoop.jl`.

### L22-21 A reader that throws loses the key, and the edit verbs answer success before any paint

- Category: Correctness · Severity: Low · Confidence: Confirmed · Planned: plan/pending/a-fault-is-easy-to-see-and-stays-small.md (P4/D6, P5/D7)
- Where: [EditorLoop.jl:71-78](../../../source/kernel/editor/EditorLoop.jl#L71) ⬜, [DocumentEdits.jl:41-54](../../../source/kernel/editor/DocumentEdits.jl#L41) ⬜
- Evidence: the read barrier answers `false`, so the gesture is gone and the frame stops its reads. `_replace_elements!` evaluates and answers the collection, and a paint that fails after it does not reach the caller.
- Rule: the problems P4 and P5 of the plan.
- Fix: as the plan proposes.
- Reach: as the plan names.

### L22-22 `_repair_selection!` clears the selection outside an operation

- Category: Architecture · Severity: Low · Confidence: Confirmed
- Where: [FaultBarriers.jl:126](../../../source/kernel/editor/FaultBarriers.jl#L126) ⬜
- Evidence: `clear_selection!(editor.document)` writes the document directly. The write starts at the root, so PAR-SELECTION-WRITTEN-AT-ROOT holds. No operation carries it, so a history and the gesture log do not see it.
- Rule: PAR-ONE-WAY-TO-EDIT.
- Fix: express the repair as an operation and evaluate it in the same repair.
- Reach: `FaultBarriers.jl`.

### L22-23 The loop hard-codes the zoom keys, and only the SDL backend evaluates the operation

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ReadEvaluatePrint.jl:50-54](../../../source/kernel/editor/ReadEvaluatePrint.jl#L50) ⬜, [ReadEvaluatePrint.jl:126-137](../../../source/kernel/editor/ReadEvaluatePrint.jl#L126) ⬜
- Evidence: `_zoom_operation` maps Ctrl with `=`, `-` or `0` to `AdjustZoomOperation` or `AdjustFontZoomOperation` inside the kernel loop, outside the binding layer. Only `source/backend/sdl/SdlBackend.jl:3926-3941` evaluates the two operations. On the web and console backends the key becomes an operation that does nothing, but the editor logs it and stores it in `editor.operation`.
- Rule: architecture-rules.md, the seam pattern (a lower layer declares, a higher package binds).
- Fix: move the two keys into a gesture binding set that the backend package or the screen package gives, or let each backend answer the zoom through a backend generic. The font half is deferred with `plan/pending/font-zoom-per-editor.md`.
- Reach: `ReadEvaluatePrint.jl`, `source/backend/sdl/SdlBackend.jl`.

### L22-24 Four exports have no user outside the layer, and six more have users only in tests

- Category: Shape · Severity: Low · Confidence: Confirmed (a search of `source/`, `package/`, `example/`, `tool/`, `test/`, omnet-julia and inet-julia)
- Where: [EditorModule.jl:32-39](../../../source/kernel/editor/EditorModule.jl#L32) ⬜
- Evidence: no user outside the layer: `is_editor_degraded`, `enter_safe_mode!`, `leave_safe_mode!`, `report_frame_faults!`. Users only in tests: `get_consecutive_fault_limit`, `is_editor_in_safe_mode`, `InboxFeed`, `wake_editor!`, `drain_feeds!`, and `read!` (also `PlaybackModule`).
- Rule: code-quality-rules.md §4, "The public functions come first" (each public name costs every later caller).
- Fix: keep the names that a caller needs (`wake_editor!` is the documented producer wake), and make the rest private or say why each stays public.
- Reach: `EditorModule.jl`; the tests that import them.

### L22-25 The fragments do not hold what their headers say

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [ReadEvaluatePrint.jl:1](../../../source/kernel/editor/ReadEvaluatePrint.jl#L1) ⬜, [ReadEvaluatePrint.jl:143](../../../source/kernel/editor/ReadEvaluatePrint.jl#L143) ⬜, [FaultBarriers.jl:141-193](../../../source/kernel/editor/FaultBarriers.jl#L141) ⬜, [EditorLoop.jl:1](../../../source/kernel/editor/EditorLoop.jl#L1) ⬜
- Evidence: the header of `ReadEvaluatePrint.jl` names "the three stages of a frame", but the file holds `read!`, `read_rooted_operation` and `get_fault_store`; `evaluate!` and `print!` are in `FaultBarriers.jl`. `FaultModule.get_fault_store(editor::Editor)` is an accessor of the editor. The header of `EditorLoop.jl` names the counter log, one frame and the main loop, but the file also holds `make_editor` and `get_frame_clock_time`.
- Rule: code-quality-rules.md §1 (a fragment header says what the fragment adds); PAR-MODULE-DOCSTRING.
- Fix: move `evaluate!` and `print!` into `ReadEvaluatePrint.jl` and keep the barrier helpers in `FaultBarriers.jl`. Move `get_fault_store` into `Editor.jl`, and correct the header of `EditorLoop.jl`.
- Reach: the four files; no caller changes.

### L22-26 The module header, the export block and one list of keywords do not follow code-quality §1 and §4

- Category: Shape · Severity: Low · Confidence: Confirmed · Planned in part: plan/pending/export-block-rule.md (the export block)
- Where: [EditorModule.jl:1-39](../../../source/kernel/editor/EditorModule.jl#L1) ⬜, [EditorLoop.jl:279-285](../../../source/kernel/editor/EditorLoop.jl#L279) ⬜
- Evidence: the 18 `using` lines are not in the order of the module names. `import ..FeedModule: drain_changes!` has no comment that says the module extends it. One export statement covers eight fragments (`test/suite/exports.jl:56` lists the module as not migrated). The module docstring does not say what each fragment holds. `run_editor!(backend, projection, document; …)` takes seven keyword arguments, and four of them (`mcp`, `mcp_instructions`, `mcp_host`, `mcp_port`) are one server option.
- Rule: code-quality-rules.md §1; §4, "More than five keyword arguments is a type that is missing".
- Fix: sort the header, add the comment, write one export statement for each fragment, and list the fragments in the docstring. Pass the server options as one value to both `run_editor!` methods (a wider change; the owner decides).
- Reach: `EditorModule.jl`, `EditorLoop.jl`; the callers that pass `mcp_*` keywords.

### L22-27 `perf!` and `_zoom_operation` do not start with a verb, and `perf` is a short form that the rules forbid

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [EditorLoop.jl:12](../../../source/kernel/editor/EditorLoop.jl#L12) ⬜, [ReadEvaluatePrint.jl:126](../../../source/kernel/editor/ReadEvaluatePrint.jl#L126) ⬜
- Evidence: naming-rules.md says "Every function name starts with a verb" and lists "`performance` not `perf`". `perf!` writes the counters to the log. `_zoom_operation` finds an operation or `nothing`. The locals `op`, `ev`, `m` and `z` (ReadEvaluatePrint.jl:42, 50, 128-131) use short forms that the rules discourage.
- Rule: naming-rules.md "Functions" and "Words"; PAR-NAMING-LAW.
- Fix: `log_performance_counters!` and `_find_zoom_operation`, with `workspace/bin/julia-rename.jl`; then fix the prose that names `perf!`.
- Reach: `EditorLoop.jl`, `ReadEvaluatePrint.jl`; comments in `test/kernel/editor/`; `editor.md`; `architecture-invariants.md:1028`; `plan/pending/a-present-that-is-a-timeout.md`.

### L22-28 Three texts say that `run_editor!` turns the barriers on, but `make_editor` does

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [Editor.jl:31-37](../../../source/kernel/editor/Editor.jl#L31) ⬜, [FaultBarriers.jl:6-8](../../../source/kernel/editor/FaultBarriers.jl#L6) ⬜, [architecture-invariants.md:970-975](../../../documentation/rule/architecture-invariants.md#L970)
- Evidence: `run_editor!(editor; fault_policy = editor.fault_policy)` keeps the policy of its editor, so an `Editor(…)` stays strict in its loop. `make_editor` gives `FaultPolicy()`, which catches. Decision 3 of `plan/done/an-editor-is-made-before-its-loop-runs.md` made this change, and the `run_editor!` docstring (EditorLoop.jl:129-131) states it. The invariants text also says that no test calls `run_editor!`; `WaitTest.jl` and `InboxTest.jl` call it.
- Rule: PAR-HONEST-DOCS.
- Fix: say that `make_editor` turns the barriers on and `run_editor!` keeps the policy of its editor. The change to architecture-invariants.md needs the owner's word.
- Reach: `Editor.jl`, `FaultBarriers.jl`, `documentation/rule/architecture-invariants.md`.

### L22-29 `editor.md` describes an older editor layer

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [editor.md:14-27](../../../documentation/package/kernel/editor.md#L14), [editor.md:49](../../../documentation/package/kernel/editor.md#L49), [editor.md:207](../../../documentation/package/kernel/editor.md#L207), [editor.md:404](../../../documentation/package/kernel/editor.md#L404), [editor.md:493-497](../../../documentation/package/kernel/editor.md#L493), [editor.md:510-528](../../../documentation/package/kernel/editor.md#L510), [editor.md:536-544](../../../documentation/package/kernel/editor.md#L536)
- Evidence: the struct block lists 10 of the 17 fields. The text says the recognizer folds "`KeyDown` sequences into `KeyChord`", but the editor makes `GestureRecognizer()` with no chord table, and a `MousePress` follows its `MouseUp` and does not replace it. "There are two implementations" omits `WebBackend`. The layer section names one file, `EditorModule.jl`, for the loop; the loop is nine files. The list of downward edges omits `IntentModule`, `IoMapModule`, `FaultModule`, `SelectionModule`, `ReferenceModule`, `CellModule` and `FeedModule`. The test list omits `WaitTest.jl`, `test/kernel/editor/FeedsTest.jl` and the safe-mode test. (The playback items of this document are in L23-11.)
- Rule: PAR-UPDATE-THE-GUIDE, PAR-HONEST-DOCS.
- Fix: update the sections. The chord plan is deferred, so the text must say that the editor recognizes no chord today.
- Reach: `documentation/package/kernel/editor.md`.

### L22-30 Docstrings and comments name consumers, cite a rule, and pass the line budget

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [Editor.jl:8](../../../source/kernel/editor/Editor.jl#L8) ⬜, [EditorLoop.jl:233-235](../../../source/kernel/editor/EditorLoop.jl#L233) ⬜, [EditorLoop.jl:269](../../../source/kernel/editor/EditorLoop.jl#L269) ⬜, [ReadEvaluatePrint.jl:47-49](../../../source/kernel/editor/ReadEvaluatePrint.jl#L47) ⬜, [Inbox.jl:8](../../../source/kernel/editor/Inbox.jl#L8) ⬜, [FaultBarriers.jl:165-167](../../../source/kernel/editor/FaultBarriers.jl#L165) ⬜, [EditorLoop.jl:106](../../../source/kernel/editor/EditorLoop.jl#L106) ⬜, [FaultBarriers.jl:136-139](../../../source/kernel/editor/FaultBarriers.jl#L136) ⬜, [DocumentEdits.jl:1-2](../../../source/kernel/editor/DocumentEdits.jl#L1) ⬜, [DocumentEdits.jl:57-66](../../../source/kernel/editor/DocumentEdits.jl#L57) ⬜
- Evidence:
  - The kernel names consumers: "(e.g. SdlBackend)", "the full SDL hardware set", "such as the `ConsoleBackend`", "use `write_image` for offscreen", "clipboard add/remove on Ctrl+=/-".
  - `Inbox.jl:8` cites "(PAR-NO-WRITE-IN-THUNK)" to state compliance.
  - The `print!` docstring has "so animated cells descendants build subscribe", which is not a sentence.
  - The header line of the `run_editor!(editor)` docstring names only `mcp` of its five keywords.
  - The `evaluate!` docstring says nothing about the barrier, the inverse and the repairs.
  - `insert_elements!` evaluates at once, so it must run on the editor task; its docstring does not say so (`read_rooted_operation` does).
  - The header of `DocumentEdits.jl` takes two lines. 19 lines of the layer pass 90 characters, and seven fragment headers are 111 to 159 characters long.
- Rule: PAR-NO-CONSUMER-DOCS, PAR-CITE-EXCEPTIONS-ONLY, PAR-MODULE-DOCSTRING, code-quality-rules.md §1 and §5.
- Fix: correct the texts and wrap the long lines.
- Reach: the files of the layer.

### L22-31 The edit verbs have tests only in the umbrella, the REPL driver uses a stand-in editor, and tests import private names

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/projectured/editor/ReferencedDocumentEditorTest.jl`; [ReplTest.jl:17-20](../../../test/kernel/editor/ReplTest.jl#L17); [InboxTest.jl:15-16](../../../test/kernel/editor/InboxTest.jl#L15); [FrameDrainTest.jl:15](../../../test/kernel/editor/FrameDrainTest.jl#L15); [WaitTest.jl:19-21](../../../test/kernel/editor/WaitTest.jl#L19)
- Evidence: `find_rooted_operation`, `insert_elements!` and `delete_elements!` have tests only in the umbrella suite; the kernel suite does not test the search from the deepest place or the case that no place carries the operation. `walk_repl_loop` drives `_ReplEditor`, a stand-in with two fields, and prints the pipeline again after each event. It does not run `read!`, the recognizer, the Escape and zoom keys, or the reuse of the IoMap. The tests import `RunFunctionOperation`, `MAX_OPERATIONS_PER_FRAME`, `FRAME_INTERVAL` and `compute_wait_timeout`, which the module does not export.
- Rule: PAR-NEW-CODE-SHIPS-TESTS (the lowest test package); PAR-MODULE-BOUNDARY-IS-API.
- Fix: add a kernel test of `find_rooted_operation` with a stand-in projection that follows a route. Drive `walk_repl_loop` through a real `Editor` and `run_frame!`. Export the four names or qualify them in the tests.
- Reach: `test/kernel/editor/`.

## Accepted before, not raised again

No audit plan of this layer exists. These decisions of the owner, or documented designs, are not raised:

- The seven keywords of `run_fault_barrier` (accepted 2026-09-24); `_run_barrier` passes them on.
- Reactive cells hold `Any`.
- An `Editor` starts strict (`the-editor-survives-a-fault.md`, step 1 of §5), and `make_editor` gives a policy that catches (`an-editor-is-made-before-its-loop-runs.md`, decision 3). L22-28 raises only the stale text.
- The operation barrier gives a `CompoundOperation` no rollback (`the-editor-survives-a-fault.md` §3.4).
- A posted operation does not become `editor.operation`, and the editor does not log it (`editor.md`, "The inbox").
- Escape quits when no reader takes it, and a modified Escape goes to the projections (`editor.md`, `EscapeQuitTest.jl`).
- Input read against no IoMap after a projection swap between frames is dropped (`test/platform/fault/FaultSafeModeTest.jl:69-72`). L22-18 raises only the two cases beyond it.
- The limit of each fault counter lives in the editor layer (`plan/done/fault-policy-limits.md`).
- `read!`, `evaluate!` and `print!` keep their names under the naming law (`naming-rule-renames.md`). L22-13 raises the clash with `Base`, not the law.
- The owner approved `insert_elements!` and `delete_elements!` and their shape (D24). L22-1 raises only the guard.
- Deferred: `key-chords-from-bindings.md` (the editor makes `GestureRecognizer()` with no chord table); `font-zoom-per-editor.md` (`AdjustFontZoomOperation` writes the process-global `_FONT_ZOOM` through the SDL package); `sdl-per-editor-state.md` Part 2.

## Checked and clean

- PAR-PER-EDITOR-STATE inside the layer: each mutable value is a field of `Editor` or reachable from it. The recognizer, clock, tool set, fault store, frame measurement store and default devices are new for each editor. Module-level values are constants.
- PAR-STORE-THEN-DRAIN: the feeds drain on the editor task before `read!`, the fault report runs at the top of `run_frame!`, and a wake is atomic and coalesces.
- PAR-SELECTION-WRITTEN-AT-ROOT: the one direct selection write starts at the root; the verbs root their operations through the readers.
- PAR-ONE-WAY-TO-EDIT: the verbs and the inbox go through `evaluate_operation` (except L22-22).
- PAR-MANY-WINDOWS: `make_editor` opens the native windows of the document before the first print, and the loop gives the whole output to the backend.
- PAR-BACKEND-SEAM: apart from L22-12, the loop calls only backend generics.
- PAR-OPT-IN-DEPENDENCY: the MCP server comes through `make_agent_server(:mcp, …)`.
- PAR-QUALIFIED-EXTENSION: each extension is imported (`drain_changes!`) or qualified (six generics). PAR-MODULE-BOUNDARY-IS-API: the source uses only exported names; no `Module._private` reference.
- PAR-NO-TEST-DOUBLES-IN-MAIN: the tests use `HeadlessBackend` from `ProjecturedKernelExample`.
- PAR-NO-NEW-SYNTHETIC-EVENT: `read_rooted_operation` uses the route field that `Intent` already has.
- Pass-through exceptions: `RunFunctionOperation` and `_answer_waiting_calls!` rethrow them.
- Layering: the layer imports only lower layers; the kernel layering guard passes in the baseline.
- No history comment (the one hit, "no longer resolves", describes a run).
- Types: the abstract fields of `Editor` cost a dynamic call a few times in a frame, which is not a hot loop.
