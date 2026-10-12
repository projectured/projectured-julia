# The walkthrough of the performance layer.

const _PERFORMANCE_WALKTHROUGH = [
    "# The counters are in the kernel only when the preference performance_counters was on when the kernel compiled. It is off by default.",
    "PERFORMANCE_COUNTERS_ENABLED",
    "# A scope runs its body and answers the value of the body. With the counters, the body counts into a store of its own.",
    "run_with_performance_counters(() -> 6 * 7)",
    "# A timed expression answers its own value. With the counters, a scope adds its time in nanoseconds.",
    "@measure_performance_time :print_time sum(1:10)",
    "# Outside a scope there is no store, so the counters read empty.",
    "get_performance_counters()",
    "# A frame store keeps the measurements of the last frames in a ring. An editor has one.",
    "store = FrameMeasurementStore(capacity = 3); get_frame_count(store)",
    "# A frame records its times in seconds and its counts, as name => value pairs, and the time at which it ended.",
    "record_frame_measurements!(store; times = [:frame_time => 0.010], counts = [:reads => 120], end_time = 100.0); get_frame_count(store)",
    "record_frame_measurements!(store; times = [:frame_time => 0.020], end_time = 100.5); get_frame_measurement_names(store)",
    "# A summary covers the frames in the ring. A frame that did not measure a name does not count for it.",
    "frame_time = compute_frame_measurement_summary(store, :frame_time); (frame_time.unit, frame_time.count, frame_time.mean, frame_time.maximum)",
    "compute_frame_measurement_summary(store, :reads)",
    "# A name keeps the unit of the group that first gave it. A wrong call leaves the store as it was.",
    "try record_frame_measurements!(store; times = [:reads => 0.5]) catch exception; exception end",
    "get_frame_count(store)",
    "# The ring keeps the last frames, oldest first. A value is NaN where a frame did not measure the name.",
    "record_frame_measurements!(store; times = [:frame_time => 0.030], counts = [:reads => 80], end_time = 101.0); record_frame_measurements!(store; times = [:frame_time => 0.015], end_time = 101.5); get_frame_count(store)",
    "recent = collect_recent_frame_measurements(store); recent.frames",
    "[(column.name, column.unit, column.values) for column in recent.columns]",
    "# The frames go out as CSV, with a time in milliseconds. A file path in place of the buffer writes a file.",
    "buffer = IOBuffer(); write_frame_measurements!(buffer, store)",
    "readlines(seekstart(buffer))",
]

"""
    print_performance_example(io::IO = stdout)

Print a REPL session that shows the performance layer: the switch of the
counters, a scope and a timed expression, the counters outside a scope, and a
frame store with its records, its summaries, its unit rule, its ring and its CSV.

Each line runs as it prints, so the value under a line is the value that the line
gives. To try the lines, type them in a REPL after
`using ProjecturedKernel.PerformanceModule`. A session can not show a count: the
counters are in the kernel only when the preference `performance_counters`
compiled them in, and the counts of a frame come from the cells of an editor.

# Example

    julia> using ProjecturedKernelExample

    julia> print_performance_example()

See also [`print_cell_example`](@ref) and [`print_fault_example`](@ref).
"""
print_performance_example(io::IO = stdout) =
    _print_walkthrough(io, PerformanceModule, _PERFORMANCE_WALKTHROUGH)
