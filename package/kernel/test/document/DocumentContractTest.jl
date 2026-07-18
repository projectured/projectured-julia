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
using ProjecturedKernel.CellModule: Cell, ImmutableCell, is_cell_up_to_date
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

end
end # test_document_contract
