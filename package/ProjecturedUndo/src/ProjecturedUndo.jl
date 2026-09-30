"""
    ProjecturedUndo

The `UndoBuffer` overlay document and the transparent projection that records
the way back from every change that passes through it.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedUndo

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule
const ToolModule = ProjecturedKernel.ToolModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const StyleModule = ProjecturedStyle.StyleModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const TextModule = ProjecturedText.TextModule

include("../../../source/platform/undo/UndoModule.jl")

end # module ProjecturedUndo
