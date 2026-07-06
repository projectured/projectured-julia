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
# obeys those dependency edges.

# ── Cell layer (layer 1 — the DAG's dependency-free base) ──────────────────
# PerformanceCounter (leaf) before the cells, whose reactive kind bumps its
# `_perf` on the hot path. CellModule is the aggregator; it includes the base
# type and the three kind files (AbstractCell/ReactiveCell/MutableCell/ImmutableCell).
# Time is the one global animation clock, a single `Cell` built on the engine
# above — it belongs beside cells, not with the editor loop that drives it.
include("cell/PerformanceCounter.jl")
include("cell/CellModule.jl")
include("cell/Time.jl")

# ── API — abstract types + `function foo end` stubs ────────────────────────
# ProjectionApi and IoMapApi declare abstract types and open generics up front
# so lower layers can add methods without a dependency cycle.
include("projection/ProjectionApi.jl")
include("projection/IoMapApi.jl")

# ── Document layer (layer 2 — the contract) ────────────────────────────────
# The Document abstract type, the selection generics, the shared @document
# machinery. DocumentModule.jl is the aggregator; it includes Interface.jl
# (the contract fragment) then Document.jl (the machinery fragment).
include("document/DocumentModule.jl")

# ── References, operations ─────────────────────────────────────────────────
# Reference machinery and the operation layer. These declare open seams
# (generics) that `package/base` extends for its concrete documents and
# document-shaped projections; the kernel itself carries no concrete document.
include("projection/Intent.jl")
include("projection/IoMap.jl")
include("reference/ReferenceModule.jl")
include("operation/OperationModule.jl")

# ── Device layer (layer 5 — input devices, events, gestures) ───────────────
# The DeviceModule interface, the modifier/keyboard/mouse event types, and
# GestureModule (the @event_case macro + parser and the reified
# GestureBinding/@gestures DSL). GestureModule owns EventEnvelope, so the
# editor and gesture layers don't depend on a concrete document type.
include("device/Device.jl")
include("device/Modifiers.jl")
include("device/Keyboard.jl")
include("device/Mouse.jl")
include("device/GestureModule.jl")

# ── Backend layer (layer 6 — rendering targets, independent of device) ─────
# BackendModule declares the abstract Backend, the batch generics
# (initialize_backend!, quit_backend!, measure_text, write_image, record_video,
# render_canvas, decode_image, get_pointer_position), and the make_backend
# factory seam. DisplayModule holds the display-size query with a provider
# indirection.
include("backend/Backend.jl")
include("backend/Display.jl")
include("backend/HeadlessBackend.jl")

# ── Projection infrastructure & algebra ────────────────────────────────────
# PrinterContext (Reactive + Reference only) is projection-layer infrastructure
# consumed by ProjectionModule and the generic projections, so it leads here.
# Then the higher-order combinators and the generic projections.
include("projection/PrinterContext.jl")
# Open generics for the children container ProjectionTemplate uses; base's
# Collection.jl adds the CellVector methods.
include("projection/ChildrenContainer.jl")
# Must load before the combinators (Chaining/Nesting/Recursive/TypeDispatching)
# that import collect_gesture_bindings from it.
include("projection/GestureBindings.jl")
include("projection/higherorder/Chaining.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Switching.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/EnvelopeUnwrapping.jl")
include("projection/generic/Identity.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Constant.jl")
include("projection/generic/Focusing.jl")

# ── Projection defaults & the `@projection` macro ──────────────────────────
# ProjectionModule holds the four-generic fallbacks and the `@projection`
# macro. Nothing in the kernel imports it, so it loads after the whole algebra;
# it needs Primitive, ReferenceCase/Builder, PrinterContext, Keyboard, Mouse.
include("projection/Projection.jl")

# ── ProjectionTemplate ─────────────────────────────────────────────────────
# The builder-and-walk projection-template engine every XToSyntax uses. It is
# projection machinery, not per-domain content. It keeps two base seams open:
#   (a) constructive CellVector(...) sites go through the children-container
#       generic (make_children_container / children_container_type); base's
#       Collection.jl registers the CellVector methods.
#   (b) the ReplaceStringRangeOperation read_intent method lives in
#       base/projection/ReaderDefaults.jl beside the primitive-op defaults.
include("projection/ProjectionTemplate.jl")

# ── Agent layer (layer 8 — the AI control surface, side-stack) ─────────────
# AgentModule declares the make_agent_server / start_agent_server! /
# stop_agent_server! seam the editor loop reaches through. Llm, ToolRegistry,
# Mcp are the dependency-free client seams the real transports (opt-in
# ProjecturedLlm / ProjecturedMcp packages) implement against.
include("agent/Agent.jl")
include("agent/Llm.jl")
include("agent/ToolRegistry.jl")
include("agent/Mcp.jl")

# ── Editor ─────────────────────────────────────────────────────────────────
# The read-eval-print loop. GestureRecognizer lives in device/ (it operates on
# device event types and EventEnvelope; no document coupling). ScreenDevice
# loads late because it references WindowQuit from ScreenDocumentModule.
include("device/ScreenDevice.jl")
include("device/GestureRecognizer.jl")
include("editor/Editor.jl")
# Scripted live playback builds on the editor loop, so it loads last.
include("editor/Playback.jl")

end # module ProjecturedKernel
