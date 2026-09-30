# Layer 23 — playback (`source/kernel/playback/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 2 files).

## Verdict

`play_live!` plays a timeline in a real window, but it runs a second frame loop of its own beside `run_editor!`.
That loop leaves out the inbox, the feeds, the clock tick, the fault report, `loop_task`, the counters and the wait, so an editor behaves differently under playback.
Its schedule starts before the first print, and its event entries skip the gesture recognizer, so a scripted press and release is not a click.
Three interpreters read the one timeline format with different rules, and `VideoBackend` already plays a timeline through `run_editor!` as a source of input.
The only caller is an example package, no test covers the layer, and its place in the kernel is open.

## Shape

- Purpose: play a timeline of entries (`event`, `operation` or `await`, each with a `hold`) on a wall-clock schedule in a live editor, so that a person watches a scripted session.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `PlaybackModule.jl` | 24 | ⬜ | docstring, 8 `using`, one export, one include |
  | `Playback.jl` | 127 | ⬜ | `_path_to_steps`, `_timeline_operation`, `play_live!(editor, timeline; …)`, `play_live!(backend, timeline; …)` |

- Imports: `EditorModule`, `ProjectionModule`, `IntentModule`, `EventModule`, `OperationModule`, `ReferenceModule`, `BackendModule`, `DeviceModule`. The layer extends no generic.
- Imported by: nothing in the kernel. The umbrella re-exports `play_live!`.
- Public surface: 1 exported name, `play_live!`. Its one caller is `play_live_example` in `ProjecturedSdlExample` (`example/sdl/LiveExamples.jl:136`). `tool/video/record_json_from_nothing.jl` uses the same timeline but records it with `record_live_example`. omnet-julia and inet-julia do not use `play_live!`.
- Module/Interface/Defaults: one module file and one fragment; no interface, no default, no seam.
- State: none at module level. The schedule (`fire_at`, `next`, `start`) is local to one call.
- Tests: none. `test/kernel/KernelSuite.jl:21` names the layer for the layering guard, but no `test/kernel/playback/` folder exists and no test calls `play_live!`.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 1 | 2 | 1 |
| Shape | 0 | 2 | 2 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 1 | 0 |

## Findings

### L23-1 `play_live!` runs a second frame loop that leaves out the inbox, the feeds, the clock and the fault report

