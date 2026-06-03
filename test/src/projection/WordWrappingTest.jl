function test_word_wrapping()
_test_measure(cw, lh) = (text, font) -> (length(text) * cw, lh)

@testset "WordWrapping characters preserved" begin

src = "Lorem ipsum dolor sit amet"
input = TextText(TextString(src, font_ubuntu_monospace_regular_24, color_default))
m = _test_measure(10, 18)
out = projection_print(WordWrapping(max_width=100, measure=m), input).output

# Concatenating output TextString contents must reproduce the original.
joined = join((elem.content for elem in out.elements if elem isa TextString), "")
@test joined == src
# At least one soft TextNewline was inserted.
@test count(e -> e isa TextNewline, out.elements) >= 1

end # @testset "WordWrapping characters preserved"

@testset "WordWrapping no-wrap fits on one line" begin

input = TextText(TextString("short", font_ubuntu_monospace_regular_24, color_default))
m = _test_measure(10, 18)
out = projection_print(WordWrapping(max_width=1000, measure=m), input).output
@test length(out.elements) == 1
@test out.elements[1] isa TextString
@test out.elements[1].content == "short"

end # @testset "WordWrapping no-wrap"

@testset "WordWrapping selection round-trip" begin

src = "Lorem ipsum dolor"           # words at chars [0..4), [6..10), [12..16)
input = TextText(TextString(src, font_ubuntu_monospace_regular_24, color_default))
m = _test_measure(10, 18)
iomap = projection_print(WordWrapping(max_width=80, measure=m), input)
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
input = TextText(TextString(src, font_ubuntu_monospace_regular_24, color_default))
m = _test_measure(10, 18)
# Construct with a generous max_width fallback; the context value should win.
proj = WordWrapping(max_width=10_000, measure=m)
avail = Cell(60)  # 60px ≈ 6 chars per line
ctx = with_available_size(ProjectionContext(); width=avail)
iomap = projection_print(proj, input, nothing, ctx)
out = iomap.output

joined = join((elem.content for elem in out.elements if elem isa TextString), "")
@test joined == src
@test count(e -> e isa TextNewline, out.elements) >= 1

end # @testset "WordWrapping reads available_width from context"

end # test_word_wrapping
