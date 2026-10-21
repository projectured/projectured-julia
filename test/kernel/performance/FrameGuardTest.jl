# The self-test of the frame guard (`FrameGuard.jl`): synthetic parts whose work
# is known, so the bounds of the guard can be set, and a guard can be seen to fail
# for a part that grows with its input.
#
# Each part does its work in the drain of a feed of a small headless editor, so the
# rest of a frame is the same at each size. A part of fixed work and a part whose
# work grows with the logarithm of its size must pass; a part of 10 ns of work for
# each element of its input must fail. A burst that a feed drains at most 64 items
# for each frame must keep its frames flat; one that drains all items in one frame
# must not.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.FeedModule
import ProjecturedKernel.FeedModule: drain_changes!, compute_wake_deadline
using ProjecturedKernel.EditorModule: Editor, run_print_stage!
using ProjecturedKernelExample

@document struct FrameGuardProbe
    value::Int = 0
end

struct FrameGuardProbeProjection <: Projection end
ProjectionModule.print_document(::FrameGuardProbeProjection, recursion, input, context) =
    SimpleIoMap(nothing, input, input)

# A feed whose drain runs the work of a part at the size of its scene.
mutable struct FrameGuardWorkFeed <: Feed
    work::Function
end

drain_changes!(feed::FrameGuardWorkFeed, editor) = (feed.work(); 0)

# A feed that holds a queue of items and drains at most `limit` of them in each
# frame; each item costs some work and some bytes.
mutable struct FrameGuardQueueFeed <: Feed
    waiting::Int
    limit::Int
end

function drain_changes!(feed::FrameGuardQueueFeed, editor)
    count = min(feed.waiting, feed.limit)
    for _ in 1:count
        _frame_guard_work(20)
    end
    feed.waiting -= count
    count
end

compute_wake_deadline(feed::FrameGuardQueueFeed, editor) = feed.waiting > 0 ? 0.0 : nothing

# About 10 ns of work for each of `count` steps, and 8 bytes for each, kept so the
# compiler can drop neither.
const _FRAME_GUARD_SINK = Ref{Any}(nothing)
function _frame_guard_work(count::Integer)
    values = Vector{Float64}(undef, count)
    total = 0.0
    for i in 1:count
        total = sin(total + i)
        values[i] = total
    end
    _FRAME_GUARD_SINK[] = values
    nothing
end

function _make_frame_guard_editor(feed::Feed)
    editor = Editor(FrameGuardProbe(), FrameGuardProbeProjection(); backend = HeadlessBackend(),
                    devices = Device[], feeds = Feed[feed])
    run_print_stage!(editor)
    editor
end

const _FRAME_GUARD_SIZES = [1_000, 10_000, 100_000]

# A scene whose part does `work(size)` in each frame.
_make_frame_guard_scene(name, work) =
    FrameScene(name; sizes = _FRAME_GUARD_SIZES,
               make_editor = size -> _make_frame_guard_editor(FrameGuardWorkFeed(() -> work(size))),
               give_input! = (editor, size) -> nothing)

# A burst of `size` items that a feed drains at most `limit` of in each frame.
function _make_frame_guard_burst(name, limit_of)
    FrameScene(name; sizes = [100, 1_000, 10_000], is_burst = true,
               make_editor = size -> _make_frame_guard_editor(FrameGuardQueueFeed(0, limit_of(size))),
               give_input! = (editor, size) -> (only(feed for feed in editor.feeds
                                                     if feed isa FrameGuardQueueFeed).waiting = size))
end

const _FRAME_GUARD_FIXED = _make_frame_guard_scene("fixed work", size -> _frame_guard_work(1_000))
const _FRAME_GUARD_LOGARITHMIC = _make_frame_guard_scene("logarithmic work",
    size -> foreach(_ -> _frame_guard_work(100), 1:ceil(Int, log2(size))))
const _FRAME_GUARD_LINEAR = _make_frame_guard_scene("10 ns for each element", _frame_guard_work)

"""
    report_frame_guard_calibration(; io = stdout) -> Vector

Measure the synthetic parts of the self-test of the frame guard, print their rows,
and answer their growth: the numbers that set the bounds `FLAT_TIME_RATIO`,
`FLAT_ALLOCATION_RATIO` and `FLAT_WORK_RATIO`.
"""
function report_frame_guard_calibration(; io::IO = stdout)
    growths = Any[]
    for scene in (_FRAME_GUARD_FIXED, _FRAME_GUARD_LOGARITHMIC, _FRAME_GUARD_LINEAR,
                  _make_frame_guard_burst("burst of 64 for each frame", size -> 64),
                  _make_frame_guard_burst("burst in one frame", size -> size))
        works = measure_frame_work(scene)
        print_frame_work(io, scene.name, works)
        growth = compute_frame_growth(works)
        println(io, "  growth: time ", round(growth.time_ratio; digits = 2), ", bytes ",
                round(growth.allocation_ratio; digits = 2), ", frames ",
                round(growth.frame_count_ratio; digits = 2))
        push!(growths, scene.name => growth)
    end
    growths
end

function test_frame_guard()
@testset "the frame guard" begin
    @testset "a part of fixed work passes" begin
        check_frame_growth(_FRAME_GUARD_FIXED)
    end

    @testset "a part whose work grows with the logarithm of its size passes" begin
        check_frame_growth(_FRAME_GUARD_LOGARITHMIC)
    end

    @testset "a part of 10 ns for each element fails the bounds" begin
        growth = compute_frame_growth(measure_frame_work(_FRAME_GUARD_LINEAR))
        @test growth.time_ratio > FLAT_TIME_RATIO
        @test growth.allocation_ratio > FLAT_ALLOCATION_RATIO
    end

    @testset "a burst that a feed drains 64 items for each frame keeps its frames flat" begin
        scene = _make_frame_guard_burst("burst of 64 for each frame", size -> 64)
        growth = check_frame_growth(scene)
        # 10_000 items at 64 for each frame: about 157 frames, against 2 for 100.
        @test growth.frame_count_ratio >= 50
    end

    @testset "a burst that one frame drains fails the bounds" begin
        scene = _make_frame_guard_burst("burst in one frame", size -> size)
        growth = compute_frame_growth(measure_frame_work(scene))
        @test growth.time_ratio > FLAT_TIME_RATIO
        @test growth.allocation_ratio > FLAT_ALLOCATION_RATIO
    end

    @testset "a scene can wait for the deadline of a feed before each frame" begin
        feed = FrameGuardQueueFeed(0, 1)
        scene = FrameScene("deadline"; sizes = [1, 10], waits_for_deadline = true,
                           make_editor = size -> _make_frame_guard_editor(feed),
                           give_input! = (editor, size) -> (feed.waiting = 1))
        works = measure_frame_work(scene; warm_frames = 2, frames = 3)
        @test [work.frame_count for work in works] == [3, 3]
        @test feed.waiting == 0
    end
end
end
