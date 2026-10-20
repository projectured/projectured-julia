# The feeds of the editor, `editor/Feeds.jl` — the registered inflows of a
# running editor.
#
# A feed moves what producers stored into a target document, once per frame,
# on the editor task. The inbox is the built-in first feed; every other feed
# is given at construction and the list is fixed from then on. A producer
# wakes the editor through the callback the editor attached at registration.
#
# The file also tests the frame performance that `record_frame_performance!` of
# `editor/Feeds.jl` records: the frame time, the time of each stage, of the held
# frames, of the collections and of the compiles, the allocated bytes, and, when
# the counters are compiled in, every counter of the frame with its unit.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.FeedModule
using ProjecturedKernel.PerformanceModule
import ProjecturedKernel.FeedModule: drain_changes!, compute_wake_deadline,
                                     attach_wake_callback!
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, InboxFeed, post_operation!,
                                       drain_feeds!, wake_editor!, run_editor!
import ProjecturedKernel.OperationModule: QuitEditorOperation
import ProjecturedKernel.OperationModule: Operation, evaluate_operation
import ProjecturedKernel.FaultModule: record_fault!, FaultPolicy, get_fault_records
using ProjecturedKernelExample

@document struct FeedProbe
    value::Int = 0
end

struct FeedProbeProjection <: Projection end
ProjectionModule.print_document(::FeedProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

# A feed that records each drain and keeps the callback it was attached with.
mutable struct ProbeFeed <: Feed
    log::Vector{Any}
    tag::Symbol
    pending::Int
    wake::Any
end
ProbeFeed(log, tag; pending::Int = 0) = ProbeFeed(log, tag, pending, nothing)

function drain_changes!(feed::ProbeFeed, editor::Editor)
    push!(feed.log, (feed.tag, current_task()))
    moved = feed.pending
    feed.pending = 0
    moved
end

attach_wake_callback!(feed::ProbeFeed, wake) = (feed.wake = wake; nothing)

# A feed whose drain throws, as a feed with a broken store does.
struct DrainFailingFeed <: Feed end
drain_changes!(::DrainFailingFeed, editor::Editor) = error("the drain failed")

_quiet_feed_policy() = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)

struct ProbeFeedOperation <: Operation
    log::Vector{Any}
end

evaluate_operation(::Editor, operation::ProbeFeedOperation) =
    (push!(operation.log, (:inbox, current_task())); nothing)

_feed_editor(feeds::Vector{Feed} = Feed[]) =
    Editor(FeedProbe(), FeedProbeProjection(); backend = HeadlessBackend(),
           devices = Device[], feeds = feeds)

