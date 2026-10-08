# An inline image (`TextGraphics`) is one position of the flat caret space: the
# caret before it and the caret after it are different offsets, and every reader
# of the space agrees on it.

_image() = TextGraphics(ImageMemory(nothing), 24, 24)
_run(text) = TextString(text, StyleFont("Ubuntu Mono", 20), color_default)
const _splice_value! = ProjecturedKernel.OperationModule.splice_value!

# The editor an operation is applied against: the document, and no view.
# The text stage of a wrapper of a text: a highlight or a filter of a document,
# and a plain block as it is.
_ii_text_stage() = RecursiveProjection(TypeDispatchingProjection(
    HighlightedText => HighlightedTextToText(),
    TextBlock       => IdentityProjection()))

# The block of a document that is a block or wraps one in its `text`.
_ii_block_of(document::TextBlock) = document
_ii_block_of(document) = _ii_block_of(document.text)

# A caret of the block, as a path of the document that wraps it.
_ii_wrap_caret(document::TextBlock, caret) = caret
_ii_wrap_caret(document, caret) =
    ConcreteReference(FieldReferenceStep("text"), _ii_wrap_caret(document.text, caret))

# An operation of a wrapper of a text, with the step `text` taken off what each
# part names, so a check of an edit of a block reads it as the block's own.
_ii_strip_text(operation::CompoundOperation) =
    CompoundOperation(Any[_ii_strip_text(member) for member in operation.operations])
function _ii_strip_text(operation)
    reference = operation_reference(operation)
    reference isa ConcreteReference || return operation
    stripped = strip_reference_types(reference)
    head = get_reference_head(stripped)
    (head isa FieldReferenceStep && head.name == "text") || return operation
    retarget_operation(operation, get_reference_tail(stripped))
end

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
    # A range over the image and a character straddles two spans and changes
    # nothing.
    _splice_value!(nothing, :content, block, 2, 4, "")
    @test get_flat_string(block) == "abY\uFFFCXcd"
    # Beside an image, where no run holds the offset, the edit is made as the
    # reader makes it: a new run, or the image removed or replaced.
    only = TextBlock(_image())
    _splice_value!(nothing, :content, only, 0, 0, "x")
    @test get_flat_string(only) == "x\uFFFC"
    after = TextBlock(_run("ab"), _image())
    _splice_value!(nothing, :content, after, 3, 3, "x")
    @test get_flat_string(after) == "ab\uFFFCx"
    _splice_value!(nothing, :content, after, 2, 3, "")
    @test get_flat_string(after) == "abx"
    replaced = TextBlock(_run("ab"), _image(), _image(), _run("cd"))
    _splice_value!(nothing, :content, replaced, 2, 4, "y")
    @test get_flat_string(replaced) == "abycd"
    @test length(replaced.elements) == 3
end

