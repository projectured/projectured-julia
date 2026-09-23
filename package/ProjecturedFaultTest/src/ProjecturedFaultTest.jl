"""
    ProjecturedFaultTest

The suite of `ProjecturedFault`, aggregated by `test_fault()`.

It tests two things that no other suite can. The first is containment: a printer
that fails on one node must cost that node and nothing else, and the failure is
raised from inside the output cell rather than from `print_document`, because
that is where a real printer fails. The second is that the report never lies —
a store, a log target and a backend that all throw at once still answer a tier.
"""
module ProjecturedFaultTest

using Test
import ProjecturedFault
# The shared static layering guard lives at the bottom of the test-package DAG.
using ProjecturedKernelTest: check_layering, get_package_source_root
using ProjecturedCollection.CollectionModule
using ProjecturedFault.FaultViewModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EditorModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.FaultModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernelExample
using ProjecturedProjection.ProjectionAlgebraModule
using ProjecturedSyntax.SyntaxModule
using ProjecturedText.TextModule
# Through the package under test, which declares both: the tooltip generic that
# a fault report answers, and the widget a mark is drawn as.
using ProjecturedFault.DomainModule
using ProjecturedFault.WidgetModule

import ProjecturedKernel.EditorModule: read!

include("../../../test/fault/FaultStoreTest.jl")
include("../../../test/fault/FaultCatchingTest.jl")
include("../../../test/fault/FaultSafeModeTest.jl")
include("../../../test/fault/FaultSuite.jl")

end # module ProjecturedFaultTest
