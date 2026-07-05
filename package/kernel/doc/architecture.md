# ProjecturedKernel — architecture

Contributor-facing guide to the **internal** structure of the `ProjecturedKernel`
package: its layers, what depends on what, and the conventions the code assumes.
For the whole-system picture (packages, backends, the projection pipeline) see the
repository-level [documentation/architecture.md](../../../documentation/architecture.md);
this document is **only about the kernel**.

## What the kernel is

`ProjecturedKernel` is the headless, domain-agnostic engine: the reactive cell
system, the reference/operation/IO-map machinery, the projection algebra
(higher-order combinators + generic projections), the input-device abstraction,
the editor read-eval-print loop, and the agent control surface. **No concrete
documents** live here — Collection / Primitive / ScreenDocument moved to the
`ProjecturedBase` package at plan phase P8. The kernel now has **zero
concrete-document imports**. **No backends** either (except the dependency-free
in-memory `HeadlessBackend` used by editor tests). **No runtime dependencies** —
`using ProjecturedKernel` precompiles and loads on its own.

## Layered structure (kernel plan P0–P10, 2026-07-05)

Kernel plan P0 through P10 restructured the package around a strict layered
architecture with per-layer guards, docs, and tests:

```
Layer 1 — cell/       cells + performance counter + the editor clock
Layer 2 — document/   the Document contract + @document + Cell-struct codegen
Layer 3 — reference/  reference paths + @reference / @reference_case DSLs
Layer 4 — operation/  Operation + evaluate_operation + R1 traversal + R2 reroot
Layer 5 — device/     Device/Modifiers/Keyboard/Mouse + GestureModule + EventEnvelope
Layer 6 — backend/    Backend + Display + HeadlessBackend
Layer 7 — projection/ ProjectionApi/IoMap/Intent/PrinterContext + 12 combinators
Layer 8 — agent/      Agent + Llm + ToolRegistry + Mcp (side-stack)
Layer 9 — editor/     the run_editor! loop + Playback
```

Every kernel file lives under a declared layer folder (`api/` and `common/`
still hold ProjectionApi/IoMapApi/Intent/IoMap/Projection.jl — the projection
consolidation is a deferred cosmetic pass). The **layered guard** in
[test/runtests.jl](../test/runtests.jl) statically parses `import ..XxxModule`
lines and asserts every dep points to the same or a lower layer; the plan
phase per-layer runners (`test/<layer>/`) exercise each layer against its
own tests, and can be filtered with
`Pkg.test("ProjecturedKernel"; test_args=["cell","projection"])`.

The package is one flat include list in [src/ProjecturedKernel.jl](../src/ProjecturedKernel.jl):
~50 files, each defining exactly one module. Those modules form a **single acyclic
dependency DAG**, machine-checked by the include-order guard (see below).

## Layer diagram — what depends on what

Grouped by role, top = highest level. **Every arrow points *down*: "depends on".**
The API-stub tier (B) is the cycle-breaker: implementation tiers depend downward
onto the abstract stubs, never up. The editor reaches the agent surface only
through the `AgentApiModule` *stub* (a `make_agent_server(:mcp, …)` factory seam), so
it does **not** depend on `Mcp`/`Llm` — which is why the agent surface hangs off to
the side.

```
   ┌──────────────────────────────────────────────────────────────┐
 H │  EDITOR      EditorModule  ·  ScreenDeviceModule(device)  ·          │  run_editor!/play_live!
   │              GestureRecognizerModule                           │
   └───┬───────────────────────────────┬─────────────────┬─────────┘
       │ (pulls in nearly every tier)  │                 │ via AgentApiModule stub
       │                               │                 ▼
       │                               │      ┌───────────────────────────┐
       │                               │    G │ AGENT SURFACE             │
       │                               │      │  ToolRegistry · Llm ·      │
       │                               │      │  Mcp(→ToolRegistry)        │  (independent
       │                               │      └───────────────────────────┘   side-stack)
       ▼                               ▼
   ┌──────────────────────────────────────────────────────────────┐
 F │  PROJECTION ALGEBRA + DEFAULTS   17 projection modules  +      │
   │  ProjectionModule (@projection, four-generic fallbacks)        │
   └───┬───────────────────────────┬──────────────────┬────────────┘
       │                           │                  │
       ▼                           ▼                  ▼
   ┌─────────────────────────┐ ┌──────────────────────────────────┐
 D │ FOUNDATIONAL DOCUMENTS  │ │ E  INPUT DEVICES & GESTURES       │
   │  Collection · Primitive │ │  Modifiers · Keyboard · Mouse ·   │
   │  · ScreenDocument       │ │  EventCase · GestureBinding       │
   └───────────┬─────────────┘ └───────────────┬──────────────────┘
               │                               │
               ▼                               ▼
   ┌──────────────────────────────────────────────────────────────┐
 C │  CORE DATA & REFERENCES                                        │
   │  Document · IoMap · Reference · Operation · OperationRerooting │
   │  · PrinterContext                                              │
   └───────────────────────────────┬──────────────────────────────┘
                                    ▼
   ┌──────────────────────────────────────────────────────────────┐
 B │  API STUBS (abstract types + `function foo end`)               │
   │  Projection · Operation · Document · IoMap ·                   │
   │  Backend · Device · Agent          ← the cycle-breaker         │
   └───────────────────────────────┬──────────────────────────────┘
                                    ▼
   ┌──────────────────────────────────────────────────────────────┐
 A │  REACTIVE ENGINE     PerformanceCounter → Reactive            │
   │  (reactive/, layer A — the DAG's dependency-free base)         │
   └──────────────────────────────────────────────────────────────┘
```

