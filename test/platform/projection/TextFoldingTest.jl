"""
Tests for `TextFolding`: a closed fold hides the lines after its first one, the
numbers that a stage before it put count the hidden lines, the first line shows a
triangle and a placeholder, and a click on either, or Ctrl+., folds and opens.
"""

using Test
using ProjecturedKernel.GestureModule: MouseClick
using ProjecturedKernel.OperationModule: ToggleCollapseOperation
using ProjecturedPlatform.TextModule: TextGutter, TextGutterToGraphics, TextBlockToScrollLayout,
    TextBlock, TextLine, TextString, TextToGraphics, TextDocument, TextLineNumbering, TextFold,
    TextFolding, make_flat_caret_reference, get_flat_offsets
using ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsToGraphics
using ProjecturedPlatform.StyleModule: StyleFont, color_default
using ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection, TypeDispatchingProjection,
    ChainingProjection

const _FT_FONT = StyleFont("Ubuntu Mono", 14)
_ft_measure() = FixedMeasure(10, 15, 5, 0)

_ft_line(text; fold = nothing) = TextLine(TextString(text, _FT_FONT, color_default); fold)

_ft_chain() = ChainingProjection(TextLineNumbering(), TextFolding(),
                                 TextBlockToScrollLayout(; measure = _ft_measure()))
_ft_renderer() = RecursiveProjection(TypeDispatchingProjection(Pair{Type, Any}[
    TextGutter => TextGutterToGraphics(),
    TextBlock => TextToGraphics(; measure = _ft_measure()),
    GraphicsCanvas => GraphicsToGraphics()]))

_ft_unwrap(x) = x isa AbstractCell ? x[] : x

# The text of the mark in the lane `lane` of the gutter of `line`.
_ft_mark_text(line, lane) = getproperty(line.gutter, lane).elements[1].content

# The text of the spans of `line`.
_ft_line_text(line) = join(span.content for span in line.elements)

function test_text_folding()
@testset "a text folds a region of its lines" begin
    outer = TextFold(; line_count = 2)
    inner = TextFold(; line_count = 1)
    block = TextBlock(TextDocument[_ft_line("one"), _ft_line("two {"; fold = outer),
                                   _ft_line("three ["; fold = inner), _ft_line("four"),
                                   _ft_line("five }"), _ft_line("six")])
    chain = _ft_chain()
    renderer = _ft_renderer()
    iomap = print_document(chain, renderer, block, PrinterContext())
    folding = iomap.step_iomaps[2][]
    folded = folding.output

    @testset "an open fold hides nothing, and its line shows the open triangle" begin
        @test length(folded.elements) == 6
        @test _ft_mark_text(folded.elements[2], :fold) == "▾"
        @test _ft_mark_text(folded.elements[3], :fold) == "▾"
        @test folded.elements[1].gutter.fold === nothing
        @test [_ft_mark_text(folded.elements[k], :number) for k in 1:6] == string.(1:6)
    end

    @testset "a closed fold hides its lines, and the numbers count them" begin
        outer.collapsed = true
        @test length(folded.elements) == 4
        @test [_ft_mark_text(folded.elements[k], :number) for k in 1:4] == ["1", "2", "5", "6"]
        @test _ft_mark_text(folded.elements[2], :fold) == "▸"
        @test _ft_line_text(folded.elements[2]) == "two {…"
        # The caret at the start of the fifth line is at the start of the third line
        # shown.
        input_start = get_flat_offsets(folding.input)[5]
        output_start = get_flat_offsets(folded)[3]
        @test map_reference_forward(folding.projection, folding, make_flat_caret_reference(input_start)) ==
              make_flat_caret_reference(output_start)
        @test map_reference_backward(folding.projection, folding, make_flat_caret_reference(output_start)) ==
              make_flat_caret_reference(input_start)
    end

    @testset "a click on the triangle or on the placeholder folds and opens" begin
        layout = iomap.step_iomaps[3][]
        row = _ft_unwrap(layout.gutter_rows)[2]
        fold_x = Int(getfield(row.iomap, :child_iomaps)[][3][1][]) + 1
        click(x, y) = read_intent(chain, renderer,
                                  Intent(MouseClick(:left, x, y, ModifierKeys(); time = 0.0)), iomap).operation
        answer = click(fold_x, Int(row.row.y[]) + 3)
        @test answer isa ToggleCollapseOperation
        @test answer.target === outer
        # The placeholder `…` stands after the five characters of "two {", 10 pixels each.
        gutter_w = Int(layout.output.left.w[])
        answer = click(gutter_w + 58, Int(row.row.y[]) + 3)
        @test answer isa ToggleCollapseOperation
        @test answer.target === outer
        # A click on the text of the line puts a caret.
        @test click(gutter_w + 12, Int(row.row.y[]) + 3) isa ReplaceSelectionOperation
    end

    @testset "Ctrl+. folds the innermost fold around the caret" begin
        outer.collapsed = false
        caret = get_flat_offsets(block)[4] + 1
        getfield(block, :selection)[] = make_flat_caret_reference(caret)
        answer = read_intent(folding.projection, folding, ToggleCollapseOperation())
        @test answer isa ToggleCollapseOperation
        @test answer.target === inner
    end
    @testset "a click on the triangle of a syntax node toggles the node" begin
        body = SyntaxNode(SyntaxDocument[SyntaxLeaf("a"), SyntaxLeaf("b")];
                          open = "(", close = ")", sep = " ", indentation = 1)
        syntax_chain = ChainingProjection(RecursiveProjection(SyntaxToText(text_folds = true)),
                                          TextLineNumbering(), TextFolding(),
                                          TextBlockToScrollLayout(; measure = _ft_measure()))
        syntax_iomap = print_document(syntax_chain, renderer, body, PrinterContext())
        syntax_layout = syntax_iomap.step_iomaps[4][]
        row = _ft_unwrap(syntax_layout.gutter_rows)[1]
        fold_x = Int(getfield(row.iomap, :child_iomaps)[][3][1][]) + 1
        answer = read_intent(syntax_chain, renderer,
                             Intent(MouseClick(:left, fold_x, Int(row.row.y[]) + 3, ModifierKeys(); time = 0.0)),
                             syntax_iomap).operation
        @test answer isa ToggleCollapseOperation
        # The fold shares the `collapsed` cell of the node, so the toggle folds the node.
        @test getfield(answer.target, :collapsed) === getfield(body, :collapsed)
    end
end
end
