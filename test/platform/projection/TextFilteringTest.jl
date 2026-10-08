function test_text_filtering()

# Build the standard fixture: three logical lines, the first and third
# containing "dolor". Spans are 1-based input element indices:
#   1: "alpha dolor"   2: newline   3: "beta gamma"   4: newline   5: "delta dolor"
function _fixture()
    nl() = TextNewline(font=StyleFont("Ubuntu Mono", 20))
    TextBlock(
        TextString("alpha dolor", StyleFont("Ubuntu Mono", 20), color_default),
        nl(),
        TextString("beta gamma", StyleFont("Ubuntu Mono", 20), color_default),
        nl(),
        TextString("delta dolor", StyleFont("Ubuntu Mono", 20), color_default),
    )
end

# `elements[span].content{char}` cursor path (span/char are 1-based / 0-based).
# Canonical (typed) form: the projection emits the same self-describing
# `::TextBlock.elements[..].content::String{..}` checkpoints, so the round-trip
# assertions compare typed-against-typed.
_ref(span, char) = @reference ::TextBlock.elements::CellVector[span]::TextString.content::String{char}::Position

# `elements[span].content[start:stop]` range path.
_range(span, start, stop) = ConcreteReference(FieldReferenceStep("elements"),
    ConcreteReference(RangeReferenceStep(span - 1, span),
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))))

_contents(text) = [e.content for e in text.elements if e isa TextString]

@testset "TextFiltering keeps matching lines" begin

    iomap = print_document(TextFiltering(r"dolor"), _fixture())
    out = iomap.output
    @test _contents(out) == ["alpha dolor", "delta dolor"]
    @test iomap.kept == [1, 2, 5]           # both matching lines incl. line 1's newline
    @test count(e -> e isa TextNewline, out.elements) == 1

end # @testset

@testset "TextFiltering invert keeps the complement" begin

    iomap = print_document(TextFiltering(r"dolor", invert=true), _fixture())
    @test _contents(iomap.output) == ["beta gamma"]
    @test iomap.kept == [3, 4]

end # @testset

@testset "TextFiltering nothing pattern is pass-through" begin

    iomap = print_document(TextFiltering(), _fixture())
    @test length(iomap.output.elements) == 5
    @test iomap.kept == [1, 2, 3, 4, 5]
    @test _contents(iomap.output) == ["alpha dolor", "beta gamma", "delta dolor"]

end # @testset

@testset "TextFiltering selection round-trip" begin

    proj = TextFiltering(r"dolor")
    input = _fixture()
    iomap = print_document(proj, input)
    out = iomap.output
    # Flat caret at (span, char); the fixture carries newlines, so the flat offset
    # is not the raw char index.
    fin(span, char)  = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(input, span, char))
    fout(span, char) = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, span, char))

    # Kept line 1 (output span 1) and line 3 (output span 3) round-trip; dropping
    # the middle line shifts line 3's flat offset back by its length.
    for (in_span, out_span, char) in ((1, 1, 3), (5, 3, 2))
        fwd = map_reference_forward(proj, iomap, fin(in_span, char))
        @test fwd == fout(out_span, char)
        @test map_reference_backward(proj, iomap, fwd) == fin(in_span, char)
    end

    # A cursor on the filtered-out middle line has no image in the output.
    @test map_reference_forward(proj, iomap, fin(3, 2)) === nothing

end # @testset

@testset "TextFiltering maps a whole-element box past a dropped line" begin

    box(s, e) = ConcreteReference(TextSpanReferenceStep(s, e), EmptyReference())
    proj = TextFiltering(r"dolor")
    input = _fixture()
    iomap = print_document(proj, input)

    # "delta dolor" is 23:34 in the input and 12:23 in the output, because the
    # dropped line "beta gamma" ⏎ is 11 characters long.
    @test map_reference_forward(proj, iomap, box(23, 34)) == box(12, 23)
    @test map_reference_backward(proj, iomap, box(12, 23)) == box(23, 34)
    # A box on a kept line before the dropped one does not move.
    @test map_reference_forward(proj, iomap, box(6, 11)) == box(6, 11)
    # A box on the dropped line has no image.
    @test map_reference_forward(proj, iomap, box(12, 22)) === nothing
    # A box over all three lines keeps the part that is shown.
    @test map_reference_forward(proj, iomap, box(0, 34)) == box(0, 23)
    # The output selection is the mapped box.
    set_selection!(input, box(23, 34))
    @test strip_reference_types(iomap.output.selection) == box(12, 23)

