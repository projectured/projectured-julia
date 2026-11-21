"""
    ProjecturedPrecompileTest

The test package of `ProjecturedPrecompile`: the preferences, the compile of a
package at each value, the report of a failure, and the recording.
"""
module ProjecturedPrecompileTest

using Test
using ProjecturedPrecompile
using ProjecturedKernelTest: check_layering, get_package_source_root, TestSuite

include("../../../test/tool/precompile/PrecompileSuite.jl")

# The image of this package holds the recorded calls of its parts (compile-ahead.md,
# Decision 11): its workload is all of its parts.
import ProjecturedKernelTest
using ProjecturedPrecompile: @compile_ahead
@compile_ahead ProjecturedKernelTest.run_suite(test_precompile)

end # module ProjecturedPrecompileTest
