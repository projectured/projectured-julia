# Layer 21 — feed (`source/kernel/feed/`)

Commit 15b40434, 2026-09-27. Seal state: none sealed (0 of 3).

## Verdict

The layer is the contract of a feed: one abstract type, three generics and two defaults, in 89 lines.
It imports nothing, so its place at 21 comes from its concept, not from a dependency. It earns its
own module: three packages implement `Feed` and do not import `EditorModule`. The contract text is
clean, but it is silent on four things, and the code that uses it fails on each. It does not bind a
feed to one editor, and the two feeds with session defaults share one store, one wake and one document
among all editors (L21-1). It does not say what a drain or a deadline that throws does: the editor
drains all feeds in one barrier, so one feed that throws stops the rest (L21-2), and it asks for the
deadlines outside every barrier, so one deadline that throws ends the editor loop (L21-3). It does not
bound a drain, and it gives a drain no way to apply an operation without a block (L21-4, L21-5).

## Shape

- Purpose: the feed contract. A feed is one registered inflow of an editor: a producer on any task
  writes a store, and the editor task moves what is new into a target document once per frame.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `FeedModule.jl` | 30 | ⬜ | module head: docstring, one export statement, two includes; no `using` |
  | `FeedInterface.jl` | 48 | ⬜ | contract: `Feed`, `drain_changes!`, `compute_wake_deadline`, `attach_wake_callback!` (bodiless) |
  | `FeedDefaults.jl` | 11 | ⬜ | `compute_wake_deadline(::Feed, editor) = nothing`, `attach_wake_callback!(::Feed, wake) = nothing` |

- Imports: none. Imported by: `EditorModule` (`InboxFeed`, `drain_feeds!`, `compute_wait_timeout`,
  `Editor.feeds`), and outside the kernel `MessageLogModule` (ProjecturedLog), `FrameStatisticsModule`
  (ProjecturedStatistics), `ReflectionModule` (ProjecturedReflection), `TooltipModule`
  (ProjecturedTooltip), `ScreenModule` (a `feeds::Vector{Feed}` keyword) and `ShellModule`. omnet-julia
  and inet-julia do not use the layer.
- Concrete feeds: `InboxFeed` (`editor/Feeds.jl:16`), `MessageLogFeed`, `FrameStatisticsFeed`,
  `ReflectionFeed`, `TooltipFeed`; the tests add `ProbeFeed` and `DeadlineFeed`.
- Size as a layer: small, and with no dependency height of its own. It is a separate module because
  `MessageLogModule`, `FrameStatisticsModule` and `ReflectionModule` implement `Feed` without the 23
  exports of `EditorModule`; the kernel's rule "a layer holds exactly one module" then makes it a layer.
  A merge into `EditorModule` would widen the import of those three packages for four names. Keep it.
- How `editor/Feeds.jl` uses it: `Editor(...)` puts `InboxFeed()` first and calls
  `attach_wake_callback!` on every feed (`editor/Editor.jl:93-102`). `compute_wait_timeout` takes the
  smallest `compute_wake_deadline` (`editor/Feeds.jl:35-43`, called at `editor/EditorLoop.jl:166`
  outside any barrier). `drain_feeds!` calls `drain_changes!` on each feed in order, inside one
  `:evaluate` barrier (`editor/Feeds.jl:79-85`, `editor/EditorLoop.jl:179-181`).
- Public surface: 4 exported names, all used outside the kernel.
- State: none in the layer.
- Tests: `test/kernel/feed/FeedTest.jl` (16 assertions, all on the editor side), and
  `test/kernel/editor/WaitTest.jl` (deadlines), `test/projectured/editor/MessageLogFeedTest.jl`,
  `FrameStatisticsFeedTest.jl`, `test/shell/TooltipProbeTest.jl`,
  `test/projectured/projection/ToolViewTest.jl` for the concrete feeds.

## Summary

| category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 4 | 0 |
| State | 1 | 0 | 0 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 0 | 1 |

## Findings

### L21-1 The contract does not bind a feed to one editor, and the session feeds share a wake and a document among editors