@testset "an offset beside an image is a place of the image" begin
    place(block, k) = TextModule.get_flat_cursor_coordinate(
        set_selection!(block, TextModule.make_flat_caret_reference(k)))
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
        set_selection!(block, TextModule.make_flat_caret_reference(k))).output)
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
    # An image of zero width still has its carets for the geometric keys.
    flat = TextBlock(_run("ab"), TextGraphics(ImageMemory(nothing)))
    @test after(flat, 3, key(:home)) == 0
    @test after(flat, 0, key(:end)) == 3
    # A line of images only has carets too.
    images = TextBlock(_image(), _image())
    @test after(images, 0, key(:end)) == 2
    @test after(images, 2, key(:home)) == 0

    # Up and Down keep the x of the caret; each half of an image is one side.
    # Line 1: [image] 0..24, "ab" 24..44. Line 2: "cd" 0..20, [image] 20..44.
    lines = TextBlock(_image(), _run("ab"), TextNewline(font = StyleFont("Ubuntu Mono", 20)),
                      _run("cd"), _image())
    @test after(lines, 3, key(:down)) == 7      # x 44: after the image
    @test after(lines, 7, key(:up)) == 3        # x 44: the end of "ab"
    @test after(lines, 0, key(:down)) == 4      # x 0: the start of "cd"
    @test after(lines, 4, key(:up)) == 0        # x 0: before the image

    # A click on the left half of an image is before it, on the right half after it.
    click(block, x) = (op = read_intent(projection, print_document(projection, block),
                                        MouseClick(:left, x, 5; time = 0.0));
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
        document = editor.document
        clear_selection!(document)
        set_selection!(document, _ii_wrap_caret(document, selection))
        op = read_intent(projection, print_document(projection, document), event)
        op === nothing && return (nothing, nothing)
        (op, ProjecturedKernel.OperationModule.evaluate_invertible_operation!(editor, op))
    end
    at(k) = TextModule.make_flat_caret_reference(k)
    over(s, e) = TextModule.make_flat_range_reference(s, e)
    undo!(editor, inverse) = evaluate_operation(editor, inverse)

    # Each decorator declines the edit of its output and lowers the key against
    # its input, so the edit and its undo work through every chain.
    # A wrapper of a text, such as a highlight, is the document, and its stage
    # passes the edit to the block in its `text`.
    decorators = (WordWrapping(measure = measure, max_width = 1000),
                  TextFiltering(r""), TextFirstLine(), TextLineNumbering())
    chains = Any[(TextToGraphics(measure = measure), identity),
                 ((ChainingProjection(d, TextToGraphics(measure = measure)), identity)
                  for d in decorators)...,
                 (ChainingProjection(_ii_text_stage(), TextToGraphics(measure = measure)),
                  block -> HighlightedText(text = block, pattern = "b"))]
    for (projection, wrap) in chains
        editor(block) = _InlineImageEditor(wrap(block))
        block_of(e) = _ii_block_of(e.document)

        # A character after an image with no run after it starts a new run, in
        # the style of the run before the image.
        e = editor(TextBlock(TextString("ab", StyleFont("Ubuntu", 20), color_red), _image()))
        op, inverse = edit!(e, projection, at(3), type('x'))
        @test TextModule.is_text_element_write(wrap === identity ? op : _ii_strip_text(op))
        @test get_flat_string(block_of(e)) == "ab\uFFFCx"
        @test block_of(e).elements[3].font == StyleFont("Ubuntu", 20)
        @test block_of(e).elements[3].font_color == color_red
        @test caret_of(block_of(e)) == (4, 4, true)
        undo!(e, inverse)
        @test get_flat_string(block_of(e)) == "ab\uFFFC"
        @test length(block_of(e).elements) == 2

        # Before an image with no run before it, the new run takes the style of
        # the run after the image.
        e = editor(TextBlock(_image(), TextString("ab", StyleFont("Ubuntu", 20), color_red)))
        edit!(e, projection, at(0), type('x'))
        @test get_flat_string(block_of(e)) == "x\uFFFCab"
        @test block_of(e).elements[1].font_color == color_red
        @test caret_of(block_of(e)) == (1, 1, true)

        # Where a run touches the image, the character goes into that run.
        e = editor(TextBlock(_run("ab"), _image(), _run("cd")))
        edit!(e, projection, at(3), type('x'))
        @test get_flat_string(block_of(e)) == "ab\uFFFCxcd"
        @test length(block_of(e).elements) == 3
        edit!(e, projection, at(2), type('y'))
        @test get_flat_string(block_of(e)) == "aby\uFFFCxcd"

        # Backspace after an image and Delete before it delete the image; undo
        # puts the same image back.
        for (k, event) in ((3, key(:backspace)), (2, key(:delete)))
            image = _image()
            e = editor(TextBlock(_run("ab"), image, _run("cd")))
            op, inverse = edit!(e, projection, at(k), event)
            @test get_flat_string(block_of(e)) == "abcd"
            @test caret_of(block_of(e)) == (2, 2, true)
            undo!(e, inverse)
            @test get_flat_string(block_of(e)) == "ab\uFFFCcd"
            @test block_of(e).elements[2] === image
        end
        e = editor(TextBlock(_image(), _run("ab")))
        edit!(e, projection, at(1), key(:backspace))
        @test get_flat_string(block_of(e)) == "ab"
        @test caret_of(block_of(e)) == (0, 0, true)

        # A range of text and an image does nothing; a range of only images is
        # deleted, or replaced by a run of the typed text.
        e = editor(TextBlock(_run("ab"), _image(), _run("cd")))
        edit!(e, projection, over(1, 3), key(:backspace))
        @test get_flat_string(block_of(e)) == "ab\uFFFCcd"
        e = editor(TextBlock(_run("ab"), _image(), _image(), _run("cd")))
        edit!(e, projection, over(2, 4), type('x'))
        @test get_flat_string(block_of(e)) == "abxcd"
        @test length(block_of(e).elements) == 3
        @test caret_of(block_of(e)) == (3, 3, true)
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
    offset(op) = (last(get_reference_steps(strip_reference_types(op.path)))::TextRangeReferenceStep).start
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
    plain(decorator) = (string(nameof(typeof(decorator))),
                        ChainingProjection(decorator, TextToGraphics(measure = measure)), identity)
    entries = Any[(plain(d) for d in (WordWrapping(measure = measure, max_width = 1000),
                                      TextFiltering(r"ab"), TextFirstLine(), TextLineNumbering(),
                                      SelectionInverting(block_cursor = false)))...,
                  ("HighlightedTextToText",
                   ChainingProjection(_ii_text_stage(), TextToGraphics(measure = measure)),
                   block -> HighlightedText(text = block, pattern = "b"))]
    for (name, projection, wrap) in entries
        document = wrap(TextBlock(_image(), _run("ab"), _image()))
        # The flat offset after `event` from caret `k`, back in the document, and
        # the x of the caret drawn at `k`.
        function after(k, event)
            clear_selection!(document)
            set_selection!(document, _ii_wrap_caret(document, TextModule.make_flat_caret_reference(k)))
            op = read_intent(projection, print_document(projection, document), event)
            op isa ReplaceSelectionOperation ? offset(op) : nothing
        end
        function drawn(k)
            clear_selection!(document)
            set_selection!(document, _ii_wrap_caret(document, TextModule.make_flat_caret_reference(k)))
            caret_rects(print_document(projection, document).output)
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

@testset "beside an image, the style of the nearest text run" begin
    # `small` has ascent 12 and descent 4, `large` ascent 16, descent 6 and a
    # line gap of 2; every character is 10 wide. `large` is the font of a text
    # that names none.
    small = StyleFont("Ubuntu", 20)
    large = UNSTYLED_TEXT_FONT
    measure = FixedMeasure(10, 12, 4, 0; fonts = Dict(large => FontMetrics(16, 6, 2)))
    projection = TextToGraphics(measure = measure)
    caret(block, k) = begin
        clear_selection!(block)
        set_selection!(block, TextModule.make_flat_caret_reference(k))
        canvas = print_document(projection, block).output
        out = Any[]
        walk(c, x0, y0) = for e in c.elements
            if e isa GraphicsCanvas
                walk(e, x0 + Int(e.x), y0 + Int(e.y))
            elseif e isa GraphicsRect && Int(e.w) == 2
                push!(out, (x0 + Int(e.x), y0 + Int(e.y), Int(e.h)))
            end
        end
        walk(canvas, 0, 0)
        out
    end

    # The image is 30 high, so the baseline is 30 below the top; the caret after
    # it has the height of `small`, the font of the run before it.
    block = TextBlock(TextString("ab", small, color_black), TextGraphics(ImageMemory(nothing), 24, 30))
    @test caret(block, 2) == [(20, 30 - 12, 16)]
    @test caret(block, 3) == [(44, 30 - 12, 16)]

    # A line that holds only an image: the caret takes the prevailing font of
    # the block, `large`. Line 2 begins at 24 and its baseline is the bottom of
    # the image.
    block = TextBlock(TextString("x", large, color_black), TextNewline(font = large), _image())
    @test caret(block, 3) == [(24, 24 + 24 - 16, 22)]
    # A block with no font at all: the font of `TextString(content)`, which is
    # `large` here.
    @test caret(TextBlock(_image()), 1) == [(24, 24 - 16, 22)]

    # A run typed after the image of that line takes the style of the block.
    editor = _InlineImageEditor(TextBlock(TextString("x", large, color_red), TextNewline(font = small),
                                          _image()))
    clear_selection!(editor.document)
    set_selection!(editor.document, TextModule.make_flat_caret_reference(3))
    evaluate_operation(editor, read_intent(projection, print_document(projection, editor.document),
                                           KeyPress('y'; time = 0.0)))
    @test get_flat_string(editor.document) == "x\n\uFFFCy"
    @test editor.document.elements[4].font == large
    @test editor.document.elements[4].font_color == color_red

    # The soft newline that `WordWrapping` puts before an image takes the style
    # of the run before the image.
    wrapped = print_document(WordWrapping(measure = measure, max_width = 50),
                             TextBlock(TextString("aaaa", small, color_red), _image())).output
    newline = wrapped.elements[2]
    @test newline isa TextNewline
    @test newline.font == small
    @test newline.font_color == color_red
end

@testset "the string of a text is its flat string" begin
    to_string(block) = (o = print_document(RecursiveProjection(TextToString()), block).output;
                        o isa AbstractString ? o : o[])
    spacing = TextSpacing(4; font = StyleFont("Ubuntu Mono", 20))
    block = TextBlock(TextLine(_run("ab"), _image()), TextLine(_run("c"), spacing, _image(); indentation = 2))
    @test to_string(block) == "ab\uFFFC\n  c \uFFFC"
    @test to_string(block) == get_flat_string(block)
    example = make_text_with_image_example()
    @test to_string(example) == get_flat_string(example)
    @test length(to_string(example)) == TextModule._text_flat_total(example)
end

@testset "a range is painted over exactly its characters and images" begin
    # Every character is 10 wide and the image 24.
    measure = FixedMeasure(10, 12, 4, 0)
    # The left and the right end of each row of the highlight: the rects of the
    # first element of the canvas, the highlight canvas.
    function rows(projection, block, s, e)
        clear_selection!(block)
        set_selection!(block, TextModule.make_flat_range_reference(s, e))
        highlight = print_document(projection, block).output.elements[1]
        [(Int(r.x), Int(r.x) + Int(r.w)) for r in highlight.elements if Int(r.w) > 0]
    end
    plain = TextToGraphics(measure = measure)
    nl() = TextNewline(font = StyleFont("Ubuntu Mono", 20))

    # Across a `TextNewline`, which is one position: 'b', the break and 'c'.
    @test rows(plain, TextBlock(_run("ab"), nl(), _run("cd")), 1, 4) == [(10, 20), (0, 10)]
    # An image in a range is painted.
    @test rows(plain, TextBlock(_run("ab"), _image(), _run("cd")), 2, 3) == [(20, 44)]
    @test rows(plain, TextBlock(_run("ab"), _image(), _run("cd")), 1, 3) == [(10, 44)]
    # Across a soft newline: "aaa " wraps before "bbb" at 50, and the range
    # "a bb" of the document is "a " on line 1 and "bb" on line 2.
    wrapped = ChainingProjection(WordWrapping(measure = measure, max_width = 50), TextToGraphics(measure = measure))
    @test rows(wrapped, TextBlock(_run("aaa bbb")), 2, 6) == [(20, 40), (0, 20)]
end

end # @testset "Inline image caret"
end # test_inline_image_caret
