"""
    ProjecturedChart

The chart domain.

The data-series documents and axes, the plot document that holds the transient
view state, and the two stages that turn a chart into a plot and draw it.

The arithmetic and the colour and marker vocabulary are not here: a sequence
chart needs them too, so they live in visual's plot slice.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedChart

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedPlot
using ProjecturedStyle

for _src in (ProjecturedCollection, ProjecturedDomain, ProjecturedGraphics, ProjecturedKernel, ProjecturedPlot, ProjecturedStyle)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("ChartSampleReferenceStep.jl")
include("Chart.jl")
include("ChartPlot.jl")
include("ChartToChartPlot.jl")
include("ChartPlotToGraphics.jl")

end # module ProjecturedChart
