function test_text_line_numbering()

_font = font_ubuntu_monospace_regular_20
_span(text) = TextString(text, _font, color_default)
_caret(k) = make_flat_caret_reference(k)

@testset "TextLineNumbering puts a number before each line" begin
    input = TextBlock(_span("abc"), TextNewline(font = _font), _span("def"))
    iomap = print_document(TextLineNumbering(), input)
    @test [e isa TextString ? e.content : "⏎" for e in iomap.output.elements] ==
          ["1 | ", "abc", "⏎", "2 | ", "def"]
end

@testset "TextLineNumbering maps the caret past the numbers" begin
    # "1 | " is 0:4, "abc" 4:7, ⏎ 7:8, "2 | " 8:12, "def" 12:15.
    proj = TextLineNumbering()
    input = TextBlock(_span("abc"), TextNewline(font = _font), _span("def"))
    iomap = print_document(proj, input)

    @test map_reference_forward(proj, iomap, _caret(0)) == _caret(4)
    @test map_reference_forward(proj, iomap, _caret(3)) == _caret(7)
    @test map_reference_forward(proj, iomap, _caret(4)) == _caret(12)
    @test map_reference_forward(proj, iomap, _caret(5)) == _caret(13)
    @test map_reference_forward(proj, iomap, make_flat_range_reference(1, 5)) ==
          make_flat_range_reference(5, 13)

    # The output selection follows the input selection, so a caret shows.
    set_selection!(input, _caret(5))
    @test strip_reference_types(iomap.output.selection) == _caret(13)

    # Backward: a caret in a line maps back; a caret on a number goes to the
    # first character of its line.
    @test map_reference_backward(proj, iomap, _caret(13)) == _caret(5)
    @test map_reference_backward(proj, iomap, _caret(9)) == _caret(4)
    @test map_reference_backward(proj, iomap, _caret(1)) == _caret(0)
    op = read_intent(proj, iomap, ReplaceSelectionOperation(_caret(13)))
    @test op isa ReplaceSelectionOperation && op.path == _caret(5)
end

@testset "TextLineNumbering maps a caret in a span that holds a line break" begin
    # "1 | " 0:4, "ab\n" 4:7, "2 | " 7:11, "cd" 11:13.
    proj = TextLineNumbering()
    input = TextBlock(_span("ab\ncd"))
    iomap = print_document(proj, input)
    @test map_reference_forward(proj, iomap, _caret(2)) == _caret(6)
    @test map_reference_forward(proj, iomap, _caret(3)) == _caret(11)
    @test map_reference_forward(proj, iomap, _caret(4)) == _caret(12)
    @test map_reference_backward(proj, iomap, _caret(12)) == _caret(4)
end

@testset "TextLineNumbering reads a key against its input, or returns nothing" begin
    proj = TextLineNumbering()
    input = TextBlock(_span("abc"), TextNewline(font = _font), _span("def"))
    iomap = print_document(proj, input)
    set_selection!(input, _caret(5))
    # A key with a rule of the text is an edit at the caret of the input.
    op = read_intent(proj, iomap, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test op isa ReplaceTextRangeOperation
    @test op isa ReplaceTextRangeOperation &&
          strip_reference_types(op.reference) == make_flat_range_reference(4, 5) && op.replacement == ""
    # A key with no rule gets no operation, and the gesture is never the answer.
    @test read_intent(proj, iomap, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing
    # In a chain, the stage before the numbering then gets the key.
    measure = FixedMeasure(10, 18, 6, 0)
    chain = ChainingProjection(TextLineNumbering(), TextToGraphics(measure = measure))
    chain_iomap = print_document(chain, input)
    @test read_intent(chain, chain_iomap, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing
    @test read_intent(chain, chain_iomap, KeyDown(:return, ModifierKeys(); time = 0.0)) === nothing
end

end # test_text_line_numbering
