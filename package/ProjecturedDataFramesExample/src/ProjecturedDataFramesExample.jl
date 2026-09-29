"""
    ProjecturedDataFramesExample

The DataFrames tier of the example-package DAG: `make_data_frame_example`, a
factory that builds a deterministic `DataFrame` — no random numbers, so a test
or a gallery gets the same rows every run.
"""
module ProjecturedDataFramesExample

using DataFrames
using ProjecturedDataFrames

include("../../../example/dataframes/DataFrameExample.jl")

export make_data_frame_example

end # module ProjecturedDataFramesExample
