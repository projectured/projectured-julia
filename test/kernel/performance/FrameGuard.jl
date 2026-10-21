# The frame guard — the harness that drives one part of the editor at several sizes
# of its input and compares the work of its frames.
#
# The rule that a guard checks: the work of one frame has two limits, what the
# window shows and a fixed count for each frame, and it never grows with the size of
# a document, a store, a queue or a burst. A guard drives a part at sizes that grow
# by 10 times, measures its frames with the record of each frame
# (`record_frame_performance!`), and compares the frames at the largest size with
# the frames at the smallest. A ratio of minimum times and a ratio of allocated
# bytes do not depend on the speed or the load of the machine, so a guard fails for
# a change of the code and not for a busy machine.

using Test
using ProjecturedKernel.EditorModule: Editor, run_measured_frame!, compute_wait_timeout
using ProjecturedKernel.CellModule: add_cell_writer!, remove_cell_writer!
using ProjecturedKernel.PerformanceModule: get_frame_count, collect_recent_frame_measurements

"""
    FrameScene(name; sizes, make_editor, give_input!, is_burst = false,
               is_input_done = editor -> true, waits_for_deadline = false,
               count_work = nothing, release_editor = editor -> nothing)

A part of the editor that a frame guard drives at each of `sizes`.

- `make_editor(size)` makes the editor of the part at `size`, with its first print
  done, and answers it.
- `give_input!(editor, size)` gives the input of a frame: a gesture, a post from
  another task, or a change in a store. A function that does nothing gives an idle
  frame.
- With `is_burst`, the input comes once, and the frames run until the editor has
  nothing left to do: no wake waits, the wait of the loop is not 0, and
  `is_input_done(editor)` says that all of the input arrived, such as the posts of
  another task.
- With `waits_for_deadline`, each frame waits, outside its measured time, until a
  feed of the editor is due, as the loop waits for a deadline.
- `count_work(editor)` answers a count of the work of the part that the part keeps,
  such as the rows that a print built, or `nothing`.
- `release_editor(editor)` runs after the frames of a size, such as the quit of a
  backend that opened a window.
"""
struct FrameScene
    name::String
    sizes::Vector{Int}
    make_editor::Function
    give_input!::Function
    is_burst::Bool
    is_input_done::Function
    waits_for_deadline::Bool
    count_work::Union{Function,Nothing}
    release_editor::Function
end

FrameScene(name::AbstractString; sizes::AbstractVector{<:Integer}, make_editor::Function,
           give_input!::Function, is_burst::Bool = false,
           is_input_done::Function = editor -> true, waits_for_deadline::Bool = false,
           count_work::Union{Function,Nothing} = nothing,
           release_editor::Function = editor -> nothing) =
    FrameScene(String(name), collect(Int, sizes), make_editor, give_input!, is_burst,
               is_input_done, waits_for_deadline, count_work, release_editor)

"""
    FrameWork

The frames of a `FrameScene` at one size, as `measure_frame_work` answers them:
the minimum and the median frame time without the garbage collections of the
frame, the median time of each stage, the median
of the bytes that a frame allocated, the time of the garbage collector and of the
compiler over the measured frames, and the median count of work, or `nothing`. A
burst gives, for each of its repetitions, the slowest frame and the frame that
allocated most, and `frame_count` is the median count of frames that a burst
took; `is_finished` is false when a burst did not end within the limit of frames.
"""
struct FrameWork
    size::Int
    minimum_seconds::Float64
    median_seconds::Float64
    median_stage_seconds::NamedTuple
    median_allocated_bytes::Float64
    garbage_collection_seconds::Float64
    compile_seconds::Float64
    work_count::Union{Float64,Nothing}
    frame_count::Int
    is_finished::Bool
end

"""
    FrameGrowth

The ratios of the frames of a scene at its largest size to the frames at its
smallest size: of the minimum frame time, of the allocated bytes, of the count of
work (or `nothing`), and of the count of frames that a burst took.
"""
struct FrameGrowth
    time_ratio::Float64
    allocation_ratio::Float64
    work_ratio::Union{Float64,Nothing}
    frame_count_ratio::Float64
end

