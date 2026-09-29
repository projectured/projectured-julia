"""
    ProjecturedDataFramesTest

The DataFrames tier of the test-package DAG: the layering guard, and the shape
check on `make_data_frame_example`.

Everything is aggregated by `test_dataframes()`.
"""
module ProjecturedDataFramesTest

using Test
using DataFrames
using ProjecturedDataFrames
using ProjecturedDataFramesExample
using ProjecturedKernelTest

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/dataframes/DataFrameExampleTest.jl")
include("../../../test/dataframes/DataFramesSuite.jl")

end # module ProjecturedDataFramesTest
