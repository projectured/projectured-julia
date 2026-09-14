"""
    ProjecturedInspector

The reference inspector document, its text rendering, and the hover probe
that follows the pointer with an inspector window.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedInspector

using ProjecturedKernel
using ProjecturedScreen
using ProjecturedStyle
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const TextModule = ProjecturedText.TextModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IntentModule = ProjecturedKernel.IntentModule
const EventModule = ProjecturedKernel.EventModule
const OperationModule = ProjecturedKernel.OperationModule
const ScreenModule = ProjecturedScreen.ScreenModule

include("../../../source/inspector/ReferenceInspector.jl")

end # module ProjecturedInspector
