"""
    ProjecturedDataFramesTest

The DataFrames tier of the test-package DAG: the layering guard, the shape of
`make_data_frame_example`, the view of a data frame drawn through the natural
renderer, and a data frame shown through the seams of the display.

Everything is aggregated by `test_dataframes()`.
"""
module ProjecturedDataFramesTest

using Test
using DataFrames
using ProjecturedCollection.CollectionModule
using ProjecturedDataFrames
using ProjecturedDataFrames.DataFramesModule
using ProjecturedDataFramesExample
using ProjecturedDisplay
using ProjecturedGraphics.GraphicsModule
using ProjecturedKernel
using ProjecturedKernel.AgentModule
using ProjecturedKernel.BackendModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.GestureModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernelTest
using ProjecturedLayout.LayoutModule
using ProjecturedNatural.NaturalModule
using ProjecturedPane.PaneModule
using ProjecturedStyle.StyleModule
using ProjecturedWidget.WidgetModule

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/dataframes/DataFrameExampleTest.jl")
include("../../../test/dataframes/DataFrameViewTest.jl")
include("../../../test/dataframes/DataFrameDisplayTest.jl")
include("../../../test/dataframes/DataFramesSuite.jl")

end # module ProjecturedDataFramesTest
