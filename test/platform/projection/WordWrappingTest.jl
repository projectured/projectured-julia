function test_word_wrapping()
_test_measure(cw, lh) = FixedMeasure(cw, lh - lh÷4, lh÷4, 0)

@testset "WordWrapping characters preserved" begin

src = "Lorem ipsum dolor sit amet"
input = TextBlock(TextString(src, StyleFont("Ubuntu Mono", 20), color_default))
m = _test_measure(10, 18)
out = print_document(WordWrapping(max_width=100, measure=m), input).output

# Concatenating output TextString contents must reproduce the original.
joined = join((elem.content for elem in out.elements if elem isa TextString), "")
@test joined == src
# At least one soft TextNewline was inserted.
@test count(e -> e isa TextNewline, out.elements) >= 1

end # @testset "WordWrapping characters preserved"

@testset "WordWrapping no-wrap fits on one line" begin

input = TextBlock(TextString("short", StyleFont("Ubuntu Mono", 20), color_default))
m = _test_measure(10, 18)
out = print_document(WordWrapping(max_width=1000, measure=m), input).output
@test length(out.elements) == 1
@test out.elements[1] isa TextString
@test out.elements[1].content == "short"

end # @testset "WordWrapping no-wrap"

@testset "WordWrapping selection round-trip" begin

src = "Lorem ipsum dolor"           # words at chars [0..4), [6..10), [12..16)
input = TextBlock(TextString(src, StyleFont("Ubuntu Mono", 20), color_default))
m = _test_measure(10, 18)
proj = WordWrapping(max_width=80, measure=m)
iomap = print_document(proj, input)
out = iomap.output
segs = iomap.segs

# Every output sub-span offset maps backward then forward to itself, in the flat
# break-aware coordinate (a flat `TextRangeReferenceStep` caret, not the structural path).
for seg in segs
    for k in 0:seg.length
        out_ref = TextModule.make_flat_caret_reference(convert_element_to_flat_offset(out, seg.out_index, k))
        in_ref  = map_reference_backward(proj, iomap, out_ref)
        @test in_ref !== nothing
        # Inverting via forward at the same input offset lands on a valid output
        # caret (modulo the boundary-duplicate convention).
        back_out = map_reference_forward(proj, iomap, in_ref)
        @test back_out !== nothing
    end
end

end # @testset "WordWrapping selection round-trip"

@testset "WordWrapping maps a range across a soft break" begin

src = "Lorem ipsum dolor"
input = TextBlock(TextString(src, StyleFont("Ubuntu Mono", 20), color_default))
proj = WordWrapping(max_width=80, measure=_test_measure(10, 18))
iomap = print_document(proj, input)
@test count(e -> e isa TextNewline, iomap.output.elements) >= 1

# "psum do" crosses the break after "ipsum ": the output range starts on one line
# and stops on the next, and maps back to the one input range it came from.
out_range = map_reference_forward(proj, iomap, TextModule.make_flat_range_reference(7, 14))
@test out_range.head isa TextRangeReferenceStep
@test out_range.head.start < out_range.head.stop
in_range = map_reference_backward(proj, iomap, out_range)
@test (in_range.head.start, in_range.head.stop) == (7, 14)

# A caret still maps to a caret.
caret = map_reference_backward(proj, iomap, TextModule.make_flat_caret_reference(2))
@test caret.head.start == caret.head.stop == 2

end # @testset "WordWrapping maps a range across a soft break"

@testset "WordWrapping maps a whole-element box past a soft break" begin

# "Lorem " ⏎ "ipsum " ⏎ "dolor": each soft break adds one flat offset.
box(s, e) = ConcreteReference(TextSpanReferenceStep(s, e), EmptyReference())
font = StyleFont("Ubuntu Mono", 20)
input = TextBlock(TextString("Lorem ipsum dolor", font, color_default))
proj = WordWrapping(max_width=80, measure=_test_measure(10, 18))
iomap = print_document(proj, input)
@test count(e -> e isa TextNewline, iomap.output.elements) == 2

