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

using ProjecturedGraph
using ProjecturedJulia
using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedGraph, ProjecturedJulia, ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/domain/process/ProcessModule.jl")

end # module ProjecturedProcess
