# ProjecturEd

A Julia reimplementation of [ProjecturEd](https://github.com/projectured/projectured), a generic-purpose projectional editor. Documents are structured data (trees, ASTs, graphs) presented through bidirectional, composable projections; editing acts on the projection and is mapped back to the underlying domain.

## 🔒 Sealed files — DO NOT MODIFY

**Some files in this repository are *sealed*. A sealed file MUST NOT be modified by an AI in any way — no edits, no reformatting, no "while I'm here" cleanups, no incidental changes as part of a larger task — unless the user gives explicit permission for that specific file in the current conversation.** This overrides every other instruction, including a broad task that would otherwise touch a sealed file. If a change you are asked to make would require editing a sealed file, STOP and tell the user the file is sealed and ask for explicit permission before proceeding.

The list below is authoritative. It is the ordered inventory of the kernel main folder (`package/kernel/main/`), in the order the files are loaded, being reviewed and sealed one at a time. `🔒` = sealed, `⬜` = not yet sealed.

**Audit a file against [documentation/architecture-requirements.md](documentation/architecture-requirements.md) the moment you introduce it as the next file — before inviting review and before offering to seal.** Present the audit result first; never say "seal as-is" or ask whether to seal until the audit has been reported. A file is sealed only once it complies (or a specific non-compliance is explicitly accepted by the user in the conversation). If a violation is found in an already-sealed file, report it and ask permission before fixing (the seal still holds until permission is given).

### `package/kernel/main/` seal status

- 🔒 `ProjecturedKernel.jl` — module root, the layer diagram

The layer *numbers* below live only in this list and in `ProjecturedKernel.jl`'s
include order — the source files state their dependencies, never their index.

- **Layer 1 — cell** (`cell/`)
  - 🔒 `cell/CellLayer.jl`
  - 🔒 `cell/PerformanceCounter.jl`
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
- **Layer 2 — clock** (`clock/`)
  - 🔒 `clock/ClockLayer.jl`
  - 🔒 `clock/Clock.jl`
- **Layer 3 — event** (`event/`)
  - 🔒 `event/EventLayer.jl`
  - 🔒 `event/EventModule.jl`
  - 🔒 `event/EventInterface.jl`
  - 🔒 `event/ModifierKeys.jl`
  - 🔒 `event/KeyboardEvent.jl`
  - 🔒 `event/MouseEvent.jl`
  - 🔒 `event/WindowEvent.jl`
  - 🔒 `event/WindowInput.jl`
  - 🔒 `event/EventDefaults.jl`
  - 🔒 `event/EventPattern.jl`
- **Layer 4 — device** (`device/`)
  - 🔒 `device/DeviceLayer.jl`
  - 🔒 `device/DeviceModule.jl`
  - 🔒 `device/Device.jl`
  - 🔒 `device/Keyboard.jl`
  - 🔒 `device/Mouse.jl`
  - 🔒 `device/Display.jl`
- **Layer 5 — gesture** (`gesture/`)
  - 🔒 `gesture/GestureLayer.jl`
  - 🔒 `gesture/GestureRecognizer.jl`
- **Layer 6 — backend** (`backend/`)
  - 🔒 `backend/BackendLayer.jl`
  - 🔒 `backend/BackendModule.jl`
  - 🔒 `backend/BackendInterface.jl`
  - 🔒 `backend/BackendDefaults.jl`
- **Layer 7 — document** (`document/`)
  - 🔒 `document/DocumentLayer.jl`
  - ⬜ `document/DocumentModule.jl`
  - ⬜ `document/DocumentInterface.jl`
  - ⬜ `document/DocumentDefaults.jl`
  - ⬜ `document/DocumentCopy.jl`
  - ⬜ `document/DocumentSync.jl`
  - 🔒 `document/DocumentMacro.jl`
  - 🔒 `document/DocumentWalk.jl`
  - 🔒 `document/DocumentSearch.jl`
  - 🔒 `document/ForwardProtocol.jl`
- **Layer 8 — reference** (`reference/`)
  - 🔒 `reference/ReferenceLayer.jl`
  - ⬜ `reference/ReferenceModule.jl`
  - 🔒 `reference/ReferenceInterface.jl`
  - 🔒 `reference/ReferenceStep.jl`
  - 🔒 `reference/ReferencePath.jl`
  - 🔒 `reference/ReferenceEvaluation.jl`
  - 🔒 `reference/ReferenceSearch.jl`
  - 🔒 `reference/ReferenceSyntax.jl`
  - ⬜ `reference/ReferenceCase.jl`
  - ⬜ `reference/ReferenceRules.jl`
  - 🔒 `reference/ReferenceBuilder.jl`
- **Layer 9 — selection** (`selection/`)
  - 🔒 `selection/SelectionLayer.jl`
  - 🔒 `selection/SelectionModule.jl`
  - 🔒 `selection/SelectionInterface.jl`
  - 🔒 `selection/SelectionDefaults.jl`
- **Layer 10 — operation** (`operation/`)
  - ⬜ `operation/OperationLayer.jl`
  - ⬜ `operation/OperationModule.jl`
  - ⬜ `operation/Interface.jl`
  - ⬜ `operation/Operations.jl`
  - ⬜ `operation/Rerooting.jl`
- **Layer 11 — binding** (`binding/`)
  - ⬜ `binding/BindingLayer.jl`
  - ⬜ `binding/GestureBinding.jl`
  - ⬜ `binding/Gestures.jl`
- **Layer 12 — iomap** (`iomap/`)
  - 🔒 `iomap/IoMapLayer.jl`
  - 🔒 `iomap/IoMapModule.jl`
  - 🔒 `iomap/IoMapInterface.jl`
  - ⬜ `iomap/IoMapDefaults.jl`
  - ⬜ `iomap/IoMapReconcile.jl`
- **Layer 13 — projection** (`projection/`)
  - ⬜ `projection/ProjectionLayer.jl`
  - ⬜ `projection/ProjectionReferenceStep.jl`
  - ⬜ `projection/ProjectionApi.jl`
  - ⬜ `projection/Intent.jl`
  - ⬜ `projection/PrinterContext.jl`
  - ⬜ `projection/ChildrenContainer.jl`
  - ⬜ `projection/GestureBindings.jl`
  - ⬜ `projection/Projection.jl`
  - ⬜ `projection/ProjectionTemplate.jl`
- **Layer 14 — tool** (`tool/`)
  - ⬜ `tool/ToolLayer.jl`
  - ⬜ `tool/ToolModule.jl`
  - ⬜ `tool/Tool.jl`
  - ⬜ `tool/ToolSet.jl`
  - ⬜ `tool/CodeExecution.jl`
  - ⬜ `tool/Documentation.jl`
  - ⬜ `tool/DefaultTools.jl`
- **Layer 14 — llm** (`llm/`)
  - ⬜ `llm/LlmLayer.jl`
  - ⬜ `llm/LlmModule.jl`
  - ⬜ `llm/Llm.jl`
  - ⬜ `llm/LlmMessage.jl`
  - ⬜ `llm/LlmEvent.jl`
- **Layer 15 — agent** (`agent/`)
  - ⬜ `agent/AgentLayer.jl`
  - ⬜ `agent/AgentServer.jl`
  - ⬜ `agent/AgentModule.jl`
  - ⬜ `agent/Agent.jl`
  - ⬜ `agent/AgentLoop.jl`
- **Layer 16 — editor** (`editor/`)
  - ⬜ `editor/EditorLayer.jl`
  - ⬜ `editor/Editor.jl`
  - ⬜ `editor/Playback.jl`

When a file is sealed, flip its `⬜` to `🔒` in the same commit. Do not remove entries or reorder the list.

## Before working in this repo

Read the guides in [documentation/](documentation/) before making non-trivial changes. They explain the architecture, the reactive cell system, and the domain/projection/editor pipeline that the code assumes you understand. The division vocabulary (package / layer / slice / module) is defined in [documentation/terminology.md](documentation/terminology.md) — use those terms exactly.

The canonical reading order for contributors is in [README.md](README.md) under **"Building something? Read next"**. A quick summary:

1. [documentation/concepts.md](documentation/concepts.md) — plain-English conceptual guide (domain, document, selection, operation, projection). **Start here if you are new.**
2. [documentation/architecture.md](documentation/architecture.md) — the package chain, layer/slice structure, and module inventory.
3. [package/kernel/doc/cell.md](package/kernel/doc/cell.md) — the pull-based reactive cell system that powers incrementality.
4. [package/kernel/doc/macros.md](package/kernel/doc/macros.md) — `@document`, `@projection`, `@iomap`.
5. [package/kernel/doc/projection-system.md](package/kernel/doc/projection-system.md) — the four interface functions and the printer/reader pair.
6. [package/kernel/doc/editor.md](package/kernel/doc/editor.md) — the read-eval-print loop, event handling, and rendering pipeline.

Per-package reference guides live in each package's `doc/` directory next to the
code they document; the cross-cutting concept/architecture/tooling guides stay in
[documentation/](documentation/). When touching selection/reference handling or a
specific domain, also consult:

- [package/kernel/doc/reference.md](package/kernel/doc/reference.md) and [package/kernel/doc/selection.md](package/kernel/doc/selection.md) — how references and selections are represented and mapped through projections, with worked examples.
- Per-domain guides: [json](package/domain/doc/json.md), [xml](package/domain/doc/xml.md), [workbench](package/domain/doc/workbench.md), [versioning](package/domain/doc/versioning.md) (domain); [text](package/visual/doc/text.md), [syntax](package/visual/doc/syntax.md), [graphics](package/visual/doc/graphics.md), [widget](package/visual/doc/widget.md) (visual); [collection](package/base/doc/collection.md) and [bounded-sync](package/base/doc/bounded-sync.md) (base).

When iterating in the REPL or running the test suite:

- [documentation/debugging.md](documentation/debugging.md) — REPL debugging tips: `run_example`, `print_example`, `write_example_image`, driving the printer/reader by hand, and forcing reactive cells.
- [documentation/testing.md](documentation/testing.md) — testing tips: `test_all`, `test_printers`, `test_readers`, `test_position_navigations`, `test_repls`, and the walker helpers behind them.

## Conventions

- All indexing is 1-based (Julia convention).
- Projections must be bidirectional: every printer needs a matching reader, and the IO map is what makes the inversion possible.

## Testing a change

When you change something and want to verify it, run the **smallest test that covers the change** — do not blindly run `test_all`. It is slow and its output floods the context with tokens.

Pick the narrowest scope that exercises your change:

- A single example: `test_printer(json_example)`, `test_reader(json_example)`, `test_position_navigation(json_example)`, `test_repl(json_example)`, or `test_example(json_example)` for all three at once. Add `test_position_navigation(json_example; check_reaches_all=true)` to also assert navigation reaches every enumerated position.
- A single domain or pipeline stage: e.g. `test_json()`, `test_syntax()`, `test_json_to_syntax()`, `test_syntax_to_text()`.
- One main package's whole suite: `test_kernel()`, `test_base()`, `test_visual()`, `test_domain()` — each lives in its own test package (`package/kernel/test` … `package/domain/test`) that only depends on the main packages below it, so these also run in an environment without SDL/ODBC/Tulip installed (`julia --project=package/kernel/test`, etc.). Each includes its package's static layering guard (`test_kernel_layering()`, …).
- The reactive primitive only: `test_cell()`.
- Want errors back as a `Vector{String}` instead of `@testset` output (less noise, keeps going on failure): the walker helpers `walk_printer_output(doc, proj)`, `walk_repl_loop(doc, proj)`, `explore_position_selections(doc, proj)`.

Running `test_all()` is usually not needed — the targeted test above is enough to verify a change. Only reach for the per-package aggregators (`test_kernel()` / `test_base()` / `test_visual()` / `test_domain()`), the loop-over-every-example functions (`test_printers()` / `test_readers()` / `test_position_navigations()` / `test_repls()`), and rarely `test_all()` (which runs the four per-package suites plus the umbrella integration tests), when you specifically want a broad sweep after the targeted test already passes. See [documentation/testing.md](documentation/testing.md) for the full table of test functions and which package each one covers.

Always narrow down tests to the smallest reasonable scope — never default to `test_all()`, it is slow. Prefer single-example or single-domain test functions as described in the "Testing a change" section above.

**Reading the summary.** An unmarked `Fail` or `Error` is a regression from your change — do not need to bisect to know. Known-failing assertions are marked `@test_broken` and appear in the `Broken` column; only `Fail` / `Error` counts should be zero after a passing run. If the count of `Broken` changes, read the `# @broken:` comment on the marker: fewer broken means an assertion started passing (promote it to `@test`); more broken means a new marker was added. See the "Marking known-failing tests" section in [documentation/testing.md](documentation/testing.md).
