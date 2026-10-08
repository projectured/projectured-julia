"""
Tests for `TextFile`, the simplest file document, saved and loaded one at a
time: the interface (`get_filename`, `get_file_content`, `emit_text`), the
write gate, and recreation after an external deletion.
"""

using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedPlatform.FileFormatModule: make_file_tab, make_file_tab_content
using ProjecturedPlatform.UndoModule: UndoBuffer
using ProjecturedKernel.DocumentModule: @document, get_document_title

"""
A file whose whole node is its content: its title and its body are the file,
the way a `NedFile`'s children and version are the file. It says so with
`is_own_content`, reads itself with `make_file`, and prints itself.
"""
@document struct NoteFile <: FileDocument
    filename::String
    title::String = ""
    body::String  = ""
end

SerializationModule.is_own_content(::NoteFile) = true
SerializationModule.get_file_content(f::NoteFile) = f
SerializationModule.get_file_domain(::Type{<:NoteFile}) = Document
SerializationModule.emit_text(f::NoteFile) = f.title * "\n" * f.body

function SerializationModule.make_file(::Type{<:NoteFile}, filename::AbstractString,
                                       text::AbstractString)
    lines = split(String(text), "\n", limit = 2)
    NoteFile(String(filename), String(lines[1]), String(length(lines) > 1 ? lines[2] : ""))
end

function test_text_file()
@testset "TextFile: save and load one file" begin

    @testset "FileDocument interface: filename + content" begin
        f = TextFile("hello.txt", "world")
        @test get_filename(f) == "hello.txt"
        @test get_file_content(f) == "world"
        # subtype relationship
        @test f isa FileDocument
    end

    @testset "a file may be its own content" begin
        register_file_document_type!(".note", NoteFile)
        d = mktempdir()
        try
            note = NoteFile("a.note", "Title", "Body")
            # There is no `content` field to read through: the file is the tree.
            @test get_file_content(note) === note
            @test save_file!(note, d)
            @test read(joinpath(d, "a.note"), String) == "Title\nBody"
            # The parser built the file, so the load takes it as it is.
            back = load_file(d, "a.note")
            @test back isa NoteFile
            @test get_filename(back) == "a.note"
            @test back.title == "Title" && back.body == "Body"
            # And it saves beside a file of another kind, which is the only way
            # one file can name another.
            @test save_project!(FileProject(d, [note, TextFile("b.txt", "plain")]))
            @test read(joinpath(d, "b.txt"), String) == "plain"
            # A tab holds the file itself under its absolute path, and a history
            # goes around the file, because no content inside it can hold one.
            path = joinpath(d, "a.note")
            tab = make_file_tab(path)
            @test tab isa NoteFile
            @test get_filename(tab) == abspath(path)
            @test tab.title == "Title" && tab.body == "Body"
            buffer = make_file_tab(path, UndoBuffer)
            @test buffer isa UndoBuffer && buffer.content isa NoteFile
            @test get_filename(buffer.content) == abspath(path)
            @test get_document_title(make_file_tab_content(path, UndoBuffer)) == "a.note"
        finally
            rm(d; recursive = true, force = true)
        end
    end

    @testset "emit_text on TextFile is the identity" begin
        @test emit_text(TextFile("x.txt", "abc")) == "abc"
        @test emit_text(TextFile("x.txt", "")) == ""
    end

    @testset "save_file! writes the root to base_dir/filename" begin
        d = mktempdir()
        try
            f = TextFile("out.txt", "hello")
            save_file!(f, d)
            @test isfile(joinpath(d, "out.txt"))
            @test read(joinpath(d, "out.txt"), String) == "hello"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "save_file! creates parent directories" begin
        d = mktempdir()
        try
            f = TextFile("sub/dir/nested.txt", "nested")
            save_file!(f, d)
            @test isfile(joinpath(d, "sub", "dir", "nested.txt"))
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "load_file reads what save_file! wrote" begin
        d = mktempdir()
        try
            save_file!(TextFile("hello.txt", "world"), d)
            g = load_file(d, "hello.txt")
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
            save_file!(f, d)
            first = mtime(joinpath(d, "h.txt"))
            # Sleep long enough that a rewrite would definitely bump mtime.
            sleep(0.05)
            save_file!(TextFile("h.txt", "x"), d)
            @test mtime(joinpath(d, "h.txt")) == first
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "byte-equality guard: re-save with changed content writes" begin
        d = mktempdir()
        try
            save_file!(TextFile("h.txt", "before"), d)
            save_file!(TextFile("h.txt", "after"), d)
            @test read(joinpath(d, "h.txt"), String) == "after"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "recreate: save after external deletion writes again" begin
        d = mktempdir()
        try
            save_file!(TextFile("h.txt", "value"), d)
            rm(joinpath(d, "h.txt"))
            @test !isfile(joinpath(d, "h.txt"))
            save_file!(TextFile("h.txt", "value"), d)
            @test isfile(joinpath(d, "h.txt"))
            @test read(joinpath(d, "h.txt"), String) == "value"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "round-trip: save → external edit → load reflects the edit" begin
        d = mktempdir()
        try
            save_file!(TextFile("h.txt", "original"), d)
            open(joinpath(d, "h.txt"), "w") do io
                write(io, "edited on disk")
            end
            g = load_file(d, "h.txt")
            @test get_file_content(g) == "edited on disk"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a marker may name a type, and then it constructs one" begin
        # A document is a data structure, and a constructor is how one is
        # written down. The capital is what tells `TextFile(…)` from `file(…)`,
        # and the registry is what says a file may name this one.
        ctx = FileProject(".", [])
        built = evaluate_marker("TextFile(\"page.txt\", \"hello\")", ctx)
        @test built isa TextFile
        @test get_filename(built) == "page.txt"
        # A type nothing offered is refused, so a file cannot build what it has
        # no business building.
        @test_throws ErrorException evaluate_marker("NotOffered()", ctx)
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

end
end
