# ProjecturedKernel — architecture

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Contributor-facing guide to the **internal** structure of the `ProjecturedKernel`
package: its layers, what depends on what, and the conventions the code assumes.
For the whole-system picture (packages, backends, the projection pipeline) see the
repository-level [documentation/design/system-anatomy.md](../../design/system-anatomy.md);
this document is **only about the kernel**.

## What the kernel is

`ProjecturedKernel` is the headless, domain-agnostic engine: the reactive cell
system, the reference/operation/IO-map machinery, the projection *interface and
infrastructure* (the four generic functions, the IO maps, the `@projection`
macro, the projection-template engine, gesture bindings), the input-device
abstraction, the editor read-eval-print loop, and the agent control surface.
**No concrete projections** live here — the domain-independent projection
algebra (higher-order combinators + generic projections) lives in the
platform. **No concrete documents** either — Collection and Primitive live in
the platform's collection and primitive slices, and ScreenDocument in its
screen slice.
The kernel has **zero concrete-document imports**. **No backends** either —
the dependency-free in-memory `HeadlessBackend` test double lives in
`ProjecturedKernelExample`, not here. **No runtime dependencies** —
`using ProjecturedKernel` precompiles and loads on its own.

## Layered structure

The package is organized around a strict layered architecture with per-layer
guards, docs, and tests. [system-anatomy.md](../../design/system-anatomy.md#the-23-kernel-layers)
carries the same 23 layers as a repository-wide table; this list adds the
per-layer key types and files a kernel contributor needs:

```
Layer 1  — fault/       the fault record, the store, the barrier and the report — what lets the editor survive a failure; it names no document and no projection
Layer 2  — performance/ the performance counters and the frame measurements of an editor
Layer 3  — cell/        the Cell kinds — ReactiveCell/MutableCell/ImmutableCell, Computation and @computation
Layer 4  — struct/      @cell_struct and the builders of a struct of cells (CellStructPlan)
Layer 5  — clock/       the animation clock — Clock (a @cell_struct), get_reactive_clock_time/get_clock_time, set_clock_time!, start_wall_clock!/stop_wall_clock!
Layer 6  — event/       the input events (Event, ModifierKeys, KeyDown/KeyPress/Mouse*/Window*) + WindowInput
Layer 7  — device/      Device abstract + the Keyboard/Mouse/Display devices (physical properties)
Layer 8  — gesture/     the gestures (Gesture, MouseClick/MouseDwell/KeyChord), the pattern language (GesturePattern, @gesture_case) and the recognitions (GestureRecognition, ChordRecognition/ClickRecognition/DwellRecognition)
Layer 9  — backend/     Backend + the device I/O, display-size, and device-config seams
Layer 10 — document/    the Document contract + @document
Layer 11 — reference/   reference paths + @reference / @reference_case DSLs
Layer 12 — selection/   the selection primitives (get/clear/set/replace_selection!) — a document's current-focus state, a reference stored on a document
Layer 13 — operation/   Operation + evaluate_operation + the traversal and reroot seams
Layer 14 — intent/      Intent and ClaimedGesture, the unit that flows back through the readers, and CollectIntents
Layer 15 — binding/     gesture → operation bindings, @gestures/@gesture_set, read_gesture
Layer 16 — iomap/       the IoMap contract (IoMap + accessors) + the concrete IO maps (SimpleIoMap/ChildrenIoMap/ContentIoMap, @iomap) + the child reconcilers (make_reconciled_child_iomaps_cell/make_reconciled_child_iomap_cell)
Layer 17 — projection/  ProjectionInterface/PrinterContext + @projection macro + ProjectionTemplate + the projection-typed gesture-binding seam (the concrete combinators live in the platform's projection slice)
Layer 18 — tool/        the editor's capability surface — Tool/Resource/ToolSet, execute_julia_code!, doc/API search, register_default_tools! (side-stack)
Layer 19 — llm/         the LLM provider abstraction — Llm, stream_turn/render_tool_schema, LlmMessage/LlmRequest, LlmEvent (side-stack)
Layer 20 — agent/       the AI control surface — AgentModule, with the inbound MCP seam and the outbound Agent and run_turn! loop (side-stack)
Layer 21 — feed/        the feed contract — a registered inflow that the editor moves into a target document once per frame
Layer 22 — editor/      the run_editor! loop — run_read_stage!, run_evaluate_stage!, run_print_stage! and the frame
Layer 23 — playback/    scripted live playback — a timeline that fires in the editor loop on a wall-clock schedule
```

Every kernel file lives under a declared layer folder. The **layered guard** in
[test/runtests.jl](../../../package/ProjecturedKernelTest/runtests.jl) statically parses `import ..XxxModule`
lines and asserts every dep points to the same or a lower layer; the
per-layer runners (`test/<layer>/`) exercise each layer against its
own tests, and can be filtered with
`Pkg.test("ProjecturedKernel"; test_args=["cell","projection"])`.

The package file [package/ProjecturedKernel/src/ProjecturedKernel.jl](../../../package/ProjecturedKernel/src/ProjecturedKernel.jl) includes
one **module file per layer** (`fault/FaultModule.jl`, …,
`playback/PlaybackModule.jl`), bottom-to-top, so the root reads as the layer
diagram; each module file carries its own ordered fragment include list. The
modules form a **single acyclic dependency DAG**, machine-checked by the
include-order guard (see below).

## Dependency diagram — what depends on what

**The twenty-three layers *are* the dependency diagram.** A layer imports only layers below
it. That is the whole rule, and the static guard enforces it exactly, so there is
no second grouping to learn. What the plain stack does not show is the two places
the shape is more interesting than "N depends on N−1":

**The interface files are the cycle-breaker.** Each layer opens with its contract:
`document/DocumentInterface.jl` (the `Document` supertype), `reference/ReferenceInterface.jl` (the
`ReferenceStep` / `Reference` types and the step seam), `selection/SelectionInterface.jl`,
`operation/OperationInterface.jl` (`Operation` + `evaluate_operation`), the iomap layer's
`IoMapInterface.jl`, and the projection layer's `ProjectionInterface.jl`. These hold abstract types plus open
generic *declarations* (`function f end`) and nothing else. A higher layer, or a
higher *package*, extends them by adding methods at its own definition site, so a
lower layer never names its implementors and no cycle is needed. `ReferenceStep` is
the clearest case: `ProjectionReferenceStep` (layer 17), `PointReferenceStep`, and the
text-selection siblings `TextRangeReferenceStep`/`TextColumnReferenceStep`/`TextSpanReferenceStep`
(all in the platform) subtype it and register
their navigation through `evaluate_reference_step`, with no edit to layer 11.

**The agent stack is a side-stack.** The editor (layer 22) reaches it only through
the factory seam `make_agent_server(:mcp, editor)` declared in
`agent/AgentInterface.jl` (`AgentModule`), so the editor does **not** depend on
`ProjecturedMCP`, `ProjecturedAnthropic` or `ProjecturedOllama`. These opt-in
packages hold the real transports, and they register their methods on load.

**Fan-in.** A count of the kernel module files that name a module in a
`using ..XxxModule` or `import ..XxxModule` line identifies the hubs. These are the
modules a consolidation must keep cheap to import:

| Hub | Layer | Imported by |
| --- | --- | --- |
| `CellModule` | 3 | 9 kernel module files |
| `EventModule` | 6 | 5 |
| `DocumentModule` | 10 | 7 |
| `ReferenceModule` | 11 | 6 |
| `OperationModule` | 13 | 4 |
| `ProjectionModule` | 17 | 2 |

## The interface files are the extension SPI

The per-layer interface files are not just an internal decoupling seam. Together
they are the **service-provider interface** that a third party implements to extend
ProjecturEd: a new `Backend`, `Device`, agent server, domain `Document`,
`ReferenceStep`, or `Projection`. They are kept **pure**:
abstract types + generic function *declarations* (`function f end`) + docstrings.
They hold **no** concrete types, algorithms, factory registries, or mutable globals.
Implementations live in their own impl modules: the
`splice_*` text helpers and default `evaluate_operation` methods in
`OperationModule`, and the concrete protocol data types `Intent` / `DoNothingOperation`.
These are data vehicles that cross the seam, not interfaces to
implement. The stateless factory seam `make_agent_server(kind)` is the one
deliberate exception, kept as the SPI's own registration entry. Backends need no
such seam: they construct by naming the type directly (`SdlBackend()`) or via
`default_backend`'s reflection. An interface is its functions,
not just its type, so interface
files grow accessor/behaviour operations over time (e.g. the
`get_iomap_projection` / `get_iomap_input` / `get_iomap_output` accessors on `IoMapModule`).

## Load order and the include-order guard

The include tree is a hand-maintained **topological sort**: the layer fragments run
in order, each with its own include list, and every file appears after the
modules named in its `import ..XxxModule` headers. Julia enforces this
only implicitly: an out-of-order include throws `UndefVarError` deep in
precompilation. So [test/runtests.jl](../../../package/ProjecturedKernelTest/runtests.jl) enforces it
**statically, without loading the package** (~0.4 s). It parses each file's AST and
asserts that every relative `..XxxModule` import resolves to a module defined by an
*earlier* include, that every source file is included exactly once, and that each
module is defined once. Run it with:

```
julia --project=package/ProjecturedKernelTest package/ProjecturedKernelTest/runtests.jl
```

Depth ≠ include index. A module's *earliest safe position* is its longest path from
a dependency-free source, and that is not the same as where it sits in the include
list: `PerformanceModule`, `EventModule`, `ToolModule` and the
interface files are sources (they import nothing), while `EditorModule` is deepest.
It pulls in nearly every layer. The guard enforces only the real constraint
(every module precedes its users), not one specific linearization, so a file may
legitimately sit later in the list than its depth requires.

## Folder layout

Each layer lives in its own folder under [source/kernel/](../../../source/kernel/):

| Folder | Holds |
| --- | --- |
| `fault/` | `FaultModule` — the fault record, the store, the policy, the barrier and the report (see [fault.md](../platform/fault/fault.md)) |
| `performance/` | `PerformanceModule` — the per-frame performance counters and the frame measurement store of an editor, `FrameMeasurementStore` (see [cell.md](cell.md)) |
| `cell/` | the reactive engine — `AbstractCell` and the `ReactiveCell` / `MutableCell` / `ImmutableCell` kinds (see [cell.md](cell.md)) |
| `struct/` | `CellStructModule` — `@cell_struct` and the builders of a struct of cells (see [cell.md](cell.md)) |
| `clock/` | `ClockModule` — the animation `Clock` (a `@cell_struct`), `get_reactive_clock_time`/`get_clock_time`/`set_clock_time!`, and `start_wall_clock!`/`stop_wall_clock!`, the heartbeat that writes real time into a clock |
| `event/` | `EventModule` — the input event vocabulary (Event, ModifierKeys, KeyDown/KeyUp/KeyPress, Mouse*, Window*, TimerExpire, DisplayUpdate, SystemColors, SystemColorsChange, WindowInput) |
| `device/` | `DeviceModule` — the `Device`, `Keyboard`, `Mouse`, `Display` device types (with physical properties) |
| `gesture/` | `GestureModule` — the gestures (`MouseClick`, `MouseDwell`, `KeyChord`), the pattern language (`GesturePattern`, `@gesture_case`) and the recognitions (`GestureRecognition`, `ChordRecognition`, `ClickRecognition`, `DwellRecognition`) |
| `backend/` | `Backend`, the device I/O + display-size + device-config seams |
| `document/` | the Document contract (`DocumentInterface.jl`), the `@document` codegen (`DocumentMacro.jl`), the value protocol (`DocumentCopy.jl` / `DocumentSync.jl`), the reflection walk (`DocumentWalk.jl` / `DocumentSearch.jl`), and the protocol forward/adapt helpers (`ForwardProtocol.jl`) |
| `reference/` | the step/path contract (`ReferenceInterface.jl`), the step and path types, the value protocol, `search_references`, and the `@reference` / `@reference_step` / `@reference_case` DSLs |
| `selection/` | the selection primitives — `get_selection`, `clear_selection!`, `set_selection!`, `replace_selection!` |
| `operation/` | the Operation contract, the built-in operations, rerooting |
| `intent/` | `IntentModule` — `Intent` and `ClaimedGesture`, the unit that flows back through the readers, and `CollectIntents` |
| `binding/` | `GestureBindingModule` — `GestureBinding`, the per-document-type registry, `@gestures`/`@gesture_set`, `read_gesture`/`read_bound_gesture` |
| `iomap/` | `IoMapModule` — the `IoMap` contract (`IoMapInterface.jl`), the concrete IO maps (`IoMapDefaults.jl`: `SimpleIoMap`, `ChildrenIoMap`, `ContentIoMap`, `@iomap`), and the child reconcilers (`IoMapReconcile.jl`: `make_reconciled_child_iomaps_cell`, `make_reconciled_child_iomap_cell`) |
| `projection/` | the projection interface and infrastructure only — `ProjectionInterface`, `PrinterContext`, `GestureBindings`, `Projection` (`@projection` + fallbacks), `ProjectionTemplate`. The concrete `higherorder/` and `generic/` combinators live in the platform's projection slice. |
| `tool/` | `ToolModule` — Tool, Resource, ToolSet, `execute_julia_code!`, doc/API search, `register_default_tools!` |
| `llm/` | `LlmModule` — Llm, `stream_turn`/`render_tool_schema`, LlmMessage/LlmRequest, LlmEvent |
| `agent/` | `AgentModule` — the inbound contract (`make/start/stop_agent_server!`, `run_on_editor_task!`) and the outbound Agent and `run_turn!` |
| `feed/` | `FeedModule` — the feed contract: a registered inflow that the editor moves into a target document once per frame |
| `editor/` | Editor (the `run_editor!` loop) |
| `playback/` | `PlaybackModule` — scripted live playback of a timeline in the editor loop |

## How the kernel is consumed

A domain package binds the kernel's submodules as `const XxxModule =
ProjecturedKernel.XxxModule` aliases, so its files can use relative `..XxxModule`
imports. `ProjecturedAll` mechanically re-exports every public name of every
kernel and platform submodule, the console, the PDF backend and every domain
into one flat namespace. The `Projectured` umbrella re-exports only the twelve
names of the platform's essentials slice (`ProjecturedPlatform.EssentialsModule`);
see [essentials.md](../platform/essentials/essentials.md). Consequently,
**module names are de-facto public API**: renaming one ripples into the domain
alias block and `ProjecturedAll`'s flat namespace. The module of a new layer,
such as `PerformanceModule` or `IntentModule`, is picked up by `ProjecturedAll`
automatically and needs only an added domain alias if a domain file imports
from it directly.
