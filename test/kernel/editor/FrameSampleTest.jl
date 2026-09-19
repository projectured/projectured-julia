# The frame sample store — the fold the loop feeds and a statistics feed
# flushes. The properties under test: the fold matches a reference
# computation, the name order is stable, and the unflushed count tells a
# flush from a fold.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.FrameSampleModule
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
        summary = MeasurementSummary()
        for value in (1, 2, 3, 4)
            record_measurement!(summary, value)
        end
        @test summary.count == 4
        @test summary.minimum == 1.0
        @test summary.maximum == 4.0
        @test summary.mean == 2.5
        @test summary.total == 10.0
        @test compute_standard_deviation(summary) ≈ sqrt(5 / 3)
    end

    @testset "below two values the deviation is zero" begin
        summary = MeasurementSummary()
        @test compute_standard_deviation(summary) == 0.0
        record_measurement!(summary, 7)
        @test compute_standard_deviation(summary) == 0.0
    end

    @testset "names keep first-seen order, flushes only reset the count" begin
        store = FrameSampleStore()
        record_frame_sample!(store, [:frame_time => 0.01, :reads => 5.0])
        record_frame_sample!(store, [:frame_time => 0.02, :reads => 7.0])
        @test get_measurement_names(store) == [:frame_time, :reads]
        @test count_unflushed_samples(store) == 2
        mark_samples_flushed!(store)
        @test count_unflushed_samples(store) == 0
        @test find_measurement_summary(store, :frame_time).count == 2
        @test find_measurement_summary(store, :absent) === nothing
    end

    @testset "the editor folds its frame time" begin
        editor = Editor(HeadlessBackend(), FrameSampleProbe(),
                        FrameSampleProbeProjection(), Device[])
        record_frame_measurements!(editor, 0.016)
        summary = find_measurement_summary(editor.frame_samples, :frame_time)
        @test summary !== nothing
        @test summary.count == 1
        @test summary.total ≈ 0.016
    end
end
end
