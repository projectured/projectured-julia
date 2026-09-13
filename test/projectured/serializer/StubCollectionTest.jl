"""
Tests for **marker collection at parse time**: a parser makes every stub, so a
load session knows its markers without searching the tree for them.

The properties: the parse registers what it made, `resolve_stubs!` with the
session drains that list (transitively, through the files a marker pulls in),
the session-less call still walks, and the drain stops at the document it was
asked about instead of reaching every other document the session holds.
"""

using Test
using ProjecturedSerialization.FileProjectModule
using ProjecturedMarkdown.MarkdownFileModule
using ProjecturedJulia.JuliaFileModule
using ProjecturedSerialization.TextFileModule

# One page, one marker at the named target.
_stub_page(dir, name, marker) =
    write(joinpath(dir, name), """
        # $name

        ```pred-ref
        <<$marker>>
        ```
        """)

function test_stub_collection()
@testset "Marker collection: the parser reports, the drain resolves" begin

    @testset "the parse registers the markers it made" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "one")
            _stub_page(d, "page.md", "file(\"a.txt\")")
            ctx  = LoaderContext(d)
            page = evaluate_marker("file(\"page.md\")", ctx)
            # The list is filed under the document the parse produced, and it is
            # the marker the page carries — not a marker anyone searched for.
            @test haskey(ctx.stubs, page)
            @test length(ctx.stubs[page]) == 1
            @test ctx.stubs[page][1].source == "file(\"a.txt\")"
            # Registering is not resolving: loading stays lazy.
            @test !is_resolved(ctx.stubs[page][1])
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "the drain resolves what the parse registered" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "one")
            _stub_page(d, "page.md", "file(\"a.txt\")")
            ctx  = LoaderContext(d)
            page = evaluate_marker("file(\"page.md\")", ctx)
            resolve_stubs!(page; context = ctx)
            @test is_resolved(ctx.stubs[page][1])
            @test get_file_content(ctx.stubs[page][1].resolved) == "one"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "the drain follows the files a marker pulls in" begin
        d = mktempdir()
        try
            # page -> middle.md -> leaf.txt. `middle.md` is parsed *during* the
            # drain, so its own marker can only be resolved if the parse reports
            # into the drain that pulled it.
            write(joinpath(d, "leaf.txt"), "deep")
            _stub_page(d, "middle.md", "file(\"leaf.txt\")")
            _stub_page(d, "page.md", "file(\"middle.md\")")
            ctx  = LoaderContext(d)
            page = evaluate_marker("file(\"page.md\")", ctx)
            resolve_stubs!(page; context = ctx)
            middle = ctx.stubs[page][1].resolved
            @test middle isa MarkdownFile
            @test is_resolved(ctx.stubs[middle][1])
            @test get_file_content(ctx.stubs[middle][1].resolved) == "deep"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a marker naming part of a file still drains that file" begin
        d = mktempdir()
        try
            # `definition(…)` answers with a node *inside* the Julia file rather
            # than with the file, so the file's own markers reach the drain only
            # because the parse reported them.
            write(joinpath(d, "s.jl"), """
                function step(x)
                    pred_ref("<<file(\\"note.txt\\")>>")
                    x
                end
                """)
            write(joinpath(d, "note.txt"), "a note")
            _stub_page(d, "page.md", "definition(file(\"s.jl\"), \"step\")")
            ctx  = LoaderContext(d)
            page = evaluate_marker("file(\"page.md\")", ctx)
            resolve_stubs!(page; context = ctx)
            source = ctx.intern["file(\"s.jl\")"]
            @test source isa JuliaFile
            @test length(ctx.stubs[source]) == 1
            @test is_resolved(ctx.stubs[source][1])
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a file already parsed joins a drain that reaches it" begin
        d = mktempdir()
        try
            write(joinpath(d, "leaf.txt"), "deep")
            _stub_page(d, "shared.md", "file(\"leaf.txt\")")
            _stub_page(d, "page.md", "file(\"shared.md\")")
            ctx    = LoaderContext(d)
            shared = evaluate_marker("file(\"shared.md\")", ctx)   # parsed first
            page   = evaluate_marker("file(\"page.md\")", ctx)
            @test !is_resolved(ctx.stubs[shared][1])
            resolve_stubs!(page; context = ctx)
            @test is_resolved(ctx.stubs[shared][1])
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "the drain stops at the document it was asked about" begin
        d = mktempdir()
        try
            # Two unrelated pages in one session. Draining the first must not
            # reach the second: they share nothing but the session, and a
            # session is not a reason to open a page nobody asked for.
            write(joinpath(d, "a.txt"), "one")
            write(joinpath(d, "b.txt"), "two")
            _stub_page(d, "first.md", "file(\"a.txt\")")
            _stub_page(d, "second.md", "file(\"b.txt\")")
            ctx    = LoaderContext(d)
            first  = evaluate_marker("file(\"first.md\")", ctx)
            second = evaluate_marker("file(\"second.md\")", ctx)
            resolve_stubs!(first; context = ctx)
            @test is_resolved(ctx.stubs[first][1])
            @test !is_resolved(ctx.stubs[second][1])
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a cycle terminates" begin
        d = mktempdir()
        try
            _stub_page(d, "a.md", "file(\"b.md\")")
            _stub_page(d, "b.md", "file(\"a.md\")")
            ctx = LoaderContext(d)
            a   = evaluate_marker("file(\"a.md\")", ctx)
            resolve_stubs!(a; context = ctx)
            b = ctx.stubs[a][1].resolved
            @test b isa MarkdownFile
            @test is_resolved(ctx.stubs[b][1])
            @test ctx.stubs[b][1].resolved === a
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "without a session the markers are still found by walking" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "one")
            _stub_page(d, "page.md", "file(\"a.txt\")")
            ctx  = LoaderContext(d)
            page = evaluate_marker("file(\"page.md\")", ctx)
            resolve_stubs!(page)                     # no context given
            @test is_resolved(ctx.stubs[page][1])
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a document the session never loaded falls back to the walk" begin
        d = mktempdir()
        try
            write(joinpath(d, "a.txt"), "one")
            ctx  = LoaderContext(d)
            stub = ReferenceStub("file(\"a.txt\")", ctx)
            # Composed in memory: the session has no list for this holder, so
            # passing the session must not make the marker unreachable.
            resolve_stubs!(stub; context = ctx)
            @test is_resolved(stub)
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