- Category: Correctness · Severity: High · Confidence: Confirmed
- Checked by the lead on 2026-09-27: Read the code: the loop at `Playback.jl:85-97` calls `read!`, `evaluate!`, `print!` and `sleep(0.01)`, and nothing else.
- Where: [Playback.jl:85-100](../../../source/kernel/playback/Playback.jl#L85) ⬜, [Playback.jl:114-127](../../../source/kernel/playback/Playback.jl#L114) ⬜
- Evidence: each turn of the loop is `read!(editor)`, at most one entry, `evaluate!(editor)`, `print!(editor)` and `sleep(0.01)`. Against `run_editor!` and `run_frame!`, the loop leaves out these steps:
  1. `drain_feeds!`: the inbox and every feed. A `post_operation!` is never applied, and after 64 posts the poster blocks for ever. Posters are `post_pane_operation!` (menu commands) and any driver that posts, such as a simulation watch.
  2. `editor.loop_task`: it stays `nothing`, so `run_on_editor_task!` runs each call at once on the task that calls it, beside the frame (an assistant turn, a tool call).
  3. `set_clock_time!`: the clock of the editor never moves, so an animation stands still.
  4. `report_frame_faults!`: no fault of the playback reaches the log or the console.
  5. `with_performance_counters`, `perf!` and `record_frame_performance!`: no counters and no frame measurements.
  6. The `:read` and `:print` barriers of the frame and `_consider_safe_mode!`: a reader that throws, or a `print_document` that throws, ends the playback, also for an editor from `make_editor`.
  7. `wait_for_input`: the loop sleeps 10 ms whatever happens, `wake_editor!` has no effect, and the loop turns 100 times a second for as long as the window is open.
  8. `MAX_OPERATIONS_PER_FRAME`: one operation of real input in each frame, so a burst of input falls behind.
  9. The bootstrap method does not call `configure_devices!`, gives the `Editor` no feed, and reads once before its first print.
- Scenario: a caller plays a timeline over an editor from `make_editor` with the window tools. A menu command posts its pane edit, which never applies, and the message log and the frame statistics stay empty.
- Rule: bug; PAR-STORE-THEN-DRAIN ("Only the editor task writes a document a running editor shows").
- Fix: see L23-5. Inside the present shape: set `editor.loop_task`, and in place of the four calls run the steps of `run_editor!` (the clock, `drain_feeds!` in its barrier, `run_frame!`), with `wait_for_input` bounded by the time to the next entry.
- Reach: `Playback.jl`.

### L23-2 The schedule starts before the first print, and a late entry does not move the entries after it

- Category: Correctness · Severity: Medium · Confidence: Confirmed by the code; the length of a first print was not measured here.
- Where: [Playback.jl:76-83](../../../source/kernel/playback/Playback.jl#L76) ⬜, [Playback.jl:90-93](../../../source/kernel/playback/Playback.jl#L90) ⬜
- Evidence: `start = time()` runs before the first `read!` and the first `print!`. Entry `i` fires when `time() - start >= fire_at[i]`, one entry in each turn. A first print compiles code, and package-rules.md measures 0.66 s to 8.36 s for a first paint. Each entry whose time passes during that print fires in the next turns, 10 ms apart, so its `hold` is lost and the viewer sees a burst. The same happens after a slow frame, and after a turn that real input took, because the schedule is absolute. `VideoBackend` starts its clock only when the first frame is on disk (`source/video/VideoBackend.jl:170-178`), and it holds the next entry until the last one is painted.
- Rule: bug; the docstring says that `hold` is "the dwell after the entry" and that "each resulting state is visible".
- Fix: take `start` after the first `print!`, and move the rest of the schedule by the delay of an entry that fired late.
- Reach: `Playback.jl`.

### L23-3 Event entries skip the gesture recognizer, so a scripted press and release gives no `MousePress`

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [Playback.jl:37-43](../../../source/kernel/playback/Playback.jl#L37) ⬜, [Playback.jl:18-21](../../../source/kernel/playback/Playback.jl#L18) ⬜
- Evidence: `_timeline_operation` wraps `entry.event` in `WindowInput(window_id, entry.event)` and calls `read_intent` directly. Live input and `VideoBackend` go through `read!`, whose `pop_gesture!` gives each event to the recognizer, so a `MouseDown` and `MouseUp` pair gets its `MousePress`. A timeline that scripts a click as a press and a release, the form that `VideoBackend` needs, clicks nothing here when the reader binds `MousePress`. The event also keeps the time at which the timeline was built (`KeyDown(…; time = time())`, `example/sdl/LiveExamples.jl:159`), where `VideoBackend` stamps the time it fires (`source/video/VideoBackend.jl:223`). The docstring says that the entry takes "the same path live input takes".
- Rule: bug.
- Fix: give each event entry to the recognizer, stamped with the time it fires (through `pop_gesture!`, or through a source of input as in L23-5).
- Reach: `Playback.jl`.

### L23-4 Three interpreters read one timeline format with different rules

- Category: Shape · Severity: Medium · Confidence: Confirmed
- Where: [Playback.jl:28-44](../../../source/kernel/playback/Playback.jl#L28) ⬜, [Playback.jl:76-81](../../../source/kernel/playback/Playback.jl#L76) ⬜
- Evidence:

  | entry | `record_video` (`source/video/Video.jl`) | `VideoBackend` (`source/video/VideoBackend.jl`) | `play_live!` (kernel) |
  | --- | --- | --- | --- |
  | `event` | `read_intent` directly (Video.jl:155) | through `read!` and the recognizer | `read_intent` directly |
  | `operation` | evaluated; a thunk gets the document | refused: "carries neither `event` nor `await`" (VideoBackend.jl:138) | evaluated; rerooted by a fixed prefix |
  | `await` | waits for `pred(document)`, at most `hold` (Video.jl:135-138) | waits for `entry.await(editor)`, at most `hold`, then moves the rest of the schedule (VideoBackend.jl:239-245) | waits the whole `hold`; the predicate is not called |
  | clock | video frames | the wall or the video clock, from the first frame on disk | the wall clock, from before the first print |

  No type or function declares the entry format; each interpreter reads the keys of a `NamedTuple`. The `timed_await` docstring (`example/sdl/LiveExamples.jl:61-73`) documents the difference, but no plan decides it.
- Rule: redundancy; PAR-FRAMEWORKS-SINK (a framework sinks once, below its users).
- Fix: declare the entry kinds once, in the lowest package that the three interpreters reach (the kernel, beside the `record_video` seam), with one meaning of `await` (a predicate of the editor).
- Reach: `Playback.jl`, `source/video/Video.jl`, `source/video/VideoBackend.jl`, `example/sdl/LiveExamples.jl` (the `timed_*` builders), `example/sdl/ApplicationVideo.jl`, `tool/video/`.

### L23-5 Playback needs no second loop, and its place in the kernel is open

- Category: Shape · Severity: Medium · Confidence: Confirmed for the facts. The recommendation is the auditor's, and the owner decides.
- Where: [PlaybackModule.jl:1-24](../../../source/kernel/playback/PlaybackModule.jl#L1) ⬜, [Playback.jl:71-127](../../../source/kernel/playback/Playback.jl#L71) ⬜
- Evidence: the one caller is `play_live_example` in `ProjecturedSdlExample`. The kernel test of architecture-rules.md asks "does the editor loop itself need it?", and the loop does not need it. PAR-LOWEST-PACKAGE puts code in the lowest package that it hard-references, which is the kernel. The two rules point to different homes. `VideoBackend` shows a timeline that plays through `run_editor!` as a source of input: its `read_from_devices` answers the next due event, and the real loop does the rest. `example/sdl/ApplicationVideo.jl:4-9` makes that choice against "`play_live!`'s side channel".
- Rule: architecture-rules.md, "kernel — machinery and interfaces only … Membership tests"; PAR-LOWEST-PACKAGE.
- Fix (recommendation): replace the loop with a source of input that wraps the live backend and answers due events from `read_from_devices`. Post each due operation with `post_operation!`, and run `run_editor!`. Then decide the home of what is left, a small reader of the timeline, together with L23-4. This change also removes L23-1, L23-2 and L23-3.
- Reach: `Playback.jl`, `PlaybackModule.jl`, `example/sdl/LiveExamples.jl`. If the layer moves: `package/ProjecturedKernel/src/ProjecturedKernel.jl`, `SEALING.md`, `test/kernel/KernelSuite.jl`, `system-anatomy.md`, `division-terminology.md`.

### L23-6 No test covers the layer

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [Playback.jl:71-127](../../../source/kernel/playback/Playback.jl#L71) ⬜; `test/kernel/KernelSuite.jl:21`
- Evidence: no test calls `play_live!`, and `test/kernel/playback/` does not exist. The loop has no end after the last entry. An event entry with `WindowQuit` goes to `read_intent`, not to the `WindowQuit` branch of `read!`, so it does not end the loop. Only an operation entry `QuitEditorOperation()`, or a reader that answers a quit, ends it.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: add `test/kernel/playback/PlaybackTest.jl` with `HeadlessBackend` and a short timeline (an event, an operation, an await, then `QuitEditorOperation()`). Check the order of the entries and the rerooting.
- Reach: `test/kernel/playback/`, `package/ProjecturedKernelTest/src/ProjecturedKernelTest.jl`, `test/kernel/KernelSuite.jl`.

### L23-7 Entries fail in silence or end the playback, and the schedule checks no bound

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Playback.jl:35](../../../source/kernel/playback/Playback.jl#L35) ⬜, [Playback.jl:42](../../../source/kernel/playback/Playback.jl#L42) ⬜, [Playback.jl:76-83](../../../source/kernel/playback/Playback.jl#L76) ⬜, [Playback.jl:98-100](../../../source/kernel/playback/Playback.jl#L98) ⬜
- Evidence: an event entry that no reader answers, and an operation entry that is not an `Operation`, are consumed with no message. An operation thunk or a reader that throws ends `play_live!`, because `_timeline_operation` runs outside every barrier and the `catch` of the loop rethrows. Each entry must have a `hold`, and a negative `hold` moves later entries earlier; nothing checks it. The schedule reads `time()`, a wall clock.
- Rule: bug.
- Fix: log a skipped entry with its index, check `hold >= 0` when the schedule is built, and read `time_ns()`.
- Reach: `Playback.jl`.

### L23-8 Operation entries skip the readers between the root and the content

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [Playback.jl:34-36](../../../source/kernel/playback/Playback.jl#L34) ⬜
- Evidence: `reroot_operation(op, op_prefix)` puts a fixed prefix before the path. The readers between the root and the content do not see the operation: a history reader does not record it, and a reader that maps a path, such as a sorted view, does not map it. `read_rooted_operation(editor, place, operation)` in the editor layer carries an operation from a place through those readers.
- Rule: PAR-DELEGATE-AND-LIFT (a reader lifts the operation on its way out); `editor.md`, "An operation from a place, not a gesture".
- Fix: `read_rooted_operation(editor, op_prefix, op)` in place of `reroot_operation`.
- Reach: `Playback.jl`.

### L23-9 `_path_to_steps` copies `get_reference_steps`

- Category: Shape · Severity: Low · Confidence: Confirmed
- Where: [Playback.jl:4-13](../../../source/kernel/playback/Playback.jl#L4) ⬜
- Evidence: `_path_to_steps` walks `head` and `tail` of a `ConcreteReference` by hand and answers a `Tuple`. `get_reference_steps` (`source/kernel/reference/ReferencePath.jl:224`) is the same walk, and the reference layer exports it.
- Rule: redundancy; PAR-REFERENCE-DSL (do not take a path apart by hand).
- Fix: `Tuple(get_reference_steps(op_prefix))`, or no step list at all with L23-8.
- Reach: `Playback.jl`.

### L23-10 Two private names have no verb, and a public keyword uses the short form `op`

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [Playback.jl:4](../../../source/kernel/playback/Playback.jl#L4) ⬜, [Playback.jl:28](../../../source/kernel/playback/Playback.jl#L28) ⬜, [Playback.jl:72](../../../source/kernel/playback/Playback.jl#L72) ⬜
- Evidence: `_path_to_steps` and `_timeline_operation` do not start with a verb. Each call site writes the keyword `op_prefix` (`example/sdl/LiveExamples.jl:138`), and naming-rules.md says "`operation` not `op`". The locals `op`, `acc`, `cur` and `n` use short forms.
- Rule: naming-rules.md "Functions" and "Words" (argument names are outside the law, but full words are encouraged).
- Fix: `_make_timeline_operation` and `operation_prefix`; remove `_path_to_steps` (L23-9).
- Reach: `Playback.jl`, `example/sdl/LiveExamples.jl`, `editor.md`.

### L23-11 The texts of the layer name consumers, and three documents describe an older playback

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [Playback.jl:29-31](../../../source/kernel/playback/Playback.jl#L29) ⬜, [Playback.jl:18-21](../../../source/kernel/playback/Playback.jl#L18) ⬜, [Playback.jl:103-106](../../../source/kernel/playback/Playback.jl#L103) ⬜, [editor.md:352-398](../../../documentation/package/kernel/editor.md#L352), [editor.md:493-497](../../../documentation/package/kernel/editor.md#L493), [editor.md:530-532](../../../documentation/package/kernel/editor.md#L530), [architecture-invariants.md:1026-1029](../../../documentation/rule/architecture-invariants.md#L1026)
- Evidence:
  - The kernel names consumers: "(see `timed_await`)", "a prior ENTER", "an async turn".
  - The docstring claim "the same path live input takes" is false (L23-3).
  - The header line of the bootstrap docstring omits `op_prefix`.
  - `editor.md` gives `play_live!(backend, projection, document, timeline; …)`; the code takes `play_live!(backend, timeline; projection, document, …)`. It lists `PlaybackModule.jl` in `source/kernel/editor/`, but the layer is `source/kernel/playback/`. It says that playback uses `OperationModule` "to preview `reroot_operation` as scripted events replay", but playback reroots operation entries, and events go through the readers.
  - `architecture-invariants.md` says: "Known remaining instance: `PlaybackModule` reaches into `EditorModule`'s non-exported `read!`/`evaluate!`/`print!`/`perf!`". `EditorModule` exports `read!`, `evaluate!` and `print!`, and playback does not call `perf!`, so the instance does not exist.
  - Six lines of `Playback.jl` pass 90 characters.
- Rule: PAR-NO-CONSUMER-DOCS, PAR-HONEST-DOCS, PAR-UPDATE-THE-GUIDE, code-quality-rules.md §5.
- Fix: correct the texts, and delete the sentence of the invariants document with the owner's word.
- Reach: `Playback.jl`, `documentation/package/kernel/editor.md`, `documentation/rule/architecture-invariants.md`.

## Accepted before, not raised again

- No audit plan of this layer exists, and no plan records a decision of the owner about the behaviour of `play_live!`.
- The rename of `LivePlaybackModule` to `PlaybackModule` (`plan/done/kernel-naming-consistency.md`) is settled.
- After the last entry the window stays live; the docstring states it. L23-6 names only its effect on a test.
- Findings of layer 22 that `play_live!` inherits through `read!`, `evaluate!` and `print!` are in the layer 22 report (for example L22-13, the clash of `read!` with `Base`).

## Checked and clean

- PAR-PER-EDITOR-STATE: no module-level state; the schedule is local to a call, and the bootstrap makes new devices.
- PAR-MODULE-BOUNDARY-IS-API: the layer uses only exported names; the old reach into private loop steps is gone.
- PAR-QUALIFIED-EXTENSION: the layer extends nothing and imports no single name.
- PAR-SELECTION-WRITTEN-AT-ROOT: an operation entry is rooted by `op_prefix` and evaluated at the root of the editor.
- PAR-MANY-WINDOWS: the bootstrap opens the native windows before the first frame.
- PAR-NO-TEST-DOUBLES-IN-MAIN: no double.
- Layering: the layer imports only lower layers; the kernel layering guard passes in the baseline.
- File shape: the module file holds the docstring, the header, one export and one include; the fragment opens with a one-line header.
- No history comment.
