function test_text_line_numbering()

_font = StyleFont("Ubuntu Mono", 20)
_span(text) = TextString(text, _font, color_default)
_caret(k) = make_flat_caret_reference(k)

@testset "TextLineNumbering puts the number of each line in its gutter" begin
    input = TextBlock(TextLine(_span("abc")), TextLine(_span("def")))
    iomap = print_document(TextLineNumbering(), input)
    @test [get_flat_string(line.gutter.number) for line in iomap.output.elements] == ["1", "2"]
    @test [get_flat_string(line) for line in iomap.output.elements] == ["abc", "def"]
end

@testset "TextLineNumbering maps every caret to itself" begin
    # A number is in the gutter of its line, so it is no character: "abc" is 0:3,
    # the break 3:4, "def" 4:7.
    proj = TextLineNumbering()
    input = TextBlock(TextLine(_span("abc")), TextLine(_span("def")))
    iomap = print_document(proj, input)

    for k in 0:7
        @test map_reference_forward(proj, iomap, _caret(k)) == _caret(k)
        @test map_reference_backward(proj, iomap, _caret(k)) == _caret(k)
    end
    @test map_reference_forward(proj, iomap, make_flat_range_reference(1, 5)) ==
          make_flat_range_reference(1, 5)

    # The output selection follows the input selection, so a caret shows.
    set_selection!(input, _caret(5))
    @test strip_reference_types(iomap.output.selection) == _caret(5)

    op = read_intent(proj, iomap, ReplaceSelectionOperation(_caret(5)))
    @test op isa ReplaceSelectionOperation && op.path == _caret(5)
end

@testset "TextLineNumbering maps a caret in a text made of a string with line breaks" begin
    proj = TextLineNumbering()
    input = make_text_block("ab\ncd", StyleText(_font, color_default))
    iomap = print_document(proj, input)
    @test [get_flat_string(line.gutter.number) for line in iomap.output.elements] == ["1", "2"]
    for k in 2:4
        @test map_reference_forward(proj, iomap, _caret(k)) == _caret(k)
        @test map_reference_backward(proj, iomap, _caret(k)) == _caret(k)
    end
end

@testset "TextLineNumbering reads a key against its input, or returns nothing" begin
    proj = TextLineNumbering()
    input = TextBlock(TextLine(_span("abc")), TextLine(_span("def")))
    iomap = print_document(proj, input)
    set_selection!(input, _caret(5))
    # A key with a rule of the text is an edit at the caret of the input, lowered
    # to the run that holds it: "def", character 0.
    op = read_intent(proj, iomap, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test op isa ReplaceStringRangeOperation
    @test op isa ReplaceStringRangeOperation && op.replacement == "" &&
          is_reference_equal(strip_reference_types(op.reference), TextModule._text_replace_path(Int[2, 1], 0, 1))
    # A key with no rule gets no operation, and the gesture is never the answer.
    @test read_intent(proj, iomap, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing
    # In a chain, the stage before the numbering then gets the key.
    measure = FixedMeasure(10, 18, 6, 0)
    chain = ChainingProjection(TextLineNumbering(), TextToGraphics(measure = measure))
    chain_iomap = print_document(chain, input)
    @test read_intent(chain, chain_iomap, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing
    # A line break is an edit of the lines of the input, which stays flat.
    enter = read_intent(chain, chain_iomap, KeyDown(:return, ModifierKeys(); time = 0.0))
    @test enter isa ReplaceTextRangeOperation && enter.replacement == "\n"
    # A typed key: the string edit of the numbered output is declined, and the key
    # is read again against the input, so it types into "def" at character 1.
    op = read_intent(chain, chain_iomap, KeyPress('x'; time = 0.0))
    @test op isa ReplaceStringRangeOperation &&
          is_reference_equal(strip_reference_types(op.reference), TextModule._text_replace_path(Int[2, 1], 1, 1))
end

end # test_text_line_numbering