function test_editor_feeds()
@testset "the editor's feeds" begin
    @testset "the inbox feed is always first" begin
        probe = ProbeFeed(Any[], :probe)
        editor = _feed_editor(Feed[probe])
        @test length(editor.feeds) == 2
        @test editor.feeds[1] isa InboxFeed
        @test editor.feeds[2] === probe
    end

    @testset "feeds drain in registration order, on the editor task" begin
        log = Any[]
        first_feed = ProbeFeed(log, :first)
        second_feed = ProbeFeed(log, :second)
        editor = _feed_editor(Feed[first_feed, second_feed])
        post_operation!(editor, ProbeFeedOperation(log))
        drain_feeds!(editor)
        @test [tag for (tag, _) in log] == [:inbox, :first, :second]
        @test all(task === current_task() for (_, task) in log)
    end

    @testset "drain_feeds! answers the total moved" begin
        editor = _feed_editor(Feed[ProbeFeed(Any[], :a; pending = 2),
                                   ProbeFeed(Any[], :b; pending = 3)])
        post_operation!(editor, ProbeFeedOperation(Any[]))
        @test drain_feeds!(editor) == 6      # 1 operation + 2 + 3
        @test drain_feeds!(editor) == 0      # everything is drained
    end

    @testset "a drain that throws is recorded, and the next feed still drains" begin
        log = Any[]
        editor = _feed_editor(Feed[DrainFailingFeed(),
                                   ProbeFeed(log, :after; pending = 2)])
        editor.fault_policy = _quiet_feed_policy()
        @test drain_feeds!(editor) == 2            # the failed drain counts as no item
        @test [tag for (tag, _) in log] == [:after]
        records = get_fault_records(editor.faults)
        @test length(records) == 1
        @test records[1].site === :evaluate
        @test records[1].origin === :DrainFailingFeed
    end

    @testset "construction starts with a pending wake" begin
        # The first frame runs before the first wait, so the editor paints
        # once before anything has happened.
        editor = _feed_editor()
        @test editor.wake_pending[]
    end

    @testset "construction attaches the wake callback" begin
        probe = ProbeFeed(Any[], :probe)
        editor = _feed_editor(Feed[probe])
        @test probe.wake !== nothing
        Threads.atomic_xchg!(editor.wake_pending, false)
        probe.wake()
        @test editor.wake_pending[]
    end

    @testset "post_operation! wakes the editor" begin
        editor = _feed_editor()
        Threads.atomic_xchg!(editor.wake_pending, false)
        post_operation!(editor, ProbeFeedOperation(Any[]))
        @test editor.wake_pending[]
    end

    @testset "wakes coalesce into one pending frame" begin
        editor = _feed_editor()
        wake_editor!(editor)
        wake_editor!(editor)
        # The frame takes the whole flag at once, so two wakes cost one frame.
        @test Threads.atomic_xchg!(editor.wake_pending, false)
        @test !Threads.atomic_xchg!(editor.wake_pending, false)
    end

    @testset "the default deadline is no bound" begin
        editor = _feed_editor()
        @test compute_wake_deadline(InboxFeed(), editor) === nothing
        @test compute_wake_deadline(ProbeFeed(Any[], :probe), editor) === nothing
    end

    @testset "a recorded fault wakes the editor" begin
        editor = _feed_editor()
        Threads.atomic_xchg!(editor.wake_pending, false)
        record_fault!(editor.faults, :print; origin = :Probe, exception = ErrorException("e"))
        @test editor.wake_pending[]
    end
end
end

@document struct FrameMeasurementProbe
    value::Int = 0
end

struct FrameMeasurementProbeProjection <: Projection end
ProjectionModule.print_document(::FrameMeasurementProbeProjection, recursion, input,
                                ctx) =
    SimpleIoMap(nothing, input, input)

# A feed whose first drain takes `seconds`, and whose next drain ends the loop.
mutable struct SlowFrameProbeFeed <: Feed
    seconds::Float64
    drains::Int
end

function drain_changes!(feed::SlowFrameProbeFeed, editor)
    feed.drains += 1
    feed.drains == 1 && sleep(feed.seconds)
    feed.drains == 2 && post_operation!(editor, QuitEditorOperation())
    0
end

# A feed whose drain runs `work`, so a frame does that work in its feed stage.
struct FrameWorkProbeFeed <: Feed
    work::Function
end

drain_changes!(feed::FrameWorkProbeFeed, editor) = (feed.work(); 0)

# The store of an editor that ran one measured frame, whose feed stage runs `work`.
function _measure_probe_frame(work)
    editor = Editor(FrameMeasurementProbe(), FrameMeasurementProbeProjection();
                    backend = HeadlessBackend(), devices = Device[],
                    feeds = Feed[FrameWorkProbeFeed(work)])
    EditorModule.run_measured_frame!(editor, 0.0)
    editor.frame_measurements
end

_get_frame_total(store, name) = compute_frame_measurement_summary(store, name).total

const _FRAME_RECORD_TIMES = (:frame_time, :feed_time, :read_time, :evaluate_time,
                             :print_time, :report_time, :held_time,
                             :garbage_collection_time, :compile_time)