Four modules carry almost all the fan-in (a consolidation must keep them cheap to
import); everything else is depended on ≤7 times:

| Hub | Tier | Depended on by |
| --- | --- | --- |
| `ProjectionApiModule` | B | ~20 modules |
| `CellModule` | A | ~19 |
| `ReferenceModule` | C | ~17 |
| `IoMapApiModule` | B | ~12 |

## The API tier is the extension SPI

Tier B is not just an internal decoupling seam — it is the **service-provider
interface** a third party implements to extend ProjecturEd (a new `Backend`,
`Device`, agent server, domain `Document`, or `Projection`). It is kept **pure**:
abstract types + generic function *declarations* (`function f end`) + docstrings —
**no** concrete types, algorithms, factory registries, or mutable globals.
(Implementations that used to sit here now live in their impl modules: the
`splice_*` text helpers and default `evaluate_operation` methods in
`OperationModule`, and the concrete protocol data types `Intent` / `DoNothingOperation`
in `common/` — they are data vehicles that cross the seam, not interfaces to
implement.) The stateless factory seams `make_backend(kind)` /
`make_agent_server(kind)` are the one deliberate exception, kept as the SPI's own
registration entry. An interface is its functions, not just its type, so api
modules are expected to grow accessor/behaviour operations (e.g. the
`get_iomap_projection` / `get_iomap_input` / `get_iomap_output` accessors on `IoMapApiModule`).

## Load order and the include-order guard

The include list is a hand-maintained **topological sort**: every file appears
after the modules named in its `import ..XxxModule` headers. Julia enforces this
only implicitly (an out-of-order include throws `UndefVarError` deep in
precompilation), so [test/runtests.jl](../test/runtests.jl) enforces it
**statically, without loading the package** (~0.4 s): it parses each file's AST and
asserts every relative `..XxxModule` import resolves to a module defined by an
*earlier* include, plus that every source file is included exactly once and each
module is defined once. Run it with:

```
julia --project=package/kernel package/kernel/test/runtests.jl
```

Depth ≠ include index. Layering each module by its *longest path from a source*
(its earliest-safe position) gives roughly: **D0** sources (Reactive's
PerformanceCounter, Modifiers, ToolRegistry, Llm, the api stubs) → **D1** Device,
Document, IoMap, Reactive, Mcp → **D2** Keyboard, Mouse, Reference, EditorTime →
**D3** Collection, EventCase, Operation, Primitive, PrinterContext,
ReferenceCase/Builder → **D4** GestureBinding, OperationRerooting, ScreenDocument,
ProjectionModule + several generic projections → **D5** the remaining projections +
GestureRecognizer → **D6** Editor (deepest). The guard enforces only the real
constraint (every module precedes its users), not a specific linearization.

## Folder layout

The kernel is mid-migration from a `common/` grab-bag toward one folder per layer
(see [plan/pending/kernel-cleanup.md](../../../plan/pending/kernel-cleanup.md)).
Current shape:

| Folder | Holds |
| --- | --- |
| `reactive/` | the reactive engine layer — `Reactive` (Cell), `PerformanceCounter` (see [reactive.md](reactive.md)) |
| `api/` | the pure interface/SPI tier (tier B) |
| `reference/` | reference paths, `@reference`, `@reference_case` |
| `device/` | Modifiers, Keyboard, Mouse, EventCase, ScreenDevice |
| `document/` | Collection, Primitive, ScreenDocument (the engine's own vocabulary) |
| `common/` | remaining cross-layer impl (Intent, Document, IoMap, Operation, GestureBinding, Projection defaults) — being dissolved into per-layer folders |
| `projection/` | the projection algebra (`higherorder/`, `generic/`) |
| `editor/` | EditorTime (the animation clock), PrinterContext, GestureRecognizer, ToolRegistry, Llm, Mcp, Editor |

## How the kernel is consumed

`ProjecturedDomain` binds the kernel's submodules as `const XxxModule =
ProjecturedKernel.XxxModule` aliases so its files can use relative `..XxxModule`
imports; the `Projectured` umbrella mechanically re-exports every public name of
every kernel (and domain) submodule into one flat namespace. Consequently **module
names are de-facto public API** — renaming one ripples into the domain alias block
and the umbrella. New sub-modules extracted within a layer (as `PerformanceCounter`
/ `EditorTime` / `Intent` were) are picked up by the umbrella automatically and
need only an added domain alias if a domain file imports from them directly.