- Category: State · Severity: High · Confidence: Confirmed (the effect with two editors is not run)
- Checked by the lead on 2026-09-27: Read the code: `MessageLogFeed()` and `FrameStatisticsFeed()` default to `get_session_message_log_store()` and `get_session_frame_statistics()`, which answer process constants.
- Where: [FeedInterface.jl:40-48](../../../source/kernel/feed/FeedInterface.jl#L40) ⬜;
  [MessageLogStore.jl:77-81](../../../source/log/MessageLogStore.jl#L77),
  [MessageLogFeed.jl:20-22](../../../source/log/MessageLogFeed.jl#L20),
  [FrameStatisticsFeed.jl:33-36](../../../source/statistics/FrameStatisticsFeed.jl#L33),
  [WindowChrome.jl:216](../../../source/shell/WindowChrome.jl#L216)
- Evidence: `attach_wake_callback!` says "Hand `feed` the wake function of its editor, once, at
  registration". It says nothing of a feed or a store that two editors register. `MessageLogFeed()`
  defaults to the process-global `_SESSION_MESSAGE_LOG_STORE` and `_SESSION_MESSAGE_LOG`, and the store
  keeps one wake (`store.wake = wake`). `FrameStatisticsFeed()` defaults to the process-global
  `_SESSION_FRAME_STATISTICS` and `_SESSION_FRAME_PLOT` (`FrameStatisticsDocument.jl:87, 159`).
  `run_with_window_tools` gives both feeds, with these defaults, to every editor that it runs. With two
  editors in one process:
  1. The second registration replaces the wake of the first. A log line wakes only the second editor;
     the first shows it after some unrelated input.
  2. Both editors drain the one store and write the one `MessageLog` from two editor tasks. So a task
     of one editor writes a document that the other editor shows.
  3. Each `FrameStatisticsFeed` flushes its own editor's frame measurements into the one table and
     plot, which then alternate between the numbers of the two editors.
- Rule: PAR-PER-EDITOR-STATE (the carve-out covers only a value that is the same for every editor);
  PAR-STORE-THEN-DRAIN ("Only the editor task writes a document a running editor shows").
- Fix: write in the contract whether one feed may serve two editors. Then either give the two feeds a
  store and a target per editor by default, or record the one session log as an accepted carve-out and
  let its store keep one wake per editor, with one editor that drains it.
- Reach: `FeedInterface.jl` (docstring); ProjecturedLog (`MessageLogStore.jl`, `MessageLogFeed.jl`);
  ProjecturedStatistics; ProjecturedShell (`WindowChrome.jl`).

### L21-2 One feed whose drain throws stops every feed after it

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [FeedInterface.jl:15-27](../../../source/kernel/feed/FeedInterface.jl#L15) ⬜;
  [Feeds.jl:79-85](../../../source/kernel/editor/Feeds.jl#L79) ⬜,
  [EditorLoop.jl:179-181](../../../source/kernel/editor/EditorLoop.jl#L179) ⬜ (layer 22)
- Evidence: `drain_feeds!` calls every `drain_changes!` inside one `_run_barrier(editor, :evaluate)`,
  with the default origin `:editor` (`editor/FaultBarriers.jl:15-19`). A drain that throws ends the
  loop, so the feeds after it do not drain in that frame. A feed that throws in every frame starves
  them in every frame. The fault store keeps one record per key, so the log shows one fault with the
  origin `:editor`, which does not name the feed. The inbox drains first: a posted operation that
  throws also stops the other queued operations and every other feed for that frame. The contract does
  not say what a drain that throws does.
- Rule: PAR-REPORT-NEVER-THROWS ("a barrier never swallows a fault in silence": the record does not say
  which feed failed, and the other feeds stop with no record).
- Fix: one barrier per feed in `drain_feeds!`, with `origin = typeof(feed)`. Write in the contract that
  a drain that throws is recorded and that the next feed still drains.
- Reach: `editor/Feeds.jl` (layer 22), `FeedInterface.jl` (docstring).

### L21-3 A deadline that throws ends the editor loop

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [FeedInterface.jl:29-38](../../../source/kernel/feed/FeedInterface.jl#L29) ⬜;
  [Feeds.jl:35-43](../../../source/kernel/editor/Feeds.jl#L35) ⬜,
  [EditorLoop.jl:165-168](../../../source/kernel/editor/EditorLoop.jl#L165) ⬜ (layer 22)
- Evidence: `run_editor!` calls `compute_wait_timeout(editor)` before each wait, outside every barrier,
  and `compute_wait_timeout` calls `compute_wake_deadline` on each feed. An exception there reaches the
  `catch` of `run_editor!`, which rethrows everything except `QuitEditorException`
  (EditorLoop.jl:189-190). So the loop ends and the backend quits. Concrete deadlines call code that
  the embedder gives: `TooltipFeed` calls `feed.now()` (`source/tooltip/TooltipRest.jl:82`). The
  contract does not say that a deadline must not throw.
- Rule: PAR-REPORT-NEVER-THROWS (one broken feed turns into a dead editor).
- Fix: call each `compute_wake_deadline` inside a barrier that answers `nothing` on a fault, or write
  in the contract that a deadline must not throw.
- Reach: `editor/Feeds.jl` (layer 22), `FeedInterface.jl` (docstring).

### L21-4 The inbox drain has no bound per frame

- Category: Correctness · Severity: Medium · Confidence: Suspected (needs a run with a producer on
  another thread that posts faster than the editor applies)
- Where: [FeedInterface.jl:18](../../../source/kernel/feed/FeedInterface.jl#L18) ⬜;
  [Inbox.jl:62-69](../../../source/kernel/editor/Inbox.jl#L62) ⬜ (layer 22)
- Evidence: the contract says "Move everything new". `drain_operations!` takes operations while
  `isready(editor.inbox)`. A producer on another thread that posts faster than `evaluate_operation`
  applies keeps the channel ready, so the drain does not end and the frame does not paint. The reader
  half of the same frame has a bound for this reason (`MAX_OPERATIONS_PER_FRAME = 32`,
  EditorLoop.jl:30-35); the inbox has none.
- Rule: bug (a loop with no bound).
- Fix: drain at most the count that was ready when the drain started, and write in the contract that a
  drain moves what the store held when the drain started.
- Reach: `editor/Inbox.jl` (layer 22), `FeedInterface.jl` (docstring).

### L21-5 A feed that posts from its drain can block the editor task on its own inbox

- Category: Correctness · Severity: Medium · Confidence: Suspected (needs a producer that fills the
  inbox between the inbox drain and the tooltip drain)
- Where: [FeedInterface.jl:21-22](../../../source/kernel/feed/FeedInterface.jl#L21) ⬜;
  [TooltipRest.jl:87-100](../../../source/tooltip/TooltipRest.jl#L87)
- Evidence: the contract says "A feed must not block". The drain of `TooltipFeed` reads a
  `PointerRest` through the projection and calls `post_operation!` (line 99). `post_operation!` blocks
  when `INBOX_CAPACITY` (64) operations wait (`editor/Inbox.jl:19-21`, `editor/Editor.jl:78`). The
  drain runs on the editor task, and only that task empties the inbox, so a full inbox at that moment
  blocks the editor on itself. The operation also waits one frame, because the inbox of this frame has
  already drained. The contract gives a drain no way to apply an operation without a block.
- Rule: the feed contract (`drain_changes!` docstring); PAR-STORE-THEN-DRAIN.
- Fix: a drain on the editor task applies its operation with `evaluate_operation(editor, operation)`;
  write in the contract that a drain applies an operation directly and never posts one.
- Reach: ProjecturedTooltip (`TooltipRest.jl`); `FeedInterface.jl` (docstring).

### L21-6 The contract text names consumers, gives feeds a will, and a guide states history

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [FeedModule.jl:11-13](../../../source/kernel/feed/FeedModule.jl#L11),
  [FeedModule.jl:20](../../../source/kernel/feed/FeedModule.jl#L20),
  [FeedInterface.jl:4](../../../source/kernel/feed/FeedInterface.jl#L4),
  [FeedInterface.jl:19-20](../../../source/kernel/feed/FeedInterface.jl#L19),
  [FeedInterface.jl:35-36](../../../source/kernel/feed/FeedInterface.jl#L35),
  [FeedInterface.jl:45-46](../../../source/kernel/feed/FeedInterface.jl#L45),
  [FeedDefaults.jl:2](../../../source/kernel/feed/FeedDefaults.jl#L2) ⬜;
  [Feeds.jl:21-22](../../../source/kernel/editor/Feeds.jl#L21) ⬜ (layer 22);
  `documentation/package/kernel/editor.md:186-195`
- Evidence:
  - PAR-NO-CONSUMER-DOCS: "the inbox feed in `EditorModule`, the message log feed in `ProjecturedLog`"
    (FeedModule.jl:11-13); "before `read!`" names a function of the editor layer (FeedInterface.jl:19-20);
    "as the frame measurement store does" (:35-36).
  - writing-rules.md "No personification": "the parts a feed may decline" (FeedInterface.jl:4,
    FeedModule.jl:20), "a feed whose producers never wake declines the callback" (:45-46), "the
    generics a feed may leave unanswered" (FeedDefaults.jl:2).
  - editor.md:186 "The concrete feeds so far" states a time and omits `TooltipFeed`
    (`source/tooltip/TooltipRest.jl:60`). editor.md:195 "The fault store predates the feeds" and
    Feeds.jl:21-22 "the cadence the polling loop had" state history.
- Rule: PAR-NO-CONSUMER-DOCS; writing-rules.md ("No personification", "The present state only");
  code-quality-rules.md §2.
- Fix: name the kinds ("a feed that holds a queue of operations", "the read step of a frame"); write
  "the default does nothing, for a feed whose producers never wake the editor"; add `TooltipFeed` to the
  table and drop "so far"; state the fault store and the tick cadence in the present tense.
- Reach: `FeedModule.jl`, `FeedInterface.jl`, `FeedDefaults.jl`, `editor/Feeds.jl`, editor.md.

### L21-7 The feed test tests the editor, and the edges of the contract have no test

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: `test/kernel/feed/FeedTest.jl`
- Evidence: the file defines `test_editor_feeds` and tests `InboxFeed`, `drain_feeds!`,
  `post_operation!`, `wake_editor!` and the fault wake, which are all in `editor/Feeds.jl`,
  `editor/Inbox.jl` and `editor/Editor.jl`. Its name names no file of the layer (naming-rules.md:
  `<Thing>Test.jl`, where `<Thing>` is the file it tests); it belongs beside
  `test/kernel/editor/InboxTest.jl` as `FeedsTest.jl`. No test covers a drain that throws (L21-2), a
  deadline that throws (L21-3), or a feed that two editors register (L21-1).
- Rule: naming-rules.md (test files); PAR-NEW-CODE-SHIPS-TESTS.
- Fix: move and rename the file; add the three cases.
- Reach: `test/kernel/feed/`, `test/kernel/editor/`, `package/ProjecturedKernelTest`.

## Accepted before, not raised again

- There is no prior audit of this layer.
- `FeedModule` is its own module and not a fragment of `EditorModule`, because "the contract names no
  editor": plan/done/the-editor-waits-for-events.md §3.1.
- The fault store is not a `Feed`, and it keeps its own wake (`attach_fault_wake!`) beside
  `attach_wake_callback!`: `run_frame!` reports it at its top so that a frame driven by hand also
  collects its faults (editor.md:195, the same plan §2.2).
- `drain_changes!` has no default on purpose, so a feed that can not drain raises a `MethodError`
  (FeedDefaults.jl:4-5, FeedInterface.jl:24-25).

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `FeedInterface.jl` holds one abstract type and three bodiless generics,
  all exported; the guard lists the file.
- code-quality-rules.md §1: one export statement, for the one fragment that defines names; the module
  is not on the list of modules that are not migrated in `test/suite/exports.jl`.
- PAR-PER-EDITOR-STATE and PAR-NO-PROJECTION-GLOBALS in the layer: no global, no `Ref`.
- PAR-LOWEST-PACKAGE and the layer order: the layer imports nothing, and every user sits above it.
- PAR-QUALIFIED-EXTENSION: every implementer imports exactly the generics it extends
  (`import ..FeedModule: drain_changes!, …`); `EditorModule` imports only `drain_changes!`.
- PAR-MODULE-BOUNDARY-IS-API: no code reaches a private name of `FeedModule`.
- Naming: `Feed`, `drain_changes!`, `compute_wake_deadline`, `attach_wake_callback!`; no history
  comment in the layer.
