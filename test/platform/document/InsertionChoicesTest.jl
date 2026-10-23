# The kinds that a person picks from while typing: a whole name first, then a word
# of a name, and the traits that say what a kind shows and where it stands.

function test_insertion_choices()
@testset "insertion choices" begin
    @testset "a word of a name finds a kind, after the kinds of which a whole name starts so" begin
        found = find_insertion_choices(Document, "block")
        @test TextBlock in found
        starts(T) = any(name -> startswith(lowercase(name), "block"), get_insertion_names(T))
        @test !starts(TextBlock)
        # The kinds of which a whole name starts so come first.
        whole = filter(starts, found)
        @test found[1:length(whole)] == whole
        # A word match completes, with no continuation: its name does not start so.
        completed = complete_insertion(Document, "block")
        @test completed.state !== :invalid
        any(starts, found) || @test completed.continuation == ""
        # Nothing finds nothing, and an empty text finds every kind that is kept.
        @test isempty(find_insertion_choices(Document, "zzzzz"))
        kept = find_insertion_choices(Document, ""; include = T -> T === TextBlock)
        @test kept == Type[TextBlock]
    end

    @testset "a kind has no icon and stands as no element unless its domain says so" begin
        @test get_insertion_icon(TextBlock) === nothing
        @test !is_element_type(TextBlock)
    end

    @testset "an empty insertion shows a pale text that names what it takes" begin
        @test DOCUMENT_INSERTION_PLACEHOLDER == "Type a kind"
    end
end
end