"""
    FLAT_TIME_RATIO, FLAT_ALLOCATION_RATIO, FLAT_WORK_RATIO

The bounds of the growth of a flat part, at 100 times the size of its input: of the
minimum frame time, of the allocated bytes of a frame, and of a count of work. The
self-test of the harness (`test_frame_guard`) sets the first two: a part whose work
grows with the logarithm of its size gives a time ratio of 1.49 and a ratio of bytes
of 1.38, so it passes with a margin of 2 times, and a part of 10 ns for each element
gives 78 to 85 and 51, so it fails. A count of work is exact, and a flat part gives
1 for it.
"""
const FLAT_TIME_RATIO = 3.0
const FLAT_ALLOCATION_RATIO = 3.0
const FLAT_WORK_RATIO = 2.0

# A ratio of allocated bytes adds this many bytes on both sides, so a frame that
# allocates almost nothing at the smallest size gives no ratio of noise.
const _ALLOCATION_FLOOR_BYTES = 4096.0

# A ratio of minimum times adds this many seconds on both sides: a difference below
# a tenth of a millisecond, such as the caches after a long input, is far below the
# budget of a frame, and is no growth.
const _TIME_FLOOR_SECONDS = 1e-4

# The most frames that one burst may take before the harness stops it, unless a
# measurement names another limit.
const _BURST_FRAME_LIMIT = 2000

# The longest wait for a deadline before a frame of a scene that waits for one.
const _DEADLINE_WAIT_LIMIT = 2.0

"""
    measure_frame_work(scene; warm_frames = 30, frames = 50, repetitions = 5,
                       frame_limit = 2000) -> Vector{FrameWork}

Drive `scene` at each of its sizes, in order, and answer one row for each size.

At each size, the harness makes the editor, runs `warm_frames` frames to compile,
collects the garbage, and then measures `frames` frames, each after the input of a
frame. A burst gives its input `repetitions` times, and each time runs the frames
until the editor has nothing left to do, at most `frame_limit` frames. Each frame runs as the loop runs it, with
[`run_measured_frame!`](@ref), on this task as the loop task and the writer of the
cells.
"""
function measure_frame_work(scene::FrameScene; warm_frames::Integer = 30,
                            frames::Integer = 50, repetitions::Integer = 5,
                            frame_limit::Integer = _BURST_FRAME_LIMIT)
    [_measure_frame_work_at(scene, size, warm_frames, frames, repetitions, frame_limit)
     for size in scene.sizes]
end

function _measure_frame_work_at(scene::FrameScene, size::Int, warm_frames, frames, repetitions,
                                frame_limit)
    editor = scene.make_editor(size)
    previous_loop_task = editor.loop_task
    editor.loop_task = current_task()
    add_cell_writer!(current_task())
    started = time_ns()
    try
        run_frame = () -> _run_scene_frame!(scene, editor, started)
        if scene.is_burst
            _run_burst!(scene, editor, size, run_frame, frame_limit)        # the warm-up
            GC.gc()
            bursts = [_measure_burst!(scene, editor, size, run_frame, frame_limit) for _ in 1:repetitions]
            _make_burst_work(size, bursts)
        else
            for _ in 1:warm_frames
                scene.give_input!(editor, size)
                run_frame()
            end
            GC.gc()
            first = get_frame_count(editor.frame_measurements) + 1
            counts = Float64[]
            for _ in 1:frames
                scene.give_input!(editor, size)
                run_frame()
                scene.count_work === nothing || push!(counts, scene.count_work(editor))
            end
            rows = _collect_frame_rows(editor, first)
            _make_frame_work(size, rows, isempty(counts) ? nothing : _median(counts), length(rows), true)
        end
    finally
        remove_cell_writer!(current_task())
        editor.loop_task = previous_loop_task
        scene.release_editor(editor)
    end
end

# One frame as the loop runs it after its wait: the frame takes every wake posted
# before it, and runs with the wall time since the measurement started.
function _run_scene_frame!(scene::FrameScene, editor::Editor, started::UInt64)
    scene.waits_for_deadline && _wait_for_deadline(editor)
    Threads.atomic_xchg!(editor.wake_pending, false)
    run_measured_frame!(editor, (time_ns() - started) / 1e9)
end

function _wait_for_deadline(editor::Editor)
    timeout = compute_wait_timeout(editor)
    isfinite(timeout) && timeout > 0 && sleep(min(timeout, _DEADLINE_WAIT_LIMIT))
    nothing
