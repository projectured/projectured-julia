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
using ProjecturedPlatform.CollectionModule
using ProjecturedPlatform.DomainModule: compute_context_menu
using ProjecturedDataFrames
using ProjecturedDataFrames.DataFramesModule
using ProjecturedDataFramesExample
using ProjecturedPlatform
using ProjecturedPlatform.GraphicsModule
using ProjecturedKernel
using ProjecturedKernel.AgentModule
using ProjecturedKernel.BackendModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.GestureModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernelTest
using ProjecturedPlatform.LayoutModule
using ProjecturedPlatform.NaturalModule
using ProjecturedPlatform.PaneModule
using ProjecturedPlatform.ScreenModule: OpenPopupOperation
using ProjecturedPlatform.StyleModule
using ProjecturedPlatform.WidgetModule

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/adapter/dataframes/DataFrameExampleTest.jl")
include("../../../test/adapter/dataframes/DataFrameViewTest.jl")
include("../../../test/adapter/dataframes/DataFrameColumnTest.jl")
include("../../../test/adapter/dataframes/DataFrameDisplayTest.jl")
include("../../../test/adapter/dataframes/DataFramesSuite.jl")

end # module ProjecturedDataFramesTest
