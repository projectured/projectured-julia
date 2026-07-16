function test_text_filtering()

# Build the standard fixture: three logical lines, the first and third
# containing "dolor". Spans are 1-based input element indices:
#   1: "alpha dolor"   2: newline   3: "beta gamma"   4: newline   5: "delta dolor"
function _fixture()
    nl() = TextNewline(font=font_ubuntu_monospace_regular_20)
    TextBlock(
        TextString("alpha dolor", font_ubuntu_monospace_regular_20, color_default),
        nl(),
        TextString("beta gamma", font_ubuntu_monospace_regular_20, color_default),
        nl(),
        TextString("delta dolor", font_ubuntu_monospace_regular_20, color_default),
    )
end

# `elements[span].content{char}` cursor path (span/char are 1-based / 0-based).
# Canonical (typed) form: the projection emits the same self-describing
# `::TextBlock.elements[..].content::String{..}` checkpoints, so the round-trip
# assertions compare typed-against-typed.
_ref(span, char) = @reference ::TextBlock.elements::CellVector[span]::TextString.content::String{char}::Position

# `elements[span].content[start:stop]` range path.
_range(span, start, stop) = ConcreteReferencePath(FieldReference("elements"),
    ConcreteReferencePath(RangeReference(span - 1, span),
        ConcreteReferencePath(FieldReference("content"),
            ConcreteReferencePath(RangeReference(start, stop), EmptyReferencePath()))))

_contents(text) = [e.content for e in text.elements if e isa TextString]

@testset "TextFiltering keeps matching lines" begin

    iomap = print_document(TextFiltering(r"dolor"), _fixture())
    out = iomap.output
    @test _contents(out) == ["alpha dolor", "delta dolor"]
    @test iomap.kept[] == [1, 2, 5]           # both matching lines incl. line 1's newline
    @test count(e -> e isa TextNewline, out.elements) == 1

end # @testset

@testset "TextFiltering invert keeps the complement" begin

    iomap = print_document(TextFiltering(r"dolor", invert=true), _fixture())
    @test _contents(iomap.output) == ["beta gamma"]
    @test iomap.kept[] == [3, 4]

end # @testset

@testset "TextFiltering nothing pattern is pass-through" begin

    iomap = print_document(TextFiltering(), _fixture())
    @test length(iomap.output.elements) == 5
    @test iomap.kept[] == [1, 2, 3, 4, 5]
    @test _contents(iomap.output) == ["alpha dolor", "beta gamma", "delta dolor"]

end # @testset

@testset "TextFiltering selection round-trip" begin

    proj = TextFiltering(r"dolor")
    input = _fixture()
    iomap = print_document(proj, input)
    out = iomap.output
    # Flat caret at (span, char); the fixture carries newlines, so the flat offset
    # is not the raw char index.
    fin(span, char)  = TextModule._flat_caret_ref(text_elem_to_flat(input, span, char))
    fout(span, char) = TextModule._flat_caret_ref(text_elem_to_flat(out, span, char))

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

@testset "TextFiltering reader remaps element index" begin

    proj = TextFiltering(r"dolor")
    input = _fixture()
    iomap = print_document(proj, input)
    out = iomap.output

    # ReplaceSelectionOperation on output span 3 → input span 5, char preserved
    # (a flat caret; the reader remaps the flat offset across the dropped line).
    sel = read_intent(proj, iomap, ReplaceSelectionOperation(
        TextModule._flat_caret_ref(text_elem_to_flat(out, 3, 2))))
    @test sel isa ReplaceSelectionOperation
    @test sel.path == TextModule._flat_caret_ref(text_elem_to_flat(input, 5, 2))

    # ReplaceStringRangeOperation on output span 3 → input span 5, range preserved.
    edit = read_intent(proj, iomap, ReplaceStringRangeOperation(_range(3, 1, 4), "XYZ"))
    @test edit isa ReplaceStringRangeOperation
    @test edit.reference == _range(5, 1, 4)
    @test edit.replacement == "XYZ"

end # @testset

@testset "TextFiltering re-filters when the pattern cell changes" begin

    pat = Cell(r"dolor")
    iomap = print_document(TextFiltering(pat), _fixture())
    @test iomap.kept[] == [1, 2, 5]

    pat[] = r"gamma"
    @test iomap.kept[] == [3, 4]
    @test _contents(iomap.output) == ["beta gamma"]

    pat[] = nothing                 # empty search → keep everything
    @test iomap.kept[] == [1, 2, 3, 4, 5]

end # @testset

@testset "TextFiltering string source, case_insensitive and reactive invert" begin

    # String source compiles to a Regex; empty source keeps everything.
    iomap = print_document(TextFiltering("dolor"), _fixture())
    @test iomap.kept[] == [1, 2, 5]

    # case_insensitive adds the `i` flag.
    ci = Cell(false)
    iomap2 = print_document(TextFiltering(Cell("DOLOR"); case_insensitive=ci), _fixture())
    @test iomap2.kept[] == Int[]             # case-sensitive: no line matches "DOLOR"
    ci[] = true
    @test iomap2.kept[] == [1, 2, 5]         # now the dolor lines match

    # invert is now a reactive Cell.
    inv = Cell(false)
    iomap3 = print_document(TextFiltering(Cell("dolor"); invert=inv), _fixture())
    @test iomap3.kept[] == [1, 2, 5]
    inv[] = true
    @test iomap3.kept[] == [3, 4]            # keep the complement

end # @testset

end # test_text_filtering