end

# Whether the editor has nothing left to do: no wake waits, and the loop would wait.
_is_editor_settled(editor::Editor) =
    !editor.wake_pending[] && compute_wait_timeout(editor) > 0

# The input of a burst, then frames until the editor settles and all of the input
# arrived; the count of frames, and whether the burst ended within the limit.
function _run_burst!(scene::FrameScene, editor::Editor, size::Int, run_frame, frame_limit)
    scene.give_input!(editor, size)
    count = 0
    while count < frame_limit
        run_frame()
        count += 1
        if _is_editor_settled(editor)
            scene.is_input_done(editor) && return (count, true)
            # The rest of the input comes from another task: wait for it, as the
            # loop waits for input, and run no empty frame meanwhile.
            timedwait(() -> editor.wake_pending[] || scene.is_input_done(editor),
                      _DEADLINE_WAIT_LIMIT; pollint = 0.001)
        end
    end
    (count, false)
end

function _measure_burst!(scene::FrameScene, editor::Editor, size::Int, run_frame, frame_limit)
    first = get_frame_count(editor.frame_measurements) + 1
    count, is_finished = _run_burst!(scene, editor, size, run_frame, frame_limit)
    rows = _collect_frame_rows(editor, first)
    work = scene.count_work === nothing ? nothing : Float64(scene.count_work(editor))
    (; rows, count, is_finished, work)
end

# The rows of the frames from the frame number `first` on, as named tuples of the
# names that each frame records.
function _collect_frame_rows(editor::Editor, first::Int)
    recent = collect_recent_frame_measurements(editor.frame_measurements)
    selected = findall(>=(first), recent.frames)
    names = Tuple(column.name for column in recent.columns)
    [NamedTuple{names}(Tuple(column.values[i] for column in recent.columns)) for i in selected]
end

# The median of `values`; the kernel test package depends on no statistics package.
function _median(values)
    sorted = sort!(collect(Float64, values))
    count = length(sorted)
    isodd(count) ? sorted[(count + 1) ÷ 2] : (sorted[count ÷ 2] + sorted[count ÷ 2 + 1]) / 2
end

_get_frame_value(row, name::Symbol) =
    (value = get(row, name, NaN); isnan(value) ? 0.0 : value)

# The time of a frame without its garbage collections: a collection comes from the
# bytes of many frames, and the ratio of bytes guards it.
_get_frame_work_seconds(row) =
    max(0.0, _get_frame_value(row, :frame_time) - _get_frame_value(row, :garbage_collection_time))

const _STAGE_NAMES = (:feed_time, :read_time, :evaluate_time, :print_time, :report_time)

function _make_frame_work(size::Int, rows, work_count, frame_count::Int, is_finished::Bool)
    times = [_get_frame_work_seconds(row) for row in rows]
    stages = NamedTuple{_STAGE_NAMES}(Tuple(_median(_get_frame_value(row, name) for row in rows)
                                            for name in _STAGE_NAMES))
    FrameWork(size, minimum(times), _median(times), stages,
              _median(_get_frame_value(row, :allocated_bytes) for row in rows),
              sum(_get_frame_value(row, :garbage_collection_time) for row in rows),
              sum(_get_frame_value(row, :compile_time) for row in rows),
              work_count, frame_count, is_finished)
end

# A burst: for each repetition the slowest frame and the frame that allocated most;
# the minimum of the slowest frames, the median of the most bytes, and the median
# count of frames.
function _make_burst_work(size::Int, bursts)
    slowest = [maximum(_get_frame_work_seconds(row) for row in burst.rows) for burst in bursts]
    most_bytes = [maximum(_get_frame_value(row, :allocated_bytes) for row in burst.rows) for burst in bursts]
    all_rows = reduce(vcat, [burst.rows for burst in bursts])
    stages = NamedTuple{_STAGE_NAMES}(Tuple(_median(_get_frame_value(row, name) for row in all_rows)
                                            for name in _STAGE_NAMES))
    works = [burst.work for burst in bursts if burst.work !== nothing]
    FrameWork(size, minimum(slowest), _median(slowest), stages, _median(most_bytes),
              sum(_get_frame_value(row, :garbage_collection_time) for row in all_rows),
              sum(_get_frame_value(row, :compile_time) for row in all_rows),
              isempty(works) ? nothing : _median(works),
              round(Int, _median([burst.count for burst in bursts])),
              all(burst -> burst.is_finished, bursts))
