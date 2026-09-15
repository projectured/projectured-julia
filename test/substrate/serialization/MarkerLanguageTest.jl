"""
Tests for the **marker language** — `<<expr>>` bodies as restricted Julia
expressions, the vocabulary registry, and the interpreter.

Recognition is syntactic — the vocabulary is consulted only when a marker is
evaluated, so load order between packages cannot turn a marker into text.
"""

using Test
using ProjecturedSerialization.SerializationModule

"A project of every file in `d`: the context a marker is evaluated in."
_ml_project(d) = load_project(d, readdir(d))

function test_marker_language()
@testset "Marker language: restricted Julia in <<…>>" begin

    @testset "recognises a call, returns the body verbatim" begin
        @test parse_marker_text("<<file(\"a.txt\")>>") == "file(\"a.txt\")"
        # Surrounding whitespace (a fenced block's body) is ignored, but the
        # body itself comes back exactly as written — that is what save re-emits.
        @test parse_marker_text("\n  <<file( \"a.txt\" )>>  \n") == "file( \"a.txt\" )"
        @test parse_marker_text("<<definition(file(\"s.jl\"), \"queue_step\")>>") ==
              "definition(file(\"s.jl\"), \"queue_step\")"
    end

    @testset "rejects everything that is not a restricted call" begin
        for text in ("plain text", "<<>>", "<<x>>", "<<42>>", "<<file(\"a\")",
                     "file(\"a\")", "<<a = file(\"x\")>>", "<<for i in 1:3 end>>",
                     "<<file(\"a\") junk>>", "<<file(x)>>")
            @test parse_marker_text(text) === nothing
        end
    end

    @testset "a marker is not evaluated at parse time" begin
        # An unregistered name still round-trips: whether the vocabulary has it
        # is settled when the marker is evaluated, so load order between
        # packages cannot turn a marker into plain text.
        @test parse_marker_text("<<nosuch(\"a\")>>") == "nosuch(\"a\")"
    end

    @testset "file(…) loads through the context" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = _ml_project(d)
            f = evaluate_marker("file(\"a.txt\")", ctx)
            @test f isa TextFile
            @test get_file_content(f) == "hello"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "the same file, however spelled, is the project's one file" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = _ml_project(d)
            a = evaluate_marker("file(\"a.txt\")", ctx)
            # Different spelling, same file: spacing is not part of the name,
            # and neither is a redundant path segment.
            b = evaluate_marker("file( \"a.txt\" )", ctx)
            c = evaluate_marker("file(\"./a.txt\")", ctx)
            @test a === b
            @test a === c
            # A different project holds a different file.
            @test evaluate_marker("file(\"a.txt\")", _ml_project(d)) !== a
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "nested calls evaluate inside-out" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = _ml_project(d)
            # A vocabulary function registered by a "domain": it receives the
            # project and the already-evaluated inner value.
            register_marker_function!(:_test_upcase, (project, doc) -> uppercase(get_file_content(doc)))
            @test evaluate_marker("_test_upcase(file(\"a.txt\"))", ctx) == "HELLO"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "unknown function and malformed body fail loudly" begin
        d = mktempdir()
        try
            ctx = FileProject(d, [])
            @test_throws ErrorException evaluate_marker("nosuch(\"a.txt\")", ctx)
            @test_throws ErrorException evaluate_marker("not a marker", ctx)
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
