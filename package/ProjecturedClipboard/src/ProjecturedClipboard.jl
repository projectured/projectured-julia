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
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IntentModule = ProjecturedKernel.IntentModule
const OperationModule = ProjecturedKernel.OperationModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DomainModule = ProjecturedDomain.DomainModule
const SelectionModule = ProjecturedKernel.SelectionModule
const TextModule = ProjecturedText.TextModule
const IoMapModule = ProjecturedKernel.IoMapModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const EventPatternModule = ProjecturedKernel.EventPatternModule

include("../../../source/clipboard/ClipboardModule.jl")

end # module ProjecturedClipboard
