# The editor that an operation is applied against: whatever holds the document.
mutable struct _FilterEditor
    document::Any
end

function test_filtered_text_to_text()

# Build the standard fixture: three logical lines, the first and third
# containing "dolor". Spans are 1-based element indices of the block:
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

# `elements[span].content[start:stop]` range path.
_range(span, start, stop) = ConcreteReference(FieldReferenceStep("elements"),
    ConcreteReference(RangeReferenceStep(span - 1, span),
        ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))))

_text(reference) = ConcreteReference(FieldReferenceStep("text"), reference)

_contents(text) = [e.content for e in text.elements if e isa TextString]

# The text stage: a filter, a highlight, and a plain block as it is.
_stage() = RecursiveProjection(TypeDispatchingProjection(
    FilteredText    => FilteredTextToText(),
    HighlightedText => HighlightedTextToText(color = color_red),
    TextBlock       => IdentityProjection()))

_print(document) = (stage = _stage(); print_document(stage, stage, document, PrinterContext()))

@testset "FilteredTextToText keeps matching lines" begin
    iomap = _print(FilteredText(text = _fixture(), pattern = "dolor"))
    out = iomap.output
    @test _contents(out) == ["alpha dolor", "delta dolor"]
    @test iomap.kept == [1, 2, 5]           # both matching lines incl. line 1's newline
    @test count(e -> e isa TextNewline, out.elements) == 1
end # @testset

@testset "FilteredTextToText invert keeps the complement" begin
    iomap = _print(FilteredText(text = _fixture(), pattern = "dolor", invert = true))
    @test _contents(iomap.output) == ["beta gamma"]
    @test iomap.kept == [3, 4]
end # @testset

@testset "FilteredTextToText with an empty pattern is a pass-through" begin
    iomap = _print(FilteredText(text = _fixture()))
    @test length(iomap.output.elements) == 5
    @test iomap.kept == [1, 2, 3, 4, 5]
    @test _contents(iomap.output) == ["alpha dolor", "beta gamma", "delta dolor"]
end # @testset

@testset "FilteredTextToText selection round-trip through the step text" begin
    stage = _stage()
    block = _fixture()
    iomap = print_document(stage, stage, FilteredText(text = block, pattern = "dolor"),
                           PrinterContext())
    out = iomap.output
    # Flat caret at (span, char); the fixture carries newlines, so the flat offset
    # is not the raw char index.
    fin(span, char)  = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(block, span, char))
    fout(span, char) = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, span, char))
    # Kept line 1 (output span 1) and line 3 (output span 3) round-trip; dropping
    # the middle line shifts line 3's flat offset back by its length.
    for (in_span, out_span, char) in ((1, 1, 3), (5, 3, 2))
        fwd = map_reference_forward(stage, iomap, _text(fin(in_span, char)))
        @test strip_reference_types(fwd) == strip_reference_types(fout(out_span, char))
        @test strip_reference_types(map_reference_backward(stage, iomap, fwd)) ==
              strip_reference_types(_text(fin(in_span, char)))
    end
    # A cursor on the filtered-out middle line has no image in the output.
    @test map_reference_forward(stage, iomap, _text(fin(3, 2))) === nothing
end # @testset

@testset "FilteredTextToText maps a whole-element box past a dropped line" begin
    box(s, e) = ConcreteReference(TextSpanReferenceStep(s, e), EmptyReference())
    stage = _stage()
    document = FilteredText(text = _fixture(), pattern = "dolor")
    iomap = print_document(stage, stage, document, PrinterContext())
    # "delta dolor" is 23:34 in the block and 12:23 in the output, because the
    # dropped line "beta gamma" ⏎ is 11 characters long.
    @test map_reference_forward(stage, iomap, _text(box(23, 34))) == box(12, 23)
    @test strip_reference_types(map_reference_backward(stage, iomap, box(12, 23))) == _text(box(23, 34))
    # A box on a kept line before the dropped one does not move.
    @test map_reference_forward(stage, iomap, _text(box(6, 11))) == box(6, 11)
    # A box on the dropped line has no image.
    @test map_reference_forward(stage, iomap, _text(box(12, 22))) === nothing
    # A box over all three lines keeps the part that is shown.
    @test map_reference_forward(stage, iomap, _text(box(0, 34))) == box(0, 23)
    # The output selection is the mapped box.
    set_selection!(document, _text(box(23, 34)))
    @test strip_reference_types(iomap.output.selection) == box(12, 23)
end # @testset

