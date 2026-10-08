"""
Tests for the gutter of a text: `TextGutterToGraphics` lays out the lanes of one
line, and `TextBlockToScrollLayout` puts the gutter of each line beside it, on
its baseline, as the left edge of a `ScrollLayout`, and maps references, points
and clicks to the lines or to a gutter.
"""

using Test
using ProjecturedKernel.GestureModule: MouseClick
using ProjecturedPlatform.TextModule: TextGutter, TextGutterToGraphics, TextBlockToScrollLayout,
    TextBlock, TextLine, TextString, TextToGraphics, TextRangeReferenceStep, PrimitiveNumberToText,
    TextDocument, TextLineNumbering, WordWrapping, TextHighlighting, TextFiltering,
    SelectionInverting, TextFirstLine
using ProjecturedPlatform.LayoutModule: ScrollLayout
using ProjecturedPlatform.WidgetModule: WidgetScrollPane, Point2D, WidgetToGraphics
using ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsViewport,
    GraphicsToGraphics, layout_none, find_first_baseline
using ProjecturedPlatform.StyleModule: StyleFont, FontMetrics, color_black, color_default
using ProjecturedPlatform.PrimitiveModule: PrimitiveNumber
using ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection, TypeDispatchingProjection,
    ChainingProjection

const _GT_SMALL = StyleFont("Ubuntu Mono", 14)
const _GT_LARGE = StyleFont("Ubuntu Mono", 28)
_gt_measure() = FixedMeasure(10, 15, 5, 0; fonts = Dict(_GT_LARGE => FontMetrics(30, 10, 0)))

_gt_renderer() = RecursiveProjection(TypeDispatchingProjection(vcat(
    Pair{Type, Any}[
        TextBlock => TextBlockToScrollLayout(; measure = _gt_measure()),
        TextGutter => TextGutterToGraphics(),
        PrimitiveNumber => ChainingProjection(PrimitiveNumberToText(), TextToGraphics(; measure = _gt_measure())),
        GraphicsCanvas => GraphicsToGraphics()],
    WidgetToGraphics(_GT_SMALL; measure = _gt_measure()).dispatch)))

# A marker: a canvas of 10 by 10, filled.
_gt_marker() = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(10)), Cell(Int32(10)),
                              CellVector(Cell[Cell(GraphicsRect(0, 0, 10, 10; color = color_black))]),
                              layout_none, true, Cell(nothing))

_gt_line(text, font, n; marker = nothing) =
    TextLine(TextString(text, font, color_default); gutter = TextGutter(; marker, number = PrimitiveNumber(n)))

_gt_block() = TextBlock(TextDocument[_gt_line("alpha", _GT_SMALL, 1),
                                     _gt_line("beta", _GT_LARGE, 2; marker = _gt_marker()),
                                     _gt_line("gamma", _GT_SMALL, 3)])

# The steps of a reference, as a vector.
function _gt_steps(reference)
    steps = Any[]
    while reference isa ConcreteReference
        push!(steps, reference.head)
        reference = reference.tail
    end
    steps
end

_gt_unwrap(x) = x isa AbstractCell ? x[] : x

# A chain that numbers the lines and draws them with their gutters, and the
# recursion that prints the marks: a number is a `TextBlock`, which the text draws.
_gt_numbering_chain() = ChainingProjection(TextLineNumbering(),
                                           TextBlockToScrollLayout(; measure = _gt_measure()))
_gt_mark_renderer() = RecursiveProjection(TypeDispatchingProjection(Pair{Type, Any}[
    TextGutter => TextGutterToGraphics(),
    TextBlock => TextToGraphics(; measure = _gt_measure()),
    GraphicsCanvas => GraphicsToGraphics()]))

_gt_plain_line(text) = TextLine(TextString(text, _GT_SMALL, color_default))

# The text of the number in the gutter of output line `i`.
_gt_number_text(output, i) = output.elements[i].gutter.number.elements[1].content

