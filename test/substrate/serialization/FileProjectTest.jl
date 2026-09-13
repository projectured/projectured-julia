"""
Tests for the `SerializationModule` — the natural-format save/load driver
and its simplest concrete file document, `TextFile`.

S2 covers a one-file project: no cross-file traversal, no marker walk,
no intern table. It exercises the interface (`filename`, `content`,
`emit_text`, `load_file`), the driver's byte-equality dirty guard, and
recreation after external deletion.
"""

using Test
using ProjecturedSerialization.SerializationModule
using ProjecturedSerialization.SerializationModule
using ProjecturedSerialization.SerializationModule: register_marker_type_resolver!

function test_file_project()
@testset "FileProject: TextFile round-trip" begin

    @testset "FileDocument interface: filename + content" begin
        f = TextFile("hello.txt", "world")
        @test get_filename(f) == "hello.txt"
        @test get_file_content(f) == "world"
        # subtype relationship
        @test f isa FileDocument
    end

    @testset "emit_text on TextFile is the identity" begin
        @test emit_text(TextFile("x.txt", "abc")) == "abc"
        @test emit_text(TextFile("x.txt", "")) == ""
    end

    @testset "save_project! writes the root to base_dir/filename" begin
        d = mktempdir()
        try
            f = TextFile("out.txt", "hello")
            save_project!(f, d)
            @test isfile(joinpath(d, "out.txt"))
            @test read(joinpath(d, "out.txt"), String) == "hello"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "save_project! creates parent directories" begin
        d = mktempdir()
        try
            f = TextFile("sub/dir/nested.txt", "nested")
            save_project!(f, d)
            @test isfile(joinpath(d, "sub", "dir", "nested.txt"))
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "load_project reads what save_project! wrote" begin
        d = mktempdir()
        try
            save_project!(TextFile("hello.txt", "world"), d)
            g = load_project(TextFile, "hello.txt", d)
            @test g isa TextFile
            @test get_filename(g) == "hello.txt"
            @test get_file_content(g) == "world"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "byte-equality guard: re-save with identical content is a no-op" begin
        d = mktempdir()
        try
            f = TextFile("h.txt", "x")
            save_project!(f, d)
            first = mtime(joinpath(d, "h.txt"))
            # Sleep long enough that a rewrite would definitely bump mtime.
            sleep(0.05)
            save_project!(TextFile("h.txt", "x"), d)
            @test mtime(joinpath(d, "h.txt")) == first
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "byte-equality guard: re-save with changed content writes" begin
        d = mktempdir()
        try
            save_project!(TextFile("h.txt", "before"), d)
            save_project!(TextFile("h.txt", "after"), d)
            @test read(joinpath(d, "h.txt"), String) == "after"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "recreate: save after external deletion writes again" begin
        d = mktempdir()
        try
            save_project!(TextFile("h.txt", "value"), d)
            rm(joinpath(d, "h.txt"))
            @test !isfile(joinpath(d, "h.txt"))
            save_project!(TextFile("h.txt", "value"), d)
            @test isfile(joinpath(d, "h.txt"))
            @test read(joinpath(d, "h.txt"), String) == "value"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "round-trip: save → external edit → load reflects the edit" begin
        d = mktempdir()
        try
            save_project!(TextFile("h.txt", "original"), d)
            open(joinpath(d, "h.txt"), "w") do io
                write(io, "edited on disk")
            end
            g = load_project(TextFile, "h.txt", d)
            @test get_file_content(g) == "edited on disk"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a marker may name a type, and then it constructs one" begin
        # A document is a data structure, and a constructor is how one is
        # written down. Nothing is registered per type: the capital is what
        # tells `MarkdownFile(…)` from `file(…)`.
        ctx = LoaderContext(".")
        resolver = name -> name == "TextFile" ? TextFile :
                           error("test resolver: no type named ", name)
        register_marker_type_resolver!(resolver)
        try
            built = evaluate_marker("TextFile(\"page.txt\", \"hello\")", ctx)
            @test built isa TextFile
            @test get_filename(built) == "page.txt"
            # A type the resolver refuses is refused here, so a file cannot
            # build what it has no business building.
            @test_throws ErrorException evaluate_marker("NotOffered()", ctx)
        finally
            register_marker_type_resolver!(nothing)
        end
    end

    @testset "keywords are in the marker subset" begin
        # `UdpHeader(source_port = 5000)` and the `\$doctype` object with the
        # same fields are one statement in two spellings.
        @test parse_marker_text("<<Header(port = 5000)>>") == "Header(port = 5000)"
        @test parse_marker_text("<<Header(; port = 5000)>>") == "Header(; port = 5000)"
        @test parse_marker_text("<<f(1, b = 2, c = \"x\")>>") == "f(1, b = 2, c = \"x\")"
        # A keyword's value is an argument like any other, so it is restricted
        # the same way: a bare name is still out.
        @test parse_marker_text("<<Header(port = some_binding)>>") === nothing
        @test parse_marker_text("<<Header(port = 1 + 1)>>") === nothing
        # And arithmetic is not a marker at all: `+` is a call with a symbol
        # callee like any other, so the callee has to be an identifier.
        @test parse_marker_text("<<1 + 1>>") === nothing
    end

    @testset "ReferenceStub: constructor and printing" begin
        stub = ReferenceStub("file(\"child.json\")")
        @test stub isa SerializationModule.ReferenceStub
        @test stub.source == "file(\"child.json\")"
        @test format_marker_text(stub) == "<<file(\"child.json\")>>"
        @test occursin("ReferenceStub", sprint(show, stub))
        # equality is by marker source
        @test ReferenceStub("file(\"child.json\")") == stub
        @test ReferenceStub("file(\"other.json\")") != stub
    end

end
end
