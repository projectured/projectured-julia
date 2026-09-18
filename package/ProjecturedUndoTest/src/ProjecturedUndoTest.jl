"""
    ProjecturedUndoTest

The suite of `ProjecturedUndo`, aggregated by `test_undo()`.

It holds no domain and no example: the documents it edits are declared in the
suite itself, and the content projection it drives through is the identity. So
the way back is tested on the operations and the buffer alone, which is what the
slice owns.
"""
module ProjecturedUndoTest

using Test
import ProjecturedUndo
using ProjecturedCollection.CollectionModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule
using ProjecturedProjection.ProjectionAlgebraModule: IdentityProjection
using ProjecturedUndo.UndoModule

export test_undo

include("../../../test/undo/UndoBufferTest.jl")

end # module ProjecturedUndoTest
