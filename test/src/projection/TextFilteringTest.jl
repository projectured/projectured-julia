function test_text_filtering()

# Build the standard fixture: three logical lines, the first and third
# containing "dolor". Spans are 1-based input element indices:
#   1: "alpha dolor"   2: newline   3: "beta gamma"   4: newline   5: "delta dolor"
function _fixture()
    nl() = TextNewline(font=font_ubuntu_monospace_regular_24)
    TextText(
        TextString("alpha dolor", font_ubuntu_monospace_regular_24, color_default),
        nl(),
        TextString("beta gamma", font_ubuntu_monospace_regular_24, color_default),
        nl(),
        TextString("delta dolor", font_ubuntu_monospace_regular_24, color_default),
    )
end

# `elements[span].content{char}` cursor path (span/char are 1-based / 0-based).
_ref(span, char) = ConcreteReferencePath(FieldReference("elements"),
    ConcreteReferencePath(RangeReference(span - 1, span),
        ConcreteReferencePath(FieldReference("content"),
            ConcreteReferencePath(RangeReference(char, char), EmptyReferencePath()))))

# `elements[span].content[start:stop]` range path.
_range(span, start, stop) = ConcreteReferencePath(FieldReference("elements"),
    ConcreteReferencePath(RangeReference(span - 1, span),
        ConcreteReferencePath(FieldReference("content"),
            ConcreteReferencePath(RangeReference(start, stop), EmptyReferencePath()))))

_contents(text) = [e.content for e in text.elements if e isa TextString]

@testset "TextFiltering keeps matching lines" begin

    iomap = projection_print(TextFiltering(r"dolor"), _fixture())
    out = iomap.output
    @test _contents(out) == ["alpha dolor", "delta dolor"]
    @test iomap.kept[] == [1, 2, 5]           # both matching lines incl. line 1's newline
    @test count(e -> e isa TextNewline, out.elements) == 1

end # @testset

@testset "TextFiltering invert keeps the complement" begin

    iomap = projection_print(TextFiltering(r"dolor", invert=true), _fixture())
    @test _contents(iomap.output) == ["beta gamma"]
    @test iomap.kept[] == [3, 4]

end # @testset

@testset "TextFiltering nothing pattern is pass-through" begin

    iomap = projection_print(TextFiltering(), _fixture())
    @test length(iomap.output.elements) == 5
    @test iomap.kept[] == [1, 2, 3, 4, 5]
    @test _contents(iomap.output) == ["alpha dolor", "beta gamma", "delta dolor"]

end # @testset

@testset "TextFiltering selection round-trip" begin

    proj = TextFiltering(r"dolor")
    iomap = projection_print(proj, _fixture())

    # Kept line 1 (output span 1) and line 3 (output span 3) round-trip.
    for (in_span, out_span, char) in ((1, 1, 3), (5, 3, 2))
        fwd = map_reference_forward(proj, iomap, _ref(in_span, char))
        @test fwd == _ref(out_span, char)
        @test map_reference_backward(proj, iomap, fwd) == _ref(in_span, char)
    end

    # A cursor on the filtered-out middle line has no image in the output.
    @test map_reference_forward(proj, iomap, _ref(3, 2)) === nothing

end # @testset

@testset "TextFiltering reader remaps element index" begin

    proj = TextFiltering(r"dolor")
    iomap = projection_print(proj, _fixture())

    # ReplaceSelectionOperation on output span 3 → input span 5, char preserved.
    sel = projection_read(proj, iomap, ReplaceSelectionOperation(_ref(3, 2)))
    @test sel isa ReplaceSelectionOperation
    @test sel.path == _ref(5, 2)

    # StringReplaceRangeOperation on output span 3 → input span 5, range preserved.
    edit = projection_read(proj, iomap, StringReplaceRangeOperation(_range(3, 1, 4), "XYZ"))
    @test edit isa StringReplaceRangeOperation
    @test edit.reference == _range(5, 1, 4)
    @test edit.replacement == "XYZ"

end # @testset

@testset "TextFiltering re-filters when the pattern cell changes" begin

    pat = Cell(r"dolor")
    iomap = projection_print(TextFiltering(pat), _fixture())
    @test iomap.kept[] == [1, 2, 5]

    pat[] = r"gamma"
    @test iomap.kept[] == [3, 4]
    @test _contents(iomap.output) == ["beta gamma"]

    pat[] = nothing                 # empty search → keep everything
    @test iomap.kept[] == [1, 2, 3, 4, 5]

end # @testset

end # test_text_filtering
