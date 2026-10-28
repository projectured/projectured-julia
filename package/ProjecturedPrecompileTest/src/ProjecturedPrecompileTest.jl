"""
    ProjecturedPrecompileTest

The test package of `ProjecturedPrecompile`: the preferences, the compile of a
package at each value, the report of a failure, and the recording.
"""
module ProjecturedPrecompileTest

using Test
using ProjecturedPrecompile
using ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/tool/precompile/PrecompileSuite.jl")

end # module ProjecturedPrecompileTest
