"""
Tests for the **marker language** — `<<expr>>` bodies as restricted Julia
expressions, the vocabulary registry, and the interpreter's interning.

The three properties a marker must keep (module docstring of
`FileProjectModule`): verbatim source, interning by canonical source,
and lazy evaluation. Recognition is syntactic — the vocabulary is
consulted only when a stub is resolved.
"""

using Test
using ProjecturedSerialization.SerializationModule
using ProjecturedSerialization.SerializationModule

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
                     "<<file(\"a\") junk>>", "<<file(x)>>", "<<file(\"a\"; k=1)>>")
            @test parse_marker_text(text) === nothing
        end
    end

    @testset "a marker is not evaluated at parse time" begin
        # An unregistered name still round-trips: whether the vocabulary has it
        # is settled at resolve time, so load order between packages cannot
        # turn a marker into plain text.
        @test parse_marker_text("<<nosuch(\"a\")>>") == "nosuch(\"a\")"
    end

    @testset "the stub keeps its source verbatim" begin
        stub = ReferenceStub("file( \"a.txt\" )")
        @test format_marker_text(stub) == "<<file( \"a.txt\" )>>"
    end

    @testset "file(…) loads through the context" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = LoaderContext(d)
            f = evaluate_marker("file(\"a.txt\")", ctx)
            @test f isa TextFile
            @test get_file_content(f) == "hello"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "interning: same canonical source ⇒ === value" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = LoaderContext(d)
            a = evaluate_marker("file(\"a.txt\")", ctx)
            # Different spelling, same call: spacing is not part of the key,
            # and neither is a redundant path segment.
            b = evaluate_marker("file( \"a.txt\" )", ctx)
            c = evaluate_marker("file(\"./a.txt\")", ctx)
            @test a === b
            @test a === c
            # A different load session is a different intern table.
            @test evaluate_marker("file(\"a.txt\")", LoaderContext(d)) !== a
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "nested calls evaluate inside-out and intern at every level" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = LoaderContext(d)
            # A vocabulary function registered by a "domain": it receives the
            # already-evaluated inner value.
            register_marker_function!(:_test_upcase, (c, doc) -> uppercase(get_file_content(doc)))
            @test evaluate_marker("_test_upcase(file(\"a.txt\"))", ctx) == "HELLO"
            @test haskey(ctx.intern, "file(\"a.txt\")")
            @test haskey(ctx.intern, "_test_upcase(file(\"a.txt\"))")
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "unknown function and malformed body fail loudly" begin
        d = mktempdir()
        try
            ctx = LoaderContext(d)
            @test_throws ErrorException evaluate_marker("nosuch(\"a.txt\")", ctx)
            @test_throws ErrorException evaluate_marker("not a marker", ctx)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "resolve! is lazy, once, and reactive" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "hello")
            ctx = LoaderContext(d)
            stub = ReferenceStub("file(\"a.txt\")", ctx)
            @test !is_resolved(stub)
            @test stub.resolved === nothing
            first = resolve!(stub)
            @test is_resolved(stub)
            @test stub.resolved === first
            @test resolve!(stub) === first
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "resolve_stubs! forces the graph transitively" begin
        d = mktempdir()
        try
            # a.txt is plain text, so build the chain with a vocabulary function
            # that returns another stub-bearing document: use two text files
            # reached through one manually built holder.
            write(joinpath(d, "a.txt"), "one")
            write(joinpath(d, "b.txt"), "two")
            ctx = LoaderContext(d)
            a = ReferenceStub("file(\"a.txt\")", ctx)
            b = ReferenceStub("file(\"b.txt\")", ctx)
            resolve_stubs!(TextFile("holder.txt", "x"))   # nothing to force
            for s in (a, b)
                @test !is_resolved(s)
            end
            resolve_stubs!(a)
            @test is_resolved(a)
            @test !is_resolved(b)
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
