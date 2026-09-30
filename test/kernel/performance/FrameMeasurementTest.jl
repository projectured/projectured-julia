# The frame measurement store — the ring of recent frames. The properties under
# test: a summary matches a reference computation, the ring keeps exactly the
# last frames, a frame that did not measure a name holds no value for it, the
# unit comes from the group that gave the name, and the CSV text is what a
# spreadsheet reads.

using Test
using ProjecturedKernel.PerformanceModule

function test_frame_measurements()
@testset "the frame measurement store" begin
    @testset "a summary matches a reference computation" begin
        store = FrameMeasurementStore()
        for value in (1, 2, 3, 4)
            record_frame_measurements!(store; counts = [:x => value])
        end
        summary = compute_frame_measurement_summary(store, :x)
        @test summary.unit === :count
        @test summary.count == 4
        @test summary.minimum == 1.0
        @test summary.maximum == 4.0
        @test summary.mean == 2.5
        @test summary.total == 10.0
        @test summary.standard_deviation ≈ sqrt(5 / 3)
    end

    @testset "below two values the deviation is zero" begin
        store = FrameMeasurementStore()
        record_frame_measurements!(store; counts = [:x => 7])
        @test compute_frame_measurement_summary(store, :x).standard_deviation == 0.0
    end

    @testset "names keep first-seen order, and the store counts every frame" begin
        store = FrameMeasurementStore()
        record_frame_measurements!(store; times = [:frame_time => 0.01],
                                   counts = [:reads => 5])
        record_frame_measurements!(store; times = [:frame_time => 0.02],
                                   counts = [:reads => 7])
        @test get_frame_measurement_names(store) == [:frame_time, :reads]
        @test get_frame_count(store) == 2
        @test compute_frame_measurement_summary(store, :frame_time).count == 2
        @test_throws KeyError compute_frame_measurement_summary(store, :absent)
    end

    @testset "the unit comes from the group that gave the name" begin
        store = FrameMeasurementStore()
        record_frame_measurements!(store; times = [:frame_time => 0.01],
                                   counts = [:reads => 5])
        @test compute_frame_measurement_summary(store, :frame_time).unit === :second
        @test compute_frame_measurement_summary(store, :reads).unit === :count
        columns = collect_recent_frame_measurements(store).columns
        @test [column.unit for column in columns] == [:second, :count]
        # A name in the other group would mix two units in one column, and the
        # wrong call leaves the store as it was.
        @test_throws ArgumentError record_frame_measurements!(store;
                                                              counts = [:frame_time => 3])
        @test get_frame_count(store) == 1
    end

    @testset "a name in both groups of one call leaves the store as it was" begin
        store = FrameMeasurementStore(capacity = 2)
        record_frame_measurements!(store; counts = [:reads => 5], end_time = 1.0)
        end_times = copy(store.end_times)
        columns = Dict(name => copy(column) for (name, column) in store.columns)
        @test_throws ArgumentError record_frame_measurements!(store;
                                                              times = [:x => 0.01],
                                                              counts = [:x => 3])
        @test get_frame_count(store) == 1
        @test get_frame_measurement_names(store) == [:reads]
        @test isequal(store.end_times, end_times)
        @test isequal(store.columns, columns)
    end

    @testset "the ring keeps the last frames" begin
        store = FrameMeasurementStore(capacity = 3)
        for value in 1:5
            record_frame_measurements!(store; counts = [:x => value],
                                       end_time = 10.0 + value)
        end
        @test get_frame_count(store) == 5
        recent = collect_recent_frame_measurements(store)
        @test recent.frames == [3, 4, 5]
        @test recent.end_times == [13.0, 14.0, 15.0]
        @test recent.columns[1].values == [3.0, 4.0, 5.0]
        summary = compute_frame_measurement_summary(store, :x)
        @test (summary.count, summary.minimum, summary.maximum) == (3, 3.0, 5.0)
    end

    @testset "a frame that did not measure a name holds no value for it" begin
        store = FrameMeasurementStore(capacity = 4)
        record_frame_measurements!(store; counts = [:a => 1])
        record_frame_measurements!(store; counts = [:a => 2, :b => 10])
        record_frame_measurements!(store; counts = [:a => 3])
        columns = collect_recent_frame_measurements(store).columns
        @test columns[1].values == [1.0, 2.0, 3.0]
        @test isequal(columns[2].values, [NaN, 10.0, NaN])
        @test compute_frame_measurement_summary(store, :b).count == 1

        # After the ring wraps, the slot of an old frame holds no old value.
        store = FrameMeasurementStore(capacity = 2)
        record_frame_measurements!(store; counts = [:a => 1, :b => 5])
        record_frame_measurements!(store; counts = [:a => 2])
        record_frame_measurements!(store; counts = [:a => 3])
        summary = compute_frame_measurement_summary(store, :b)
        @test summary.count == 0
        @test isnan(summary.mean)
    end

    @testset "the frames are written as CSV, times in milliseconds" begin
        store = FrameMeasurementStore(capacity = 3)
        record_frame_measurements!(store; times = [:frame_time => 0.010],
                                   counts = [:reads => 5], end_time = 100.0)
        record_frame_measurements!(store; times = [:frame_time => 0.020],
                                   end_time = 100.5)
        record_frame_measurements!(store; times = [:frame_time => 0.0123456],
                                   counts = [:reads => 7], end_time = 100.5160000001)
        io = IOBuffer()
        @test write_frame_measurements!(io, store) == 3
        # A time is rounded to a microsecond.
        @test String(take!(io)) == """
            frame,end_time_s,frame_time_ms,reads
            1,0,10,5
            2,0.5,20,
            3,0.516,12.346,7
            """
    end
end
end
