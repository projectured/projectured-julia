# One module per layer

> **Kind:** plan · **Status:** pending · **Written:** 2026-09-20
> **Stands on:** [system-anatomy.md](../../documentation/design/system-anatomy.md),
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [the-editor-waits-for-events.md](../done/the-editor-waits-for-events.md)

Make every kernel layer hold exactly one module, and delete the `*Layer.jl`
indirection files. The root then includes the 23 module files directly, reads
as the layer diagram, and the layer/module duplication is gone.

## 1. What the kernel is today

Eighteen layers, twenty-six modules. Each layer folder holds a `<Stem>Layer.jl`
fragment — its ordered include list — and the sealed root includes the
eighteen layer files. Thirteen of the layer files hold exactly one include:
pure indirection. Five layers hold several modules:

| layer | modules | inner order |
| --- | --- | --- |
| cell | `PerformanceCounterModule`, `CellModule`, `CellStructModule` | counters < engine < codegen |
| event | `EventModule`, `EventPatternModule` | vocabulary < pattern language |
| operation | `OperationModule`, `IntentModule` | edits < the reader carrier |
| agent | `AgentServerModule`, `AgentModule` | server seam ‖ agent loop |
| editor | `FeedModule`, `FrameSampleModule`, `EditorModule`, `PlaybackModule` | contracts < loop < playback |

The layer files earn their place only as the unsealed growth joint of a
sealed root. With one module per layer the root line **is** the layer, growth
becomes an explicit sealed edit, and the joint is not needed.

## 2. The rule, and the decisions

Merge two sibling modules when they are one concept. Give a module its own
layer when it is a concept of its own. The user took the decisions:

- **Split cell into three**: performance < cell < struct. The engine counts
  into the counters (`ReactiveCell` records), so performance sits below cell.
- **Merge event**: the pattern language is the event vocabulary's own query
  form. `EventPatternModule` becomes the fragment `EventPattern.jl` of
  `EventModule`.
- **Split operation into two**: operation < intent. `Intent` is its own
  vocabulary word, `GestureBindingModule` reads it, and it has 52 external
  users — the split costs zero imports.
- **Merge agent**: `AgentServerModule` becomes the fragment `AgentServer.jl`
  of `AgentModule`.
- **Split editor into four concepts**, of which one moves down: feed,
  editor and playback become layers; frame-sample merges into performance
  (section 3).
- **Folder names**: the counter layer folder is `performance`, the cell-struct
  layer folder is `struct`.

## 3. Frame-sample merges into performance

Both modules are what the editor measures about itself: the counters a frame
binds, and the folded summaries of frames. Both import nothing above `Base`,
so the merged module sits legally below cell — the sample store touches no
cell by design. `EditorModule` then imports one measurement module instead of
two, and the statistics feed reads one namespace.

The counter-argument, recorded: the two stores have different lifecycles —
the counter store is frame-scoped, the sample store lives with its editor.
The fragment boundary inside one module is what expresses that:
`PerformanceCounter.jl` and `FrameSample.jl` stay separate files.

The merged module is named **`PerformanceModule`** — `PerformanceCounterModule`
would be too narrow once it holds the samples. The rename churn is about
seven files, all unsealed.

## 4. The new order — 23 layers, 23 modules

