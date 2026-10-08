# BookToSyntax: the structure a book renders as.
#
# Three of the five rules are hand-written rather than `@projection_template`,
# because their mapping cannot be expressed by the markers — a conditional
# author leaf in front of a spliced collection, a title leaf fusing numbering
# with title at a character offset, and a per-item bullet decorator. Those three
# are what this suite pins down; the templated rules carry their own generic
# coverage.
#
# The constructors are positional: `@document` generates an all-positional form
# that fills a trailing run of defaults, not a keyword form.

using Test

"""
    test_book_to_syntax()

The book, chapter and list rules: what renders, what an absent author does, and
how numbering fuses into the chapter title.
"""
function test_book_to_syntax()
@testset "BookToSyntax" begin

b2s = RecursiveProjection(BookToSyntax())
render(doc) = get_flat_string(
    print_document(RecursiveProjection(SyntaxToText()),
                   print_document(b2s, doc).output).output)
para(text) = BookParagraph(TextBlock(TextString(text)))

    @testset "a book renders its title, and its author only when it has one" begin
        text = render(BookBook("The Title", "An Author"))
        @test occursin("The Title", text)
        @test occursin("An Author", text)

        # `author` defaults to nothing, and the leaf disappears rather than
        # rendering an empty line — that conditional is why the rule is
        # hand-written.
        anonymous = render(BookBook("Just A Title"))
        @test occursin("Just A Title", anonymous)
        @test !occursin("An Author", anonymous)
        @test count('\n', anonymous) < count('\n', text)
    end

    @testset "a chapter fuses its numbering into the title" begin
        numbered = render(BookChapter("Beginnings", "1"))
        @test occursin("Beginnings", numbered)
        @test occursin("1", numbered)
        # Numbering defaults to empty, and then only the title shows.
        plain = render(BookChapter("Beginnings"))
        @test occursin("Beginnings", plain)
        @test length(plain) < length(numbered)
    end

    @testset "a book splices its elements" begin
        text = render(BookBook("Whole", nothing,
                               [BookChapter("One", "1"), BookChapter("Two", "2")]))
        @test occursin("Whole", text)
        @test occursin("One", text)
        @test occursin("Two", text)
        # The chapters land in document order, not sorted or reversed.
        @test findfirst("One", text).start < findfirst("Two", text).start
    end

    @testset "a list decorates each item" begin
        # The bullet is a per-item decorator wrapping each whole projected
        # element, which is the other reason a rule stayed hand-written.
        one = render(BookList([para("alpha")]))
        two = render(BookList([para("alpha"), para("beta")]))
        @test occursin("alpha", one)
        @test occursin("beta", two)
        @test length(two) > length(one)
    end

    @testset "a paragraph renders the flat string of its text" begin
        # An edit of the leaf goes back into the text by `splice_value!` at the
        # same offset, so the leaf holds one character for each flat position:
        # here the break of the `TextNewline` between the two runs.
        content = TextBlock(TextString("ab"), TextNewline(font = StyleFont("Ubuntu Mono", 20)),
                            TextString("cd"))
        @test occursin("ab\ncd", render(BookParagraph(content)))
    end

    @testset "an empty book still prints" begin
        # A book with no elements is a reachable intermediate state, so it must
        # render rather than throw.
        @test occursin("Empty", render(BookBook("Empty")))
    end

end # @testset "BookToSyntax"
end # test_book_to_syntax
