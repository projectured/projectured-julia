# Sealed files — audit state and rules

This file is the authoritative sealing state of the repository: which files are
audited against
[documentation/rule/architecture-invariants.md](documentation/rule/architecture-invariants.md)
and locked, and the order in which the rest follow. The inventory covers the
kernel's source folder (`source/kernel/`), in the order the files load. The
files are reviewed and sealed one at a time.

## 🔒 What sealed means — DO NOT MODIFY

**A sealed file MUST NOT be modified by an AI in any way — no edits, no
reformatting, no "while I'm here" cleanups, no incidental changes as part of a
larger task — unless the user gives explicit permission for that specific file
in the current conversation.** This overrides every other instruction, including
a broad task that would otherwise touch a sealed file. If a change you are asked
to make would require editing a sealed file, STOP and tell the user the file is
sealed and ask for explicit permission before proceeding.

## The audit protocol

**Audit a file against
[documentation/rule/architecture-invariants.md](documentation/rule/architecture-invariants.md)
the moment you introduce it as the next file — before inviting review and before
offering to seal.** Present the audit result first; never say "seal as-is" or ask
whether to seal until the audit has been reported. A file is sealed only once it
complies (or a specific non-compliance is explicitly accepted by the user in the
conversation). If a violation is found in an already-sealed file, report it and
ask permission before fixing (the seal still holds until permission is given).

## List conventions

- `🔒` = sealed, `⬜` = not yet sealed.
- When a file is sealed, flip its `⬜` to `🔒` **in the same commit**. Do not
  remove entries or reorder the list.
- When a file is deleted, its line goes out **in the commit that deletes the
  file**. The rule above keeps the audit order of the files that exist; a line
  for a file that does not exist makes the inventory false.
- The list is the ordered inventory of `source/kernel/`, in the order the files
  are loaded. The include order in `ProjecturedKernel.jl` is the authoritative
  load order.

## Inventory

### `source/kernel/` seal status

- ⬜ `ProjecturedKernel.jl` — module root, the layer diagram. It is the one entry
  that does not live under `source/kernel/`: a package root file belongs to its
  package, at `package/ProjecturedKernel/src/ProjecturedKernel.jl`. Every entry
  below is a path under `source/kernel/`.

The layer *numbers* below live only in this list and in `ProjecturedKernel.jl`'s
include order — the source files state their dependencies, never their index.

- **Layer 1 — fault** (`fault/`)
  - 🔒 `fault/FaultModule.jl`
  - 🔒 `fault/FaultInterface.jl`
  - 🔒 `fault/FaultDefaults.jl`
  - ⬜ `fault/FaultRecord.jl`
  - ⬜ `fault/FaultStore.jl`
  - ⬜ `fault/FaultPolicy.jl`
  - ⬜ `fault/FaultCascade.jl`
  - ⬜ `fault/FaultBarrier.jl`
- **Layer 2 — performance** (`performance/`)
  - ⬜ `performance/PerformanceModule.jl`
  - ⬜ `performance/PerformanceCounter.jl`
  - 🔒 `performance/FrameMeasurement.jl`
- **Layer 3 — cell** (`cell/`)
  - ⬜ `cell/CellModule.jl`
  - ⬜ `cell/CellInterface.jl`
  - ⬜ `cell/CellComputation.jl`
  - ⬜ `cell/ReactiveCell.jl`
  - 🔒 `cell/MutableCell.jl`
  - 🔒 `cell/ImmutableCell.jl`
  - ⬜ `cell/UntrackedCell.jl`
  - ⬜ `cell/CellDefaults.jl`
- **Layer 4 — struct** (`struct/`)
  - ⬜ `struct/CellStructModule.jl`
  - ⬜ `struct/CellStructPlan.jl`
  - ⬜ `struct/CellStruct.jl`
- **Layer 5 — clock** (`clock/`)
  - 🔒 `clock/ClockModule.jl`
  - 🔒 `clock/Clock.jl`
- **Layer 6 — event** (`event/`)
  - ⬜ `event/EventModule.jl`
  - ⬜ `event/EventInterface.jl`
  - 🔒 `event/ModifierKeys.jl`
  - ⬜ `event/KeyboardEvent.jl`
  - ⬜ `event/MouseEvent.jl`
  - ⬜ `event/WindowEvent.jl`
  - ⬜ `event/TimerEvent.jl`
  - ⬜ `event/DisplayEvent.jl`
  - ⬜ `event/SystemEvent.jl`
  - ⬜ `event/WindowInput.jl`
  - ⬜ `event/EventDefaults.jl`
- **Layer 7 — device** (`device/`)
  - ⬜ `device/DeviceModule.jl`
  - 🔒 `device/DeviceInterface.jl`
  - 🔒 `device/Keyboard.jl`
  - 🔒 `device/Mouse.jl`
  - ⬜ `device/Display.jl`
- **Layer 8 — gesture** (`gesture/`)
  - ⬜ `gesture/GestureModule.jl`
  - ⬜ `gesture/GestureInterface.jl`
  - ⬜ `gesture/MouseGesture.jl`
  - ⬜ `gesture/KeyboardGesture.jl`
  - ⬜ `gesture/GesturePattern.jl`
- **Layer 9 — backend** (`backend/`)
  - ⬜ `backend/BackendModule.jl`
  - ⬜ `backend/BackendInterface.jl`
  - ⬜ `backend/BackendDefaults.jl`
