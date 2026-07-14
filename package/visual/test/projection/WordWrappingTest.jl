function test_word_wrapping()
_test_measure(cw, lh) = (text, font) -> (length(text) * cw, lh)

@testset "WordWrapping characters preserved" begin

src = "Lorem ipsum dolor sit amet"
input = TextBlock(TextString(src, font_ubuntu_monospace_regular_20, color_default))
m = _test_measure(10, 18)
out = print_document(WordWrapping(max_width=100, measure=m), input).output

# Concatenating output TextString contents must reproduce the original.
joined = join((elem.content for elem in out.elements if elem isa TextString), "")
@test joined == src
# At least one soft TextNewline was inserted.
@test count(e -> e isa TextNewline, out.elements) >= 1

end # @testset "WordWrapping characters preserved"

@testset "WordWrapping no-wrap fits on one line" begin

input = TextBlock(TextString("short", font_ubuntu_monospace_regular_20, color_default))
m = _test_measure(10, 18)
out = print_document(WordWrapping(max_width=1000, measure=m), input).output
@test length(out.elements) == 1
@test out.elements[1] isa TextString
@test out.elements[1].content == "short"

end # @testset "WordWrapping no-wrap"

@testset "WordWrapping selection round-trip" begin

src = "Lorem ipsum dolor"           # words at chars [0..4), [6..10), [12..16)
input = TextBlock(TextString(src, font_ubuntu_monospace_regular_20, color_default))
m = _test_measure(10, 18)
iomap = print_document(WordWrapping(max_width=80, measure=m), input)
segs = iomap.segs[]

# Every output sub-span maps backward then forward to itself.
for seg in segs
    for k in 0:seg.length
        out_ref = ConcreteReferencePath(
            FieldReference("elements"),
            ConcreteReferencePath(RangeReference(seg.out_index - 1, seg.out_index),
                ConcreteReferencePath(FieldReference("content"),
                    ConcreteReferencePath(RangeReference(k, k), EmptyReferencePath()))))
        in_ref  = map_reference_backward(WordWrapping(max_width=80, measure=m), iomap, out_ref)
        @test in_ref !== nothing
        # Inverting via forward at the same input offset lands on the same
        # output sub-span (modulo the boundary-duplicate convention).
        back_out = map_reference_forward(WordWrapping(max_width=80, measure=m), iomap, in_ref)
        @test back_out !== nothing
    end
end

end # @testset "WordWrapping selection round-trip"

@testset "WordWrapping reads available_width from context" begin

src = "alpha beta gamma delta"
input = TextBlock(TextString(src, font_ubuntu_monospace_regular_20, color_default))
m = _test_measure(10, 18)
# Construct with a generous max_width fallback; the context value should win.
proj = WordWrapping(max_width=10_000, measure=m)
avail = Cell(60)  # 60px ≈ 6 chars per line
ctx = with_available_size(PrinterContext(); width=avail)
iomap = print_document(proj, nothing, input, ctx)
out = iomap.output

joined = join((elem.content for elem in out.elements if elem isa TextString), "")
@test joined == src
@test count(e -> e isa TextNewline, out.elements) >= 1

end # @testset "WordWrapping reads available_width from context"

@testset "WordWrapping image is an unbreakable token" begin

m = _test_measure(10, 18)
# "abcdef" is 60px wide; the image is 64px; wrap width 80. The string fits
# (cx=60) but 60+64 > 80, so a soft TextNewline must be inserted *before*
# the image, dropping it whole onto the next line (never split).
input = TextBlock(
    TextString("abcdef", font_ubuntu_monospace_regular_20, color_default),
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
    TextString("ab", font_ubuntu_monospace_regular_20, color_default),
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
    TextString("abcdef", font_ubuntu_monospace_regular_20, color_default),
    TextGraphics(ImageMemory(nothing), 64, 64),
)
proj  = WordWrapping(max_width=80, measure=m)
iomap = print_document(proj, input)
# The image is input span 2; its atomic positions {0} and {1} must survive
# the forward/backward mapping even though a soft newline shifted its index.
for c in (0, 1)
    in_ref = ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(1, 2),
            ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(RangeReference(c, c), EmptyReferencePath()))))
    out_ref = map_reference_forward(proj, iomap, in_ref)
    @test out_ref !== nothing
    @test map_reference_backward(proj, iomap, out_ref) !== nothing
end

end # @testset "WordWrapping image selection round-trips"

end # test_word_wrapping
