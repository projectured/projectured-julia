# The following copy of a document: one object whose fields follow the document
# that its source answers now.

@document struct _FollowedPage
    title::Any
    count::Int
end

function test_following_document()
@testset "the following copy of a document" begin
    first = _FollowedPage("One", 1)
    second = _FollowedPage("Two", 2)
    pages = [first, second]
    selected = Cell(1)
    shown = make_following_document(() -> pages[selected[]])

    @testset "the copy shows the fields of the document that the source answers" begin
        @test shown isa _FollowedPage
        @test shown !== first
        @test shown.title == "One"
        @test shown.count == 1
    end

    @testset "the copy stays one object and follows the source" begin
        before = shown
        selected[] = 2
        @test shown === before
        @test shown.title == "Two"
        @test shown.count == 2
        selected[] = 1
        @test shown.title == "One"
    end

    @testset "a change of the document of the source shows in the copy" begin
        first.title = "One again"
        @test shown.title == "One again"
    end

    @testset "a value of the copy is the value of the document of the source" begin
        inner = _FollowedPage("inner", 0)
        holder = _FollowedPage(inner, 3)
        copy = make_following_document(() -> holder)
        @test copy.title === inner
    end

    @testset "a document whose fields are cells can be followed, and another can not" begin
        @test is_followable_document(first)
        @test !is_followable_document((line = "a line",))
        @test !is_followable_document("a text")
    end

    @testset "the selection follows the document of the source" begin
        reference = ConcreteReference(FieldReferenceStep("title"))
        getfield(first, :selection)[] = reference
        @test getfield(shown, :selection)[] === reference
    end
end
end
