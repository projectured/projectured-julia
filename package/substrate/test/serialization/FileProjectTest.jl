"""
Tests for the `FileProjectModule` — the natural-format save/load driver
and its simplest concrete file document, `TextFile`.

S2 covers a one-file project: no cross-file traversal, no marker walk,
no intern table. It exercises the interface (`filename`, `content`,
`emit_text`, `load_file`), the driver's byte-equality dirty guard, and
recreation after external deletion.
"""

using Test
using ProjecturedSerialization.FileProjectModule
using ProjecturedSerialization.TextFileModule

function test_file_project()
@testset "FileProject: TextFile round-trip" begin

    @testset "FileDocument interface: filename + content" begin
        f = TextFile("hello.txt", "world")
        @test filename(f) == "hello.txt"
        @test content(f) == "world"
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
            @test filename(g) == "hello.txt"
            @test content(g) == "world"
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
            @test content(g) == "edited on disk"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "ReferenceStub: constructor and printing" begin
        stub = ReferenceStub("file(\"child.json\")")
        @test stub isa FileProjectModule.ReferenceStub
        @test stub.source == "file(\"child.json\")"
        @test marker_text(stub) == "<<file(\"child.json\")>>"
        @test occursin("ReferenceStub", sprint(show, stub))
        # equality is by marker source
        @test ReferenceStub("file(\"child.json\")") == stub
        @test ReferenceStub("file(\"other.json\")") != stub
    end

end
end
