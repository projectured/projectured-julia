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

_stub = FixedMeasure(10, 18, 6, 0)

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
        op = read_gesture(file, KeyDown(:s, ModifierKeys(ctrl = true); time = 0.0))
        @test op isa Operation
        evaluate_operation(nothing, op)
        @test occursin("goodbye", read(path, String))
    end

    # Ctrl+O answers the reload and a selection of the whole file. The selection
    # needs an editor, so the case evaluates the reload alone.
    @testset "Ctrl+O reads the file back, and selects the whole file" begin
        file = make_file(get_file_document_type(path), path, read(path, String))
        write(path, "{\"greeting\": \"reloaded\"}")
        op = read_gesture(file, KeyDown(:o, ModifierKeys(ctrl = true); time = 0.0))
        @test op isa CompoundOperation
        @test any(o -> o isa ReplaceSelectionOperation && o.path isa EmptyReference, op.operations)
        evaluate_operation(nothing, only(o for o in op.operations if o isa ReloadFileOperation))
        @test occursin("reloaded", render(file))
    end

    # A press inside the file goes to the file's content, and its answer names
    # the content; the file's own keys still answer.
    @testset "a press inside the file reaches its content" begin
        write(path, "{\"greeting\": \"hello\"}")
        file = make_file(get_file_document_type(path), path, read(path, String))
        renderer = NaturalToGraphics(measure = _stub)
        iomap = print_document(renderer, nothing, file,
                               PrinterContext(EmptyReference(), Cell(600), Cell(400),
                                              Dict{Symbol,Any}()))
        (x, y) = only((x, y) for (text, x, y) in _app_drawn_at(get_iomap_output(iomap))
                      if occursin("hello", text))
        answer = read_intent(renderer, iomap, MouseClick(:left, x + 3, y + 3, 1, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceSelectionOperation
        @test occursin(r"^\.content\.entries\[1\]\.value\.value\{\d+\}$",
                       repr(strip_reference_types(answer.path)))
        @test read_intent(renderer, iomap, KeyDown(:s, ModifierKeys(ctrl = true); time = 0.0)) isa SaveFileOperation
    end

    @testset "a file with an empty name declines both" begin
        file = JsonFile("", JsonNull())
        @test read_gesture(file, KeyDown(:s, ModifierKeys(ctrl = true); time = 0.0)) === nothing
        @test read_gesture(file, KeyDown(:o, ModifierKeys(ctrl = true); time = 0.0)) === nothing
    end
end

end
end
