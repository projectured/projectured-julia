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
# obeys those dependency edges. Only ProjectionApiModule (api/ProjectionApi.jl) is
# structurally load-bearing among the api stubs.

# ── Cell layer (layer 1 — the DAG's dependency-free base) ──────────────────
# PerformanceCounter (leaf) before the cells, whose reactive kind bumps its
# `_perf` on the hot path. CellModule is the aggregator; it includes the base
# type and the three kind files (AbstractCell/ReactiveCell/MutableCell/ImmutableCell).
# Time is the one global animation clock, a single `Cell` built on the engine
# above — it belongs beside cells (P1), not with the editor loop that drives it.
include("cell/PerformanceCounter.jl")
include("cell/CellModule.jl")
include("cell/Time.jl")

# ── API — abstract types + `function foo end` stubs ────────────────────────
# Remaining interface modules (Document/Operation/Backend/Device/Projection/
# IoMap/Agent) are being folded into their owning layers phase by phase; the
# separate api/ tier will disappear at P10. DocumentApi merged into
# DocumentModule at P2.
include("api/BackendApi.jl")
include("api/DeviceApi.jl")
include("api/ProjectionApi.jl")
include("api/IoMapApi.jl")
include("api/AgentApi.jl")

# ── Document layer (layer 2 — the contract) ────────────────────────────────
# The Document abstract type, the selection generics, the shared @document
# machinery. DocumentModule.jl is the aggregator; it includes Interface.jl
# (the contract fragment) then Document.jl (the machinery fragment). Merged
# at P2 from the old api/DocumentApi.jl + common/Document.jl.
include("document/DocumentModule.jl")

# ── References, operations, foundational documents ─────────────────────────
# The reference machinery, operations, and the foundational document
# vocabulary (Collection, Primitive) the engine still depends on for now.
# Collection precedes Operation so the latter can dispatch on `CellVector`
# directly (a pre-order walk needs it); Operation precedes Primitive, which
# imports its splice helpers; OperationRerooting needs Operation + Primitive,
# so it closes the section. Intent (the reader's backward-flowing protocol
# type) is a dependency-free leaf. Concrete documents move to base at P7.
include("common/Intent.jl")
include("common/IoMap.jl")
# Reference layer (layer 3) — the ReferenceModule aggregator wraps the three
# fragments: Reference.jl (types + value protocol), ReferenceCase.jl (the
# @reference_case DSL), ReferenceBuilder.jl (the @reference/@step DSL).
# Merged from ReferenceModule + ReferenceCaseModule + ReferenceBuilderModule
# at P3; the old names live on as aliases in ProjecturedDomain.
include("reference/ReferenceModule.jl")
# Operation layer (layer 4) — the OperationModule aggregator wraps Interface
# (Operation + evaluate_operation + invalidate_projection!), Operations
# (built-in ops + splice helpers + R1 child_reference_steps seam), and
# Rerooting (R2 open reroot_operation seam). Merged from OperationApi +
# Operation + OperationRerooting at P4; the old names live on as aliases in
# ProjecturedDomain. Loaded before Collection.jl so the CellVector seam
# method (R1) registers into an already-declared generic; Primitive.jl
# similarly adds the R2 methods for its splice-range ops.
include("operation/OperationModule.jl")
include("document/Collection.jl")
include("document/Primitive.jl")

# ── Input devices & events ─────────────────────────────────────────────────
# Keyboard/Mouse need Modifiers + the Device stub; EventCase (the `@event_case`
# pattern parser) needs the event types. These must precede GestureBinding.
# Display (display-size query + provider glue) is a dependency-free leaf.
include("device/Display.jl")
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
include("projection/higherorder/Chaining.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Switching.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/WindowManaging.jl")
include("projection/higherorder/EnvelopeUnwrapping.jl")
include("projection/generic/Identity.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Filtering.jl")
include("projection/generic/Searching.jl")
include("projection/generic/Sorting.jl")
include("projection/generic/Copying.jl")
include("projection/generic/Constant.jl")
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
# The read-eval-print loop and its immediate dependencies: the Screen device
# and the gesture recognizer (which needs ScreenDocument). The animation clock
# (TimeModule) is now included at the top of the file beside CellModule (P1).
# Editor pulls in nearly every layer above.
include("device/ScreenDevice.jl")
include("editor/GestureRecognizer.jl")
include("editor/Editor.jl")
# Scripted live playback builds on the editor loop, so it loads last.
include("editor/Playback.jl")

end # module ProjecturedKernel
