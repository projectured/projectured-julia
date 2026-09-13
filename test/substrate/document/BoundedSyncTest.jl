"""
`ReflectionModule` — the walk that stops at a bound and leaves an
`UnsyncedDocument` where it stopped, and the copy that builds such a shadow in
the first place.

Four properties carry this suite, and they are what the mechanism is worth:

- **An unbounded policy is the old behaviour, not an imitation of it.** The
  bounded walk mirrors the sealed one's structure, so the only thing keeping the
  two in step is a test that syncs the same source both ways and compares.
- **Ancestors keep their identity across a bounded sync.** That is what lets
  expansion state live in the shadow instead of a side table — a widget holding a
  node must still be holding it after the next sync.
- **Expansion converges.** One request buys one level, and syncing again with no
  request changes nothing. The failure mode this guards is oscillation: a node
  materialised past the bound being collapsed again by the next sync.
- **Collapse is symmetric with expansion**, at any depth, including inside the
  bound — otherwise the sync would fight the user.
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

# The way a consumer gets a shadow: bounded from the start. A shadow built by the
# ordinary full copy has already grown everything, and a bound can only withhold
# what has not been grown yet.
bounded_shadow(source, depth::Int) =
    copy_document(get_cell_struct_kind(source), source, DepthPolicy(depth))

# How deep the real (non-marker) chain goes.
function sync_depth(d)
    k = 0
    while d isa ASyncNode && d.child isa ASyncNode
        k += 1; d = d.child
    end
    k
end

# The chain's one marker — what a UI would put a chevron on.
function shadow_marker(d)
    while d isa ASyncNode
        d.child isa AUnsyncedDocument && return d.child
        d = d.child
    end
    error("no marker in this shadow")
end

# Depth of the first marker, or -1 if the chain runs to a real leaf.
function sync_marker_depth(d)
    k = 0
    while d isa ASyncNode
        d.child isa AUnsyncedDocument && return k + 1
        d.child isa ASyncNode || return -1
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
        shadow = bounded_shadow(source, d)
        @test sync_marker_depth(shadow) == d + 1
        @test sync_depth(shadow) == d

        sync_document!(shadow, source, DepthPolicy(d))     # and syncing changes nothing
        @test sync_marker_depth(shadow) == d + 1
        @test sync_depth(shadow) == d
    end
end

# ── Ancestors above the bound match an unbounded sync ─────────────────────
# The bound changes what is *below* it and nothing above.
@testset "ancestors are identical to an unbounded sync" begin
    full = sync_chain(6)
    sync_document!(full, source, UNBOUNDED_SYNC)
    cut = bounded_shadow(source, 3)
    sync_document!(cut, source, DepthPolicy(3))

    a, b = full, cut
    for _ in 1:3
        @test a.label == b.label
        a, b = a.child, b.child
    end
    @test b isa ASyncNode && b.child isa AUnsyncedDocument
end

# ── Identity survives, which is the whole basis for storing state in the shadow ──
@testset "same-type children are synced in place" begin
    shadow = bounded_shadow(source, 2)
    held = shadow.child                       # what a widget would be holding

    source.label = "changed"
    sync_document!(shadow, source, DepthPolicy(2))

    @test shadow.label == "changed"           # leaves still update
    @test shadow.child === held               # ...without replacing the node
    source.label = "n6"
end

# ── The marker says what stands there ─────────────────────────────────────
@testset "marker carries kind and size" begin
    m = shadow_marker(bounded_shadow(source, 1))

    @test m isa AUnsyncedDocument
    @test string(m.kind) == "SyncNode"
    @test m.size == 2                         # a SyncNode has two fields
    @test m.requested == false                # nobody asked yet
end

# ── The bound is a depth, not a path: every branch stops at the same level ──
@testset "branching stops on every branch" begin
    src = SyncPair(sync_chain(3), sync_chain(3))
    shadow = bounded_shadow(src, 2)
    sync_document!(shadow, src, DepthPolicy(2))

    for side in (shadow.left, shadow.right)
        @test side isa ASyncNode
        @test side.child isa ASyncNode
        @test side.child.child isa AUnsyncedDocument
    end
end

# ── A collection's elements are children like any other ───────────────────
# Here the shadow starts empty, so the bound governs the elements the sync
# *appends* — the growth path rather than the copy path.
@testset "collection elements obey the bound" begin
    src = CellVector([sync_chain(3), sync_chain(3), sync_chain(3)])
    shadow = CellVector(Any[])
    sync_document!(shadow, src, DepthPolicy(2))

    @test length(shadow) == 3
    for e in shadow
        @test e isa ASyncNode
        @test e.child isa ASyncNode         # depth 2
        @test e.child.child isa AUnsyncedDocument
    end
end

# ── The element cap: what makes a thousand-entry array survivable ─────────
# Depth alone does not save you. A big array is one level down, so a walk bounded
# only by depth still touches every entry of it.
@testset "a large collection syncs a prefix and marks the tail" begin
    big = CellVector([sync_chain(2) for _ in 1:10_000])
    policy = DepthPolicy(depth = 2, elements = 8)

    shadow = copy_document(get_cell_struct_kind(big), big, policy)
    @test length(shadow) == 9                      # 8 elements + one tail marker
    tail = shadow[9]
    @test tail isa AUnsyncedDocument
    @test tail.size == 9_992                       # ...which says how many are behind it

    sync_document!(shadow, big, policy)            # and syncing changes nothing
    @test length(shadow) == 9
    @test shadow[9] === tail

    # the cost is the point: touching 8 of 10 000 must not scale with the 10 000
    n = @allocated sync_document!(shadow, big, policy)
    @test n < 100_000
end

@testset "requesting the tail buys one more page" begin
    big = CellVector([sync_chain(1) for _ in 1:100])
    policy = DepthPolicy(depth = 1, elements = 10)
    shadow = copy_document(get_cell_struct_kind(big), big, policy)

    for shown in (20, 30, 40)
        request_sync!(shadow[length(shadow)])
        sync_document!(shadow, big, policy)
        @test length(shadow) == shown + 1
        @test shadow[shown + 1].size == 100 - shown
        @test !shadow[shown + 1].requested         # the request is spent, not sticky
    end
end

@testset "a collection shorter than the cap has no tail marker" begin
    small = CellVector([sync_chain(1) for _ in 1:3])
    policy = DepthPolicy(depth = 2, elements = 8)
    shadow = copy_document(get_cell_struct_kind(small), small, policy)

    @test length(shadow) == 3
    @test !any(e -> e isa AUnsyncedDocument, shadow)

    pop!(small); sync_document!(shadow, small, policy)   # and it tracks a shrinking source
    @test length(shadow) == 2
end

# ── Requests: the drill-down, one level per interaction ───────────────────
# This is the mechanism's whole point — the shadow grows only where someone
# looked, and it grows a level at a time rather than all at once.
@testset "a requested marker fills in one level" begin
    shadow = bounded_shadow(source, 1)
    @test sync_marker_depth(shadow) == 2

    for expected in 3:6
        request_sync!(shadow_marker(shadow))
        sync_document!(shadow, source, DepthPolicy(1))
        @test sync_marker_depth(shadow) == expected
    end

    # ...and at the bottom the marker is gone, because there is nothing below
    request_sync!(shadow_marker(shadow))
    sync_document!(shadow, source, DepthPolicy(1))
    @test sync_marker_depth(shadow) == -1
    @test sync_depth(shadow) == 6
end

@testset "an unasked marker stays put across syncs" begin
    shadow = bounded_shadow(source, 2)
    held = shadow_marker(shadow)

    for _ in 1:5
        sync_document!(shadow, source, DepthPolicy(2))
    end
    @test sync_marker_depth(shadow) == 3
    @test shadow_marker(shadow) === held      # not even rewritten
end

# ── Collapse is the inverse, and it sticks ────────────────────────────────
@testset "expand then collapse returns to where it started" begin
    shadow = bounded_shadow(source, 2)
    before = sync_marker_depth(shadow)

    request_sync!(shadow_marker(shadow))
    sync_document!(shadow, source, DepthPolicy(2))
    @test sync_marker_depth(shadow) == before + 1

    # collapse: write a marker back over the node the request materialised
    parent = shadow.child.child                # depth 2; its child is the new depth 3
    parent.child = make_unsynced_marker(parent.child)
    sync_document!(shadow, source, DepthPolicy(2))
    @test sync_marker_depth(shadow) == before
end

# The depth bound says where growth *starts*, not what may be collapsed. A
# collapse inside the bound must survive the next sync, or the UI would fight it.
@testset "a collapse inside the depth bound is not undone" begin
    shadow = bounded_shadow(source, 4)
    @test sync_marker_depth(shadow) == 5

    shadow.child = make_unsynced_marker(shadow.child)   # collapse at depth 1, well inside
    for _ in 1:3
        sync_document!(shadow, source, DepthPolicy(4))
        @test sync_marker_depth(shadow) == 1
    end
end

# ── A request cannot outlive the node it was made on (§5) ─────────────────
# Expansion replaces the marker, so the flag goes with it; and a marker under a
# wholesale-replaced parent is a fresh one, never a resurrected request.
@testset "requests do not resurrect" begin
    shadow = bounded_shadow(source, 1)
    m = shadow_marker(shadow)
    request_sync!(m)
    sync_document!(shadow, source, DepthPolicy(1))

    @test !(shadow.child.child isa AUnsyncedDocument)   # m was consumed
    @test m.requested                                          # the discarded marker still says so
    deeper = shadow_marker(shadow)
    @test deeper !== m && !deeper.requested                    # ...but the new one does not

    # a wholesale parent replacement rebuilds the subtree from scratch
    src = SyncPair(sync_chain(3), sync_chain(3))
    sh = bounded_shadow(src, 1)
    request_sync!(sh.left.child)
    sh.left = make_unsynced_marker(sh.left)          # collapse the parent, request and all
    sync_document!(sh, src, DepthPolicy(1))
    @test sh.left isa AUnsyncedDocument  # stays collapsed; the inner request is gone
end

# ── A marker is an ordinary document, so references reach it ──────────────
# It has to be, or a projection could not address one to flag it.
@testset "a marker is addressable" begin
    shadow = bounded_shadow(source, 1)
    found = search_documents(shadow, d -> d isa AUnsyncedDocument)

    @test length(found) == 1
    @test found[1] === shadow.child.child
end

end
end