| # | folder | module | action |
| --- | --- | --- | --- |
| 1 | `fault` | `FaultModule` | keep |
| 2 | `performance` | `PerformanceModule` | **merge + rename**: fragments `PerformanceCounter.jl` (was `PerformanceCounterModule.jl` 🔒) and `FrameSample.jl` (was `FrameSampleModule.jl`) |
| 3 | `cell` | `CellModule` | keep; loses two siblings |
| 4 | `struct` | `CellStructModule` | **move** `CellStructModule.jl`, `CellStructPlan.jl`, `CellStruct.jl` (all 🔒) from `cell/` |
| 5 | `clock` | `ClockModule` | keep |
| 6 | `event` | `EventModule` | **merge**: `EventPattern.jl` fragment (both files 🔒) |
| 7 | `device` | `DeviceModule` | keep |
| 8 | `gesture` | `GestureRecognizerModule` | keep |
| 9 | `backend` | `BackendModule` | keep |
| 10 | `document` | `DocumentModule` | keep |
| 11 | `reference` | `ReferenceModule` | keep |
| 12 | `selection` | `SelectionModule` | keep |
| 13 | `operation` | `OperationModule` | keep; loses intent |
| 14 | `intent` | `IntentModule` | **move** from `operation/` |
| 15 | `binding` | `GestureBindingModule` | keep |
| 16 | `iomap` | `IoMapModule` | keep |
| 17 | `projection` | `ProjectionModule` | keep |
| 18 | `tool` | `ToolModule` | keep |
| 19 | `llm` | `LlmModule` | keep |
| 20 | `agent` | `AgentModule` | **merge**: `AgentServer.jl` fragment (both ⬜) |
| 21 | `feed` | `FeedModule` | **move** `FeedModule.jl`, `FeedInterface.jl`, `FeedDefaults.jl` from `editor/` |
| 22 | `editor` | `EditorModule` | keep; loses three siblings |
| 23 | `playback` | `PlaybackModule` | **move** from `editor/` |

Every ordering constraint holds: performance < cell (the engine counts),
struct < clock (`Clock` is a `@cell_struct`), operation < intent < binding
(the binder reads intents), agent < editor (the loop starts the server),
feed < editor < playback. The current include order is already this
topological order, so the change is mechanical.

The root includes the 23 module files directly, one line per layer, with the
layer comment each line carries today. All 18 `*Layer.jl` files are deleted.

## 5. The churn

- **The splits cost zero imports.** `IntentModule`, `CellStructModule`,
  `FeedModule` and `PlaybackModule` keep their names; only their paths move.
- **The event merge** touches ~42 files: 39 external and 3 kernel files
  (`binding/Gestures.jl`, `binding/GestureBindingModule.jl`,
  `projection/ProjectionModule.jl` — all ⬜) rename their
  `EventPatternModule` reference to `EventModule`; `EventModule` gains the
  include and the pattern exports.
- **The agent merge** touches ~6 files, `ProjecturedMcp` and `EditorModule`
  among them.
- **The performance merge** touches ~7 files: `CellModule`'s and
  `EditorModule`'s imports, the `ProjecturedStatistics` alias, the tests,
  and the suite lists.
- **Registrations**: the layering guard's `layers` list becomes the 23
  folders; `SEALING.md` renumbers its inventory and drops the layer-file
  rows; the root comment's "eighteen" becomes "twenty-three";
  [system-anatomy.md](../../documentation/design/system-anatomy.md) follows;
  the test tree mirrors the moves (`test/kernel/performance/`,
  `test/kernel/struct/`, `test/kernel/feed/`, with
  `FrameSampleTest.jl` and `PerformanceCounterTest.jl` under performance).

## 6. The sealed gate

One gate, before any edit. Show the user, for acceptance:

1. The exact new include list of `package/ProjecturedKernel/src/ProjecturedKernel.jl` 🔒.
2. The deletion list: the 18 `*Layer.jl` files, of which 10 are sealed
   (cell, clock, event, device, gesture, backend, document, reference,
   selection, iomap).
3. The sealed moves: the `struct` trio, unchanged in content.
4. The sealed merge edits: `EventModule.jl` (one include, the pattern
   exports) and `EventPatternModule.jl` → `EventPattern.jl` (the module head
   and its imports stripped, nothing else).
5. The sealed rename-and-strip: `PerformanceCounterModule.jl` →
   `performance/PerformanceCounter.jl`.

Every file stays marked 🔒 in the inventory and joins the re-audit backlog,
beside the three backend files of the previous plan.

## 7. The phases

### Phase 1 — The gate ✅ (2026-09-20)

Prepare the five diffs of section 6, show them, and get acceptance. No edit
before it.

### Phase 2 — The splits and the root ✅ (2026-09-20)

One commit, because the tree only loads whole: move the four split groups
into their folders (`struct/`, `intent/`, `feed/`, `playback/`), rewrite the
root include list, delete the 18 layer files, update the layering guard's
folder list and `SEALING.md`. Run `test_kernel_layering()` and
`test_kernel()`.

