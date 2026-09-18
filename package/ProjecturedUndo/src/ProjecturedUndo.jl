"""
    ProjecturedUndo

The `UndoBuffer` overlay document and the transparent projection that records
the way back from every change that passes through it.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedUndo

using ProjecturedCollection
using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule

include("../../../source/undo/UndoModule.jl")

end # module ProjecturedUndo
