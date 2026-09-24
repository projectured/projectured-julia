# The frame sample store — the ring of recent frames. The properties under
# test: a summary matches a reference computation, the ring keeps exactly the
# last frames, a frame that did not measure a name holds no value for it, the
# unit follows the name, and the CSV text is what a spreadsheet reads.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.PerformanceModule
import ProjecturedKernel.EditorModule: Editor, record_frame_measurements!
using ProjecturedKernelExample

@document struct FrameSampleProbe
    value::Int = 0
end

struct FrameSampleProbeProjection <: Projection end
ProjectionModule.print_document(::FrameSampleProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

function test_frame_samples()
@testset "the frame sample store" begin
    @testset "the fold matches a reference computation" begin
        store = FrameSampleStore()
        for value in (1, 2, 3, 4)
            record_frame_sample!(store, [:x => value])
        end
        summary = compute_frame_measurement_summary(store, :x)
        @test summary.count == 4
        @test summary.minimum == 1.0
        @test summary.maximum == 4.0
        @test summary.mean == 2.5
        @test summary.total == 10.0
        @test compute_frame_standard_deviation(summary) ≈ sqrt(5 / 3)
    end

    @testset "below two values the deviation is zero" begin
        @test compute_frame_standard_deviation(FrameMeasurementSummary()) == 0.0
        store = FrameSampleStore()
        record_frame_sample!(store, [:x => 7])
        summary = compute_frame_measurement_summary(store, :x)
        @test compute_frame_standard_deviation(summary) == 0.0
    end

    @testset "names keep first-seen order, flushes only reset the count" begin
        store = FrameSampleStore()
        record_frame_sample!(store, [:frame_time => 0.01, :reads => 5.0])
        record_frame_sample!(store, [:frame_time => 0.02, :reads => 7.0])
        @test get_frame_measurement_names(store) == [:frame_time, :reads]
        @test count_unflushed_frame_samples(store) == 2
        mark_frame_samples_flushed!(store)
        @test count_unflushed_frame_samples(store) == 0
        @test compute_frame_measurement_summary(store, :frame_time).count == 2
        @test compute_frame_measurement_summary(store, :absent).count == 0
    end

    @testset "the ring keeps the last frames" begin
        store = FrameSampleStore(capacity = 3)
        for value in 1:5
            record_frame_sample!(store, [:x => value]; end_time = 10.0 + value)
        end
        @test get_frame_count(store) == 5
        samples = collect_recent_frame_samples(store)
        @test samples.frames == [3, 4, 5]
        @test samples.end_times == [13.0, 14.0, 15.0]
        @test samples.columns == [:x => [3.0, 4.0, 5.0]]
        summary = compute_frame_measurement_summary(store, :x)
        @test (summary.count, summary.minimum, summary.maximum) == (3, 3.0, 5.0)
    end

    @testset "a frame that did not measure a name holds no value for it" begin
        store = FrameSampleStore(capacity = 4)
        record_frame_sample!(store, [:a => 1])
        record_frame_sample!(store, [:a => 2, :b => 10])
        record_frame_sample!(store, [:a => 3])
        columns = collect_recent_frame_samples(store).columns
        @test last(columns[1]) == [1.0, 2.0, 3.0]
        @test isequal(last(columns[2]), [NaN, 10.0, NaN])
        @test compute_frame_measurement_summary(store, :b).count == 1

        # After the ring wraps, the slot of an old frame holds no old value.
        store = FrameSampleStore(capacity = 2)
        record_frame_sample!(store, [:a => 1, :b => 5])
        record_frame_sample!(store, [:a => 2])
        record_frame_sample!(store, [:a => 3])
        @test compute_frame_measurement_summary(store, :b).count == 0
    end

    @testset "a name that ends in _time is a time" begin
        @test is_frame_time_measurement(:frame_time)
        @test is_frame_time_measurement(:print_time)
        @test !is_frame_time_measurement(:reads)
    end

    @testset "the frames are written as CSV, times in milliseconds" begin
        store = FrameSampleStore(capacity = 3)
        record_frame_sample!(store, [:frame_time => 0.010, :reads => 5]; end_time = 100.0)
        record_frame_sample!(store, [:frame_time => 0.020]; end_time = 100.5)
        io = IOBuffer()
        @test write_frame_samples!(io, store) == 2
        @test String(take!(io)) == """
            frame,end_time_s,frame_time_ms,reads
            1,0,10,5
            2,0.5,20,
            """
    end

    @testset "the editor records its frame time" begin
        editor = Editor(HeadlessBackend(), FrameSampleProbe(),
                        FrameSampleProbeProjection(), Device[])
        record_frame_measurements!(editor, 0.016)
        summary = compute_frame_measurement_summary(editor.frame_samples, :frame_time)
        @test summary.count == 1
        @test summary.total ≈ 0.016
    end
end
end
