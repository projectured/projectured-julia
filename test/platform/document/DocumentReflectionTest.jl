"""
`ReflectionModule` — the bounded shadow of a plain Julia object.

Bounded sync needs a `Document` on both sides, and the things worth inspecting (a
live engine, a model) are ordinary structs. This walk closes that gap, and the
property it has to deliver is the one the whole feature exists for: **cost tracks
what is displayed, not what exists**. A million-element field that nobody opened
must cost the same as a thousand-element one.
"""

mutable struct ReflectLeafy
    n::Int
    s::String
end

mutable struct ReflectNested
    name::String
    inner::ReflectLeafy
    data::Vector{Int}
end

# `Document` is two things: the shape `@document` builds, and the bound an event
# argument is stored inline under. A type that is one only through the bound has
# no `selection` slot, and every field it declares is content.
mutable struct ReflectBoundOnly <: Document
    first_field::Int
    last_field::String
end

# And one that DOES hold the slot, declared the way a value-document declares it.
mutable struct ReflectWithSlot <: Document
    first_field::Int
    last_field::String
    selection::Nothing
end

# A value whose count of children notes the task that asks for it, and throws
# while `fails` is set.
mutable struct ReflectTaskProbe
    tasks::Vector{Task}
    fails::Bool
end
ProjecturedPlatform.ReflectionModule.reflect_child_count(probe::ReflectTaskProbe) =
    (push!(probe.tasks, current_task()); probe.fails && error("the count failed"); 1)
ProjecturedPlatform.ReflectionModule.reflect_child_pairs(probe::ReflectTaskProbe) = ("tasks" => 1,)

reflect_kids(node) = node.children
reflect_kid(node, i) = node.children[i]
reflect_tail(node) = (k = node.children; k[length(k)])

function test_document_reflection()
@testset "DocumentReflection" begin

obj = ReflectNested("root", ReflectLeafy(1, "x"), collect(1:1000))
policy = DepthPolicy(depth = 1, elements = 4)

# ── Which last field is machinery, and which is content ───────────────────
@testset "the selection slot is hidden by its name, not by a supertype" begin
    # A `Document` that never met the macro keeps every field it declares.
    bound = ReflectBoundOnly(1, "kept")
    @test [p.first for p in reflect_children(bound)] == ["first_field", "last_field"]
    @test reflect_child_count(bound) == 2
    # The count bounds what the sync builds and the pairs build it, so the two
    # must agree or a row goes missing or a phantom tail appears.
    @test reflect_child_count(bound) == length(reflect_children(bound))

    # One that holds the slot hides it, exactly as before.
    slotted = ReflectWithSlot(1, "kept", nothing)
    @test [p.first for p in reflect_children(slotted)] == ["first_field", "last_field"]
    @test reflect_child_count(slotted) == 2
    @test reflect_child_count(slotted) == length(reflect_children(slotted))
end

# ── The bound applies to a plain object exactly as it does to a document ──
@testset "one level open, the rest marked" begin
    n = reflect_document(obj, policy)

    @test n.kind == "ReflectNested"
    @test length(reflect_kids(n)) == 3

    name, inner, data = reflect_kid(n, 1), reflect_kid(n, 2), reflect_kid(n, 3)
    @test (name.label, name.value) == ("name", "root")
    @test name.children === nothing                  # a leaf has no children slot

    @test inner.children isa AUnsyncedDocument
    @test inner.children.size == 2                   # ...and the marker says how many
    @test data.children isa AUnsyncedDocument
    @test data.children.size == 1000

    # a parameterised type keeps its parameters — `Array` would lose the point
    @test data.kind == "Vector{Int64}"
end

# ── Drill-down, one level per request ─────────────────────────────────────
@testset "requesting a marker opens one level" begin
    n = reflect_document(obj, policy)
    request_sync!(reflect_kid(n, 2).children)
    sync_reflection!(n, obj, policy)

    kids = reflect_kids(reflect_kid(n, 2))
    @test length(kids) == 2
    @test (kids[1].label, kids[1].value) == ("n", "1")
    @test (kids[2].label, kids[2].value) == ("s", "x")
end

# ── The element cap is what makes a big field survivable ──────────────────
@testset "a big field shows a page and marks the rest" begin
    n = reflect_document(obj, policy)
    request_sync!(reflect_kid(n, 3).children)
    sync_reflection!(n, obj, policy)

    kids = reflect_kids(reflect_kid(n, 3))
    @test length(kids) == 5                          # 4 elements + tail marker
    @test [kids[i].value for i in 1:4] == ["1", "2", "3", "4"]
    @test reflect_tail(reflect_kid(n, 3)).size == 996

    request_sync!(reflect_tail(reflect_kid(n, 3)))   # ...and one more page
    sync_reflection!(n, obj, policy)
    @test length(reflect_kids(reflect_kid(n, 3))) == 9
    @test reflect_tail(reflect_kid(n, 3)).size == 992
end

# ── Identity, so a widget keeps holding what it holds ─────────────────────
@testset "materialised nodes survive a sync, values update" begin
    n = reflect_document(obj, policy)
    request_sync!(reflect_kid(n, 2).children)
    sync_reflection!(n, obj, policy)

    held_node = reflect_kid(n, 2)
    held_kids = reflect_kids(held_node)

    obj.inner.n = 42
    obj.name = "renamed"
    sync_reflection!(n, obj, policy)

    @test reflect_kid(n, 1).value == "renamed"
    @test held_kids[1].value == "42"
    @test reflect_kid(n, 2) === held_node            # identity preserved
    @test reflect_kids(held_node) === held_kids

    obj.inner.n = 1; obj.name = "root"
