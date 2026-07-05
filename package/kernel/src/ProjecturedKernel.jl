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
include("api/ProjectionApi.jl")
include("api/IoMapApi.jl")

# ── Document layer (layer 2 — the contract) ────────────────────────────────
# The Document abstract type, the selection generics, the shared @document
# machinery. DocumentModule.jl is the aggregator; it includes Interface.jl
# (the contract fragment) then Document.jl (the machinery fragment). Merged
# at P2 from the old api/DocumentApi.jl + common/Document.jl.
include("document/DocumentModule.jl")

# ── References, operations, foundational documents ─────────────────────────
# Reference machinery + operation layer with R1/R2 open seams + the concrete
# engine documents. The concrete documents (Collection, Primitive,
# ScreenDocument) will migrate to package/base at P8 alongside the
# document-shaped projections that depend on them; kernel plan P7 stood up
# the ProjecturedBase package skeleton without moving content, because
# ScreenDocument couples to WindowManagingProjection and Primitive couples
# to Projection.jl's default reader — carving them out one at a time would
# leave a wrong-direction kernel→base edge.
include("common/Intent.jl")
include("common/IoMap.jl")
include("reference/ReferenceModule.jl")
include("operation/OperationModule.jl")
include("document/Collection.jl")
include("document/Primitive.jl")

# ── Device layer (layer 5 — input devices, events, gestures) ───────────────
# The DeviceModule interface (renamed from DeviceApiModule at P5), the
# modifier/keyboard/mouse event types, and the merged GestureModule (R4: the
# @event_case macro + parser and the reified GestureBinding/@gestures DSL,
# formerly two separate modules whose only tie was a documented private edge).
# GestureModule also owns the rehomed EventEnvelope (R5) — moved out of
# ScreenDocumentModule so the editor and gesture layers no longer depend on a
# concrete document type. Display is a dependency-free leaf.
include("device/Device.jl")
include("device/Modifiers.jl")
include("device/Keyboard.jl")
include("device/Mouse.jl")
include("device/GestureModule.jl")

# ── Backend layer (layer 6 — rendering targets, independent of device) ─────
# BackendModule (renamed from BackendApiModule at P6) declares the abstract
# Backend, the batch generics (initialize_backend!, quit_backend!, measure_text,
# write_image, record_video, render_canvas, decode_image, get_pointer_position),
# and the make_backend factory seam. DisplayModule holds the display-size query
# with a provider indirection — a rendering concept, moved from device/ at P6.
include("backend/Backend.jl")
include("backend/Display.jl")
include("backend/HeadlessBackend.jl")

# ── Foundational documents (projection output vocabulary) ──────────────────
# Kernel plan P7 moved Collection and Primitive out to package/base but
# left ScreenDocument here for now — the kernel's WindowManagingProjection
# imports its types, and moving only ScreenDocument would create a
# wrong-direction kernel→base edge. Both ScreenDocument and
# WindowManagingProjection move together at P8 with the projection split.
include("document/ScreenDocument.jl")

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

# ── Agent layer (layer 8 — the AI control surface, side-stack) ─────────────
# AgentModule (renamed from AgentApiModule at P9) declares the make_agent_server
# / start_agent_server! / stop_agent_server! seam the editor loop reaches
# through. Llm, ToolRegistry, Mcp are the dependency-free client seams the
# real transports (opt-in ProjecturedLlm / ProjecturedMcp packages)
# implement against. The whole agent stack lives in agent/ now (moved from
# editor/ at P9), matching its position in the DAG.
include("agent/Agent.jl")
include("agent/Llm.jl")
include("agent/ToolRegistry.jl")
include("agent/Mcp.jl")

# ── Editor ─────────────────────────────────────────────────────────────────
# The read-eval-print loop. GestureRecognizer was moved into device/ at P5
# (it operates on device event types and the rehomed EventEnvelope; no
# document coupling). ScreenDevice loads late because it references WindowQuit
# from ScreenDocumentModule. TimeModule now lives in the cell layer (P1).
include("device/ScreenDevice.jl")
include("device/GestureRecognizer.jl")
include("editor/Editor.jl")
# Scripted live playback builds on the editor loop, so it loads last.
include("editor/Playback.jl")

end # module ProjecturedKernel
