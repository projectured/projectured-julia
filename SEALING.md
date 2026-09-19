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
- The list is the ordered inventory of `source/kernel/`, in the order the files
  are loaded. The include order in `ProjecturedKernel.jl` is the authoritative
  load order.

## Inventory

### `source/kernel/` seal status

- 🔒 `ProjecturedKernel.jl` — module root, the layer diagram. It is the one entry
  that does not live under `source/kernel/`: a package root file belongs to its
  package, at `package/ProjecturedKernel/src/ProjecturedKernel.jl`. Every entry
  below is a path under `source/kernel/`.

The layer *numbers* below live only in this list and in `ProjecturedKernel.jl`'s
include order — the source files state their dependencies, never their index.

- **Layer 1 — fault** (`fault/`)
  - ⬜ `fault/FaultLayer.jl`
  - ⬜ `fault/FaultModule.jl`
  - ⬜ `fault/FaultInterface.jl`
  - ⬜ `fault/FaultDefaults.jl`
  - ⬜ `fault/FaultRecord.jl`
  - ⬜ `fault/FaultStore.jl`
  - ⬜ `fault/FaultPolicy.jl`
  - ⬜ `fault/FaultCascade.jl`
  - ⬜ `fault/FaultBarrier.jl`

- **Layer 2 — cell** (`cell/`)
  - 🔒 `cell/CellLayer.jl`
  - 🔒 `cell/PerformanceCounterModule.jl`
  - ⬜ `cell/CellModule.jl`
  - 🔒 `cell/CellInterface.jl`
  - ⬜ `cell/CellComputed.jl`
  - ⬜ `cell/ReactiveCell.jl`
  - 🔒 `cell/MutableCell.jl`
  - 🔒 `cell/ImmutableCell.jl`
  - ⬜ `cell/CellDefaults.jl`
  - 🔒 `cell/CellStructModule.jl`
  - 🔒 `cell/CellStructPlan.jl`
  - 🔒 `cell/CellStruct.jl`
- **Layer 3 — clock** (`clock/`)
  - 🔒 `clock/ClockLayer.jl`
  - 🔒 `clock/ClockModule.jl`
- **Layer 4 — event** (`event/`)
  - 🔒 `event/EventLayer.jl`
  - 🔒 `event/EventModule.jl`
  - 🔒 `event/EventInterface.jl`
  - 🔒 `event/ModifierKeys.jl`
  - 🔒 `event/KeyboardEvent.jl`
  - 🔒 `event/MouseEvent.jl`
  - 🔒 `event/WindowEvent.jl`
  - 🔒 `event/WindowInput.jl`
  - 🔒 `event/EventDefaults.jl`
  - 🔒 `event/EventPatternModule.jl`
- **Layer 5 — device** (`device/`)
  - 🔒 `device/DeviceLayer.jl`
  - 🔒 `device/DeviceModule.jl`
  - 🔒 `device/Device.jl`
  - 🔒 `device/Keyboard.jl`
  - 🔒 `device/Mouse.jl`
  - 🔒 `device/Display.jl`
- **Layer 6 — gesture** (`gesture/`)
  - 🔒 `gesture/GestureLayer.jl`
  - 🔒 `gesture/GestureRecognizerModule.jl`
- **Layer 7 — backend** (`backend/`)
  - 🔒 `backend/BackendLayer.jl`
  - 🔒 `backend/BackendModule.jl`
  - 🔒 `backend/BackendInterface.jl`
  - 🔒 `backend/BackendDefaults.jl`
- **Layer 8 — document** (`document/`)
  - 🔒 `document/DocumentLayer.jl`
  - ⬜ `document/DocumentModule.jl`
  - ⬜ `document/DocumentInterface.jl`
  - ⬜ `document/DocumentDefaults.jl`
  - ⬜ `document/DocumentCopy.jl`
  - ⬜ `document/DocumentSync.jl`
  - ⬜ `document/DocumentMacro.jl`
  - ⬜ `document/SelectionDocument.jl`
  - 🔒 `document/DocumentWalk.jl`
  - 🔒 `document/DocumentSearch.jl`
  - 🔒 `document/ForwardProtocol.jl`
