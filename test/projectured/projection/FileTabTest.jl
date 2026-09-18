# A tab that holds a `FileDocument` draws the file's content, and Ctrl+S /
# Ctrl+O save and reload it.
#
# `FileToContent` is the row that lets a `JsonFile` (or an `XmlFile`, a
# `JuliaFile`, …) draw through the render-anything projection, the same way
# `ToolViewTest.jl` checks a tool's own row. The save/reload pair is a real
# round trip through a file on disk, in a `mktempdir`, because the whole point
# of a `FileDocument` is that it is a file.

using Test

function test_file_tab()
@testset "a file tab draws its content and saves/reloads it" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)

# Every word the canvas draws, joined. Copied from
# `test/projectured/projection/ToolViewTest.jl` rather than imported.
function drawn(node, depth = 0)
    depth > 40 && return ""
    node isa GraphicsText && return String(node.text) * " "
    node isa GraphicsCanvas &&
        return join([drawn(node.elements[i], depth + 1) for i in 1:length(node.elements)])
    node isa GraphicsViewport && return drawn(node.content, depth + 1)
    ""
end

function render(document)
    iomap = print_document(NaturalToGraphics(measure = _stub), nothing, document,
                           PrinterContext(EmptyReference(), Cell(600), Cell(400),
                                          Dict{Symbol,Any}()))
    drawn(get_iomap_output(iomap))
end

mktempdir() do dir
    # `mktempdir` hands back an absolute directory, so a file built under it —
    # exactly as a standalone tab opens one, `filename = abspath(path)` — has an
    # absolute name of its own with no project base directory to be relative to.
    path = joinpath(dir, "a.json")
    write(path, "{\"greeting\": \"hello\"}")

    @testset "the file's content draws through NaturalToGraphics" begin
        file = make_file(get_file_document_type(path), path, read(path, String))
        @test file isa JsonFile
        text = render(file)
        @test !occursin("no natural rendering", text)
        @test occursin("hello", text)
    end

    @testset "Ctrl+S writes the changed content to disk" begin
        file = make_file(get_file_document_type(path), path, read(path, String))
        file.content = parse_json("{\"greeting\": \"goodbye\"}")
        op = read_gesture(file, KeyDown(:s, ModifierKeys(ctrl = true)))
        @test op isa Operation
        evaluate_operation(nothing, op)
        @test occursin("goodbye", read(path, String))
    end

    @testset "Ctrl+O reads the file back" begin
        file = make_file(get_file_document_type(path), path, read(path, String))
        write(path, "{\"greeting\": \"reloaded\"}")
        op = read_gesture(file, KeyDown(:o, ModifierKeys(ctrl = true)))
        @test op isa Operation
        evaluate_operation(nothing, op)
        @test occursin("reloaded", render(file))
    end

    @testset "a file with an empty name declines both" begin
        file = JsonFile("", JsonNull())
        @test read_gesture(file, KeyDown(:s, ModifierKeys(ctrl = true))) === nothing
        @test read_gesture(file, KeyDown(:o, ModifierKeys(ctrl = true))) === nothing
    end
end

end
end
