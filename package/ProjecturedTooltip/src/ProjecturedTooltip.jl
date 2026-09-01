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
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ScreenDocumentModule = ProjecturedScreen.ScreenDocumentModule
const OperationApiModule = ProjecturedKernel.OperationModule

include("../../../source/tooltip/TooltipDocument.jl")
include("../../../source/tooltip/TooltipDecorator.jl")

end # module ProjecturedTooltip
