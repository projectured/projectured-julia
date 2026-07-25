"""
`BoundedSyncModule`'s three-argument `sync_document!` — the walk that stops at a
bound and leaves an `UnsyncedDocument` where it stopped.

Two properties carry this suite, and they are what the mechanism is worth:

- **An unbounded policy is the old behaviour, not an imitation of it.** The
  bounded walk mirrors the sealed one's structure, so the only thing keeping the
  two in step is a test that syncs the same source both ways and compares.
- **Ancestors keep their identity across a bounded sync.** That is what lets
  expansion state live in the shadow instead of a side table — a widget holding a
  node must still be holding it after the next sync.
"""

@document struct SyncNode
    label::Any
    child::Any          # ::SyncNode | nothing
end

@document struct SyncPair
    left::Any
    right::Any
end

sync_chain(n::Int) = n == 0 ? SyncNode("leaf", nothing) : SyncNode("n$n", sync_chain(n - 1))

# How deep the real (non-marker) chain goes.
function sync_depth(d)
    k = 0
    while d isa AbstractSyncNode && d.child isa AbstractSyncNode
        k += 1; d = d.child
    end
    k
end

# Depth of the first marker, or -1 if the chain runs to a real leaf.
function sync_marker_depth(d)
    k = 0
    while d isa AbstractSyncNode
        d.child isa AbstractUnsyncedDocument && return k + 1
        d.child isa AbstractSyncNode || return -1
        k += 1; d = d.child
    end
    -1
end

function test_bounded_sync()
@testset "BoundedSync" begin

source = sync_chain(6)

# ── An unbounded policy IS the sealed walk ────────────────────────────────
# Not "behaves like": `sync_document!` with UNBOUNDED_SYNC delegates to the
# two-argument method outright. This test is what would catch a future
# "optimisation" that made it take the bounded path with a large depth instead.
@testset "unbounded policy reproduces the sealed sync" begin
    plain, bounded = sync_chain(6), sync_chain(6)
    sync_document!(plain, source)
    sync_document!(bounded, source, UNBOUNDED_SYNC)

    @test sync_depth(plain) == sync_depth(source) == 6
    @test sync_depth(bounded) == sync_depth(plain)
    @test sync_marker_depth(bounded) == -1
end

# ── The bound produces a marker exactly one level past it ─────────────────
@testset "depth bound leaves a marker where it stopped" begin
    for d in 1:4
        shadow = sync_chain(6)
        sync_document!(shadow, source, DepthPolicy(d))
        @test sync_marker_depth(shadow) == d + 1
        @test sync_depth(shadow) == d
    end
end

# ── Ancestors above the bound match an unbounded sync ─────────────────────
# The bound changes what is *below* it and nothing above.
@testset "ancestors are identical to an unbounded sync" begin
    full, cut = sync_chain(6), sync_chain(6)
    sync_document!(full, source, UNBOUNDED_SYNC)
    sync_document!(cut, source, DepthPolicy(3))

    a, b = full, cut
    for _ in 1:3
        @test a.label == b.label
        a, b = a.child, b.child
    end
    @test b isa AbstractSyncNode && b.child isa AbstractUnsyncedDocument
end

# ── Identity survives, which is the whole basis for storing state in the shadow ──
@testset "same-type children are synced in place" begin
    shadow = sync_chain(6)
    sync_document!(shadow, source, DepthPolicy(2))
    held = shadow.child                       # what a widget would be holding

    source.label = "changed"
    sync_document!(shadow, source, DepthPolicy(2))

    @test shadow.label == "changed"           # leaves still update
    @test shadow.child === held               # ...without replacing the node
    source.label = "n6"
end

# ── The marker says what stands there ─────────────────────────────────────
@testset "marker carries kind and size" begin
    shadow = sync_chain(6)
    sync_document!(shadow, source, DepthPolicy(1))
    m = shadow.child.child

    @test m isa AbstractUnsyncedDocument
    @test string(m.kind) == "SyncNode"
    @test m.size == 2                         # a SyncNode has two fields
    @test m.requested == false                # nobody asked yet
end

# ── The bound is a depth, not a path: every branch stops at the same level ──
@testset "branching stops on every branch" begin
    src = SyncPair(sync_chain(3), sync_chain(3))
    shadow = SyncPair(sync_chain(3), sync_chain(3))
    sync_document!(shadow, src, DepthPolicy(2))

    for side in (shadow.left, shadow.right)
        @test side isa AbstractSyncNode
        @test side.child isa AbstractSyncNode
        @test side.child.child isa AbstractUnsyncedDocument
    end
end

# ── A collection's elements are children like any other ───────────────────
@testset "collection elements obey the bound" begin
    src = CellVector([sync_chain(3), sync_chain(3), sync_chain(3)])
    shadow = CellVector(Any[])
    sync_document!(shadow, src, DepthPolicy(2))

    @test length(shadow) == 3
    for e in shadow
        @test e isa AbstractSyncNode
        @test e.child isa AbstractSyncNode         # depth 2
        @test e.child.child isa AbstractUnsyncedDocument
    end
end

# ── A marker is an ordinary document, so references reach it ──────────────
# It has to be, or a projection could not address one to flag it.
@testset "a marker is addressable" begin
    shadow = sync_chain(6)
    sync_document!(shadow, source, DepthPolicy(1))
    found = search_documents(shadow, d -> d isa AbstractUnsyncedDocument)

    @test length(found) == 1
    @test found[1] === shadow.child.child
end

end
end
