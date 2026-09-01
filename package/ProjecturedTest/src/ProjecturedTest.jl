module ProjecturedTest

using Test
using Projectured

# The umbrella binds every submodule of every package as `Projectured.XxxModule`
# but exports only their symbols, so bind the module names here too. The suites
# below were written against the flat namespace and name a module directly
# (`ProjectionApiModule.print_document`, …).
include("../../../test/projectured/Suite.jl")

end # module ProjecturedTest
