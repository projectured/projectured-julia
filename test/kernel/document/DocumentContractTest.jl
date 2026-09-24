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
using ProjecturedKernel.CellModule: Cell, Computed, ImmutableCell, ReactiveCell,
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

# Two slots that can hold one child twice, or the pair itself.
@document struct ContractPair
    first::Any
    second::Any
end

# Stops at the node that carries `label`, and puts a node labelled "stopped" there.
struct ContractStopPolicy <: CopyPolicy
    label::String
end
ProjecturedKernel.DocumentModule.is_descendable_for_copy(p::ContractStopPolicy, document::ToyNode) =
    document.label != p.label
ProjecturedKernel.DocumentModule.make_copy_placeholder(::ContractStopPolicy, document) =
    ToyNode("stopped", nothing, nothing)

# Records each copy, so a child met twice is one copy.
struct ContractMemoPolicy <: CopyPolicy
    copies::IdDict{Any,Any}
end
ContractMemoPolicy() = ContractMemoPolicy(IdDict{Any,Any}())
ProjecturedKernel.DocumentModule.get_copy_memo(p::ContractMemoPolicy) = p.copies

# Refuses the node that carries `label`, and every cell that computes.
struct ContractRefusePolicy <: CopyPolicy
    label::String
end
function ProjecturedKernel.DocumentModule.is_descendable_for_copy(p::ContractRefusePolicy, document::ToyNode)
    document.label == p.label && throw(DocumentCopyException(document, "it is refused"))
    true
end
ProjecturedKernel.DocumentModule.copy_computed_cell(::ContractRefusePolicy, cell) =
    throw(DocumentCopyException(cell, "it computes"))

# The toy kinds that declare a duplicate. `ToyBox` declares none.
ProjecturedKernel.DocumentModule.has_document_duplicate(::ToyNode) = true
ProjecturedKernel.DocumentModule.has_document_duplicate(::ContractPair) = true