function test_editor_frame_performance()
@testset "the frame performance of the editor" begin
    @testset "a measured frame records its stages, its held frames, its collections, its compile and its allocations" begin
        store = _measure_probe_frame(() -> nothing)
        for name in _FRAME_RECORD_TIMES
            summary = compute_frame_measurement_summary(store, name)
            @test (name, summary.unit, summary.count) == (name, :second, 1)
            @test summary.total >= 0
        end
        @test compute_frame_measurement_summary(store, :allocated_bytes).unit === :count
        @test _get_frame_total(store, :feed_time) <= _get_frame_total(store, :frame_time)
    end

    @testset "the time of a drain is in the feed time" begin
        store = _measure_probe_frame(() -> sleep(0.05))
        @test _get_frame_total(store, :feed_time) >= 0.045
        @test _get_frame_total(store, :read_time) < 0.045
        @test _get_frame_total(store, :print_time) < 0.045
    end

    @testset "a collection in a frame is in its garbage collection time" begin
        store = _measure_probe_frame(() -> GC.gc())
        @test _get_frame_total(store, :garbage_collection_time) > 0
    end

    @testset "a compile in a frame is in its compile time" begin
        store = _measure_probe_frame() do
            scratch = Module()
            Core.eval(scratch, :(compiled_in_frame(x) = x * 2.5 + 1))
            Base.invokelatest(scratch.compiled_in_frame, 3)
        end
        @test _get_frame_total(store, :compile_time) > 0
    end

    @testset "a frame turns off the compile timer that it turned on" begin
        # The compile time of a new method, outside a frame.
        function measure_compile_ns(name)
            before = first(Base.cumulative_compile_time_ns())
            scratch = Module()
            Core.eval(scratch, :($name(x) = x * 3.5 + 1))
            Base.invokelatest(getfield(scratch, name), 3)
            first(Base.cumulative_compile_time_ns()) - before
        end
        # Another switch of this process can have the timer on already.
        if measure_compile_ns(:compiled_before_frame) == 0
            _measure_probe_frame(() -> nothing)
            @test measure_compile_ns(:compiled_after_frame) == 0
        end
    end

    @testset "the bytes that a frame allocates are its allocated bytes" begin
        kept = Ref{Any}(nothing)
        store = _measure_probe_frame(() -> (kept[] = zeros(UInt8, 10_000_000)))
        @test _get_frame_total(store, :allocated_bytes) >= 10_000_000
    end

    @testset "the yielded time is recorded where the process keeps the running time of its tasks" begin
        store = _measure_probe_frame(() -> sleep(0.05))
        if Base.Experimental.task_running_time_ns(current_task()) === nothing
            @test :yielded_time ∉ get_frame_measurement_names(store)
        else
            @test _get_frame_total(store, :yielded_time) >= 0.045
        end
    end

    @testset "a slow frame is reported with its slowest stage" begin
        feed = SlowFrameProbeFeed(1.1, 0)
        editor = Editor(FrameMeasurementProbe(), FrameMeasurementProbeProjection();
                        backend = HeadlessBackend(), devices = Device[], feeds = Feed[feed])
        @test_logs (:warn, r"a frame took 1\.\d+ s, 1\.\d+ s of it in the drain of SlowFrameProbeFeed") match_mode = :any run_editor!(editor)
        @test feed.drains >= 2
    end

    @testset "the editor records its frame time as a time" begin
        editor = Editor(FrameMeasurementProbe(), FrameMeasurementProbeProjection();
                        backend = HeadlessBackend(), devices = Device[])
        EditorModule.record_frame_performance!(editor, 0.016)
        summary = compute_frame_measurement_summary(editor.frame_measurements,
                                                    :frame_time)
        @test summary.unit === :second
        @test summary.count == 1
        @test summary.total ≈ 0.016
    end

    if PERFORMANCE_COUNTERS_ENABLED
        @testset "the editor records every counter, with its unit" begin
            editor = Editor(FrameMeasurementProbe(), FrameMeasurementProbeProjection();
                            backend = HeadlessBackend(), devices = Device[])
            # A time that no list names reaches the store all the same.
            run_with_performance_counters() do
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
