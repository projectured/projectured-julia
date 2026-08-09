"""
    ProjecturedProcess

The process domain.

A flowchart language: the step documents, the runtime that walks them, the
diagram, the notation printer, the two stages that draw the flowchart as a
graph, the code generator, and the debug session.

Actions and conditions are Julia expressions, and the flowchart prints into a
graph, so this depends on `ProjecturedJulia` and `ProjecturedGraph`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedProcess

using ProjecturedKernel
using ProjecturedBase
using ProjecturedVisual
using ProjecturedJulia
using ProjecturedGraph

for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual, ProjecturedJulia, ProjecturedGraph)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Process.jl")
include("ProcessRuntime.jl")
include("ProcessDiagram.jl")
include("ProcessDebugSession.jl")
include("ProcessToSyntax.jl")
include("ProcessToProcessDiagram.jl")
include("ProcessDiagramToGraph.jl")
include("ProcessToJuliaCode.jl")
include("ProcessDebug.jl")

end # module ProjecturedProcess