@testset "FilteredTextToText reader remaps element index" begin
    stage = _stage()
    block = _fixture()
    iomap = print_document(stage, stage, FilteredText(text = block, pattern = "dolor"),
                           PrinterContext())
    out = iomap.output
    # ReplaceSelectionOperation on output span 3 → span 5 of the block, char
    # preserved, under the step `text`.
    sel = read_intent(stage, iomap, ReplaceSelectionOperation(
        TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, 3, 2))))
    @test sel isa ReplaceSelectionOperation
    @test strip_reference_types(sel.path) ==
          _text(TextModule.make_flat_caret_reference(convert_element_to_flat_offset(block, 5, 2)))
    # ReplaceStringRangeOperation on output span 3 → span 5, range preserved.
    edit = read_intent(stage, iomap, ReplaceStringRangeOperation(_range(3, 1, 4), "XYZ"))
    @test edit isa ReplaceStringRangeOperation
    @test strip_reference_types(edit.reference) == _text(_range(5, 1, 4))
    @test edit.replacement == "XYZ"
end # @testset

@testset "FilteredTextToText filters again when a field of the document changes" begin
    document = FilteredText(text = _fixture(), pattern = "dolor")
    iomap = _print(document)
    @test iomap.kept == [1, 2, 5]
    document.pattern = "gamma"
    @test iomap.kept == [3, 4]
    @test _contents(iomap.output) == ["beta gamma"]
    document.pattern = "GAMMA"
    @test iomap.kept == Int[]              # case matters: no line matches
    document.case_insensitive = true
    @test iomap.kept == [3, 4]
    document.invert = true
    @test iomap.kept == [1, 2, 5]          # keep the complement
    document.invert = false
    document.pattern = "^delta"
    @test iomap.kept == Int[]              # literal text: no line holds "^delta"
    document.regex = true
    @test iomap.kept == [5]                # the last line starts with "delta"
    document.pattern = "delta("
    @test iomap.kept == [1, 2, 3, 4, 5]    # does not compile: keep every line
end # @testset

@testset "a filter around a highlight keeps the highlighted lines" begin
    stage = _stage()
    block = _fixture()
    highlighted = HighlightedText(text = block, pattern = "dolor")
    document = FilteredText(text = highlighted, pattern = "delta")
    iomap = print_document(stage, stage, document, PrinterContext())
    @test _contents(iomap.output) == ["delta ", "dolor"]
    fills = [e.fill_color for e in iomap.output.elements if e isa TextString]
    @test fills == [nothing, color_red]
    # A caret in the output maps back through both wrappers.
    caret = TextModule.make_flat_caret_reference(8)
    back = strip_reference_types(map_reference_backward(stage, iomap, caret))
    @test back == _text(_text(TextModule.make_flat_caret_reference(
                     convert_element_to_flat_offset(block, 5, 8))))
    # An edit in the highlighted part writes the block.
    edit = read_intent(stage, iomap, ReplaceStringRangeOperation(_range(2, 0, 5), "X"))
    evaluate_operation(_FilterEditor(document), edit)
    @test _contents(block) == ["alpha dolor", "beta gamma", "delta X"]
end # @testset

@testset "FilteredTextToText keeps the matching lines of a block of lines" begin

    font = StyleFont("Ubuntu Mono", 20)
    lines = TextBlock(TextDocument[TextLine(TextString("lorem", font, color_default)),
                                   TextLine(TextString("dolor", font, color_default); indentation = 2),
                                   TextLine(TextString("dolor sit", font, color_default))])
    stage = _stage()
    iomap = print_document(stage, stage, FilteredText(text = lines, pattern = "dolor"), PrinterContext())
    out = iomap.output
    # The kept lines are the same objects.
    @test length(out.elements) == 2
    @test out.elements[1] === lines.elements[2]
    @test out.elements[2] === lines.elements[3]
    # The first line is dropped, so a caret in the second line moves back by its
    # text and its break: "lorem" and a break are six offsets.
    @test strip_reference_types(map_reference_forward(stage, iomap, _text(make_flat_caret_reference(9)))) ==
          make_flat_caret_reference(3)
    @test strip_reference_types(map_reference_backward(stage, iomap, make_flat_caret_reference(3))) ==
          _text(make_flat_caret_reference(9))
    # An edit of a kept line maps back to its input line.
    edit = ReplaceStringRangeOperation(TextModule._text_replace_path(Int[2, 1], 0, 1), "D")
    @test strip_reference_types(read_intent(stage, iomap, edit).reference) ==
          _text(TextModule._text_replace_path(Int[3, 1], 0, 1))
    # With no pattern every line stays.
    @test length(print_document(stage, stage, FilteredText(text = lines), PrinterContext()).output.elements) == 3

end # @testset

end # test_filtered_text_to_text
