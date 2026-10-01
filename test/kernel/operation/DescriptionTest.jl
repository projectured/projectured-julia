"""
`OperationModule` — how an operation is written for a human, in one line.
Verifies `describe_operation` for each operation of this layer, the fallback for
an operation type that the layer does not name, the form of a value, and the
`(operation, root)` form, which writes a reference from the deepest titled
document on it with `describe_reference`.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.OperationModule
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.ReferenceModule

@document struct DescriptionItem
    price::Int
end

@document struct DescriptionList
    entries::Vector{DescriptionItem}
end

# A test-local document with a title, as a file is: it edits the document that
# its `content` field holds.
@document struct DescriptionFile
    content::DescriptionList
end
ProjecturedKernel.DocumentModule.get_document_title(::DescriptionFile) = "items.json"
ProjecturedKernel.DocumentModule.get_edited_field(::DescriptionFile) = :content

# A test-local operation that the layer does not name, with no reference.
struct DescriptionProbeOperation <: Operation end

# A test-local operation that the layer does not name, with a reference.
struct DescriptionMoveOperation <: Operation
    reference::Reference
end
ProjecturedKernel.OperationModule.operation_reference(
    operation::DescriptionMoveOperation) = operation.reference

_make_description_file() =
    DescriptionFile(DescriptionList([DescriptionItem(1, nothing),
                                     DescriptionItem(2, nothing)], nothing), nothing)

function test_description()
@testset "Description" begin

    @testset "each operation of the layer has its words" begin
        @test describe_operation(nothing) == "no operation"
        @test describe_operation(DoNothingOperation()) == "do nothing"
        @test describe_operation(QuitEditorOperation()) == "quit"
        @test describe_operation(SelectNextInsertionOperation(_ -> false)) ==
              "select next insertion"
        @test describe_operation(ToggleCollapseOperation()) == "toggle collapse"
        @test describe_operation(InvalidateProjectionOperation()) == "print the view again"
    end

    @testset "a selection and a write show the skeleton of the reference" begin
        path = Reference(FieldReferenceStep("entries"), RangeReferenceStep(1, 2),
                         FieldReferenceStep("price"))
        @test describe_operation(ReplaceSelectionOperation(path)) ==
              "select .entries[2].price"
        caret = Reference(FieldReferenceStep("name"), RangeReferenceStep(3, 3))
        @test describe_operation(ReplaceSelectionOperation(caret)) == "select .name{3}"
        @test describe_operation(ReplaceReferencedValueOperation(nothing, path, 12)) ==
              "set .entries[2].price = 12"
    end

    # A literal keeps its text, and a document shows its type: a whole document
    # printed into one line says nothing.
    @testset "a value is written short" begin
        name = Reference(FieldReferenceStep("name"))
        describe(value) =
            describe_operation(ReplaceReferencedValueOperation(nothing, name, value))
        @test describe("b") == "set .name = \"b\""
        @test describe(:b) == "set .name = :b"
        @test describe(true) == "set .name = true"
        @test describe(nothing) == "set .name = nothing"
        @test describe(DescriptionItem(3, nothing)) == "set .name = DescriptionItem"
        long = describe("a"^40)
        @test endswith(long, "…")
        @test length(long) == length("set .name = ") + 24
    end

    @testset "a compound joins its members, and a wrapper is what it holds" begin
        compound = CompoundOperation(Any[DoNothingOperation(), QuitEditorOperation()])
        @test describe_operation(compound) == "compound(2): do nothing + quit"
        hover = ReplaceViewStateOperation(
            ReplaceSelectionOperation(Reference(FieldReferenceStep("left"))))
        @test describe_operation(hover) == "select .left"
    end

    @testset "an operation that the layer does not name shows its type name" begin
        @test describe_operation(DescriptionProbeOperation()) == "DescriptionProbe"
        move = DescriptionMoveOperation(Reference(FieldReferenceStep("a"),
                                                  RangeReferenceStep(1, 2)))
        @test describe_operation(move) == "DescriptionMove .a[2]"
    end

    @testset "a reference is written from its deepest titled document" begin
        root = _make_description_file()
        path = Reference(FieldReferenceStep("content"), FieldReferenceStep("entries"),
                         RangeReferenceStep(1, 2), FieldReferenceStep("price"))
        @test describe_reference(path, root) == "items.json › .entries[2].price"
        @test describe_reference(Reference(FieldReferenceStep("content")), root) ==
              "items.json"
        # A reference with no titled document on it is written whole.
        list = root.content
        inner = Reference(FieldReferenceStep("entries"), RangeReferenceStep(0, 1))
        @test describe_reference(inner, list) == ".entries[1]"
    end

    @testset "the root form writes each reference from that root" begin
        root = _make_description_file()
        path = Reference(FieldReferenceStep("content"), FieldReferenceStep("entries"),
                         RangeReferenceStep(1, 2), FieldReferenceStep("price"))
        write = ReplaceReferencedValueOperation(nothing, path, 12)
        @test describe_operation(write, root) == "set items.json › .entries[2].price = 12"
        @test describe_operation(ReplaceSelectionOperation(path), root) ==
              "select items.json › .entries[2].price"
        @test describe_operation(DescriptionMoveOperation(path), root) ==
              "DescriptionMove items.json › .entries[2].price"
        # The root holds only for that call.
        @test describe_operation(write) == "set .content.entries[2].price = 12"
    end

end
end # test_description
