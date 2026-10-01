"""
    ProjecturedTulipTest

Test package for the opt-in `ProjecturedTulip` solver. Hosts `ConstraintSolverTest`
(the LP-backed `TulipConstraintSolver` constraint layout), moved down from the
umbrella. Needs the Tulip/Adaptagrams native shim, so it precompiles and runs
only where that is installed.
"""
module ProjecturedTulipTest

using Test
using ProjecturedKernel
using ProjecturedPlatform
using ProjecturedTulip
using ProjecturedKernelTest

include("../../../test/adapter/tulip/document/ConstraintSolverTest.jl")

include("../../../test/adapter/tulip/TulipSuite.jl")

end # module ProjecturedTulipTest
