# The line model of `TextToGraphics`: every box of a line sits on one baseline,
# a line is as high as its fonts ask, and the line spacing sets the distance to
# the next line. Two fonts with fixed metrics make every number exact: `small`
# has ascent 12, descent 4 and no line gap, and `large` has ascent 16, descent 6
# and a line gap of 2. Every character is 10 pixels wide.
function test_text_line_model()
@testset "a line of text sits on one baseline" begin

    small = StyleFont("Ubuntu", 20)
    large = StyleFont("Ubuntu Mono", 20)
    measure = FixedMeasure(10, 12, 4, 0; fonts = Dict(large => FontMetrics(16, 6, 2)))

    # Every element of a canvas with its absolute position.
    function flatten(canvas, x0 = 0, y0 = 0, out = Any[])
        for element in canvas.elements
            if element isa GraphicsCanvas
                flatten(element, x0 + Int(element.x), y0 + Int(element.y), out)
            else
                push!(out, (element, x0 + Int(element.x), y0 + Int(element.y)))
            end
        end
        out
    end
    texts(canvas) = [(String(e.text), x, y) for (e, x, y) in flatten(canvas) if e isa GraphicsText]
    rects(canvas) = [(x, y, Int(e.w), Int(e.h)) for (e, x, y) in flatten(canvas)
                     if e isa GraphicsRect && Int(e.w) > 0]
    print_block(block; spacing = SingleSpacing()) =
        print_document(TextToGraphics(measure = measure, line_spacing = spacing), block)
    # Two lines of `small` and a line of `large`: the lines are 16, 16 and 24 high.
    three_lines() = TextBlock(TextString("ab\ncd", small, color_black), TextNewline(font = small),
                              TextString("ef", large, color_black))

    @testset "two fonts on one line share its baseline" begin
        block = TextBlock(TextString("ab", small, color_black), TextString("cd", large, color_black))
        canvas = print_block(block).output
        # The line is 16 + 6 + 2 = 24 high, and half of its line gap is above the
        # ink, so the baseline is 1 + 16 below its top. The box of each text
        # begins its own ascent above that baseline.
        @test texts(canvas) == [("ab", 0, 17 - 12), ("cd", 20, 17 - 16)]
        @test Int(canvas.h) == 24
    end

    @testset "a line is as high as its own fonts ask" begin
        canvas = print_block(three_lines()).output
        # The lines of `small` are 16 apart. The line of `large` begins at 32, and
        # its baseline is 17 below that.
        @test texts(canvas) == [("ab", 0, 0), ("cd", 0, 16), ("ef", 0, 32 + 17 - 16)]
        @test Int(canvas.h) == 32 + 24
    end

    @testset "the spacing sets the distance of the lines" begin
        block = TextBlock(TextString("ab\ncd", small, color_black))
        tops(spacing) = [y for (_, _, y) in texts(print_block(block; spacing).output)]
        # Single: the natural distance, 16.
        @test tops(SingleSpacing()) == [0, 16]
        # Double: 32, and half of the leading of 16 above the ink.
        @test tops(MultipleSpacing(2)) == [8, 40]
        # At least 20: 20, and half of the leading of 4 above the ink.
        @test tops(AtLeastSpacing(20)) == [2, 22]
        @test tops(AtLeastSpacing(10)) == [0, 16]
        # Exactly 10: the ink of the lines overlaps, and the box of the block
        # still reaches the bottom of the ink of the last line.
        @test tops(ExactSpacing(10)) == [0, 10]
        @test Int(print_block(block; spacing = ExactSpacing(10)).output.h) == 10 + 12 + 4
    end

    @testset "the caret stands on the baseline, as high as the font at its place" begin
        block = TextBlock(TextString("ab", small, color_black), TextString("cd", large, color_black))
        caret(k) = [r for r in rects(print_block(with_selection(block,
                        TextModule.make_flat_caret_reference(k))).output) if r[3] == 2]
        @test caret(1) == [(10, 17 - 12, 2, 12 + 4)]
        @test caret(3) == [(30, 17 - 16, 2, 16 + 6)]
    end

    @testset "a selection covers each line box, with no gap between them" begin
        canvas = print_block(with_selection(three_lines(), TextModule.make_flat_range_reference(1, 7))).output
        @test [(y, h) for (_, y, w, h) in rects(canvas) if w != 2] == [(0, 16), (16, 16), (32, 24)]
    end

    @testset "a click picks the line whose box holds it" begin
        projection = TextToGraphics(measure = measure)
        iomap = print_document(projection, three_lines())
        click(x, y) = read_intent(projection, iomap, MouseClick(:left, x, y; time = 0.0)).path
        is_caret(path, k) = is_reference_equal(path, TextModule.make_flat_caret_reference(k))
        # The last row of the first line, and the first row of the second.
        @test is_caret(click(12, 15), 1)
        @test is_caret(click(12, 16), 4)
        # The line of `large` begins at 32, above the top of its text at 33. Its
        # span starts at flat offset 6, past the newline of the block.
        @test is_caret(click(12, 31), 4)
        @test is_caret(click(12, 32), 7)
    end

    @testset "a paragraph of the list path sits on one baseline" begin
        node = ListNode(TextString("ab", small, color_black))
        push!(node, TextString("cd", large, color_black))
        push!(node, TextNewline(font = small))
        push!(node, TextString("ef", small, color_black))
        block = TextBlock()
        block.elements = node
        canvas = print_document(TextToGraphics(measure = measure), IdentityProjection(), block,
                                PrinterContext()).output
        first_paragraph = canvas.elements.value
        @test [(String(e.text), Int(e.x), Int(e.y)) for e in first_paragraph.elements] ==
              [("ab", 0, 17 - 12), ("cd", 20, 17 - 16)]
        @test Int(canvas.elements.next.value.y) == 24
    end

    @testset "body text, code and an emoji share one baseline by the font files" begin
        block = TextBlock(TextString("Type ", StyleFont("Ubuntu", 20), color_black),
                          TextString("code", StyleFont("Ubuntu Mono", 20), color_black),
                          TextString(" 😀", StyleFont("Ubuntu", 20), color_black))
        canvas = print_document(TextToGraphics(measure = FontFileMeasure()), block).output
        # A backend draws the baseline of a text the ascent of its box below its `y`.
        baselines = [y + compute_text_extent(String(e.text), e.font)[2]
                     for (e, _, y) in flatten(canvas) if e isa GraphicsText]
        @test length(baselines) == 3
        @test allequal(baselines)
    end

end
end
