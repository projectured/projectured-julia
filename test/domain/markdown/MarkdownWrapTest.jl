# A page of prose breaks its lines at the edge of the page.
#
# Two things have to be true together, and each was false on its own: the page
# must OFFER each block its width, and a block of prose must BREAK its lines to
# what it was offered. A code block must not break, because the layout of code
# says which block a line is in.

function test_markdown_page_wrap()
@testset "a markdown page breaks its prose at the page edge" begin

# Eight pixels a character and sixteen a line, so a bound is arithmetic.
_measure = FixedMeasure(8, 12, 4, 0)

# Every text a canvas drew, as (right edge, content).
function _spans(node, ox = 0, found = Tuple{Int,String}[])
    if node isa GraphicsCanvas
        for element in node.elements
            _spans(element, ox + Int(node.x), found)
        end
    elseif node isa GraphicsViewport
        _spans(node.content, ox + Int(node.x), found)
    elseif node isa GraphicsText
        text = string(node.text)
        push!(found, (ox + Int(node.x) + length(text) * 8, text))
    end
    found
end

function _page_spans(source, width)
    renderer = NaturalToGraphics(measure = _measure)
    context = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
                                                height = Cell(Int32(800)))
    _spans(print_document(renderer, nothing, parse_markdown(source), context).output)
end

sentence = "one two three four five six seven eight nine ten eleven twelve thirteen"

@testset "a paragraph ends inside the page" begin
    spans = _page_spans("# A heading\n\n" * sentence * "\n", 200)
    @test length(spans) > 2
    @test maximum(right for (right, _) in spans) <= 200
end

@testset "the same page at twice the width uses fewer lines" begin
    narrow = _page_spans(sentence * "\n", 200)
    wide   = _page_spans(sentence * "\n", 400)
    @test length(wide) < length(narrow)
    @test maximum(right for (right, _) in wide) <= 400
end

@testset "a code block keeps its lines whole" begin
    code = "```julia\n" * sentence * "\n```\n"
    spans = _page_spans(code, 200)
    @test any(right -> right > 200, (right for (right, _) in spans))
end

end
end
