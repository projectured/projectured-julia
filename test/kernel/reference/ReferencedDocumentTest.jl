"""
`ReferencedDocument` and `DocumentLocator` over a test-local tree of toy documents:
a referenced document acts like its document, and every document or collection it
answers holds the reference to its place.
"""

using Test
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.DocumentModule: @document, Document

@document struct ReferencedLeaf
    name::String
end

@document struct ReferencedBranch
    name::String
    children::Vector{Any}
end

@document struct ReferencedTable
    entries::Dict{String, Any}
end

function _make_referenced_tree()
    ReferencedBranch("root",
        Any[ReferencedLeaf("a", nothing),
            ReferencedBranch("b", Any[ReferencedLeaf("c", nothing)], nothing)],
        nothing)
end

function test_referenced_document()
@testset "ReferencedDocument" begin

    @testset "a read answers a referenced document or a plain leaf" begin
        root = _make_referenced_tree()
        tree = ReferencedDocument(root, EmptyReference())
        @test get_document(tree) === root
        children = tree.children
        @test children isa ReferencedDocument
        @test get_document(children) === root.children
        first_child = tree.children[1]
        @test first_child isa ReferencedDocument
        @test get_document(first_child) === root.children[1]
        @test evaluate_reference(root, get_reference(first_child)) === root.children[1]
        @test first_child.name == "a"
        @test tree.children[2].children[1].name == "c"
        grandchild = tree.children[2].children[1]
        @test evaluate_reference(root, get_reference(grandchild)) === root.children[2].children[1]
    end

    @testset "iteration answers each element with its reference" begin
        root = _make_referenced_tree()
        tree = ReferencedDocument(root, EmptyReference())
        @test [child.name for child in tree.children] == ["a", "b"]
        @test length(tree.children) == 2
        for (i, child) in enumerate(tree.children)
            @test evaluate_reference(root, get_reference(child)) === root.children[i]
        end
    end

    @testset "a key of a dictionary is a step of the reference" begin
        root = ReferencedTable(Dict{String, Any}("leaf" => ReferencedLeaf("d", nothing)), nothing)
        table = ReferencedDocument(root, EmptyReference())
        leaf = table.entries["leaf"]
        @test leaf isa ReferencedDocument
        @test leaf.name == "d"
        @test evaluate_reference(root, get_reference(leaf)) === root.entries["leaf"]
    end

    @testset "a collection answers its keys, its values and a default" begin
        root = ReferencedTable(Dict{String, Any}("leaf" => ReferencedLeaf("d", nothing)), nothing)
        entries = ReferencedDocument(root, EmptyReference()).entries
        @test haskey(entries, "leaf")
        @test collect(keys(entries)) == ["leaf"]
        @test [value.name for value in values(entries)] == ["d"]
        @test get(entries, "missing", :none) === :none
        leaf = get(entries, "leaf", :none)
        @test evaluate_reference(root, get_reference(leaf)) === root.entries["leaf"]
        children = ReferencedDocument(_make_referenced_tree(), EmptyReference()).children
        @test !isempty(children)
        @test children[end].name == "b"
        @test get(children, 3, :none) === :none
    end

    @testset "every reference a read makes records its types" begin
        root = _make_referenced_tree()
        tree = ReferencedDocument(root, EmptyReference())
        @test is_fully_typed_reference(get_reference(tree.children[2].children[1]))
        @test all(child -> is_fully_typed_reference(get_reference(child)), tree.children)
        leaf = ReferencedDocument(ReferencedTable(Dict{String, Any}("leaf" => ReferencedLeaf("d", nothing)),
                                                  nothing), EmptyReference()).entries["leaf"]
        @test is_fully_typed_reference(get_reference(leaf))
    end

    @testset "a dictionary reads by any key, and iterates its members with references" begin
        numbers = ReferencedDocument(Dict(1 => Any[1], 2 => Any[2]), EmptyReference())
        @test get_document(numbers)[1] == (numbers[1] isa ReferencedDocument ? get_document(numbers[1]) : numbers[1])
        @test get(numbers, 3, :none) === :none
        root = ReferencedTable(Dict{String, Any}("leaf" => ReferencedLeaf("d", nothing)), nothing)
        for (key, value) in ReferencedDocument(root, EmptyReference()).entries
            @test key == "leaf"
            @test evaluate_reference(root, get_reference(value)) === root.entries["leaf"]
        end
    end

    @testset "a write goes to the document, and stores a document, never a referenced one" begin
        root = _make_referenced_tree()
        tree = ReferencedDocument(root, EmptyReference())
        first_child = tree.children[1]
        first_child.name = "A"
        @test root.children[1].name == "A"
        tree.children[1] = tree.children[2].children[1]
        @test root.children[1] isa ReferencedLeaf
        push!(tree.children, tree.children[2])
        @test length(root.children) == 3
        @test root.children[3] isa ReferencedBranch
        deleteat!(tree.children, 3)
        @test length(root.children) == 2
    end

    @testset "the display says what and where" begin
        root = _make_referenced_tree()
        first_child = ReferencedDocument(root, EmptyReference()).children[1]
        shown = repr(first_child)
        @test startswith(shown, "ReferencedDocument{ReferencedLeaf} at .children[1]: ")
        @test propertynames(first_child) == propertynames(root.children[1])
    end

    @testset "convert answers the document or the reference" begin
        root = _make_referenced_tree()
        first_child = ReferencedDocument(root, EmptyReference()).children[1]
        @test convert(ReferencedLeaf, first_child) === root.children[1]
        @test convert(Reference, first_child) === get_reference(first_child)
        leaves = ReferencedLeaf[]
        push!(leaves, first_child)
        @test only(leaves) === root.children[1]
    end

    @testset "a locator finds its document again, or answers nothing" begin
        root = _make_referenced_tree()
        first_child = ReferencedDocument(root, EmptyReference()).children[1]
        found = find_referenced_document(DocumentLocator(root, get_reference(first_child)))
        @test found isa ReferencedDocument
        @test get_document(found) === root.children[1]
        gone = extend_reference(EmptyReference(), FieldReferenceStep("missing"))
        @test find_referenced_document(DocumentLocator(root, gone)) === nothing
    end
end
end # test_referenced_document
