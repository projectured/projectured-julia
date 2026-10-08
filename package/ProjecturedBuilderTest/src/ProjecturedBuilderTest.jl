"""
    ProjecturedBuilderTest

The test package of `ProjecturedBuilder`: the binaries it builds, and the release
copy of the packages of this repository.
"""
module ProjecturedBuilderTest

using Test
using ProjecturedBuilder
using ProjecturedKernelTest: check_layering, get_package_source_root
# The parser of the application, which the help text of the binary must match.
using ProjecturedPlatform: parse_application_arguments, APPLICATION_ASSISTANTS

include("../../../test/tool/builder/BuilderSuite.jl")

end # module ProjecturedBuilderTest
