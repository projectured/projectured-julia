"""
    ProjecturedDisplayTest

The display tier of the test-package DAG: the layering guard, and a value shown
in an editor that runs beside the caller, with tabs and without.

Everything is aggregated by `test_display()`.
"""
module ProjecturedDisplayTest

using Test
using ProjecturedDisplay
using ProjecturedDisplay.DisplayModule
using ProjecturedKernel
using ProjecturedKernel.AgentModule
using ProjecturedKernel.BackendModule
using ProjecturedKernelTest
using ProjecturedPane.PaneModule
using ProjecturedPrimitive.PrimitiveModule
using ProjecturedScreen.ScreenModule
using ProjecturedWidget.WidgetModule

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/platform/display/EditorDisplayTest.jl")
include("../../../test/platform/display/DisplaySuite.jl")

end # module ProjecturedDisplayTest
