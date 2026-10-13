"""
Tests of the Julia notation, `JuliaToSyntax`, printed through the chain to a string.

An edit of a printed document reaches the output of the same IoMap: a caller
reads `.output` again and does not print again.
"""

using Test

_julia_text_projection() = ChainingProjection(RecursiveProjection(JuliaToSyntax()),
                                              RecursiveProjection(SyntaxToText()),
                                              RecursiveProjection(TextToString()))

# The least editor that `evaluate_operation` takes: a whole-root swap rebinds
# `document`.
mutable struct _JuliaToSyntaxEditor
    document::Any
    iomap::Any
end

"""
    test_julia_to_syntax()

The Julia notation follows each edit of an optional field through the same IoMap.
"""
function test_julia_to_syntax()
@testset "JuliaToSyntax" begin
    @testset "a range shows its step only while it has one" begin
        assignment = parse_julia("x = 1:2:5")
        range = assignment.value
        iomap = print_document(_julia_text_projection(), assignment)
        @test String(iomap.output) == "x = 1:2:5"
        range.step = nothing
        @test String(iomap.output) == "x = 1:5"
        range.step = parse_julia("3")
        @test String(iomap.output) == "x = 1:3:5"
    end

    @testset "a comment stands on a line of its own, at the indentation of its block" begin
        body = JuliaBlock(JuliaDocument[JuliaComment(" the start"),
                                        JuliaAssignment(JuliaIdentifier("x"), JuliaInteger(1)),
                                        JuliaMultilineComment(" one\ntwo ")])
        code = JuliaFunction(JuliaIdentifier("f"), JuliaDocument[], body)
        iomap = print_document(_julia_text_projection(), code)
        @test String(iomap.output) == "function f()\n  # the start\n  x = 1\n  #= one\n  two =#\nend"
        body.statements[1].text = " the first line"
        @test String(iomap.output) == "function f()\n  # the first line\n  x = 1\n  #= one\n  two =#\nend"
    end

    @testset "an end-of-line comment follows its statement on the same line" begin
        statement = JuliaEndOfLineComment(JuliaAssignment(JuliaIdentifier("x"), JuliaInteger(1)), " meters")
        iomap = print_document(_julia_text_projection(), statement)
        @test String(iomap.output) == "x = 1  # meters"
        statement.text = " feet"
        @test String(iomap.output) == "x = 1  # feet"
    end

    @testset "a Return key breaks the line of a multiline comment and of no other comment" begin
        projection = make_julia_projection_example()
        caret = ConcreteReference(FieldReferenceStep("text"),
                                  ConcreteReference(RangeReferenceStep(3, 3), EmptyReference()))
        function read_key(document, key)
            clear_selection!(document)
            set_selection!(document, caret)
            read_intent(projection, print_document(projection, document), KeyPress(key; time = 0.0))
        end
        for document in (JuliaComment(" note"), JuliaEndOfLineComment(JuliaIdentifier("x"), " note"))
            @test read_key(document, 'x') !== nothing
            @test read_key(document, '\n') === nothing
        end
        @test read_key(JuliaMultilineComment(" note"), '\n') !== nothing
    end

    @testset "a typed character goes into the text of a docstring, and prints escaped" begin
        projection = make_julia_projection_example()
        docstring = JuliaDocstring("A value.", JuliaAssignment(JuliaIdentifier("x"), JuliaInteger(1)))
        clear_selection!(docstring)
        set_selection!(docstring, ConcreteReference(FieldReferenceStep("text"),
                                  ConcreteReference(RangeReferenceStep(2, 2), EmptyReference())))
        iomap = print_document(projection, docstring)
        operation = read_intent(projection, iomap, KeyPress('$'; time = 0.0))
        @test operation !== nothing
        evaluate_operation(_JuliaToSyntaxEditor(docstring, iomap), operation)
        @test docstring.text == "A \$value."
        @test occursin("A \\\$value.", String(print_document(_julia_text_projection(), docstring).output))
    end

    @testset "the print of each comment is Julia that parses" begin
        for document in (JuliaComment(" a note"), JuliaMultilineComment(" a\nnote "),
                         JuliaEndOfLineComment(JuliaCall(JuliaIdentifier("f"), [JuliaIdentifier("x")]), " a note"))
            text = String(print_document(_julia_text_projection(), document).output)
            @test !Meta.isexpr(Meta.parseall(text), :error) &&
                  all(a -> !Meta.isexpr(a, (:error, :incomplete)), Meta.parseall(text).args)
        end
    end
end
end
