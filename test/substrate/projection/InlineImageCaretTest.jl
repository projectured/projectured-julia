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

@testset "an offset beside an image is a place of the image" begin
    place(block, k) = TextModule.get_flat_cursor_coordinate(
        with_selection(block, TextModule.make_flat_caret_reference(k)))
    # A text run holds the offsets at its ends, so the image of "ab"[image]"cd"
    # has no place of its own: 2 is the end of "ab", 3 the start of "cd".
    middle = TextBlock(_run("ab"), _image(), _run("cd"))
    @test [place(middle, k) for k in 0:5] ==
          [(span = [1], char = 0), (span = [1], char = 1), (span = [1], char = 2),
           (span = [3], char = 0), (span = [3], char = 1), (span = [3], char = 2)]
    # With no run on one side, the offset on that side is the image's.
    @test place(TextBlock(_image(), _run("ab")), 0) == (span = [1], char = 0)
    @test place(TextBlock(_image(), _run("ab")), 1) == (span = [2], char = 0)
    @test place(TextBlock(_run("ab"), _image()), 3) == (span = [2], char = 1)
    # Between two images, the caret after the earlier one.
    @test [place(TextBlock(_image(), _image()), k) for k in 0:2] ==
          [(span = [1], char = 0), (span = [1], char = 1), (span = [2], char = 1)]
    # In a line, after its indentation.
    line = TextBlock(TextLine(_run("ab")), TextLine(_image(); indentation = 2))
    @test place(line, 5) == (span = [2, 1], char = 0)
    @test place(line, 6) == (span = [2, 1], char = 1)
    @test place(line, 4) === nothing
end

@testset "the caret beside an image is drawn at its edge" begin
    # Every character is 10 pixels wide and the image 24.
    measure = FixedMeasure(10, 12, 4, 0)
    rects(canvas, x0 = 0, out = Any[]) = begin
        for element in canvas.elements
            if element isa GraphicsCanvas
                rects(element, x0 + Int(element.x), out)
            elseif element isa GraphicsRect && Int(element.w) == 2
                push!(out, x0 + Int(element.x))
            end
        end
        out
    end
    caret_x(block, k) = rects(print_document(TextToGraphics(measure = measure),
        with_selection(block, TextModule.make_flat_caret_reference(k))).output)
    @test [caret_x(TextBlock(_run("ab"), _image(), _run("cd")), k) for k in 0:5] ==
          [[0], [10], [20], [44], [54], [64]]
    @test [caret_x(TextBlock(_image(), _run("ab")), k) for k in 0:3] == [[0], [24], [34], [44]]
    @test [caret_x(TextBlock(_run("ab"), _image()), k) for k in 0:3] == [[0], [10], [20], [44]]
    @test [caret_x(TextBlock(_image(), _image()), k) for k in 0:2] == [[0], [24], [48]]
end

end # @testset "Inline image caret"
end # test_inline_image_caret