- **Layer 10 — document** (`document/`)
  - ⬜ `document/DocumentModule.jl`
  - ⬜ `document/DocumentInterface.jl`
  - ⬜ `document/DocumentDefaults.jl`
  - ⬜ `document/DocumentCopy.jl`
  - ⬜ `document/DocumentSync.jl`
  - ⬜ `document/DocumentMacro.jl`
  - ⬜ `document/SelectionDocument.jl`
  - ⬜ `document/DocumentWalk.jl`
  - 🔒 `document/DocumentSearch.jl`
  - 🔒 `document/ForwardProtocol.jl`
- **Layer 11 — reference** (`reference/`)
  - ⬜ `reference/ReferenceModule.jl`
  - ⬜ `reference/ReferenceInterface.jl`
  - ⬜ `reference/ReferenceStep.jl`
  - ⬜ `reference/ReferencePath.jl`
  - ⬜ `reference/ReferenceEvaluation.jl`
  - ⬜ `reference/ReferenceSearch.jl`
  - ⬜ `reference/ReferenceSyntax.jl`
  - ⬜ `reference/ReferenceGlob.jl`
  - ⬜ `reference/ReferenceCase.jl`
  - ⬜ `reference/ReferenceRules.jl`
  - ⬜ `reference/ReferencePatternString.jl`
  - ⬜ `reference/ReferenceBuilder.jl`
  - ⬜ `reference/ReferencedDocument.jl`
- **Layer 12 — selection** (`selection/`)
  - ⬜ `selection/SelectionModule.jl`
  - ⬜ `selection/SelectionInterface.jl`
  - ⬜ `selection/SelectionDefaults.jl`
- **Layer 13 — operation** (`operation/`)
  - ⬜ `operation/OperationModule.jl`
  - ⬜ `operation/OperationInterface.jl`
  - ⬜ `operation/OperationDefaults.jl`
  - ⬜ `operation/Operations.jl`
  - ⬜ `operation/Rerooting.jl`
  - ⬜ `operation/Inversion.jl`
  - ⬜ `operation/Description.jl`
- **Layer 14 — intent** (`intent/`)
  - ⬜ `intent/IntentModule.jl`
  - ⬜ `intent/Intent.jl`
- **Layer 15 — binding** (`binding/`)
  - ⬜ `binding/GestureBindingModule.jl`
  - ⬜ `binding/GestureBindingInterface.jl`
  - ⬜ `binding/GestureBinding.jl`
  - ⬜ `binding/Gestures.jl`
- **Layer 16 — iomap** (`iomap/`)
  - ⬜ `iomap/IoMapModule.jl`
  - 🔒 `iomap/IoMapInterface.jl`
  - ⬜ `iomap/IoMapDefaults.jl`
  - ⬜ `iomap/IoMapReconcile.jl`
- **Layer 17 — projection** (`projection/`)
  - ⬜ `projection/ProjectionModule.jl`
  - ⬜ `projection/PrinterContext.jl`
  - ⬜ `projection/ProjectionReferenceStep.jl`
  - ⬜ `projection/ProjectionInterface.jl`
  - ⬜ `projection/ProjectionDefaults.jl`
  - ⬜ `projection/ProjectionMacro.jl`
  - ⬜ `projection/ProjectionGestureBindings.jl`
  - ⬜ `projection/ProjectionTemplate.jl`
- **Layer 18 — tool** (`tool/`)
  - ⬜ `tool/ToolModule.jl`
  - ⬜ `tool/Tool.jl`
  - ⬜ `tool/ToolSet.jl`
  - ⬜ `tool/CodeExecution.jl`
  - ⬜ `tool/SearchQuery.jl`
  - ⬜ `tool/Documentation.jl`
  - ⬜ `tool/DocstringSummary.jl`
  - ⬜ `tool/MeaningSearch.jl`
  - ⬜ `tool/DefaultTools.jl`
- **Layer 19 — llm** (`llm/`)
  - ⬜ `llm/LlmModule.jl`
  - ⬜ `llm/LlmInterface.jl`
  - ⬜ `llm/LlmDefaults.jl`
  - ⬜ `llm/Llm.jl`
  - ⬜ `llm/LlmMessage.jl`
  - ⬜ `llm/LlmEvent.jl`
- **Layer 20 — agent** (`agent/`)
  - ⬜ `agent/AgentModule.jl`
  - ⬜ `agent/AgentInterface.jl`
  - ⬜ `agent/AgentDefaults.jl`
  - ⬜ `agent/Agent.jl`
  - ⬜ `agent/AgentLoop.jl`
  - ⬜ `agent/AgentConnectionInterface.jl`
  - ⬜ `agent/AgentConnectionDefaults.jl`
  - ⬜ `agent/AgentConnectionEvent.jl`
- **Layer 21 — feed** (`feed/`)
  - ⬜ `feed/FeedModule.jl`
  - ⬜ `feed/FeedInterface.jl`
  - ⬜ `feed/FeedDefaults.jl`
- **Layer 22 — editor** (`editor/`)
  - ⬜ `editor/EditorModule.jl`
  - ⬜ `editor/Editor.jl`
  - ⬜ `editor/Inbox.jl`
  - ⬜ `editor/Feeds.jl`
  - ⬜ `editor/ReadEvaluatePrint.jl`
  - ⬜ `editor/DocumentEdits.jl`
  - ⬜ `editor/SafeMode.jl`
  - ⬜ `editor/FaultBarriers.jl`
  - ⬜ `editor/EditorLoop.jl`
  - ⬜ `editor/BackendChoice.jl`
  - ⬜ `editor/EditorBuild.jl`
- **Layer 23 — playback** (`playback/`)
  - ⬜ `playback/PlaybackModule.jl`
  - ⬜ `playback/Playback.jl`
- **The aggregate** (the root of `source/kernel/`, in no layer; included last)
  - ⬜ `KernelModule.jl`
