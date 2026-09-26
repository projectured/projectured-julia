# An inline image (`TextGraphics`) is one position of the flat caret space: the
# caret before it and the caret after it are different offsets, and every reader
# of the space agrees on it.

_image() = TextGraphics(ImageMemory(nothing), 24, 24)
_run(text) = TextString(text, font_ubuntu_monospace_regular_20, color_default)
const _splice_value! = ProjecturedKernel.OperationModule.splice_value!

# The editor an operation is applied against: the document, and no view.
mutable struct _InlineImageEditor
    document::Any
end

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

@testset "the keys step over an image as over one character" begin
    measure = FixedMeasure(10, 12, 4, 0)
    projection = TextToGraphics(measure = measure)
    key(k; mods...) = KeyDown(k, ModifierKeys(; mods...); time = 0.0)
    offset(op) = (r = strip_reference_types(op.path); (r.head::TextRangeReferenceStep).start)
    # The flat offset after `event` from caret `k`, through the reader of
    # `TextToGraphics`, which lays the block out for the geometric keys.
    function after(block, k, event)
        clear_selection!(block)
        set_selection!(block, TextModule.make_flat_caret_reference(k))
        op = read_intent(projection, print_document(projection, block), event)
        op isa ReplaceSelectionOperation ? offset(op) : nothing
    end

    # Right from 0 visits every caret once, and Left walks back.
    block = TextBlock(_image(), _run("ab"), _image(), _image(), _run("cd"), _image())
    total = TextModule._text_flat_total(block)
    @test total == 8
    @test [after(block, k, key(:right)) for k in 0:total] == [1:total; total]
    @test [after(block, k, key(:left)) for k in 0:total] == [0; 0:total-1]
    @test after(block, 3, key(:home; ctrl = true)) == 0
    @test after(block, 3, key(:end; ctrl = true)) == total

    # Ctrl+arrow: an image is a word of its own.
    close = TextBlock(_run("ab"), _image(), _run("cd"))
    @test [after(close, k, key(:right; ctrl = true)) for k in (0, 2, 3)] == [2, 3, 5]
    @test [after(close, k, key(:left; ctrl = true)) for k in (5, 3, 2)] == [3, 2, 0]
    spaced = TextBlock(_run("ab "), _image(), _run(" cd"))
    @test [after(spaced, k, key(:right; ctrl = true)) for k in (0, 3, 5)] == [3, 5, 7]
    @test [after(spaced, k, key(:left; ctrl = true)) for k in (7, 5, 3)] == [5, 3, 0]

    # Home and End land before the first image and after the last one of a line.
    ends = TextBlock(_image(), _run("ab"), _image())
    @test after(ends, 2, key(:home)) == 0
    @test after(ends, 2, key(:end)) == 4
    # A line of images only has carets too.
    images = TextBlock(_image(), _image())
    @test after(images, 0, key(:end)) == 2
    @test after(images, 2, key(:home)) == 0

    # Up and Down keep the x of the caret; each half of an image is one side.
    # Line 1: [image] 0..24, "ab" 24..44. Line 2: "cd" 0..20, [image] 20..44.
    lines = TextBlock(_image(), _run("ab"), TextNewline(font = font_ubuntu_monospace_regular_20),
                      _run("cd"), _image())
    @test after(lines, 3, key(:down)) == 7      # x 44: after the image
    @test after(lines, 7, key(:up)) == 3        # x 44: the end of "ab"
    @test after(lines, 0, key(:down)) == 4      # x 0: the start of "cd"
    @test after(lines, 4, key(:up)) == 0        # x 0: before the image

    # A click on the left half of an image is before it, on the right half after it.
    click(block, x) = (op = read_intent(projection, print_document(projection, block),
                                        MousePress(:left, x, 5; time = 0.0));
                       op isa ReplaceSelectionOperation ? offset(op) : nothing)
    @test click(images, 5) == 0
    @test click(images, 20) == 1
    @test click(images, 30) == 1
    @test click(images, 44) == 2
end

