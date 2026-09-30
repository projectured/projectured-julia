"""
    ProjecturedHelpTest

The suite of `ProjecturedPlatform`, aggregated by `test_help()`.

It holds no domain: the lists read whatever the environment loads, and a test
compares a list with the reflection it comes from. A list is drawn to text
through the syntax and the text printers, so a test reads what a tab shows.
"""
module ProjecturedHelpTest

using Test
import ProjecturedPlatform
# The shared static layering guard lives at the bottom of the test-package DAG.
using ProjecturedKernelTest: check_layering, get_package_source_root
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ProjectionModule
using ProjecturedPlatform.DomainModule
using ProjecturedPlatform.ProjectionAlgebraModule: ChainingProjection, RecursiveProjection
using ProjecturedPlatform.SyntaxModule: SyntaxToText
using ProjecturedPlatform.TextModule: TextToString
using ProjecturedPlatform.HelpModule

include("../../../test/platform/help/DocstringSummaryTest.jl")
include("../../../test/platform/help/HelpListToSyntaxTest.jl")
include("../../../test/platform/help/AboutPageToSyntaxTest.jl")
include("../../../test/platform/help/HelpSuite.jl")

end # module ProjecturedHelpTest
