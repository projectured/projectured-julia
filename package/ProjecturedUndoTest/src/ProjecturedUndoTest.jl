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
# The shared static layering guard lives at the bottom of the test-package DAG.
using ProjecturedKernelTest: check_layering, get_package_source_root
using ProjecturedCollection.CollectionModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule
using ProjecturedKernel.ToolModule
using ProjecturedProjection.ProjectionAlgebraModule: IdentityProjection
using ProjecturedUndo.UndoModule

include("../../../test/undo/UndoBufferTest.jl")
include("../../../test/undo/UndoSuite.jl")

end # module ProjecturedUndoTest
