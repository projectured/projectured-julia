# The frame performance of the editor — `record_frame_performance!` of
# `editor/Feeds.jl`. The properties under test: the editor records its frame
# time as a time, and, when the counters are compiled in, every counter of the
# frame with its unit.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.PerformanceModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor
using ProjecturedKernelExample

@document struct FrameMeasurementProbe
    value::Int = 0
end

struct FrameMeasurementProbeProjection <: Projection end
ProjectionModule.print_document(::FrameMeasurementProbeProjection, recursion, input,
                                ctx) =
    SimpleIoMap(nothing, input, input)

function test_editor_frame_performance()
@testset "the frame performance of the editor" begin
    @testset "the editor records its frame time as a time" begin
        editor = Editor(HeadlessBackend(), FrameMeasurementProbe(),
                        FrameMeasurementProbeProjection(), Device[])
        EditorModule.record_frame_performance!(editor, 0.016)
        summary = compute_frame_measurement_summary(editor.frame_measurements,
                                                    :frame_time)
        @test summary.unit === :second
        @test summary.count == 1
        @test summary.total ≈ 0.016
    end

    if PERFORMANCE_COUNTERS_ENABLED
        @testset "the editor records every counter, with its unit" begin
            editor = Editor(HeadlessBackend(), FrameMeasurementProbe(),
                            FrameMeasurementProbeProjection(), Device[])
            # A time that no list names reaches the store all the same.
            with_performance_counters() do
                @measure_performance_time :probe_time (1 + 2)
                EditorModule.record_frame_performance!(editor, 0.016)
            end
            store = editor.frame_measurements
            @test compute_frame_measurement_summary(store, :probe_time).unit === :second
            @test compute_frame_measurement_summary(store, :reads).unit === :count
        end
    end
end
end