# "dolor" is 12:17 in the input and 14:19 in the output, after two breaks.
@test map_reference_forward(proj, iomap, box(12, 17)) == box(14, 19)
@test map_reference_backward(proj, iomap, box(14, 19)) == box(12, 17)
# A box before the first break does not move.
@test map_reference_forward(proj, iomap, box(0, 5)) == box(0, 5)
# A box over "ipsum dolor" starts after the first break and ends after the second.
@test map_reference_forward(proj, iomap, box(6, 17)) == box(7, 19)
# A box that ends at a soft break stays on its line.
@test map_reference_forward(proj, iomap, box(0, 6)) == box(0, 6)
# The output selection is the mapped box.
set_selection!(input, box(12, 17))
@test strip_reference_types(iomap.output.selection) == box(14, 19)

# A box that starts at a hard break keeps it: "ab" ⏎ "cd ef", a wrap in "cd ef".
nl = TextNewline(font = font)
input2 = TextBlock(TextString("ab", font, color_default), nl, TextString("cd ef", font, color_default))
proj2 = WordWrapping(max_width=40, measure=_test_measure(10, 18))
iomap2 = print_document(proj2, input2)
@test count(e -> e isa TextNewline, iomap2.output.elements) == 2
@test map_reference_forward(proj2, iomap2, box(2, 8)) == box(2, 9)
@test map_reference_backward(proj2, iomap2, box(2, 9)) == box(2, 8)

end # @testset "WordWrapping maps a whole-element box past a soft break"

@testset "WordWrapping reads the maximum width from the context" begin

src = "alpha beta gamma delta"
input = TextBlock(TextString(src, StyleFont("Ubuntu Mono", 20), color_default))
m = _test_measure(10, 18)
# Construct with a generous max_width fallback; the context value should win.
proj = WordWrapping(max_width=10_000, measure=m)
avail = Cell(60)  # 60px ≈ 6 chars per line
ctx = with_exact_size(PrinterContext(); width=avail)
iomap = print_document(proj, nothing, input, ctx)
out = iomap.output

joined = join((elem.content for elem in out.elements if elem isa TextString), "")
@test joined == src
@test count(e -> e isa TextNewline, out.elements) >= 1

end # @testset "WordWrapping reads the maximum width from the context"

@testset "WordWrapping image is an unbreakable token" begin

m = _test_measure(10, 18)
# "abcdef" is 60px wide; the image is 64px; wrap width 80. The string fits
# (cx=60) but 60+64 > 80, so a soft TextNewline must be inserted *before*
# the image, dropping it whole onto the next line (never split).
input = TextBlock(
    TextString("abcdef", StyleFont("Ubuntu Mono", 20), color_default),
    TextGraphics(ImageMemory(nothing), 64, 64),
)
out = print_document(WordWrapping(max_width=80, measure=m), input).output
els = [out.elements[i] for i in 1:length(out.elements)]

@test count(e -> e isa TextNewline, els) == 1
nl_idx  = findfirst(e -> e isa TextNewline, els)
img_idx = findfirst(e -> e isa TextGraphics, els)
@test nl_idx !== nothing && img_idx !== nothing
@test nl_idx < img_idx                 # newline precedes the image
@test els[img_idx].width == 64         # image passed through unchanged

end # @testset "WordWrapping image unbreakable"

@testset "WordWrapping image that fits stays on the line" begin

m = _test_measure(10, 18)
# Short string (20px) + 40px image under a generous wrap width: no newline.
input = TextBlock(
    TextString("ab", StyleFont("Ubuntu Mono", 20), color_default),
    TextGraphics(ImageMemory(nothing), 40, 40),
)
out = print_document(WordWrapping(max_width=1000, measure=m), input).output
els = [out.elements[i] for i in 1:length(out.elements)]
@test count(e -> e isa TextNewline, els) == 0
@test any(e -> e isa TextGraphics, els)

