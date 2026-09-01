"""
    ProjecturedClipboard

Copy, cut and paste over any wrapped content, mirrored to the clipboard of
the host.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedClipboard

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedPrimitive
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationModule = ProjecturedKernel.OperationModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const SelectionModule = ProjecturedKernel.SelectionModule
const TextModule = ProjecturedText.TextModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IoMapModule = ProjecturedKernel.IoMapModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule

include("../../../source/clipboard/OsClipboard.jl")
include("../../../source/clipboard/ClipboardDocument.jl")
include("../../../source/clipboard/ClipboardToAny.jl")

end # module ProjecturedClipboard