end

@testset "the feed syncs at most once per interval, and a chevron at once" begin
    # A sync that writes changes the display, and the frame of the display event
    # must not sync again, or a value that changes all the time would redraw on
    # every frame.
    drain! = ProjecturedKernel.FeedModule.drain_changes!
    deadline = ProjecturedKernel.FeedModule.compute_wake_deadline
    value = ReflectNested("root", ReflectLeafy(1, "x"), collect(1:10))
    n = reflect_document(value, policy)
    clock = Ref(5.0)
    feed = ReflectionFeed(n, value; policy = policy, now = () -> clock[])
    # A drain starts a read of the value on a task of its own, and the next drain
    # writes what it read.
    function sync!(feed)
        drain!(feed, nothing)
        feed.reading === nothing || wait(feed.reading)
        drain!(feed, nothing)
    end
    sync!(feed)
    @test deadline(feed, nothing) === nothing
    value.name = "renamed"
    clock[] += 0.125
    # Too soon: the sync waits, and the feed asks for a frame at the interval's end.
    @test drain!(feed, nothing) == 0
    @test reflect_kid(n, 1).value == "root"
    @test deadline(feed, nothing) == 0.125
    # A chevron does not wait.
    request_sync!(reflect_kid(n, 2).children)
    @test deadline(feed, nothing) == 0.0
    @test drain!(feed, nothing) == 0
    wait(feed.reading)
    @test deadline(feed, nothing) == 0.0
    @test drain!(feed, nothing) == 1
    @test reflect_kid(n, 1).value == "renamed"
    @test deadline(feed, nothing) === nothing
    value.name = "again"
    clock[] += 0.5
    sync!(feed)
    @test reflect_kid(n, 1).value == "again"
end

@testset "the feed reads the value off the loop, and writes it on the next drain" begin
    drain! = ProjecturedKernel.FeedModule.drain_changes!
    probe = ReflectTaskProbe(Task[], false)
    n = reflect_document(probe, policy)
    empty!(probe.tasks)
    feed = ReflectionFeed(n, probe; policy = policy)
    woken = Ref(0)
    ProjecturedKernel.FeedModule.attach_wake_callback!(feed, () -> (woken[] += 1))
    @test drain!(feed, nothing) == 0
    wait(feed.reading)
    @test woken[] == 1
    @test !isempty(probe.tasks) && all(task -> task !== current_task(), probe.tasks)
    @test drain!(feed, nothing) == 0
    @test feed.reading === nothing
    # A read that throws is thrown by the drain that would write it, and asks for
    # no frame.
    probe.fails = true
    feed.synced_at = -Inf
    drain!(feed, nothing)
    wait(feed.reading)
    @test_throws CapturedException drain!(feed, nothing)
    @test ProjecturedKernel.FeedModule.compute_wake_deadline(feed, nothing) === nothing
end

@testset "a node that opens during a read keeps its marker, and the next read fills it" begin
    drain! = ProjecturedKernel.FeedModule.drain_changes!
    value = ReflectNested("root", ReflectLeafy(1, "x"), collect(1:10))
    n = reflect_document(value, policy)
    feed = ReflectionFeed(n, value; policy = policy)
    drain!(feed, nothing)
    wait(feed.reading)
    # The chevron of the field `inner` opens after the read took its snapshot.
    request_sync!(reflect_kid(n, 2).children)
    @test drain!(feed, nothing) == 0
    @test reflect_kid(n, 2).children isa AUnsyncedDocument && reflect_kid(n, 2).children.requested
    drain!(feed, nothing)
    wait(feed.reading)
    @test drain!(feed, nothing) == 1
    @test reflect_kid(n, 2).children isa CellVector
end

# ── Collapse is writing a marker back, same as for documents ──────────────
@testset "collapse sticks" begin
    n = reflect_document(obj, policy)
    request_sync!(reflect_kid(n, 2).children)
    sync_reflection!(n, obj, policy)
    @test reflect_kid(n, 2).children isa CellVector

    reflect_kid(n, 2).children = make_unsynced_marker(reflect_kid(n, 2).children)
    for _ in 1:3
        sync_reflection!(n, obj, policy)
        @test reflect_kid(n, 2).children isa AUnsyncedDocument
    end
end

# ── The property the whole feature exists for ─────────────────────────────
# A collapsed field must cost the same whether it holds a thousand entries or a
# million. If this regresses, the bound is being defeated somewhere upstream —
# most likely by something materialising all the children just to count them.
@testset "cost does not grow with what is not shown" begin
    small = ReflectNested("s", ReflectLeafy(0, "a"), collect(1:1_000))
    huge  = ReflectNested("h", ReflectLeafy(0, "a"), collect(1:1_000_000))

    ns = reflect_document(small, policy); sync_reflection!(ns, small, policy)
    nh = reflect_document(huge, policy);  sync_reflection!(nh, huge, policy)

    as = @allocated sync_reflection!(ns, small, policy)
    ah = @allocated sync_reflection!(nh, huge, policy)
    @test ah < 2 * as
    @test ah < 100_000
end

end
end