### Phase 3 — Merge event ✅ (2026-09-20)

Strip `EventPattern.jl`'s module head, include it from `EventModule`, merge
the exports, sweep the ~42 `EventPatternModule` references (the rename tool
first, then the grep sweep for module-qualified references, docstrings and
package aliases). Run `test_kernel()` and one domain suite that uses
`@event_case`.

### Phase 4 — Merge agent ✅ (2026-09-20)

The same motion for `AgentServer.jl` into `AgentModule`; sweep ~6 files.
Run the agent seam and MCP tests.

### Phase 5 — Merge performance ✅ (2026-09-20)

Fold `PerformanceCounter.jl` and `FrameSample.jl` under `PerformanceModule`;
sweep ~7 files; move the two test files. Run `test_cell()`,
`test_frame_samples()` and the statistics feed test.

### Phase 6 — Sweeps and guards ✅ (2026-09-20)

`Pkg.precompile()` over `environment/all` and **read the warnings** — a
missing imported binding warns and still exits 0. Run the export-collision
and package-graph guards, and grep the repository for the three dead module
names.

### Phase 7 — Documentation ✅ (2026-09-20)

Update [system-anatomy.md](../../documentation/design/system-anatomy.md),
the root comment, [editor.md](../../documentation/package/kernel/editor.md)
(the feed table names `PerformanceModule`), and add the two-sentence
statement of the rule — one layer, one module, the root is the diagram — to
system-anatomy.

### How the phases landed (2026-09-20)

The tree only loads whole, and a merge and its reference sweep must land
together, so phases 2 to 6 landed as **one commit**; the phases above were
the checklist inside it, and the documentation followed as its own commit.
Facts the execution added:

- The gate was shown in full and the user accepted it.
- The strips ran by script: each module docstring became the fragment's
  header comment, and nothing else in the four stripped files changed.
- The sweep converted 57 files and left three duplicate `using` lines
  (projection, binding, editor) and two self-referential "mirror image"
  sentences in the agent files — all five fixed by hand.
- Verification: the layering guard passes with the 23 folders; the kernel
  suite sits exactly at the pre-existing baseline (3 failures, 3 errors);
  export-collision, package-graph and documentation guards at baseline; the
  event-pattern, gesture-binding, console, message-log-feed,
  frame-statistics-feed, SDL-wait and fault-store suites all green; the
  world precompiles with one pre-existing warning (`test_focusing`, an
  import that is byte-identical on `main`).

## 8. The hazards, and what stops each

| hazard | what stops it |
| --- | --- |
| a module-qualified reference (`Foo.EventPatternModule.x`) survives the rename tool | the grep sweep of Phase 3, and the precompile-warnings read of Phase 6 |
| an export collision appears when two export lists merge | the export-collision guard; the three merges add no overlapping names today |
| `struct` as a folder name collides with the keyword | it never becomes an identifier: folders appear only as strings in includes and in the guard's list |
| the umbrella loses the dead module aliases and outside scripts break | the three names are swept inside the repository; outside users are release notes, and this is pre-release |
| the root rewrite and the layer-file deletions land apart and the tree does not load | Phase 2 is one commit |
| a sealed file changes beyond what was accepted | the gate shows the five diffs file by file, and the commits touch nothing else sealed |

## 9. The decisions taken, and the ones that are open

**Taken.**

- 23 layers, one module each; the `*Layer.jl` files are deleted; the sealed
  root's include list is the layer diagram.
- Folder names `performance` and `struct` (the user's), and `intent`,
  `feed`, `playback` for the other splits.
- The merged modules keep the plain names `EventModule` and `AgentModule`;
  the measurement module becomes `PerformanceModule`; `CellStructModule`
  keeps its name — the macro it defines is `@cell_struct`, and its 16 users
  stay untouched.
- Frame-sample merges into performance (section 3).
- The growth rule after this plan: a new kernel module is a new layer and
  one line in the sealed root — an explicit gate, by design.

**Open.**

- None. The gate of Phase 1 is the remaining approval.