function test_text_gutter()
@testset "the gutter of a text" begin

    @testset "a gutter lays out its lanes: marker, number, fold" begin
        renderer = _gt_renderer()
        gutter = TextGutter(; marker = _gt_marker(), number = PrimitiveNumber(42))
        iomap = print_document(renderer, gutter)
        entries = getfield(iomap, :child_iomaps)[]
        @test entries[3] === nothing                        # no fold
        number_w = Int(entries[2][3].output.w[])
        # The marker lane is 16 wide, the mark 10, so it stands at 3; the number
        # lane starts after the gap, at 20, and is as wide as its mark.
        @test Int(entries[1][1][]) == 3
        @test Int(entries[2][1][]) == 20
        @test Int(iomap.output.w[]) == 16 + 4 + number_w + 4 + 16 + 4
        # The number draws text, so the gutter has its baseline.
        @test find_first_baseline(iomap) !== nothing
    end

    @testset "each gutter stands beside its line, on its baseline" begin
        renderer = _gt_renderer()
        block = _gt_block()
        iomap = print_document(renderer, block)
        output = iomap.output
        @test output isa ScrollLayout
        left, center = output.left, output.center
        rows = _gt_unwrap(iomap.gutter_rows)
        @test length(rows) == 3
        # The left edge is as wide as a gutter and as high as the lines.
        @test Int(left.w[]) == Int(rows[1].iomap.output.w[])
        @test Int(left.h[]) == Int(center.h[])
        lines = iomap.lines_iomap
        for (L, row) in enumerate(rows)
            cells = lines.line_cells(row.group)
            line_baseline = Int(cells.y[]) + cells.layout[].first_baseline
            gutter_baseline = Int(row.row.y[]) + find_first_baseline(row.iomap)
            @test gutter_baseline == line_baseline
        end
        # The second line is taller, so the third gutter stands lower than it would
        # beside a line of the small font.
        @test Int(rows[3].row.y[]) > Int(rows[2].row.y[]) + 15
    end

    @testset "a reference into a gutter maps to its row, and back" begin
        renderer = _gt_renderer()
        block = _gt_block()
        iomap = print_document(renderer, block)
        number = ConcreteReference(FieldReferenceStep("elements"),
            ConcreteReference(RangeReferenceStep(1, 2),
                ConcreteReference(FieldReferenceStep("gutter"),
                    ConcreteReference(FieldReferenceStep("number"), EmptyReference()))))
        forward = map_reference_forward(iomap.projection, iomap, number)
        @test forward !== nothing
        @test _gt_steps(forward)[1:3] ==
              Any[FieldReferenceStep("left"), FieldReferenceStep("elements"), RangeReferenceStep(1, 2)]
        back = strip_reference_types(map_reference_backward(iomap.projection, iomap, forward))
        @test back == number
        # A caret in the text maps through the lines to the center.
        caret = ConcreteReference(TextRangeReferenceStep(7, 7), EmptyReference())
        @test _gt_steps(map_reference_forward(iomap.projection, iomap, caret))[1] ==
              FieldReferenceStep("center")
    end

    @testset "a click goes to the line or to the gutter at its point" begin
        renderer = _gt_renderer()
        block = _gt_block()
        iomap = print_document(renderer, block)
        rows = _gt_unwrap(iomap.gutter_rows)
        gutter_w = Int(iomap.output.left.w[])
        lines = iomap.lines_iomap
        second = lines.line_cells(rows[2].group)
        y2 = Int(second.y[]) + 5
        click(x, y) = read_intent(iomap.projection, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))

        # On the lines: a caret in the second line, past "alpha" and its break.
        op = click(gutter_w + 1, y2)
        @test op isa ReplaceSelectionOperation
        step = _gt_steps(strip_reference_types(op.path))[1]
        @test step isa TextRangeReferenceStep && step.start in 6:7

        # On the number of the second line: into that gutter, through its number.
        number_x = Int(getfield(rows[2].iomap, :child_iomaps)[][2][1][]) + 1
        op = click(number_x, Int(rows[2].row.y[]) + 3)
        @test op isa ReplaceSelectionOperation
        @test _gt_steps(strip_reference_types(op.path))[1:4] ==
              Any[FieldReferenceStep("elements"), RangeReferenceStep(1, 2),
                  FieldReferenceStep("gutter"), FieldReferenceStep("number")]

        # On the marker, which takes no click: the marker is selected as a whole.
        # It draws no text, so it stands in the middle of the row, 5 down.
        op = click(5, Int(rows[2].row.y[]) + 8)
        @test op isa ReplaceSelectionOperation
        @test strip_reference_types(op.path) ==
              ConcreteReference(FieldReferenceStep("elements"),
                  ConcreteReference(RangeReferenceStep(1, 2),
                      ConcreteReference(FieldReferenceStep("gutter"),
                          ConcreteReference(FieldReferenceStep("marker"), EmptyReference()))))

        # On an empty lane: nothing.
        @test click(5, Int(rows[1].row.y[]) + 3) === nothing
    end

    @testset "TextLineNumbering puts the number of each line in its gutter" begin
        marker = _gt_marker()
        lines = TextDocument[_gt_plain_line("line $n") for n in 1:9]
        lines[3] = TextLine(TextString("line 3", _GT_SMALL, color_default);
                            gutter = TextGutter(; marker))
        block = TextBlock(lines)
        chain = _gt_numbering_chain()
        renderer = _gt_mark_renderer()
        iomap = print_document(chain, renderer, block, PrinterContext())
        numbered = iomap.step_iomaps[1][].output
        @test [_gt_number_text(numbered, i) for i in 1:9] == string.(1:9)
        # The other lanes keep their cells: the marker of line 3 is the same mark.
        @test numbered.elements[3].gutter.marker === marker
        @test getfield(numbered.elements[3].gutter, :marker) === getfield(block.elements[3].gutter, :marker)
        # The tenth line gives every number a second digit.
        push!(block.elements, _gt_plain_line("line 10"))
        @test _gt_number_text(numbered, 1) == " 1"
        @test _gt_number_text(numbered, 10) == "10"
        # Every row of the gutter has one width.
        layout = iomap.step_iomaps[2][]
        widths = [Int(row.iomap.output.w[]) for row in _gt_unwrap(layout.gutter_rows)]
        @test length(widths) == 10 && allequal(widths)
    end

    @testset "a click on a number selects its line" begin
        block = TextBlock(TextDocument[_gt_plain_line("alpha"), _gt_plain_line("beta"),
                                       _gt_plain_line("gamma")])
        chain = _gt_numbering_chain()
        renderer = _gt_mark_renderer()
        iomap = print_document(chain, renderer, block, PrinterContext())
        layout = iomap.step_iomaps[2][]
        row = _gt_unwrap(layout.gutter_rows)[2]
        number_x = Int(getfield(row.iomap, :child_iomaps)[][2][1][]) + 1
        click = MouseClick(:left, number_x, Int(row.row.y[]) + 3, ModifierKeys(); time = 0.0)
        answer = read_intent(chain, renderer, Intent(click), iomap).operation
        @test answer isa ReplaceSelectionOperation
        # "alpha" and its break are 6 characters, and "beta" is 4.
        @test strip_reference_types(answer.path) ==
              ConcreteReference(TextRangeReferenceStep(6, 10), EmptyReference())
    end

    @testset "a decorator keeps the gutter of a line" begin
        # Each one passes a line through with its gutter. None of them knows lines
        # yet, which is the work of text-domain-kit: a pattern of `TextFiltering`
        # matches no line of a block of lines, so the filter here is idle.
        block = _gt_block()
        gutters = [line.gutter for line in block.elements]
        for decorator in (WordWrapping(; max_width = 30, measure = _gt_measure()),
                          TextHighlighting("a"), TextFiltering(), SelectionInverting(),
                          TextFirstLine())
            output = print_document(decorator, block).output
            kept = [element.gutter for element in output.elements if element isa TextLine]
            @test !isempty(kept)
            @test all(any(g === gutter for gutter in gutters) for g in kept)
        end
    end

    @testset "in a scroll pane the gutter is the left edge" begin
        renderer = _gt_renderer()
        block = _gt_block()
        pane = WidgetScrollPane(block; size = Point2D(60, 40))
        iomap = print_document(renderer, pane)
        viewports = [node for node in (_gt_unwrap(e) for e in iomap.output.elements)
                     if node isa GraphicsViewport]
        @test length(viewports) == 2
        gutter_w = Int(iomap.content_iomap.output.left.w[])
        @test Int(viewports[1].w[]) == gutter_w
        @test Int(viewports[2].w[]) == 60 - gutter_w
        # Scrolled down and to the right, the gutter moves down only.
        getfield(pane, :scroll_position)[] = Point2D(15, 10)
        held(viewport) = _gt_unwrap(viewport.content)
        @test (Int(held(viewports[1]).x[]), Int(held(viewports[1]).y[])) == (0, -10)
        @test Int(held(viewports[2]).y[]) == -10
    end
end
end
