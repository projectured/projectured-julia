"""
    ProjecturedTooltip

The `TooltipSource` wrapper and the decorator that shows and hides a
tooltip window.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedTooltip

using ProjecturedKernel
using ProjecturedScreen

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ScreenModule = ProjecturedScreen.ScreenModule
const OperationModule = ProjecturedKernel.OperationModule

include("../../../source/tooltip/TooltipDocument.jl")

end # module ProjecturedTooltip
