module ProjecturedTest

using Test
using ProjecturedAll

# `ProjecturedAll` binds every submodule of every package as `ProjecturedAll.XxxModule`
# but exports only their symbols, so bind the module names here too. The suites
# below were written against the flat namespace and name a module directly
# (`ProjectionModule.print_document`, …).
include("../../../test/projectured/ProjecturedSuite.jl")

end # module ProjecturedTest
