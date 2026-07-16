"""
    ProjecturedKernel

The headless, domain-agnostic engine of ProjecturEd: the reactive cell system,
the reference/operation/IO-map machinery, the projection *interface and
infrastructure* (the four generic functions, the IO maps, the `@projection`
macro, the projection-template engine, gesture bindings), the input-device
abstraction, the editor read-eval-print loop, and the agent control surface
(LLM/MCP). It carries no concrete projections — the domain-independent
projection algebra (higher-order combinators + generic projections) lives in
`ProjecturedBase` — and no concrete documents at all — the foundational
document *vocabulary* (`PrimitiveModule`, `CollectionModule`) also lives in
`ProjecturedBase` and `ScreenDocumentModule` in `ProjecturedVisual` — no
concrete domains
(JSON/XML/Text/Syntax/Widget/...), no backends, and **no heavy
dependencies** — `using ProjecturedKernel` precompiles and loads on its own.
The real LLM/MCP transports are standalone opt-in packages (`ProjecturedLlm`
in `package/llm`, `ProjecturedMcp` in `package/mcp`) that depend on this
package; the kernel carries only their dependency-free seams.

The concrete domains live in `ProjecturedDomain`; the flat public API is
re-exported by the `Projectured` umbrella.
"""
module ProjecturedKernel

# The package is sixteen architectural layers, one folder each, included
# bottom-to-top below. Each layer folder keeps its own ordered include list in
# a `<Name>Layer.jl` *fragment* (a 0-module file sharing this module's
# namespace), so this file reads as the layer diagram and each layer file as
# that layer's table of contents. The include tree remains one hand-maintained
# topological sort: every file appears after the modules named in its
# `import ..XxxModule` headers, and a layer only imports layers at or below
# its own index — both enforced statically by `test_kernel_layering()`.
#
# This list is the single source of truth for the layer order; the individual
# layer files state their dependencies, never their index.
include("cell/CellLayer.jl")             # layer 1  — the reactive cell engine
include("clock/ClockLayer.jl")           # layer 2  — the animation clock
include("event/EventLayer.jl")           # layer 3  — input events + the pattern language
include("device/DeviceLayer.jl")         # layer 4  — the devices events come from
include("gesture/GestureLayer.jl")       # layer 5  — event → gesture recognition
include("backend/BackendLayer.jl")       # layer 6  — rendering-target seam
include("document/DocumentLayer.jl")     # layer 7  — the document contract
include("reference/ReferenceLayer.jl")   # layer 8  — reference machinery
include("selection/SelectionLayer.jl")   # layer 9  — document current-focus state
include("operation/OperationLayer.jl")   # layer 10 — reified edits
include("binding/BindingLayer.jl")       # layer 11 — gesture → operation bindings
include("projection/ProjectionLayer.jl") # layer 12 — projection interface & algebra
include("tool/ToolLayer.jl")             # layer 13 — the editor's capability surface
include("llm/LlmLayer.jl")               # layer 14 — the LLM provider abstraction
include("agent/AgentLayer.jl")           # layer 15 — the AI control surface
include("editor/EditorLayer.jl")         # layer 16 — the read-eval-print loop

end # module ProjecturedKernel
