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

# The image of this package holds the recorded calls of its parts (compile-ahead.md,
# Decision 11): its workload is all of its parts.
import ProjecturedKernelTest
using ProjecturedPrecompile: @compile_ahead
@compile_ahead ProjecturedKernelTest.run_suite(test_tulip)

end # module ProjecturedTulipTest