end # @testset

@testset "TextFiltering reader remaps element index" begin

    proj = TextFiltering(r"dolor")
    input = _fixture()
    iomap = print_document(proj, input)
    out = iomap.output

    # ReplaceSelectionOperation on output span 3 → input span 5, char preserved
    # (a flat caret; the reader remaps the flat offset across the dropped line).
    sel = read_intent(proj, iomap, ReplaceSelectionOperation(
        TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, 3, 2))))
    @test sel isa ReplaceSelectionOperation
    @test sel.path == TextModule.make_flat_caret_reference(convert_element_to_flat_offset(input, 5, 2))

    # ReplaceStringRangeOperation on output span 3 → input span 5, range preserved.
    edit = read_intent(proj, iomap, ReplaceStringRangeOperation(_range(3, 1, 4), "XYZ"))
    @test edit isa ReplaceStringRangeOperation
    @test edit.reference == _range(5, 1, 4)
    @test edit.replacement == "XYZ"

end # @testset

@testset "TextFiltering re-filters when the pattern cell changes" begin

    pat = Cell(r"dolor")
    iomap = print_document(TextFiltering(pat), _fixture())
    @test iomap.kept == [1, 2, 5]

    pat[] = r"gamma"
    @test iomap.kept == [3, 4]
    @test _contents(iomap.output) == ["beta gamma"]

    pat[] = nothing                 # empty search → keep everything
    @test iomap.kept == [1, 2, 3, 4, 5]

end # @testset

@testset "TextFiltering string source, case_insensitive and reactive invert" begin

    # String source compiles to a Regex; empty source keeps everything.
    iomap = print_document(TextFiltering("dolor"), _fixture())
    @test iomap.kept == [1, 2, 5]

    # case_insensitive adds the `i` flag.
    ci = Cell(false)
    iomap2 = print_document(TextFiltering(Cell("DOLOR"); case_insensitive=ci), _fixture())
    @test iomap2.kept == Int[]             # case-sensitive: no line matches "DOLOR"
    ci[] = true
    @test iomap2.kept == [1, 2, 5]         # now the dolor lines match

    # invert is now a reactive Cell.
    inv = Cell(false)
    iomap3 = print_document(TextFiltering(Cell("dolor"); invert=inv), _fixture())
    @test iomap3.kept == [1, 2, 5]
    inv[] = true
    @test iomap3.kept == [3, 4]            # keep the complement

end # @testset


@testset "TextFiltering keeps the matching lines of a block of lines" begin
    font = StyleFont("Ubuntu Mono", 20)
    lines = TextBlock(TextDocument[TextLine(TextString("lorem", font, color_default)),
                                   TextLine(TextString("dolor", font, color_default); indentation = 2),
                                   TextLine(TextString("dolor sit", font, color_default))])
    p = TextFiltering("dolor")
    iomap = print_document(p, lines)
    out = iomap.output
    # The kept lines are the same objects.
    @test length(out.elements) == 2
    @test out.elements[1] === lines.elements[2]
    @test out.elements[2] === lines.elements[3]
    # The first line is dropped, so a caret in the second line moves back by its
    # text and its break: "lorem" and a break are six offsets.
    @test map_reference_forward(p, iomap, make_flat_caret_reference(9)) == make_flat_caret_reference(3)
    @test map_reference_backward(p, iomap, make_flat_caret_reference(3)) == make_flat_caret_reference(9)
    # An edit of a kept line maps back to its input line.
    edit = ReplaceStringRangeOperation(TextModule._text_replace_path(Int[2, 1], 0, 1), "D")
    @test strip_reference_types(read_intent(p, iomap, edit).reference) ==
          TextModule._text_replace_path(Int[3, 1], 0, 1)
    # With no pattern every line stays.
    @test length(print_document(TextFiltering(), lines).output.elements) == 3
end

end # test_text_filtering
