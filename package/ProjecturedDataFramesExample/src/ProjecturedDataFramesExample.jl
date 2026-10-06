"""
    ProjecturedDataFramesExample

The DataFrames tier of the example-package DAG: `make_data_frame_example`, a
factory that builds a deterministic `DataFrame` — no random numbers, so a test
or a gallery gets the same rows every run — and `make_data_frame_navigator_example`,
a navigator on the view of such a frame.
"""
module ProjecturedDataFramesExample

using DataFrames
using ProjecturedDataFrames
using ProjecturedDataFrames.NavigatorModule: Navigator

include("../../../example/adapter/dataframes/DataFrameExample.jl")

export make_data_frame_example, make_data_frame_navigator_example

end # module ProjecturedDataFramesExample
