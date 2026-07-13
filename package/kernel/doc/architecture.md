# ProjecturedKernel — architecture

Contributor-facing guide to the **internal** structure of the `ProjecturedKernel`
package: its layers, what depends on what, and the conventions the code assumes.
For the whole-system picture (packages, backends, the projection pipeline) see the
repository-level [documentation/architecture.md](../../../documentation/architecture.md);
this document is **only about the kernel**.

## What the kernel is

`ProjecturedKernel` is the headless, domain-agnostic engine: the reactive cell
system, the reference/operation/IO-map machinery, the projection *interface and
infrastructure* (the four generic functions, the IO maps, the `@projection`
macro, the projection-template engine, gesture bindings), the input-device
abstraction, the editor read-eval-print loop, and the agent control surface.
**No concrete projections** live here — the domain-independent projection
algebra (higher-order combinators + generic projections) lives in the
`ProjecturedBase` package. **No concrete documents** either — Collection and
Primitive live in `ProjecturedBase`, and ScreenDocument in `ProjecturedVisual`.
The kernel now has **zero concrete-document imports**. **No backends** either (except the dependency-free
in-memory `HeadlessBackend` used by editor tests). **No runtime dependencies** —
`using ProjecturedKernel` precompiles and loads on its own.

## Layered structure

The package is organized around a strict layered architecture with per-layer
guards, docs, and tests:

```
Layer 1  — cell/       the Cell kinds + @cell_struct codegen + performance counters
Layer 2  — document/   the Document contract + @document + the editor clock
Layer 3  — reference/  reference paths + @reference / @reference_case DSLs
Layer 4  — selection/  the selection primitives (get/clear/set/replace_selection!) — a document's current-focus state, a reference stored on a document
Layer 5  — operation/  Operation + evaluate_operation + the traversal and reroot seams
Layer 6  — device/     Device/Modifiers/Keyboard/Mouse + GestureModule + EventEnvelope
Layer 7  — backend/    Backend + Display + HeadlessBackend
Layer 8  — projection/ ProjectionApi/IoMap/Intent/PrinterContext + @projection macro + ProjectionTemplate + gesture bindings (the concrete combinators live in ProjecturedBase)
Layer 9  — agent/      Agent + Llm + ToolRegistry + Mcp (side-stack)
Layer 10 — editor/     the run_editor! loop + Playback
```

Every kernel file lives under a declared layer folder. The **layered guard** in
[test/runtests.jl](../test/runtests.jl) statically parses `import ..XxxModule`
lines and asserts every dep points to the same or a lower layer; the
per-layer runners (`test/<layer>/`) exercise each layer against its
own tests, and can be filtered with
`Pkg.test("ProjecturedKernel"; test_args=["cell","projection"])`.

The package file [main/ProjecturedKernel.jl](../main/ProjecturedKernel.jl) includes
one **layer fragment per layer folder** (`cell/CellLayer.jl`, …,
`editor/EditorLayer.jl`), bottom-to-top; each layer fragment holds its layer's
ordered include list (~50 module files total, each defining exactly one module).
Those modules form a **single acyclic dependency DAG**, machine-checked by the
include-order guard (see below).

## Dependency diagram — what depends on what

**The ten layers *are* the dependency diagram.** A layer imports only layers below
it, and that is the whole rule — the static guard enforces exactly it, so there is
no second grouping to learn. What the plain stack does not show is the two places
the shape is more interesting than "N depends on N−1":

**The interface files are the cycle-breaker.** Each layer opens with its contract:
`document/Interface.jl` (the `Document` supertype), `reference/Interface.jl` (the
`ReferenceStep` / `ReferencePath` types and the step seam), `selection/Interface.jl`,
`operation/Interface.jl` (`Operation` + `evaluate_operation`), and the projection
layer's `ProjectionApi.jl` / `IoMapApi.jl`. These hold abstract types plus open
generic *declarations* (`function f end`) and nothing else. A higher layer — or a
higher *package* — extends them by adding methods at its own definition site, so a
lower layer never names its implementors and no cycle is needed. `ReferenceStep` is
the clearest case: `ProjectionReference` (layer 8), `PointReference` and
`TextRectangularReference` (both in `ProjecturedVisual`) all subtype it and register
their navigation through `evaluate_step`, with no edit to layer 3.

**The agent surface is a side-stack.** The editor (layer 10) reaches it only through
the factory seam `make_agent_server(:mcp, editor)` declared in `agent/Agent.jl`
(`AgentModule`), so the editor does **not** depend on `Mcp` / `Llm`. The real
transports are the opt-in `package/mcp/` and `package/llm/`, which register their
method on load.

**Fan-in.** Counting `import ..XxxModule` lines across the kernel's own files, the
hubs — the modules a consolidation must keep cheap to import — are:

