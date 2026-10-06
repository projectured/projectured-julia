"""
    ProjecturedDataFramesTest

The DataFrames tier of the test-package DAG: the layering guard, the shape of
`make_data_frame_example`, the view of a data frame drawn through the natural
renderer, its duplicate, and a data frame shown through the seams of the display.

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
using ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display
using ProjecturedKernel.DocumentModule: make_document_duplicate
using ProjecturedKernel.EditorModule: build_editor, run_frame!
using ProjecturedKernel.IoMapModule: IoMap
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
using ProjecturedPlatform.StyleModule
using ProjecturedPlatform.WidgetModule

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/adapter/dataframes/DataFrameExampleTest.jl")
include("../../../test/adapter/dataframes/DataFrameViewTest.jl")
include("../../../test/adapter/dataframes/DataFrameColumnTest.jl")
include("../../../test/adapter/dataframes/DataFramePathTest.jl")
include("../../../test/adapter/dataframes/DataFrameCellTest.jl")
include("../../../test/adapter/dataframes/DataFrameRowEditTest.jl")
include("../../../test/adapter/dataframes/DataFrameColumnEditTest.jl")
include("../../../test/adapter/dataframes/DataFrameFindTest.jl")
include("../../../test/adapter/dataframes/DataFrameFilterTest.jl")
include("../../../test/adapter/dataframes/DataFrameSortTest.jl")
include("../../../test/adapter/dataframes/DataFrameRefreshTest.jl")
include("../../../test/adapter/dataframes/DataFrameDuplicateTest.jl")
include("../../../test/adapter/dataframes/DataFrameColumnWidthTest.jl")
include("../../../test/adapter/dataframes/DataFrameDisplayTest.jl")
include("../../../test/adapter/dataframes/DataFrameThemeTest.jl")
include("../../../test/adapter/dataframes/DataFrameViewRowToWidgetTest.jl")
include("../../../test/adapter/dataframes/DataFrameTableTest.jl")
include("../../../test/adapter/dataframes/DataFramesSuite.jl")

end # module ProjecturedDataFramesTest
