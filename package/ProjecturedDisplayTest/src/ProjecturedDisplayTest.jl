"""
    ProjecturedDisplayTest

The display tier of the test-package DAG: the layering guard, and a value shown
in an editor that runs beside the caller, with tabs and without.

Everything is aggregated by `test_display()`.
"""
module ProjecturedDisplayTest

using Test
using ProjecturedPlatform
using ProjecturedPlatform.DisplayModule
using ProjecturedKernel
using ProjecturedKernel.AgentModule
using ProjecturedKernel.BackendModule
using ProjecturedKernelTest
using ProjecturedPlatform.PaneModule
using ProjecturedPlatform.PrimitiveModule
using ProjecturedPlatform.ScreenModule
using ProjecturedPlatform.WidgetModule

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/platform/display/EditorDisplayTest.jl")
include("../../../test/platform/display/DisplaySuite.jl")

end # module ProjecturedDisplayTest
