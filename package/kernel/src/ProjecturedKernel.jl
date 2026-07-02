"""
    ProjecturedKernel

The headless, domain-agnostic engine of ProjecturEd: the reactive cell system,
the reference/operation/IO-map machinery, the projection algebra (higher-order
combinators + generic projections), the input-device abstraction, the editor
read-eval-print loop, and the agent control surface (LLM/MCP). It carries the
foundational document *vocabulary* (`CollectionModule`, `PrimitiveModule`,
`ScreenDocumentModule`) that the engine itself depends on, but no concrete
domains (JSON/XML/Text/Syntax/Widget/...), no backends, and **no heavy
dependencies** — `using ProjecturedKernel` precompiles and loads on its own.
The real LLM/MCP transports are standalone opt-in packages (`ProjecturedLlm`
in `package/llm`, `ProjecturedMcp` in `package/mcp`) that depend on this
package; the kernel carries only their dependency-free seams.

The concrete domains live in `ProjecturedDomain`; the flat public API is
re-exported by the `Projectured` umbrella.
"""
module ProjecturedKernel

# The include list is a hand-maintained topological sort: every file appears
# after the modules named in its `import ..XxxModule` headers. The sections
# below group the files by architectural layer; within a section, order still
# obeys those dependency edges. Only ProjectionApiModule (api/Projection.jl) is
# structurally load-bearing among the api stubs.

# ── Reactive engine (layer 0 — the DAG's dependency-free base) ─────────────
# PerformanceCounter (leaf) before Reactive, which bumps its `_perf` on the hot path.
include("reactive/PerformanceCounter.jl")
include("reactive/Reactive.jl")

# ── API — abstract types + `function foo end` stubs ────────────────────────
# Independent interface-only modules. Change (the reader-side protocol type) is a
# leaf that the projection readers import, so it precedes Projection.
include("api/Backend.jl")
include("api/Device.jl")
include("api/Change.jl")
include("api/Projection.jl")
include("api/Operation.jl")
include("api/Document.jl")
include("api/IoMap.jl")
include("api/Agent.jl")

# ── Document core & references ──────────────────────────────────────────────
# Reactive-backed Document/IoMap, the reference machinery, operations, and the
# foundational document vocabulary (Collection, Primitive) the engine depends
# on. OperationRerooting needs Operation + Primitive, so it closes the section.
include("common/Document.jl")
include("common/IoMap.jl")
include("reference/Reference.jl")
include("reference/ReferenceCase.jl")
include("reference/ReferenceBuilder.jl")
include("common/Operation.jl")
include("document/Collection.jl")
include("document/Primitive.jl")
include("common/OperationRerooting.jl")

# ── Input devices & events ─────────────────────────────────────────────────
# Keyboard/Mouse need Modifiers + the Device stub; EventCase (the `@event_case`
# pattern parser) needs the event types. These must precede GestureBinding.
include("device/Modifiers.jl")
include("device/Keyboard.jl")
include("device/Mouse.jl")
include("device/EventCase.jl")

# ── Foundational documents (projection output vocabulary) ──────────────────
# ScreenDocument needs Collection; it is consumed by the window/envelope
# higher-order projections, GestureRecognizer, and the editor loop.
include("document/ScreenDocument.jl")

# ── Gestures ───────────────────────────────────────────────────────────────
# GestureBinding reuses EventCase's parser and needs the devices + the
# Document/Projection api stubs; several projections attach gestures through it.
include("common/GestureBinding.jl")

# ── Projection infrastructure & algebra ────────────────────────────────────
# PrinterContext (Reactive + Reference only) is projection-layer infrastructure
# consumed by ProjectionModule and the generic projections, so it leads here.
# Then the higher-order combinators and the generic projections; Preserving
# precedes Reversing/Sorting, which build on it.
include("editor/PrinterContext.jl")
include("projection/higherorder/Sequential.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Alternative.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/WindowManager.jl")
include("projection/higherorder/EnvelopeUnwrapping.jl")
include("projection/generic/Preserving.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Filtering.jl")
include("projection/generic/Searching.jl")
include("projection/generic/Sorting.jl")
include("projection/generic/Copying.jl")
include("projection/generic/Invariably.jl")
include("projection/generic/Focusing.jl")

# ── Projection defaults & the `@projection` macro ──────────────────────────
# ProjectionModule holds the four-generic fallbacks and the `@projection`
# macro. Nothing in the kernel imports it, so it loads after the whole algebra;
# it needs Primitive, ReferenceCase/Builder, PrinterContext, Keyboard, Mouse.
include("common/Projection.jl")

# ── Agent surface ──────────────────────────────────────────────────────────
# Dependency-free agent seams. Llm and ToolRegistry have no kernel imports; Mcp
# needs only ToolRegistry. The real LLM/MCP transports are the opt-in
# `ProjecturedLlm` (package/llm) and `ProjecturedMcp` (package/mcp) packages;
# these files hold only the dependency-free client seam and editor tools.
include("editor/Llm.jl")
include("editor/ToolRegistry.jl")
include("editor/Mcp.jl")

# ── Editor ─────────────────────────────────────────────────────────────────
# The read-eval-print loop and its immediate dependencies: the animation clock
# (built on Cell, advanced once per frame), the Screen device, and the gesture
# recognizer (which needs ScreenDocument). Editor pulls in nearly every layer above.
include("editor/EditorTime.jl")
include("device/ScreenDevice.jl")
include("editor/GestureRecognizer.jl")
include("editor/Editor.jl")

end # module ProjecturedKernel
