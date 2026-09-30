"""
`ReflectionToWidget` — a bounded reflected shadow rendered as a `WidgetTree`,
where a chevron drives the sync instead of merely hiding a row.

The thing under test is the *round trip*, because that is where this design
differs from an ordinary tree. `WidgetTree` owns an `expanded` set; here that set
is derived from the shadow on every print and never written back. A chevron click must therefore reach the shadow — setting a marker's `requested`
so the next sync opens one more level — and must never edit the widget's own
copy, or the widget and the shadow would hold two disagreeing versions of the
same state.

The reader is PURE (PAR-READER-IS-PURE): it returns a
`SetReflectedDisclosureOperation` naming the nodes that toggled, and evaluating
that is what moves the shadow. `apply_chevron!` below does both, standing in for
what the editor does with whatever a reader returns.
"""

mutable struct TreeReflectInner
    a::Int
    b::String
end

mutable struct TreeReflectOuter
    name::String
    inner::TreeReflectInner
    data::Vector{Int}
end

# Every label in the tree, depth-first — enough to say what is on screen.
function tree_labels(node, out = String[])
    push!(out, String(node.label))
    for c in node.children
        tree_labels(c, out)
    end
    out
end

# The operation a chevron click produces: the printed set with `path` toggled.
function chevron(tree, path::Vector{Int})
    next = copy(tree.expanded)
    path in next ? delete!(next, path) : push!(next, path)
    ReplaceReferencedValueOperation(tree, "expanded", next)
end

# Click a chevron the way the editor would: read the intent, then evaluate what
# it returns. Returns the operation so a test can assert on it.
function apply_chevron!(projection, iomap, path::Vector{Int})
    op = read_intent(projection, iomap, chevron(iomap.output, path))
    op === nothing || evaluate_operation(nothing, op)
    op
end

function test_reflection_to_widget()
@testset "ReflectionToWidget" begin

obj = TreeReflectOuter("root", TreeReflectInner(1, "x"), collect(1:100))
policy = DepthPolicy(depth = 1, elements = 4)
projection = ReflectionToWidget()

@testset "an unopened node is collapsed, and says how much is behind it" begin
    shadow = reflect_document(obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)
    tree = iomap.output
    labels = tree_labels(tree.roots[1])

    @test "name = root" in labels                    # a leaf shows its value
    @test "inner: TreeReflectInner" in labels
    @test "100 items not loaded" in labels           # ...a marker says what it hides

    # The open set is derived from the shadow: exactly the nodes whose children
    # show. The two nodes on markers are closed.
    @test tree.expanded == Set([[1]])
end

@testset "a chevron reaches the shadow and is swallowed" begin
    shadow = reflect_document(obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)
    marker = shadow.children[2].children
    @test marker isa AUnsyncedDocument
    @test !marker.requested

    @test apply_chevron!(projection, iomap, [1, 2]) isa SetReflectedDisclosureOperation
    @test marker.requested                           # the click landed on the shadow
end

# The acceptance test for the whole mechanism, end to end.
@testset "expand, sync, and one more level appears" begin
    shadow = reflect_document(obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)

    apply_chevron!(projection, iomap, [1, 2])
    sync_reflection!(shadow, obj, policy)
    labels = tree_labels(print_document(projection, nothing, shadow, nothing).output.roots[1])

    @test "a = 1" in labels                          # the level that was requested
    @test "b = x" in labels
    @test "100 items not loaded" in labels           # ...and only that one
    @test !("1" in labels)
end

# A live editor keeps the tree it printed and prints no second time, so the
# printed tree must follow the sync by itself.
@testset "the printed tree follows a sync" begin
    shadow = reflect_document(obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)
    @test !([1, 2] in iomap.output.expanded)

    apply_chevron!(projection, iomap, [1, 2])
    sync_reflection!(shadow, obj, policy)

    @test [1, 2] in iomap.output.expanded
    @test "a = 1" in tree_labels(iomap.output.roots[1])
    # The reader diffs against the tree as it is now, so the same chevron closes
    # the node it opened.
    @test apply_chevron!(projection, iomap, [1, 2]) isa SetReflectedDisclosureOperation
    @test shadow.children[2].children isa AUnsyncedDocument
    @test !([1, 2] in iomap.output.expanded)
end

@testset "collapsing puts a marker back" begin
    shadow = reflect_document(obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)
    apply_chevron!(projection, iomap, [1, 2])
    sync_reflection!(shadow, obj, policy)

    iomap = print_document(projection, nothing, shadow, nothing)
    @test [1, 2] in iomap.output.expanded            # now open

    apply_chevron!(projection, iomap, [1, 2])
    sync_reflection!(shadow, obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)

    @test !([1, 2] in iomap.output.expanded)
    @test !("a = 1" in tree_labels(iomap.output.roots[1]))
    @test shadow.children[2].children isa AUnsyncedDocument
end

# A capped collection's tail is a marker like any other, so the same click opens
# it — which is what makes a thousand-entry field walkable rather than merely
# summarised.
@testset "the tail of a capped collection opens too" begin
    shadow = reflect_document(obj, policy)
    iomap = print_document(projection, nothing, shadow, nothing)
    apply_chevron!(projection, iomap, [1, 3])
    sync_reflection!(shadow, obj, policy)

    labels = tree_labels(print_document(projection, nothing, shadow, nothing).output.roots[1])
    @test "1 = 1" in labels
    @test "4 = 4" in labels
    @test "96 items not loaded" in labels
end

@testset "a row lights while the pointer is on it" begin
    shadow = reflect_document(obj, policy)
    chain = ChainingProjection(projection,
                               make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0)))
    driver = MttDriver(chain, shadow)
    tree = driver.iomap.child_iomap.step_iomaps[1][].output
    lit_row() = WidgetModule._wtree_ref_path(get_mouse_target(tree))
    # A row is no part of the reflected node, so the node holds it as a part of
    # the view, and the tree holds the node path of the row.
    _mtt_move!(driver, 20, 5, 1.0)
    @test lit_row() == [1]
    _mtt_move!(driver, 20, 55, 1.1)
    @test length(lit_row()) == 2 && lit_row()[1] == 1
    _mtt_move!(driver, 900, 900, 1.2)
    @test get_mouse_target(tree) === nothing
end

end
end