# Copies every node with its label in upper case: a method on the pair.
struct ContractShoutPolicy <: CopyPolicy end
ProjecturedKernel.DocumentModule.copy_document(p::ContractShoutPolicy, document::ToyNode) =
    copy_document_fields(p, document; label = uppercase(document.label))

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
        native = MToyNode("root", nothing, nothing)
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
        @test copy_document(native) isa MToyNode
    end

    @testset "a new native child reaches a cell shadow as a cell node" begin
        source = MToyBox(nothing, nothing)
        shadow = ToyBox(nothing, nothing)
        source.content = MToyNode("first", nothing, nothing)
        sync_document!(shadow, source)
        # The child is rebuilt in the shadow's own layout, not copied across as it was.
        @test shadow.content isa ToyNode
        @test getfield(shadow.content, :label) isa AbstractCell

        # The point of the shadow: a reader of it runs again when the source moves.
        # A native child would read correctly here and never invalidate.
        seen = Cell(@computation(shadow.content === nothing ? "" :
                                 shadow.content.label))
        @test seen[] == "first"
        source.content.label = "second"
        sync_document!(shadow, source)
        @test seen[] == "second"
    end

    @testset "a tree that holds no cells is not a shadow" begin
        source = MToyBox(nothing, nothing)
        source.content = MToyNode("first", nothing, nothing)
        # Nothing in a native tree can invalidate a reader, so it cannot serve as a
        # shadow. The walk used to fail as a copy_document method that does not exist.
        @test_throws ErrorException sync_document!(MToyBox(nothing, nothing), source)
        # A cell shadow of the same schema takes the very same source.
        @test sync_document!(ToyBox(nothing, nothing), source).content isa ToyNode
    end

    @testset "copy_document under a policy" begin
        tree() = ToyNode("root", ToyNode("middle", ToyNode("leaf", nothing, nothing), nothing), nothing)

        @testset "the plain copy is the walk under PlainCopyPolicy" begin
            root = tree()
            clone = copy_document(PlainCopyPolicy(), root)
            @test clone isa ToyNode
            @test clone !== root
            @test clone.child !== root.child
            @test clone.child.child.label == "leaf"
            @test getfield(clone, :label) !== getfield(root, :label)
        end

        @testset "a policy stops at a kind and puts its placeholder there" begin
            root = tree()
            clone = copy_document(ContractStopPolicy("middle"), root)
            @test clone.label == "root"
            @test clone.child.label == "stopped"
            @test clone.child.child === nothing
            # The root is asked too.
            @test copy_document(ContractStopPolicy("root"), root).label == "stopped"
        end

        @testset "a memo makes a child met twice one copy" begin
            shared = ToyNode("shared", nothing, nothing)
            pair = ContractPair(shared, shared, nothing)
            clone = copy_document(ContractMemoPolicy(), pair)
            @test clone.first === clone.second
            @test clone.first !== shared
            # With no memo, each slot gets a copy of its own.
            plain = copy_document(pair)
            @test plain.first !== plain.second
        end

        @testset "a memo stops a document that holds itself" begin
            pair = ContractPair(nothing, nothing, nothing)
            pair.second = pair
            @test_throws DocumentCopyException copy_document(ContractMemoPolicy(), pair)
        end

        @testset "a hook refuses the whole copy from any depth" begin
            exception = try
                copy_document(ContractRefusePolicy("leaf"), tree())
                nothing
            catch e
                e
            end
            @test exception isa DocumentCopyException
            @test exception.value.label == "leaf"
            @test occursin("is refused", sprint(showerror, exception))
        end

        @testset "a cell that computes is the policy's to copy" begin
            node = ToyNode("", nothing, nothing)
            set_cell_function!(getfield(node, :label), () -> "computed")
            @test is_computed_cell(getfield(node, :label))
            # The plain copy keeps a moment of it, in a cell that stores.
            clone = copy_document(node)
            @test clone.label == "computed"
            @test !is_computed_cell(getfield(clone, :label))
            @test_throws DocumentCopyException copy_document(ContractRefusePolicy("none"), node)
        end

        @testset "a method on the pair replaces one step and keeps the walk" begin
            clone = copy_document(ContractShoutPolicy(), tree())
            @test clone.label == "ROOT"
            @test clone.child.child.label == "LEAF"
        end

        @testset "a replacement takes the value given, in a new cell" begin
            root = tree()
            clone = copy_document_fields(PlainCopyPolicy(), root; label = "renamed")
            @test clone.label == "renamed"
            @test root.label == "root"
            @test getfield(clone, :label) isa AbstractCell
            @test clone.child !== root.child
            @test_throws ArgumentError copy_document_fields(PlainCopyPolicy(), root; lable = "x")
        end
    end

    @testset "the duplicate of a document" begin
        # The reason a refusal gives, or `nothing` when the duplicate is made.
        refusal(document) = try
            make_document_duplicate(document)
            nothing
        catch e
            e isa DocumentCopyException || rethrow()
            e.reason
        end

        @testset "a kind that declares one gets an equal and independent copy" begin
            root = ToyNode("root", ToyNode("leaf", nothing, nothing), nothing)
            duplicate = make_document_duplicate(root)
            @test duplicate.child.label == "leaf"
            duplicate.child.label = "changed"
            @test root.child.label == "leaf"
            @test has_document_duplicate(root)
        end

        @testset "the selection is copied" begin
            path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
            root = with_selection(ToyNode("root", nothing, nothing), path)
            duplicate = make_document_duplicate(root)
            @test strip_reference_types(get_selection(duplicate)) ==
                  strip_reference_types(get_selection(root))
            @test getfield(duplicate, :selection) !== getfield(root, :selection)
        end

        @testset "a selection that a projection computes is copied as it is now" begin
            path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
            node = ToyNode("root", nothing, nothing)
            set_cell_function!(getfield(node, :selection), () -> path)
            @test is_computed_cell(getfield(node, :selection))
            duplicate = make_document_duplicate(node)
            @test !is_computed_cell(getfield(duplicate, :selection))
            @test strip_reference_types(getfield(duplicate, :selection)[]) ==
                  strip_reference_types(path)
        end

        @testset "a child whose kind declares none is shared" begin
            box = ToyBox(nothing, nothing)
            pair = ContractPair(box, ToyNode("own", nothing, nothing), nothing)
            duplicate = make_document_duplicate(pair)
            @test duplicate.first === box
            @test duplicate.second !== pair.second
            @test !has_document_duplicate(box)
            @test occursin("declares no duplicate", refusal(box))
        end

        @testset "what the duplicate can not own refuses it" begin
            computed = ToyNode("", nothing, nothing)
            set_cell_function!(getfield(computed, :label), () -> "computed")
            @test occursin("computes", refusal(computed))
            @test occursin("action", refusal(ToyNode(() -> "called", nothing, nothing)))
            @test occursin("action", refusal(ContractPair(Ref{Any}(1), nothing, nothing)))
            looped = ContractPair(nothing, nothing, nothing)
            looped.second = looped
            @test occursin("back-link", refusal(looped))
            # A plain value and a shared data object are no reason to refuse.
            data = Dict(:a => 1)
            @test make_document_duplicate(ContractPair(data, 2, nothing)).first === data
        end
    end

end
end # test_document_contract
