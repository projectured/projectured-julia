"""
`DocumentModule` — the document contract, exercised through a test-local
`ToyNode` type. Kernel tests must use ONLY toy documents/projections defined
test-locally, so the concrete engine documents (Collection, Primitive,
ScreenDocument) cannot leak in as fixtures — the resulting pressure is what
keeps the interface sufficient.

Covers:
- `@document` field auto-wrapping in Cells,
- `getproperty` unwraps stored Cells,
- selection contract: get/clear/set/with produce and propagate paths,
- `copy_document` round-trips a document tree (same kind and kind-converting).
"""

using Test
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.CellModule: Cell, ComputedCell, ImmutableCell, ReactiveCell,
                                    AbstractCell, is_cell_up_to_date
# The reference layer supplies the type our test-local selection field carries.
# Non-cell/document imports are allowed only to build the fixture; the contract
# tests below still exercise DocumentModule generics.
using ProjecturedKernel.ReferenceModule: EmptyReference, Reference,
                                         FieldReferenceStep, extend_reference,
                                         strip_reference_types

@document struct ToyNode
    label::String
    child::Union{ToyNode, Nothing}
end

# A field typed `Document` rather than one schema. That is what lets a *native*
# node into a tree of any layout, because a native node is a `Document`, and so it
# is the shape the layout rules are about. `ToyNode.child` above is typed to one
# schema and cannot hold a native node at all.
@document struct ToyBox
    content::Union{Document, Nothing} = nothing
end

function test_document_contract()
@testset "DocumentContract" begin

    @testset "@document constructs and unwraps cells" begin
        n = ToyNode("root", nothing, nothing)
        # Field auto-wrap: passing a bare value works; the field is stored as a
        # Cell under the hood but property access reads through.
        @test n.label == "root"
        @test n.child === nothing
        @test n isa Document
        # Every document carries a selection field per the contract.
        @test hasfield(typeof(n), :selection)
        @test get_selection(n) === nothing
    end

    @testset "selection contract: with_selection sets, clear_selection! clears" begin
        n = ToyNode("root", ToyNode("child", nothing, nothing), nothing)
        # A path selecting the label field.
        path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
        n2 = with_selection(n, path)
        @test n2 === n                                              # returns the document
        # Selection round-trips ignoring the reference-type annotation that
        # `set_selection!` adds — that's how every domain compares selections.
        @test strip_reference_types(get_selection(n)) == path

        clear_selection!(n)
        @test get_selection(n) === nothing
        # Deep clear: a child's selection is also cleared. Set a compound path,
        # then clear the root; the leaf's selection cell should read `nothing`.
        deep = extend_reference(
            extend_reference(EmptyReference(), FieldReferenceStep("child")),
            FieldReferenceStep("label"))
        set_selection!(n, deep)
        @test strip_reference_types(get_selection(n)) == deep
        clear_selection!(n)
        @test get_selection(n) === nothing
        @test get_selection(n.child) === nothing
    end

    @testset "copy_document round-trips a document tree" begin
        leaf = ToyNode("leaf", nothing, nothing)
        root = ToyNode("root", leaf, nothing)
        # `copy_document(K, doc)` returns a kind-converted form of the tree.
        snap = copy_document(ImmutableCell, root)
        @test snap isa ToyNode
        @test snap.label == "root"
        @test snap.child.label == "leaf"
        # `copy_document(doc)` produces an independent copy preserving the
        # source's kind that reads back equal at every level.
        clone = copy_document(root)
        @test clone !== root
        @test clone.label == "root"
        @test clone.child.label == "leaf"
    end

    @testset "copy_document preserves a function-valued field" begin
        # Copying re-boxes each field through its cell's constructor, which used to turn
        # a callback into a thunk — so a copied document called its own callbacks on read.
        callback() = "called"
        node = ToyNode(callback, nothing, nothing)
        @test copy_document(node).label === callback
        @test copy_document(ImmutableCell, node).label === callback
    end

    @testset "a kinded copy targets the cell layout, a plain copy keeps the layout" begin
        native = ToyNodeMut("root", nothing, nothing)
        # A kind is a property of a cell, so a kinded copy of a native source has to
        # convert. Copying the source's own layout is what let a native node into a
        # cell shadow, where nothing could ever invalidate it.
        reactive = copy_document(ReactiveCell, native)
        @test reactive isa ToyNode
        @test getfield(reactive, :label) isa ReactiveCell
        @test reactive.label == "root"
        @test copy_document(ImmutableCell, native) isa ToyNode
        @test getfield(copy_document(ImmutableCell, native), :label) isa ImmutableCell
        # The plain copy preserves the layout, so a native document copies into one.
        @test copy_document(native) isa ToyNodeMut
    end

    @testset "a new native child reaches a cell shadow as a cell node" begin
        source = ToyBoxMut(nothing, nothing)
        shadow = ToyBox(nothing, nothing)
        source.content = ToyNodeMut("first", nothing, nothing)
        sync_document!(shadow, source)
        # The child is rebuilt in the shadow's own layout, not copied across as it was.
        @test shadow.content isa ToyNode
        @test getfield(shadow.content, :label) isa AbstractCell

        # The point of the shadow: a reader of it runs again when the source moves.
        # A native child would read correctly here and never invalidate.
        seen = ComputedCell(() -> shadow.content === nothing ? "" : shadow.content.label)
        @test seen[] == "first"
        source.content.label = "second"
        sync_document!(shadow, source)
        @test seen[] == "second"
    end

    @testset "a tree that holds no cells is not a shadow" begin
        source = ToyBoxMut(nothing, nothing)
        source.content = ToyNodeMut("first", nothing, nothing)
        # Nothing in a native tree can invalidate a reader, so it cannot serve as a
        # shadow. The walk used to fail as a copy_document method that does not exist.
        @test_throws ErrorException sync_document!(ToyBoxMut(nothing, nothing), source)
        # A cell shadow of the same schema takes the very same source.
        @test sync_document!(ToyBox(nothing, nothing), source).content isa ToyNode
    end

end
end # test_document_contract