end

"""
    compute_frame_growth(works::Vector{FrameWork}) -> FrameGrowth

The ratios of the row of the largest size to the row of the smallest size: of the
minimum frame time with 0.1 ms added on both sides, of the allocated bytes with
4 kB added on both sides, of the count of work when both rows have one, and of the
count of frames.
"""
function compute_frame_growth(works::Vector{FrameWork})
    smallest = works[argmin([work.size for work in works])]
    largest = works[argmax([work.size for work in works])]
    work_ratio = smallest.work_count === nothing || largest.work_count === nothing ? nothing :
                 (largest.work_count + 1) / (smallest.work_count + 1)
    FrameGrowth((largest.minimum_seconds + _TIME_FLOOR_SECONDS) /
                (smallest.minimum_seconds + _TIME_FLOOR_SECONDS),
                (largest.median_allocated_bytes + _ALLOCATION_FLOOR_BYTES) /
                (smallest.median_allocated_bytes + _ALLOCATION_FLOOR_BYTES),
                work_ratio, largest.frame_count / smallest.frame_count)
end

"""
    print_frame_work([io,] name, works)

Print the rows of a scene as a table: for each size the minimum and the median
frame time, the median of each stage, the allocated bytes, the time of the garbage
collector and of the compiler, the count of work and the count of frames.
"""
function print_frame_work(io::IO, name::AbstractString, works::Vector{FrameWork})
    println(io, "frame work of ", name, ":")
    println(io, "  size        min ms   median ms  feed ms  read ms  eval ms  print ms  bytes      gc ms  compile ms  work  frames")
    for work in works
        stages = work.median_stage_seconds
        println(io, "  ", rpad(work.size, 10), lpad(_format_milliseconds(work.minimum_seconds), 8),
                lpad(_format_milliseconds(work.median_seconds), 12),
                lpad(_format_milliseconds(stages.feed_time), 9), lpad(_format_milliseconds(stages.read_time), 9),
                lpad(_format_milliseconds(stages.evaluate_time), 9), lpad(_format_milliseconds(stages.print_time), 10),
                "  ", rpad(round(Int, work.median_allocated_bytes), 10),
                lpad(_format_milliseconds(work.garbage_collection_seconds), 6),
                lpad(_format_milliseconds(work.compile_seconds), 12),
                lpad(work.work_count === nothing ? "-" : string(round(Int, work.work_count)), 6),
                lpad(work.frame_count, 8), work.is_finished ? "" : "  not finished")
    end
end

print_frame_work(name::AbstractString, works::Vector{FrameWork}) = print_frame_work(stdout, name, works)

_format_milliseconds(seconds::Real) = string(round(1e3 * seconds; digits = 3))

"""
    check_frame_growth(scene; time_bound = FLAT_TIME_RATIO,
                       allocation_bound = FLAT_ALLOCATION_RATIO,
                       work_bound = FLAT_WORK_RATIO, keywords...) -> FrameGrowth

Measure `scene` with [`measure_frame_work`](@ref), which takes `keywords`, and
assert with `@test` that each ratio of [`compute_frame_growth`](@ref) is at most
its bound, and that each burst ended. Call it inside a `@testset`. A check that
fails prints the rows of the scene. A bound of `Inf` asserts nothing for its ratio.
The bytes are those of the process, so a scene whose input allocates on other
threads while its frames run, such as many clients that start at once, passes
`allocation_bound = Inf` and asserts the time and the count of frames.
"""
function check_frame_growth(scene::FrameScene; time_bound::Real = FLAT_TIME_RATIO,
                            allocation_bound::Real = FLAT_ALLOCATION_RATIO,
                            work_bound::Real = FLAT_WORK_RATIO, keywords...)
    works = measure_frame_work(scene; keywords...)
    growth = compute_frame_growth(works)
    passed = [
        (@test growth.time_ratio <= time_bound),
        (@test growth.allocation_ratio <= allocation_bound),
        (@test all(work -> work.is_finished, works))]
    growth.work_ratio === nothing || push!(passed, (@test growth.work_ratio <= work_bound))
    all(result -> result isa Test.Pass, passed) || print_frame_work(scene.name, works)
    growth
end
