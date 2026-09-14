"""
    ProjecturedPlot

The vocabulary every plotted notation shares: axis scaling, tick selection,
the data-to-pixel mapping, the decimation that keeps a plot's cost
proportional to its pixels, and the colour and marker cycles.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedPlot

using ProjecturedStyle

const StyleModule = ProjecturedStyle.StyleModule

include("../../../source/plot/PlotModule.jl")

end # module ProjecturedPlot
