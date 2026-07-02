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

# ── API (abstract types + function stubs) ────────────────────────────────
include("api/Backend.jl")
include("api/Device.jl")
include("api/Projection.jl")
include("api/Operation.jl")
include("api/Document.jl")
include("api/IoMap.jl")
include("api/Agent.jl")

# ── Infrastructure ────────────────────────────────────────────────────────
include("common/Reactive.jl")
include("common/Document.jl")
include("common/IoMap.jl")
include("reference/Reference.jl")
include("reference/ReferenceCase.jl")
include("reference/ReferenceBuilder.jl")
include("editor/PrinterContext.jl")
include("common/Operation.jl")

# ── Foundational document vocabulary the engine depends on ─────────────────
include("document/Collection.jl")
include("device/Modifiers.jl")
include("device/Keyboard.jl")
include("device/Mouse.jl")
include("device/EventCase.jl")
include("common/GestureBinding.jl")
include("document/Primitive.jl")
include("common/OperationRerooting.jl")
# Agent LLM client seam (dependency-free LlmBackend/AnthropicLlm/FakeLlm; the
# Anthropic HTTP client lives in the `ProjecturedLlm` package, package/llm).
include("editor/Llm.jl")
include("document/Screen.jl")

# ── Domain-agnostic projection algebra ─────────────────────────────────────
include("projection/higherorder/Sequential.jl")
include("projection/higherorder/TypeDispatching.jl")
include("projection/higherorder/Recursive.jl")
include("projection/higherorder/Alternative.jl")
include("projection/higherorder/PredicateDispatching.jl")
include("projection/higherorder/ReferenceDispatching.jl")
include("projection/higherorder/Nesting.jl")
include("projection/higherorder/WindowManager.jl")
include("projection/higherorder/EnvelopeUnwrapping.jl")
include("common/Projection.jl")
include("projection/generic/Preserving.jl")
include("projection/generic/Reversing.jl")
include("projection/generic/Filtering.jl")
include("projection/generic/Searching.jl")
include("projection/generic/Sorting.jl")
include("projection/generic/Copying.jl")
include("projection/generic/Invariably.jl")
include("projection/generic/Focusing.jl")

# ── Devices, editor loop, agent control surface ────────────────────────────
include("device/Screen.jl")
include("editor/GestureRecognizer.jl")
include("editor/ToolRegistry.jl")
# Mcp.jl holds the dependency-free editor tools; the MCP transport (McpServer,
# wire bridges) lives in the `ProjecturedMcp` package, package/mcp.
include("editor/Mcp.jl")
include("editor/Editor.jl")

end # module ProjecturedKernel
