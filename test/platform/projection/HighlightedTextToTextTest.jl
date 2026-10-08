# The editor that an operation is applied against: whatever holds the document.
mutable struct _HighlightEditor
    document::Any
end

function test_highlighted_text_to_text()

_font = StyleFont("Ubuntu Mono", 20)

# `elements[span].content[start:stop]` range path.
_range(span, start, stop) = ConcreteReference(FieldReferenceStep("elements"),
    ConcreteReference(RangeReferenceStep(span - 1, span),
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))))

_contents(text) = [e.content for e in text.elements if e isa TextString]

# The text stage: a highlight, and a plain block as it is.
_stage(; color = color_red) = RecursiveProjection(TypeDispatchingProjection(
    HighlightedText => HighlightedTextToText(color = color),
    TextBlock       => IdentityProjection()))

_highlighted(text; keywords...) =
    HighlightedText(text = TextBlock(TextString(text, _font, color_default)); keywords...)

_print(document) = (stage = _stage(); print_document(stage, stage, document, PrinterContext()))

@testset "HighlightedTextToText splits and fills matches" begin

    out = _print(_highlighted("alpha beta alpha"; pattern = "alpha")).output
    @test _contents(out) == ["alpha", " beta ", "alpha"]
    fills = [e.fill_color for e in out.elements if e isa TextString]
    @test fills[1] == color_red          # matched run filled
    @test fills[2] === nothing           # unmatched gap keeps original (no) fill
    @test fills[3] == color_red

end # @testset

@testset "HighlightedTextToText leaves a no-match span untouched" begin

    document = _highlighted("beta gamma"; pattern = "alpha")
    out = _print(document).output
    @test length(out.elements) == 1
    @test out.elements[1] === document.text.elements[1]   # same object, not a copy

end # @testset

@testset "HighlightedTextToText with an empty pattern is a pass-through" begin

    block = TextBlock(TextString("a", _font, color_default), TextNewline(font=_font),
                      TextString("b", _font, color_default))
    out = _print(HighlightedText(text = block)).output
    @test length(out.elements) == 3
    for i in 1:3
        @test out.elements[i] === block.elements[i]
    end

end # @testset

@testset "HighlightedTextToText selection round-trip through the step text" begin

    stage = _stage()
    iomap = print_document(stage, stage, _highlighted("alpha beta alpha"; pattern = "alpha"),
                           PrinterContext())
    out = iomap.output
    segs = iomap.segs
    @test length(segs) == 3
    for seg in segs
        for k in 0:seg.length
            out_ref = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, seg.out_index, k))
            in_ref = map_reference_backward(stage, iomap, out_ref)
            @test in_ref !== nothing
            @test get_reference_head(strip_reference_types(in_ref)) == FieldReferenceStep("text")
            @test map_reference_forward(stage, iomap, in_ref) !== nothing
        end
    end

end # @testset

@testset "HighlightedTextToText reader shifts char range by sub-span start" begin

    stage = _stage()
    iomap = print_document(stage, stage, _highlighted("alpha beta alpha"; pattern = "alpha"),
                           PrinterContext())
    # Output span 3 is the second "alpha", starting at input char 11.
    edit = read_intent(stage, iomap, ReplaceStringRangeOperation(_range(3, 0, 5), "X"))
    @test edit isa ReplaceStringRangeOperation
    @test strip_reference_types(edit.reference) ==
          ConcreteReference(FieldReferenceStep("text"), _range(1, 11, 16))
    @test edit.replacement == "X"

end # @testset

@testset "HighlightedTextToText skips zero-width matches" begin

    # `a*` yields empty matches between consonants; they must not produce
    # zero-length sub-spans, hang, or drop characters.
    iomap = _print(_highlighted("banana"; pattern = "a*", regex = true))
    @test all(s.length >= 1 for s in iomap.segs)
    @test join((e.content for e in iomap.output.elements if e isa TextString), "") == "banana"

end # @testset

@testset "HighlightedTextToText highlights again when a field of the document changes" begin

    document = _highlighted("alpha beta"; pattern = "alpha")
    out = _print(document).output
    @test _contents(out) == ["alpha", " beta"]

    document.pattern = "beta"
    @test _contents(out) == ["alpha ", "beta"]

    document.pattern = "ALPHA"
    @test _contents(out) == ["alpha beta"]      # case matters: no match
    document.case_insensitive = true
    @test _contents(out) == ["alpha", " beta"]

    document.pattern = "a.p"
    @test _contents(out) == ["alpha beta"]      # literal text: no match
    document.regex = true
    @test _contents(out) == ["alp", "ha beta"]  # "a", any one character, "p"

    document.pattern = "("
    @test _contents(out) == ["alpha beta"]      # does not compile: no highlight

    document.pattern = ""
    @test _contents(out) == ["alpha beta"]      # empty: no highlight

end # @testset

@testset "two highlighted texts in one document each follow their own fields" begin

    first_text = _highlighted("alpha beta"; pattern = "alpha")
    second_text = _highlighted("alpha beta"; pattern = "beta")
    stage = _stage()
    first_out = print_document(stage, stage, first_text, PrinterContext()).output
    second_out = print_document(stage, stage, second_text, PrinterContext()).output
    @test _contents(first_out) == ["alpha", " beta"]
    @test _contents(second_out) == ["alpha ", "beta"]
    first_text.pattern = "beta"
    @test _contents(first_out) == ["alpha ", "beta"]
    @test _contents(second_out) == ["alpha ", "beta"]

end # @testset

@testset "an edit of the highlighted text writes the text of the document" begin

    document = _highlighted("alpha beta alpha"; pattern = "alpha")
    stage = _stage()
    iomap = print_document(stage, stage, document, PrinterContext())
    edit = read_intent(stage, iomap, ReplaceStringRangeOperation(_range(3, 0, 5), "X"))
    evaluate_operation(_HighlightEditor(document), edit)
    @test _contents(document.text) == ["alpha beta X"]

end # @testset

@testset "HighlightedTextToText marks the matches of a block of lines" begin

    lines = TextBlock(TextDocument[TextLine(TextString("sit dolor", _font, color_red)),
                                   TextLine(TextString("amet", _font, color_red); indentation = 2)])
    stage = _stage(; color = color_green)
    iomap = print_document(stage, stage, HighlightedText(text = lines, pattern = "dolor"),
                           PrinterContext())
    out = iomap.output
    # The line with the match is split, and the other line is the same object.
    @test [span.content for span in out.elements[1].elements] == ["sit ", "dolor"]
    @test out.elements[1].elements[2].fill_color == color_green
    @test out.elements[2] === lines.elements[2]
    @test get_flat_string(out) == get_flat_string(lines)
    caret = make_flat_caret_reference(6)
    in_text = ConcreteReference(FieldReferenceStep("text"), caret)
    @test strip_reference_types(map_reference_forward(stage, iomap, in_text)) == caret
    # An edit of the match maps back to its span, at the offset of the match.
    edit = ReplaceStringRangeOperation(TextModule._text_replace_path(Int[1, 2], 0, 1), "D")
    @test strip_reference_types(read_intent(stage, iomap, edit).reference) ==
          ConcreteReference(FieldReferenceStep("text"), TextModule._text_replace_path(Int[1, 1], 4, 5))

end # @testset

end # test_highlighted_text_to_text
