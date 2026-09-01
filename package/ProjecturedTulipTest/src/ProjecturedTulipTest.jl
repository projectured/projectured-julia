"""
    ProjecturedTulipTest

Test package for the opt-in `ProjecturedTulip` solver. Hosts `ConstraintSolverTest`
(the LP-backed `TulipConstraintSolver` constraint layout), moved down from the
umbrella. Needs the Tulip/Adaptagrams native shim, so it precompiles and runs
only where that is installed. Resolves through the root env and uses the flat
`Projectured` namespace plus `ProjecturedTulip`.
"""
module ProjecturedTulipTest

using Test
using Projectured
using ProjecturedExample
using ProjecturedTulip

include("../../../test/tulip/document/ConstraintSolverTest.jl")

include("../../../test/tulip/Suite.jl")

end # module ProjecturedTulipTest
