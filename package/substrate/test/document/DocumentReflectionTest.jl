"""
`DocumentReflectionModule` — the bounded shadow of a plain Julia object.

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

reflect_kids(node) = node.children
reflect_kid(node, i) = node.children[i]
reflect_tail(node) = (k = node.children; k[length(k)])

function test_document_reflection()
@testset "DocumentReflection" begin

obj = ReflectNested("root", ReflectLeafy(1, "x"), collect(1:1000))
policy = DepthPolicy(depth = 1, elements = 4)

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

# ── Collapse is writing a marker back, same as for documents ──────────────
@testset "collapse sticks" begin
    n = reflect_document(obj, policy)
    request_sync!(reflect_kid(n, 2).children)
    sync_reflection!(n, obj, policy)
    @test reflect_kid(n, 2).children isa CellVector

    reflect_kid(n, 2).children = unsynced_marker(reflect_kid(n, 2).children)
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
