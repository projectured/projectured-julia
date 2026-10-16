# The frame statistics of two measurements, a time and a count, over no recent frames.
function make_frame_statistics_document_example()
    statistics = FrameStatistics()
    push!(statistics.rows, FrameStatisticsRow("frame_time", :second, 3, 0.01, 0.03, 0.02, 0.01, 0.06))
    push!(statistics.rows, FrameStatisticsRow("reads", :count, 2, 120.0, 5000.0, 812.3, 900.14, 2436.7))
    statistics
end

# The frame time series of one measurement over three frames.
make_frame_time_series_document_example() =
    FrameTimeSeries(names = ["frame_time"], frames = [1.0, 2.0, 3.0], columns = [[0.016, 0.017, 0.015]])
