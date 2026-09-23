# The feed seam — the registered inflows of a running editor.
#
# A feed moves what producers stored into a target document, once per frame,
# on the editor task. The inbox is the built-in first feed; every other feed
# is given at construction and the list is fixed from then on. A producer
# wakes the editor through the callback the editor attached at registration.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.FeedModule
import ProjecturedKernel.FeedModule: drain_changes!, compute_wake_deadline,
                                     attach_wake_callback!
import ProjecturedKernel.EditorModule: Editor, InboxFeed, post_operation!,
                                       drain_feeds!, wake_editor!
import ProjecturedKernel.OperationModule: Operation, evaluate_operation
import ProjecturedKernel.FaultModule: record_fault!
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

struct ProbeFeedOperation <: Operation
    log::Vector{Any}
end

evaluate_operation(::Editor, operation::ProbeFeedOperation) =
    (push!(operation.log, (:inbox, current_task())); nothing)

_feed_editor(feeds::Vector{Feed} = Feed[]) =
    Editor(HeadlessBackend(), FeedProbe(), FeedProbeProjection(), Device[];
           feeds = feeds)

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
