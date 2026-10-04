function test_selection_inverting()

_font = StyleFont("Ubuntu Mono", 20)

# `elements[span].content{char}` cursor path (span 1-based, char 0-based).
_ref(span, char) = ConcreteReference(FieldReferenceStep("elements"),
    ConcreteReference(RangeReferenceStep(span - 1, span),
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(char, char), EmptyReference()))))

# `elements[span].content[start:stop]` range path.
_range(span, start, stop) = ConcreteReference(FieldReferenceStep("elements"),
    ConcreteReference(RangeReferenceStep(span - 1, span),
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))))

_contents(text) = [e.content for e in text.elements if e isa TextString]
_fills(text)    = [e.fill_color for e in text.elements if e isa TextString]
_fgs(text)      = [e.font_color for e in text.elements if e isa TextString]

# Build a one-span TextBlock carrying a selection.
function _doc(content, sel; fg=color_red, fill=nothing)
    span = TextString(Cell(content), Cell(_font), Cell(fg), Cell(fill),
                      Cell(nothing), Cell(nothing), Cell(nothing))
    TextBlock(CellVector(Cell[Cell(span)]), Cell(sel))
end

@testset "SelectionInverting nothing selection is pass-through" begin

    input = TextBlock(
        TextString("a", _font, color_default),
        TextNewline(font=_font),
        TextString("b", _font, color_default),
    )
    out = print_document(SelectionInverting(), input).output
    @test length(out.elements) == 3
    for i in 1:3
        @test out.elements[i] === input.elements[i]
    end

end # @testset

@testset "SelectionInverting range inverts exactly [start, stop)" begin

    # Select chars [0:5) ("alpha") of "alpha beta".
    out = print_document(SelectionInverting(), _doc("alpha beta", _range(1, 0, 5))).output
    @test _contents(out) == ["alpha", " beta"]
    fills = _fills(out)
    fgs = _fgs(out)
    # Inverted run: fg ← original fill (nothing → default_bg), fill ← original fg.
    @test fgs[1] == get_theme_value(TextTheme(), :inverted_background)   # default_bg (orig fill was nothing)
    @test fills[1] == color_red                       # original fg becomes the fill
    # Untouched trailing run keeps the original colors.
    @test fgs[2] == color_red
    @test fills[2] === nothing

end # @testset

@testset "SelectionInverting splits a span at both boundaries" begin

    # Select the middle [2:5) of "alphabet".
    out = print_document(SelectionInverting(), _doc("alphabet", _range(1, 2, 5))).output
    @test _contents(out) == ["al", "pha", "bet"]
    fills = _fills(out)
    @test fills[1] === nothing       # leading untouched
    @test fills[2] == color_red      # inverted middle (orig fg → fill)
    @test fills[3] === nothing       # trailing untouched

end # @testset

@testset "SelectionInverting fill_color=nothing uses default_bg" begin

    out = print_document(SelectionInverting(; default_bg=color_blue),
                           _doc("xy", _range(1, 0, 2); fg=color_green, fill=nothing)).output
    @test _fgs(out)[1] == color_blue     # inverted fg = default_bg (no transparent inversion)
    @test _fills(out)[1] == color_green  # inverted fill = original fg

end # @testset

@testset "SelectionInverting caret widens to a one-char block (mid-span)" begin

    # Zero-width caret at offset 2 of "abcde" → invert exactly the char at 2.
    out = print_document(SelectionInverting(), _doc("abcde", _ref(1, 2))).output
    @test _contents(out) == ["ab", "c", "de"]
    @test _fills(out)[2] == color_red    # the single inverted glyph

end # @testset

@testset "SelectionInverting caret at offset 0" begin

    out = print_document(SelectionInverting(), _doc("abc", _ref(1, 0))).output
    @test _contents(out) == ["a", "bc"]
    @test _fills(out)[1] == color_red

end # @testset

@testset "SelectionInverting caret at end-of-text synthesizes a block" begin

    # Caret one past the last char → a synthesized trailing inverted space.
    out = print_document(SelectionInverting(), _doc("abc", _ref(1, 3))).output
    @test _contents(out) == ["abc", " "]   # original span unchanged + block space
    @test _fills(out)[1] === nothing       # original span untouched
    @test _fills(out)[2] == color_red      # synthesized block carries inverted colors

end # @testset

@testset "SelectionInverting block_cursor=false leaves a zero-width caret" begin

    out = print_document(SelectionInverting(; block_cursor=false), _doc("abc", _ref(1, 1))).output
    @test _contents(out) == ["abc"]        # no split, no inversion
    @test _fills(out)[1] === nothing

end # @testset

@testset "SelectionInverting selection round-trip" begin

    proj = SelectionInverting()
    iomap = print_document(proj, _doc("alphabet", _range(1, 2, 5)))
    out = iomap.output
    segs = iomap.segs
    @test length(segs) == 3
    for seg in segs
        seg.length == 0 && continue
        for k in 0:seg.length
            out_ref = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, seg.out_index, k))
            in_ref = map_reference_backward(proj, iomap, out_ref)
            @test in_ref !== nothing
            @test map_reference_forward(proj, iomap, in_ref) !== nothing
        end
    end

end # @testset

@testset "SelectionInverting reader shifts char range by sub-span start" begin

    proj = SelectionInverting()
    iomap = print_document(proj, _doc("alphabet", _range(1, 2, 5)))
    # Output span 3 is the trailing "bet", starting at input char 5.
    edit = read_intent(proj, iomap, ReplaceStringRangeOperation(_range(3, 0, 3), "X"))
    @test edit isa ReplaceStringRangeOperation
    @test edit.reference == _range(1, 5, 8)
    @test edit.replacement == "X"

end # @testset

@testset "SelectionInverting out-of-range spans untouched (multi-span)" begin

    input = TextBlock(
        TextString("foo", _font, color_red),
        TextString("bar", _font, color_green),
    )
    # Flat range [3:6) selects the whole second span via a whole-element ref.
    input = TextBlock(CellVector(Cell[Cell(input.elements[1]), Cell(input.elements[2])]),
                     Cell(ConcreteReference(TextSpanReferenceStep(3, 6), EmptyReference())))
    out = print_document(SelectionInverting(), input).output
    @test _contents(out) == ["foo", "bar"]
    @test out.elements[1] === input.elements[1]   # first span untouched (same object)
    @test _fills(out)[2] == color_green           # second span inverted

end # @testset

end # test_selection_inverting
