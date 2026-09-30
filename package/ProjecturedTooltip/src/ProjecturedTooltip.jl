"""
    ProjecturedTooltip

What a part says about itself when the pointer rests on it, the wrapper that
keeps the tooltip window, and the `TooltipSource` wrapper with its decorator.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedTooltip

using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedScreen

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ScreenModule = ProjecturedScreen.ScreenModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const SelectionModule = ProjecturedKernel.SelectionModule

include("../../../source/platform/tooltip/TooltipModule.jl")

end # module ProjecturedTooltip
