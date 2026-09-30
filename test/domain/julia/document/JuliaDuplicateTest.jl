# Julia code is what a person typed, so the duplicate of a Julia document is a
# copy of it: the same code, in nodes of its own. The code of an evaluator form
# is a Julia document, and a duplicated evaluator must not type into the
# original.

using Test

# Every Julia node of `document`, each once.
_collect_julia_nodes(document) = search_documents(document, node -> node isa JuliaDocument)

# Whether `duplicate` holds a Julia node that `original` holds too.
function _shares_julia_node(duplicate, original)
    originals = Base.IdSet{Any}(_collect_julia_nodes(original))
    any(node -> node in originals, _collect_julia_nodes(duplicate))
end

function test_julia_duplicate()
@testset "the duplicate of a Julia document is a copy of it" begin

    @testset "every Julia example duplicates into the same code, in nodes of its own" begin
        example_names = [name for name in names(ProjecturedJuliaExample)
                         if startswith(String(name), "make_julia_") &&
                            endswith(String(name), "_document_example")]
        @test !isempty(example_names)
        for name in example_names
            example = getfield(ProjecturedJuliaExample, name)()
            @test has_document_duplicate(example)
            duplicate = make_document_duplicate(example)
            @test typeof(duplicate) === typeof(example)
            @test !_shares_julia_node(duplicate, example)
            @test print_natural_text(duplicate) == print_natural_text(example)
        end
    end

    @testset "an edit of the duplicate leaves the original" begin
        original = parse_julia("x = f(y) + 1")
        duplicate = make_document_duplicate(original)
        identifier = first(node for node in _collect_julia_nodes(duplicate)
                           if node isa JuliaIdentifier && node.name == "y")
        identifier.name = "z"
        @test print_natural_text(duplicate) == print_natural_text(parse_julia("x = f(z) + 1"))
        @test print_natural_text(original) == print_natural_text(parse_julia("x = f(y) + 1"))
    end

    @testset "text typed into the duplicate of an insertion stays there" begin
        original = JuliaInsertion("1 +")
        duplicate = make_document_duplicate(original)
        @test duplicate.value == "1 +"
        duplicate.value = "1 + 2"
        @test original.value == "1 +"
    end

end
end
