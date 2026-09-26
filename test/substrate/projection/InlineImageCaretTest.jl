# An inline image (`TextGraphics`) is one position of the flat caret space: the
# caret before it and the caret after it are different offsets, and every reader
# of the space agrees on it.

_image() = TextGraphics(ImageMemory(nothing), 24, 24)
_run(text) = TextString(text, font_ubuntu_monospace_regular_20, color_default)
const _splice_value! = ProjecturedKernel.OperationModule.splice_value!

function test_inline_image_caret()
@testset "Inline image caret" begin

@testset "the caret space counts an image as one position" begin
    # [image] "ab" [image] "cd" [image]
    block = TextBlock(_image(), _run("ab"), _image(), _run("cd"), _image())
    @test get_flat_length(block.elements[1]) == 1
    @test get_flat_offsets(block) == [0, 1, 3, 4, 6]
    @test TextModule._text_flat_total(block) == 7
    @test TextModule._flat_chars(block) == ['\uFFFC', 'a', 'b', '\uFFFC', 'c', 'd', '\uFFFC']
    @test get_flat_string(block) == "\uFFFCab\uFFFCcd\uFFFC"
    @test length(get_flat_string(block)) == TextModule._text_flat_total(block)
    @test get_flat_base(block, Int[2]) == 1
    @test get_flat_base(block, Int[4]) == 4

    # Inside a `TextLine`, after its break and its indentation.
    lines = TextBlock(TextLine(_run("ab")),
                      TextLine(_run("cd"), _image(), _run("ef"); indentation = 2))
    @test get_flat_length(lines.elements[2]) == 2 + 2 + 1 + 2
    @test get_flat_offsets(lines) == [0, 3]
    @test get_flat_base(lines, Int[2, 3]) == 3 + 2 + 2 + 1
    @test get_flat_string(lines) == "ab\n  cd\uFFFCef"
end

@testset "splice_value! of a TextBlock writes in the caret space" begin
    # The offsets after an image are one more than the characters of the runs
    # before it.
    block = TextBlock(_run("ab"), _image(), _run("cd"))
    _splice_value!(nothing, :content, block, 3, 3, "X")
    @test block.elements[3].content == "Xcd"
    _splice_value!(nothing, :content, block, 2, 2, "Y")
    @test block.elements[1].content == "abY"
    # A range over the image straddles two spans and changes nothing.
    _splice_value!(nothing, :content, block, 2, 4, "")
    @test get_flat_string(block) == "abY\uFFFCXcd"
end

end # @testset "Inline image caret"
end # test_inline_image_caret