- **Layer 9 — reference** (`reference/`)
  - 🔒 `reference/ReferenceLayer.jl`
  - ⬜ `reference/ReferenceModule.jl`
  - 🔒 `reference/ReferenceInterface.jl`
  - ⬜ `reference/ReferenceStep.jl` (unsealed 2026-08-24: `@cell_struct` → `@document [C, M]`, the user's direction — re-audit before resealing)
  - ⬜ `reference/ReferencePath.jl` (unsealed 2026-09-14: `head` and `tail`
    become `get_reference_head` and `get_reference_tail` and are exported, the
    user's direction — re-audit before resealing)
  - ⬜ `reference/ReferenceEvaluation.jl`
  - 🔒 `reference/ReferenceSearch.jl`
  - ⬜ `reference/ReferenceSyntax.jl` (unsealed 2026-09-12: `xs[i, j]` counts
    elements, 1-based and inclusive, the user's direction — re-audit before
    resealing)
  - ⬜ `reference/ReferenceGlob.jl`
  - ⬜ `reference/ReferenceCase.jl`
  - ⬜ `reference/ReferenceRules.jl`
  - ⬜ `reference/ReferencePatternString.jl`
  - ⬜ `reference/ReferenceBuilder.jl`
- **Layer 10 — selection** (`selection/`)
  - 🔒 `selection/SelectionLayer.jl`
  - 🔒 `selection/SelectionModule.jl`
  - 🔒 `selection/SelectionInterface.jl`
  - 🔒 `selection/SelectionDefaults.jl`
- **Layer 11 — operation** (`operation/`)
  - ⬜ `operation/OperationLayer.jl`
  - ⬜ `operation/OperationModule.jl`
  - ⬜ `operation/Interface.jl`
  - ⬜ `operation/Operations.jl`
  - ⬜ `operation/Rerooting.jl`
  - ⬜ `operation/Inversion.jl`
  - ⬜ `operation/Description.jl`
  - ⬜ `operation/IntentModule.jl`
- **Layer 12 — binding** (`binding/`)
  - ⬜ `binding/BindingLayer.jl`
  - ⬜ `binding/GestureBindingModule.jl`
  - ⬜ `binding/GestureBinding.jl`
  - ⬜ `binding/Gestures.jl`
- **Layer 13 — iomap** (`iomap/`)
  - 🔒 `iomap/IoMapLayer.jl`
  - 🔒 `iomap/IoMapModule.jl`
  - 🔒 `iomap/IoMapInterface.jl`
  - ⬜ `iomap/IoMapDefaults.jl`
  - ⬜ `iomap/IoMapReconcile.jl`
- **Layer 14 — projection** (`projection/`)
  - ⬜ `projection/ProjectionLayer.jl`
  - ⬜ `projection/ProjectionModule.jl`
  - ⬜ `projection/ChildrenContainer.jl`
  - ⬜ `projection/PrinterContext.jl`
  - ⬜ `projection/ProjectionReferenceStep.jl`
  - ⬜ `projection/ProjectionInterface.jl`
  - ⬜ `projection/ProjectionDefaults.jl`
  - ⬜ `projection/ProjectionMacro.jl`
  - ⬜ `projection/GestureBindings.jl`
  - ⬜ `projection/ProjectionTemplate.jl`
- **Layer 15 — tool** (`tool/`)
  - ⬜ `tool/ToolLayer.jl`
  - ⬜ `tool/ToolModule.jl`
  - ⬜ `tool/Tool.jl`
  - ⬜ `tool/ToolSet.jl`
  - ⬜ `tool/CodeExecution.jl`
  - ⬜ `tool/SearchQuery.jl`
  - ⬜ `tool/Documentation.jl`
  - ⬜ `tool/MeaningSearch.jl`
  - ⬜ `tool/DefaultTools.jl`
- **Layer 16 — llm** (`llm/`)
  - ⬜ `llm/LlmLayer.jl`
  - ⬜ `llm/LlmModule.jl`
  - ⬜ `llm/Llm.jl`
  - ⬜ `llm/LlmMessage.jl`
  - ⬜ `llm/LlmEvent.jl`
- **Layer 17 — agent** (`agent/`)
  - ⬜ `agent/AgentLayer.jl`
  - ⬜ `agent/AgentServerModule.jl`
  - ⬜ `agent/AgentModule.jl`
  - ⬜ `agent/Agent.jl`
  - ⬜ `agent/AgentLoop.jl`
- **Layer 18 — editor** (`editor/`)
  - ⬜ `editor/EditorLayer.jl`
  - ⬜ `editor/EditorModule.jl`
  - ⬜ `editor/PlaybackModule.jl`