@testset "an edit beside an image" begin
    measure = FixedMeasure(10, 12, 4, 0)
    key(k) = KeyDown(k, ModifierKeys(); time = 0.0)
    type(c) = KeyPress(c; time = 0.0)
    caret_of(block) = get_flat_selection(block)
    # Read `event` at `selection` through `projection` and apply the operation
    # with its inverse taken first. Answers the operation and the inverse.
    function edit!(editor, projection, selection, event)
        block = editor.document
        clear_selection!(block)
        set_selection!(block, selection)
        op = read_intent(projection, print_document(projection, block), event)
        op === nothing && return (nothing, nothing)
        (op, ProjecturedKernel.OperationModule.evaluate_invertible_operation!(editor, op))
    end
    at(k) = TextModule.make_flat_caret_reference(k)
    over(s, e) = TextModule.make_flat_range_reference(s, e)
    undo!(editor, inverse) = evaluate_operation(editor, inverse)

    for projection in (TextToGraphics(measure = measure),
                       ChainingProjection(WordWrapping(measure = measure, max_width = 1000),
                                          TextToGraphics(measure = measure)))
        editor(block) = _InlineImageEditor(block)

        # A character after an image with no run after it starts a new run, in
        # the style of the run before the image.
        e = editor(TextBlock(TextString("ab", font_ubuntu_regular_20, color_red), _image()))
        op, inverse = edit!(e, projection, at(3), type('x'))
        @test TextModule.is_text_element_write(op)
        @test get_flat_string(e.document) == "ab\uFFFCx"
        @test e.document.elements[3].font == font_ubuntu_regular_20
        @test e.document.elements[3].font_color == color_red
        @test caret_of(e.document) == (4, 4, true)
        undo!(e, inverse)
        @test get_flat_string(e.document) == "ab\uFFFC"
        @test length(e.document.elements) == 2

        # Before an image with no run before it, the new run takes the style of
        # the run after the image.
        e = editor(TextBlock(_image(), TextString("ab", font_ubuntu_regular_20, color_red)))
        edit!(e, projection, at(0), type('x'))
        @test get_flat_string(e.document) == "x\uFFFCab"
        @test e.document.elements[1].font_color == color_red
        @test caret_of(e.document) == (1, 1, true)

        # Where a run touches the image, the character goes into that run.
        e = editor(TextBlock(_run("ab"), _image(), _run("cd")))
        edit!(e, projection, at(3), type('x'))
        @test get_flat_string(e.document) == "ab\uFFFCxcd"
        @test length(e.document.elements) == 3
        edit!(e, projection, at(2), type('y'))
        @test get_flat_string(e.document) == "aby\uFFFCxcd"

        # Backspace after an image and Delete before it delete the image; undo
        # puts the same image back.
        for (k, event) in ((3, key(:backspace)), (2, key(:delete)))
            image = _image()
            e = editor(TextBlock(_run("ab"), image, _run("cd")))
            op, inverse = edit!(e, projection, at(k), event)
            @test get_flat_string(e.document) == "abcd"
            @test caret_of(e.document) == (2, 2, true)
            undo!(e, inverse)
            @test get_flat_string(e.document) == "ab\uFFFCcd"
            @test e.document.elements[2] === image
        end
        e = editor(TextBlock(_image(), _run("ab")))
        edit!(e, projection, at(1), key(:backspace))
        @test get_flat_string(e.document) == "ab"
        @test caret_of(e.document) == (0, 0, true)

        # A range of text and an image does nothing; a range of only images is
        # deleted, or replaced by a run of the typed text.
        e = editor(TextBlock(_run("ab"), _image(), _run("cd")))
        edit!(e, projection, over(1, 3), key(:backspace))
        @test get_flat_string(e.document) == "ab\uFFFCcd"
        e = editor(TextBlock(_run("ab"), _image(), _image(), _run("cd")))
        edit!(e, projection, over(2, 4), type('x'))
        @test get_flat_string(e.document) == "abxcd"
        @test length(e.document.elements) == 3
        @test caret_of(e.document) == (3, 3, true)
    end

    # A soft wrap before the image: the edit of the wrapped block names other
    # element indices, so `WordWrapping` declines it and the edit is made on its
    # input. "aaaa" is 40 wide and the image 24, so the image goes to line 2.
    wrapped = ChainingProjection(WordWrapping(measure = measure, max_width = 50),
                                 TextToGraphics(measure = measure))
    image = _image()
    e = _InlineImageEditor(TextBlock(_run("aaaa"), image, _run("b")))
    op, inverse = edit!(e, wrapped, at(5), key(:backspace))
    @test get_flat_string(e.document) == "aaaab"
    undo!(e, inverse)
    @test e.document.elements[2] === image
end

@testset "a caret beside an image passes each decorator" begin
    measure = FixedMeasure(10, 12, 4, 0)
    key(k) = KeyDown(k, ModifierKeys(); time = 0.0)
    offset(op) = (r = strip_reference_types(op.path); (r.head::TextRangeReferenceStep).start)
    caret_rects(canvas, x0 = 0, out = Int[]) = begin
        for element in canvas.elements
            if element isa GraphicsCanvas
                caret_rects(element, x0 + Int(element.x), out)
            elseif element isa GraphicsRect && Int(element.w) == 2
                push!(out, x0 + Int(element.x))
            end
        end
        out
    end
    # The block caret of `SelectionInverting` adds an inverted space at the end of
    # the text, and Right there maps past the end, with or without an image; the
    # plain caret keeps that fault out of this test.
    for decorator in (WordWrapping(measure = measure, max_width = 1000), TextFiltering(r"ab"),
                      TextFirstLine(), TextLineNumbering(), TextHighlighting(r"b"),
                      SelectionInverting(block_cursor = false))
        name = string(nameof(typeof(decorator)))
        projection = ChainingProjection(decorator, TextToGraphics(measure = measure))
        block = TextBlock(_image(), _run("ab"), _image())
        # The flat offset after `event` from caret `k`, back in the document, and
        # the x of the caret drawn at `k`.
        function after(k, event)
            clear_selection!(block)
            set_selection!(block, TextModule.make_flat_caret_reference(k))
            op = read_intent(projection, print_document(projection, block), event)
            op isa ReplaceSelectionOperation ? offset(op) : nothing
        end
        function drawn(k)
            clear_selection!(block)
            set_selection!(block, TextModule.make_flat_caret_reference(k))
            caret_rects(print_document(projection, block).output)
        end
        @testset "$name" begin
            @test [after(k, key(:right)) for k in 0:4] == [1, 2, 3, 4, 4]
            @test [after(k, key(:left)) for k in 0:4] == [0, 0, 1, 2, 3]
            xs = [drawn(k) for k in 0:4]
            @test all(x -> length(x) == 1, xs)
            @test issorted(first.(xs); lt = <=) && allunique(first.(xs))
        end
    end
end

end # @testset "Inline image caret"
end # test_inline_image_caret
