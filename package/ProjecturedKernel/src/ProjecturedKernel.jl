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

# The package is twenty-three architectural layers, one folder and one module
# each, included bottom-to-top below. This list is the layer diagram and the
# single source of truth for the layer order: every module appears after the
# modules named in its `import ..XxxModule` headers, and a layer only imports
# layers at or below its own index — both enforced statically by
# `test_kernel_layering()`. A module's own file carries its fragment include
# list, so each module file reads as that layer's table of contents.
include("../../../source/kernel/fault/FaultModule.jl")                # layer 1  — the record, the store, the barrier, the report
include("../../../source/kernel/performance/PerformanceModule.jl")   # layer 2  — what the editor measures about itself
include("../../../source/kernel/cell/CellModule.jl")                 # layer 3  — the reactive cell engine
include("../../../source/kernel/struct/CellStructModule.jl")         # layer 4  — the @cell_struct codegen
include("../../../source/kernel/clock/ClockModule.jl")               # layer 5  — the animation clock
include("../../../source/kernel/event/EventModule.jl")               # layer 6  — input events + the pattern language
include("../../../source/kernel/device/DeviceModule.jl")             # layer 7  — the devices events come from
include("../../../source/kernel/gesture/GestureRecognizerModule.jl") # layer 8  — event → gesture recognition
include("../../../source/kernel/backend/BackendModule.jl")           # layer 9  — rendering-target seam
include("../../../source/kernel/document/DocumentModule.jl")         # layer 10 — the document contract
include("../../../source/kernel/reference/ReferenceModule.jl")       # layer 11 — reference machinery
include("../../../source/kernel/selection/SelectionModule.jl")       # layer 12 — document current-focus state
include("../../../source/kernel/operation/OperationModule.jl")       # layer 13 — reified edits
include("../../../source/kernel/intent/IntentModule.jl")             # layer 14 — the reader pipeline's carrier
include("../../../source/kernel/binding/GestureBindingModule.jl")    # layer 15 — gesture → operation bindings
include("../../../source/kernel/iomap/IoMapModule.jl")               # layer 16 — projection input↔output records
include("../../../source/kernel/projection/ProjectionModule.jl")     # layer 17 — projection interface & algebra
include("../../../source/kernel/tool/ToolModule.jl")                 # layer 18 — the editor's capability surface
include("../../../source/kernel/llm/LlmModule.jl")                   # layer 19 — the LLM provider abstraction
include("../../../source/kernel/agent/AgentModule.jl")               # layer 20 — the AI control surface
include("../../../source/kernel/feed/FeedModule.jl")                 # layer 21 — the registered inflows of an editor
include("../../../source/kernel/editor/EditorModule.jl")             # layer 22 — the read-eval-print loop
include("../../../source/kernel/playback/PlaybackModule.jl")         # layer 23 — scripted live playback

end # module ProjecturedKernel
