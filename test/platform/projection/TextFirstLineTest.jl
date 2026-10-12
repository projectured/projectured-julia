function test_text_first_line()

_font = StyleFont("Ubuntu Mono", 20)
_span(text) = TextString(text, _font, color_default)
_caret(k) = make_flat_caret_reference(k)

@testset "TextFirstLine keeps the first line" begin
    iomap = print_document(TextFirstLine(), make_text_block("abc\ndef", StyleText(_font, color_default)))
    @test [get_flat_string(line) for line in iomap.output.elements] == ["abc"]
    iomap = print_document(TextFirstLine(), TextBlock(TextLine(_span("ab")), TextLine(_span("cd"))))
    @test [get_flat_string(line) for line in iomap.output.elements] == ["ab"]
end

@testset "TextFirstLine maps the flat caret" begin
    proj = TextFirstLine()
    input = make_text_block("abc\ndef", StyleText(_font, color_default))
    iomap = print_document(proj, input)

    # A caret on the first line is the same flat offset in the output.
    @test map_reference_forward(proj, iomap, _caret(2)) == _caret(2)
    @test map_reference_forward(proj, iomap, _caret(3)) == _caret(3)
    # A caret after the break is not drawn.
    @test map_reference_forward(proj, iomap, _caret(5)) === nothing
    # A range on the first line maps as a range.
    @test map_reference_forward(proj, iomap, make_flat_range_reference(0, 2)) ==
          make_flat_range_reference(0, 2)
    # The structural caret form maps to the same flat caret.
    structural = @reference ::TextBlock.elements::CellVector[1]::TextLine.elements::CellVector[1]::TextString.content::String{1}::Position
    @test map_reference_forward(proj, iomap, structural) == _caret(1)

    # The output selection follows the input selection.
    set_selection!(input, _caret(2))
    @test strip_reference_types(iomap.output.selection) == _caret(2)
    set_selection!(input, _caret(6))
    @test iomap.output.selection === nothing

    # Backward, and the reader, map the flat caret to the same offset.
    @test map_reference_backward(proj, iomap, _caret(1)) == _caret(1)
    op = read_intent(proj, iomap, ReplaceSelectionOperation(_caret(3)))
    @test op isa ReplaceSelectionOperation && op.path == _caret(3)
end

@testset "TextFirstLine maps a caret before a line break" begin
    proj = TextFirstLine()
    input = TextBlock(TextLine(_span("ab")), TextLine(_span("cd")))
    iomap = print_document(proj, input)
    @test map_reference_forward(proj, iomap, _caret(1)) == _caret(1)
    @test map_reference_forward(proj, iomap, _caret(2)) == _caret(2)
    @test map_reference_forward(proj, iomap, _caret(4)) === nothing
end


@testset "TextFirstLine keeps the first line of a block of lines" begin
    lines = TextBlock(TextDocument[TextLine(_span("ab"); indentation = 2), TextLine(_span("cd"))])
    iomap = print_document(TextFirstLine(), lines)
    @test length(iomap.output.elements) == 1
    @test iomap.output.elements[1] === lines.elements[1]
    # A caret on the first line maps to itself, and one after it to nothing.
    @test map_reference_forward(TextFirstLine(), iomap, _caret(3)) == _caret(3)
    @test map_reference_forward(TextFirstLine(), iomap, _caret(6)) === nothing
end

end # test_text_first_line