| Hub | Layer | Imported by |
| --- | --- | --- |
| `DocumentModule` | 2 | 11 kernel files |
| `ReferenceModule` | 3 | 10 |
| `CellModule` | 1 | 10 |
| `OperationModule` | 5 | 9 |
| `KeyboardModule` | 6 | 7 |
| `ProjectionApiModule` | 8 | 6 |

## The interface files are the extension SPI

The per-layer interface files are not just an internal decoupling seam — together
they are the **service-provider interface** a third party implements to extend
ProjecturEd (a new `Backend`, `Device`, agent server, domain `Document`,
`ReferenceStep`, or `Projection`). They are kept **pure**:
abstract types + generic function *declarations* (`function f end`) + docstrings —
**no** concrete types, algorithms, factory registries, or mutable globals.
(Implementations live in their own impl modules: the
`splice_*` text helpers and default `evaluate_operation` methods in
`OperationModule`, and the concrete protocol data types `Intent` / `DoNothingOperation`
— they are data vehicles that cross the seam, not interfaces to
implement.) The stateless factory seam `make_agent_server(kind)` is the one
deliberate exception, kept as the SPI's own registration entry. Backends need no
such seam: they construct by naming the type directly (`SdlBackend()`) or via
`default_backend`'s reflection. An interface is its functions,
not just its type, so interface
files are expected to grow accessor/behaviour operations (e.g. the
`get_iomap_projection` / `get_iomap_input` / `get_iomap_output` accessors on `IoMapApiModule`).

## Load order and the include-order guard

The include tree — the layer fragments in order, and each fragment's own include
list — is a hand-maintained **topological sort**: every file appears after the
modules named in its `import ..XxxModule` headers. Julia enforces this
only implicitly (an out-of-order include throws `UndefVarError` deep in
precompilation), so [test/runtests.jl](../test/runtests.jl) enforces it
**statically, without loading the package** (~0.4 s): it parses each file's AST and
asserts every relative `..XxxModule` import resolves to a module defined by an
*earlier* include, plus that every source file is included exactly once and each
module is defined once. Run it with:

```
julia --project=package/kernel/test package/kernel/test/runtests.jl
```

Depth ≠ include index. A module's *earliest safe position* is its longest path from
a dependency-free source, and that is not the same as where it sits in the include
list: `PerformanceCounterModule`, `ModifiersModule`, `ToolRegistryModule` and the
interface files are sources (they import nothing), while `EditorModule` is deepest
— it pulls in nearly every layer. The guard enforces only the real constraint
(every module precedes its users), not one specific linearization, so a file may
legitimately sit later in the list than its depth requires.

## Folder layout

Each layer lives in its own folder under [main/](../main/):

| Folder | Holds |
| --- | --- |
| `cell/` | the reactive engine — `AbstractCell` and the `ReactiveCell` / `MutableCell` / `ImmutableCell` kinds, `@cell_struct`, `PerformanceCounter` (see [cell.md](cell.md)) |
| `document/` | the Document contract (`Interface.jl` + `Document.jl` + `Forward.jl`) and the editor clock (`Clock.jl`) |
| `reference/` | the step/path contract (`Interface.jl`), the step and path types, the value protocol, `search_references`, and the `@reference` / `@step` / `@reference_case` DSLs |
| `selection/` | the selection primitives — `get_selection`, `clear_selection!`, `set_selection!`, `with_selection`, `replace_selection!` |
| `operation/` | the Operation contract, the built-in operations, rerooting |
| `device/` | Modifiers, Keyboard, Mouse, `GestureModule` (EventCase + GestureBinding), GestureRecognizer, ScreenDevice, Device |
| `backend/` | Backend, Display, HeadlessBackend |
| `projection/` | the projection interface and infrastructure only — ProjectionApi, IoMapApi, Intent, IoMap, PrinterContext, ChildrenContainer, GestureBindings, Projection (`@projection` + fallbacks), ProjectionTemplate. The concrete `higherorder/` and `generic/` combinators moved to `ProjecturedBase`. |
| `agent/` | Agent, Llm, ToolRegistry, Mcp |
| `editor/` | Editor (the `run_editor!` loop), Playback |

## How the kernel is consumed

`ProjecturedDomain` binds the kernel's submodules as `const XxxModule =
ProjecturedKernel.XxxModule` aliases so its files can use relative `..XxxModule`
imports; the `Projectured` umbrella mechanically re-exports every public name of
every kernel (and domain) submodule into one flat namespace. Consequently **module
names are de-facto public API** — renaming one ripples into the domain alias block
and the umbrella. A new sub-module added within a layer (as `PerformanceCounterModule`
and `IntentModule` are) is picked up by the umbrella automatically and
needs only an added domain alias if a domain file imports from it directly.
