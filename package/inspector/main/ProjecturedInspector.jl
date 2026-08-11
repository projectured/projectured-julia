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
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReferenceToTextModule = ProjecturedText.ReferenceToTextModule
const TextModule = ProjecturedText.TextModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IntentModule = ProjecturedKernel.IntentModule
const EventModule = ProjecturedKernel.EventModule
const OperationModule = ProjecturedKernel.OperationModule
const ScreenDocumentModule = ProjecturedScreen.ScreenDocumentModule

include("ReferenceInspector.jl")
include("ReferenceInspectorToText.jl")
include("HoverProbe.jl")

end # module ProjecturedInspector
