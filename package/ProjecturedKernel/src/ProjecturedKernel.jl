"""
    ProjecturedKernel

The headless, domain-agnostic engine of ProjecturEd: the reactive cell system,
the reference/operation/IO-map machinery, the projection *interface and
infrastructure* (the four generic functions, the IO maps, the `@projection`
macro, the projection-template engine, gesture bindings), the input-device
abstraction, the editor read-eval-print loop, and the agent control surface
(LLM/MCP).

It carries no concrete projections, no concrete documents, no concrete domains
(JSON/XML/Text/Syntax/Widget/...), no backends, and **no heavy dependencies** —
so `using ProjecturedKernel` precompiles and loads on its own. The
domain-independent projection algebra, the foundational document vocabulary,
the render substrate, and the concrete domains all live in the packages above
(`base`, `visual`, `domain`). The real LLM/MCP transports are opt-in packages
that depend on this one; the kernel carries only their dependency-free seams.
"""
module ProjecturedKernel

# The package is eighteen architectural layers, one folder each, included
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
include("../../../source/kernel/fault/FaultLayer.jl")           # layer 1  — the record, the store, the barrier, the report
include("../../../source/kernel/cell/CellLayer.jl")             # layer 2  — the reactive cell engine
include("../../../source/kernel/clock/ClockLayer.jl")           # layer 3  — the animation clock
include("../../../source/kernel/event/EventLayer.jl")           # layer 4  — input events + the pattern language
include("../../../source/kernel/device/DeviceLayer.jl")         # layer 5  — the devices events come from
include("../../../source/kernel/gesture/GestureLayer.jl")       # layer 6  — event → gesture recognition
include("../../../source/kernel/backend/BackendLayer.jl")       # layer 7  — rendering-target seam
include("../../../source/kernel/document/DocumentLayer.jl")     # layer 8  — the document contract
include("../../../source/kernel/reference/ReferenceLayer.jl")   # layer 9  — reference machinery
include("../../../source/kernel/selection/SelectionLayer.jl")   # layer 10 — document current-focus state
include("../../../source/kernel/operation/OperationLayer.jl")   # layer 11 — reified edits
include("../../../source/kernel/binding/BindingLayer.jl")       # layer 12 — gesture → operation bindings
include("../../../source/kernel/iomap/IoMapLayer.jl")           # layer 13 — projection input↔output records
include("../../../source/kernel/projection/ProjectionLayer.jl") # layer 14 — projection interface & algebra
include("../../../source/kernel/tool/ToolLayer.jl")             # layer 15 — the editor's capability surface
include("../../../source/kernel/llm/LlmLayer.jl")               # layer 16 — the LLM provider abstraction
include("../../../source/kernel/agent/AgentLayer.jl")           # layer 17 — the AI control surface
include("../../../source/kernel/editor/EditorLayer.jl")         # layer 18 — the read-eval-print loop

end # module ProjecturedKernel
