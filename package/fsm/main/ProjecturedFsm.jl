"""
    ProjecturedFsm

The finite state machine domain.

The state and transition documents, the diagram document, the notation printer,
the two stages that draw the diagram as a graph, and the code generator.

Guards, actions and entry code are Julia expressions, and the diagram prints
into a graph, so this depends on `ProjecturedJulia` and `ProjecturedGraph`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedFsm

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

include("Fsm.jl")
include("FsmDiagram.jl")
include("FsmToSyntax.jl")
include("FsmToFsmDiagram.jl")
include("FsmDiagramToGraph.jl")
include("FsmToJuliaCode.jl")

end # module ProjecturedFsm
