function test_text_highlighting()

_font = font_ubuntu_monospace_regular_20

# `elements[span].content{char}` cursor path (span 1-based, char 0-based).
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

@testset "TextHighlighting splits and fills matches" begin

    input = TextBlock(TextString("alpha beta alpha", _font, color_default))
    out = print_document(TextHighlighting(r"alpha", color=color_red), input).output
    @test _contents(out) == ["alpha", " beta ", "alpha"]
    fills = [e.fill_color for e in out.elements if e isa TextString]
    @test fills[1] == color_red          # matched run filled
    @test fills[2] === nothing           # unmatched gap keeps original (no) fill
    @test fills[3] == color_red

end # @testset

@testset "TextHighlighting leaves a no-match span untouched" begin

    input = TextBlock(TextString("beta gamma", _font, color_default))
    out = print_document(TextHighlighting(r"alpha", color=color_red), input).output
    @test length(out.elements) == 1
    @test out.elements[1] === input.elements[1]   # same object, not a copy

end # @testset

@testset "TextHighlighting nothing pattern is pass-through" begin

    input = TextBlock(
        TextString("a", _font, color_default),
        TextNewline(font=_font),
        TextString("b", _font, color_default),
    )
    out = print_document(TextHighlighting(), input).output
    @test length(out.elements) == 3
    for i in 1:3
        @test out.elements[i] === input.elements[i]
    end

end # @testset

@testset "TextHighlighting selection round-trip" begin

    proj = TextHighlighting(r"alpha", color=color_red)
    iomap = print_document(proj, TextBlock(TextString("alpha beta alpha", _font, color_default)))
    segs = iomap.segs[]
    @test length(segs) == 3
    for seg in segs
        for k in 0:seg.length
            out_ref = _ref(seg.out_index, k)
            in_ref = map_reference_backward(proj, iomap, out_ref)
            @test in_ref !== nothing
            @test map_reference_forward(proj, iomap, in_ref) !== nothing
        end
    end

end # @testset

@testset "TextHighlighting reader shifts char range by sub-span start" begin

    proj = TextHighlighting(r"alpha", color=color_red)
    iomap = print_document(proj, TextBlock(TextString("alpha beta alpha", _font, color_default)))
    # Output span 3 is the second "alpha", starting at input char 11.
    edit = read_intent(proj, iomap, ReplaceStringRangeOperation(_range(3, 0, 5), "X"))
    @test edit isa ReplaceStringRangeOperation
    @test edit.reference == _range(1, 11, 16)
    @test edit.replacement == "X"

end # @testset

@testset "TextHighlighting skips zero-width matches" begin

    # `r"a*"` yields empty matches between consonants; they must not produce
    # zero-length sub-spans, hang, or drop characters.
    out = print_document(TextHighlighting(r"a*", color=color_red),
                           TextBlock(TextString("banana", _font, color_default))).output
    iomap_segs = print_document(TextHighlighting(r"a*", color=color_red),
                                  TextBlock(TextString("banana", _font, color_default))).segs[]
    @test all(s.length >= 1 for s in iomap_segs)
    @test join((e.content for e in out.elements if e isa TextString), "") == "banana"

end # @testset

@testset "TextHighlighting re-highlights when the pattern cell changes" begin

    pat = Cell(r"alpha")
    out = print_document(TextHighlighting(pat, color=color_red),
                           TextBlock(TextString("alpha beta", _font, color_default))).output
    @test _contents(out) == ["alpha", " beta"]

    pat[] = r"beta"
    @test _contents(out) == ["alpha ", "beta"]

    pat[] = nothing
    @test _contents(out) == ["alpha beta"]   # unsplit, single span

end # @testset

@testset "TextHighlighting string source + case_insensitive flag" begin

    # A plain String source is compiled to a Regex; empty source = no highlights.
    out = print_document(TextHighlighting("alpha", color=color_red),
                           TextBlock(TextString("alpha beta", _font, color_default))).output
    @test _contents(out) == ["alpha", " beta"]

    # case_insensitive adds the `i` flag when the source String is compiled.
    ci = Cell(false)
    src = Cell("ALPHA")
    out2 = print_document(TextHighlighting(src; case_insensitive=ci, color=color_red),
                            TextBlock(TextString("alpha beta", _font, color_default))).output
    @test _contents(out2) == ["alpha beta"]    # case-sensitive: no match
    ci[] = true
    @test _contents(out2) == ["alpha", " beta"] # now matches

    # Empty source string is a pass-through.
    src[] = ""
    @test _contents(out2) == ["alpha beta"]

end # @testset

end # test_text_highlighting
