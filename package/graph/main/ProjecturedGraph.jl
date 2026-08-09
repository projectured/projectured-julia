"""
    ProjecturedGraph

The graph diagram domain.

The vertex and edge documents, the layout document that holds their geometry,
the layout-engine seam, and the two stages that size and place a graph and then
draw it.

A vertex's content re-enters the surrounding renderer, so a diagram node may be
a widget, prose or a table. The native layout engine lives in the opt-in
`ProjecturedAdaptagrams`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedGraph

using ProjecturedKernel
using ProjecturedBase
using ProjecturedVisual

for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Graph.jl")
include("GraphLayout.jl")
include("GraphLayoutEngine.jl")
include("GraphToGraphLayout.jl")
include("GraphLayoutToGraphics.jl")

end # module ProjecturedGraph