end # @testset "WordWrapping image fits"

@testset "WordWrapping image selection round-trips" begin

m = _test_measure(10, 18)
input = TextBlock(
    TextString("abcdef", StyleFont("Ubuntu Mono", 20), color_default),
    TextGraphics(ImageMemory(nothing), 64, 64),
)
proj  = WordWrapping(max_width=80, measure=m)
iomap = print_document(proj, input)
# The image is input span 2; a soft newline drops it onto the next line, shifting
# its output index. The caret before the image (flat 6) is the end of "abcdef", on
# the first line. The caret after it (flat 7) is past the soft newline in the
# output (flat 8). Both map back to where they started.
caret(k) = TextModule.make_flat_caret_reference(k)
@test convert_element_to_flat_offset(input, 2, 0) == 6
for (input_offset, output_offset) in ((6, 6), (7, 8))
    out_ref = map_reference_forward(proj, iomap, caret(input_offset))
    @test is_reference_equal(out_ref, caret(output_offset))
    @test is_reference_equal(map_reference_backward(proj, iomap, out_ref), caret(input_offset))
end

end # @testset "WordWrapping image selection round-trips"

@testset "WordWrapping keeps an empty span, and the caret in it" begin

input = TextBlock(TextString("", StyleFont("Ubuntu Mono", 20), color_default))
set_selection!(input, TextModule.make_flat_caret_reference(0))
m = _test_measure(10, 18)
proj = WordWrapping(max_width=80, measure=m)
iomap = print_document(proj, input)
@test [e.content for e in iomap.output.elements] == [""]
caret = TextModule.make_flat_caret_reference(0)
@test map_reference_forward(proj, iomap, input.selection) == caret
@test map_reference_backward(proj, iomap, caret) == caret

end # @testset "WordWrapping keeps an empty span"

@testset "WordWrapping wraps a block of lines by its soft breaks" begin

font = StyleFont("Ubuntu Mono", 20)
m = _test_measure(10, 18)
long = TextString("alpha beta gamma delta", font, color_default)
short = TextString("x", font, color_default)
input = TextBlock(TextDocument[TextLine(long; indentation = 2), TextLine(short)])
avail = Cell(100)
proj = WordWrapping(measure = m)
iomap = print_document(proj, nothing, input, with_exact_size(PrinterContext(); width = avail))
out = iomap.output

# Each line keeps its spans and its indentation; only the soft breaks are new.
@test length(out.elements) == 2
@test out.elements[1].elements[1] === long
@test out.elements[1].indentation == 2
# 100 pixels less an indentation of 20 is 8 characters on a row, and the space
# at a wrap stays at the end of the upper row.
@test out.elements[1].soft_breaks == [6, 11, 17]
@test out.elements[2].soft_breaks == Int[]

# A soft break is no character, so every offset and every caret stays.
@test get_flat_string(out) == get_flat_string(input)
caret = make_flat_caret_reference(8)
@test map_reference_forward(proj, iomap, caret) == caret
@test map_reference_backward(proj, iomap, caret) == caret

# A keystroke changes the soft breaks of its line, and neither the list of lines
# nor the soft breaks of another line.
@test out.elements[2].soft_breaks == Int[]
getfield(long, :content)[] = "alpha beta gamma"
@test is_cell_up_to_date(getfield(out.elements, :elements))
@test !is_cell_up_to_date(getfield(out.elements[1], :soft_breaks))
@test is_cell_up_to_date(getfield(out.elements[2], :soft_breaks))
@test out.elements[1].soft_breaks == [6, 11]

# A resize changes the soft breaks, and not the list of lines.
avail[] = 1000
@test is_cell_up_to_date(getfield(out.elements, :elements))
@test out.elements[1].soft_breaks == Int[]

end # @testset "WordWrapping wraps a block of lines by its soft breaks"

end # test_word_wrapping
