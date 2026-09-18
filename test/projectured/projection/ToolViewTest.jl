# A tool view draws in a tab because its own slice told the renderer how.
#
# A person opens a tool by typing its name into an empty tab, and the tab then
# holds an ordinary document. Nothing about that tab knows what a tool is: it
# draws its content through the render-anything projection, the same one that
# draws a JSON file or a table. So each tool registers one row from its own
# `__init__`, the way the file system slice already does, and no application
# names a tool anywhere.
#
# The failure this test is for is silent. A document no row claims falls through
# to the reflection tail and renders as its field names, or as the phrase "no
# natural rendering for X" — a person sees a page of nothing useful rather than
# an error.

using Test

function test_tool_views()
@testset "every tool view draws itself" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)

# Every word the canvas draws, joined.
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

# Each tool is built the way the insertion builds it: with no argument at all.
# A tool that needs one is a tool a person cannot open by typing its name.
@testset "a tool takes no argument" begin
    @test Assistant() isa Document
    @test GestureLog() isa Document
    @test ReferenceInspector() isa Document
end

@testset "the renderer claims each tool" begin
    for tool in (Assistant(), GestureLog(), ReferenceInspector())
        @test !occursin("no natural rendering", render(tool))
    end
end

# The insertion reaches each tool by its own name, which is what makes
# Ctrl+T, Insert, a name, Enter work.
@testset "the insertion resolves each tool by name" begin
    @test resolve_insertion(Document, "Assistant") === Assistant
    @test resolve_insertion(Document, "GestureLog") === GestureLog
    @test resolve_insertion(Document, "ReferenceInspector") === ReferenceInspector
end

end
end
