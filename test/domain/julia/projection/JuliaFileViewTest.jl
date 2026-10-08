# The code of a Julia file in its tab has a gutter of numbers and fold triangles;
# the same code inside another document draws with no gutter.

# The text of every `GraphicsText` that `node` draws, in order.
function _julia_file_view_texts(node, out = String[])
    if node isa GraphicsText
        push!(out, String(node.text))
    elseif node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            current = elements
            while current !== nothing
                _julia_file_view_texts(current.value, out)
                current = current.next
            end
        else
            foreach(element -> _julia_file_view_texts(element, out), elements)
        end
    elseif node isa GraphicsViewport
        _julia_file_view_texts(node.content, out)
    end
    out
end

function test_julia_file_view()
@testset "the code of a Julia file has a gutter of numbers and folds" begin
    measure = FixedMeasure(10, 15, 5, 0)
    projection = NaturalToGraphics(; measure)
    context = with_exact_size(PrinterContext(); width = Cell(Int32(400)), height = Cell(Int32(200)))
    code() = parse_julia("function f(x)\n    x + 1\nend\n")
    pane = WidgetScrollPane(JuliaFile("f.jl", code()); size = Point2D(400, 200))
    texts = _julia_file_view_texts(print_document(projection, nothing, pane, context).output)
    # The numbers of the three lines, and the open triangle of the function.
    @test "2" in texts && "3" in texts
    @test "▾" in texts
    # A Julia document that is no file draws as code with no gutter.
    snippet = _julia_file_view_texts(print_document(projection, nothing, code(), context).output)
    @test !("2" in snippet) && !("▾" in snippet)
end
end
