module ProjecturedTest

using Test
using ProjecturedAll

# `ProjecturedAll` binds every submodule of every package as `ProjecturedAll.XxxModule`
# but exports only their symbols, so bind the module names here too. The suites
# below were written against the flat namespace and name a module directly
# (`ProjectionModule.print_document`, …).
include("../../../test/projectured/ProjecturedSuite.jl")

# The image of this package holds the recorded calls of its parts (compile-ahead.md,
# Decision 11): its workload is all of its parts.
import ProjecturedKernelTest
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    ProjecturedKernelTest.run_suite(test_integration)
    ProjecturedKernelTest.run_suite(test_repository)
end

end # module ProjecturedTest
