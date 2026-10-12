"""
The walkthrough of the performance layer: the REPL session that
`print_performance_example` prints, line for line. The one line that shows the
switch of the counters says what this build has, so the test passes in both builds.
"""

using Test
using ProjecturedKernel.PerformanceModule: PERFORMANCE_COUNTERS_ENABLED
using ProjecturedKernelExample: print_performance_example

const _PERFORMANCE_EXAMPLE_TEXT = """
# Type each line in a REPL after `using ProjecturedKernel.PerformanceModule`.

# The counters are in the kernel only when the preference performance_counters was on when the kernel compiled. It is off by default.
julia> PERFORMANCE_COUNTERS_ENABLED
$(PERFORMANCE_COUNTERS_ENABLED)

# A scope runs its body and answers the value of the body. With the counters, the body counts into a store of its own.
julia> run_with_performance_counters(() -> 6 * 7)
42

# A timed expression answers its own value. With the counters, a scope adds its time in nanoseconds.
julia> @measure_performance_time :print_time sum(1:10)
55

# Outside a scope there is no store, so the counters read empty.
julia> get_performance_counters()
(counts = Dict{Symbol, Int64}(), times = Dict{Symbol, Int64}())

# A frame store keeps the measurements of the last frames in a ring. An editor has one.
julia> store = FrameMeasurementStore(capacity = 3); get_frame_count(store)
0

# A frame records its times in seconds and its counts, as name => value pairs, and the time at which it ended.
julia> record_frame_measurements!(store; times = [:frame_time => 0.010], counts = [:reads => 120], end_time = 100.0); get_frame_count(store)
1

julia> record_frame_measurements!(store; times = [:frame_time => 0.020], end_time = 100.5); get_frame_measurement_names(store)
2-element Vector{Symbol}:
 :frame_time
 :reads

# A summary covers the frames in the ring. A frame that did not measure a name does not count for it.
julia> frame_time = compute_frame_measurement_summary(store, :frame_time); (frame_time.unit, frame_time.count, frame_time.mean, frame_time.maximum)
(:second, 2, 0.015, 0.02)

julia> compute_frame_measurement_summary(store, :reads)
FrameMeasurementSummary(:count, 1, 120.0, 120.0, 120.0, 0.0, 120.0)

# A name keeps the unit of the group that first gave it. A wrong call leaves the store as it was.
julia> try record_frame_measurements!(store; times = [:reads => 0.5]) catch exception; exception end
ArgumentError("the frame measurement reads has the unit count, not second")

julia> get_frame_count(store)
2

# The ring keeps the last frames, oldest first. A value is NaN where a frame did not measure the name.
julia> record_frame_measurements!(store; times = [:frame_time => 0.030], counts = [:reads => 80], end_time = 101.0); record_frame_measurements!(store; times = [:frame_time => 0.015], end_time = 101.5); get_frame_count(store)
4

julia> recent = collect_recent_frame_measurements(store); recent.frames
3-element Vector{Int64}:
 2
 3
 4

julia> [(column.name, column.unit, column.values) for column in recent.columns]
2-element Vector{Tuple{Symbol, Symbol, Vector{Float64}}}:
 (:frame_time, :second, [0.02, 0.03, 0.015])
 (:reads, :count, [NaN, 80.0, NaN])

# The frames go out as CSV, with a time in milliseconds. A file path in place of the buffer writes a file.
julia> buffer = IOBuffer(); write_frame_measurements!(buffer, store)
3

julia> readlines(seekstart(buffer))
4-element Vector{String}:
 "frame,end_time_s,frame_time_ms,reads"
 "2,0,20,"
 "3,0.5,30,80"
 "4,1,15,"

"""

function test_performance_example()
@testset "Performance example" begin
    @test sprint(print_performance_example) == _PERFORMANCE_EXAMPLE_TEXT
    # Each call runs in a new module, so a second call starts from no store.
    @test sprint(print_performance_example) == _PERFORMANCE_EXAMPLE_TEXT
end
end
