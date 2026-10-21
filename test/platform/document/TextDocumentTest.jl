
function test_text()
@testset "ReactiveText" begin

s1 = TextString("hello", StyleFont("Ubuntu Mono", 20; weight = 700), color_red)
@test s1.content == "hello"
@test s1.font == StyleFont("Ubuntu Mono", 20; weight = 700)
@test s1.font_color == color_red

s1.content = "hi"
@test s1.content == "hi"

st = TextLine(
    TextString("aaa", StyleFont("Ubuntu Mono", 20; weight = 700), color_red),
    TextString("bbb", StyleFont("Ubuntu Mono", 20), color_blue),
)
@test length(st.elements) == 2
@test st.elements[1].content == "aaa"

push!(st.elements, TextString("ccc", StyleFont("Ubuntu Mono", 20), color_default))
@test length(st.elements) == 3

deleteat!(st.elements, 2)
@test length(st.elements) == 2
@test st.elements[2].content == "ccc"

# computed text
counter = Cell(0)
dyn_span = TextString(() -> "n=$(counter[])", StyleFont("Ubuntu Mono", 20), color_white)
@test dyn_span.content == "n=0"
counter[] = 5
@test dyn_span.content == "n=5"

end # @testset "ReactiveText"

@testset "TextGraphics inline image span" begin

img = ImageMemory(nothing)
g = TextGraphics(img, 64, 48)
@test g.content === img
@test g.width == 64
@test g.height == 48

# Mixes cleanly with TextStrings inside a TextLine; length / getindex hold.
st = TextLine(
    TextString("ab", StyleFont("Ubuntu Mono", 20), color_red),
    TextGraphics(ImageMemory(nothing), 24, 24),
    TextString("cd", StyleFont("Ubuntu Mono", 20), color_blue),
)
@test length(st.elements) == 3
@test st.elements[1].content == "ab"
@test st.elements[2] isa TextGraphics
@test st.elements[2].width == 24
@test st.elements[3].content == "cd"

end # @testset "TextGraphics inline image span"

@testset "TextLine: line-structured blocks" begin

# A block of lines. The break a line implies is a *separator*, so two lines carry
# one break: line 2 starts at 11 ("hello world") + 1.
mkblock() = TextBlock(TextLine(TextString("hello"), TextString(" world")),
                      TextLine(TextString("second"); indentation = 2))

block = mkblock()
@test length(block.elements) == 2
@test block.elements[2].indentation == 2
@test get_flat_length(block.elements[1]) == 11        # the line's own spans, no break
@test get_flat_length(block.elements[2]) == 8         # 2 indent + "second"
@test get_flat_offsets(block) == [0, 12]

# The flat offsets must agree with the characters the renderers actually emit —
# indentation included, one break between lines. Anything mapping the character
# stream back to a span (the console highlight, SelectionInverting) relies on it.
@test get_flat_offsets(block)[2] + block.elements[2].indentation ==
      length("hello world\n  ")

# The caret is a flat offset in the break/indentation-aware stream. `fb(path, k)`
# is the flat offset of char `k` in the span at the structural `path` — the shape
# the old `content{c}` cursor named; the selection is now a flat `TextRangeReferenceStep`.
fb(path, k) = TextModule.get_flat_base(mkblock(), path) + k
caret(f)    = set_selection!(mkblock(), TextModule.make_flat_caret_reference(f))
# flat offset carried by a caret op / ref
cflat(x)    = (r = strip_reference_types(x isa ReplaceSelectionOperation ? x.path : x);
               (r.head::TextRangeReferenceStep).start)

# The caret at the start of the indented line sits after the indent, not before.
@test fb(Int[2, 1], 0) == 14
@test get_flat_selection(caret(fb(Int[2, 1], 0))) == (14, 14, true)

# The flat offset of span 2 of line 1 is the length of span 1; a boundary offset
# resolves canonically to the earlier span's end (direction-independent).
b = caret(fb(Int[1, 2], 0))
@test get_flat_selection(b) == (5, 5, true)
@test TextModule.get_flat_cursor_coordinate(b) == (span = [1, 1], char = 5)

# Character motion is `± 1` in the flat stream. Every offset — including the break
# and the indentation gap between the lines — is now a valid caret rest (those
# positions are deletable), so motion no longer skips them.
motion(f, key) = cflat(read_bound_gesture(caret(f), KeyDown(key, ModifierKeys(); time = 0.0)))
@test motion(fb(Int[1, 1], 2), :right) == fb(Int[1, 1], 3)   # 2 → 3
@test motion(fb(Int[1, 1], 5), :right) == fb(Int[1, 2], 1)   # 5 → 6, into span 2
@test motion(fb(Int[1, 2], 6), :right) == 12                 # 11 → 12, onto the break gap
@test motion(fb(Int[2, 1], 0), :left)  == 13                 # 14 → 13, into the indent gap

# Bare End is geometry — TextToGraphics owns it, the domain table has no binding.
@test read_bound_gesture(caret(fb(Int[1, 1], 0)), KeyDown(:end, ModifierKeys(); time = 0.0)) === nothing
# Ctrl+End reaches the flat end; Ctrl+Left is word-wise.
@test cflat(read_bound_gesture(caret(fb(Int[1, 1], 0)), KeyDown(:end, ModifierKeys(; ctrl = true); time = 0.0))) ==
      fb(Int[2, 1], 6)
@test cflat(read_bound_gesture(caret(fb(Int[1, 2], 6)), KeyDown(:left, ModifierKeys(; ctrl = true); time = 0.0))) ==
      fb(Int[1, 2], 1)

# Typing edits that line's own span (a flat ReplaceTextRangeOperation, lowered to a
# span edit as it threads up), and the caret advances past the insert.
b = caret(fb(Int[2, 1], 6))
op = read_bound_gesture(b, KeyPress('!'; time = 0.0))
@test op isa ReplaceTextRangeOperation
# The pair registers the flat edit, so the catch-all of the kernel reroots it.
outer = (FieldReferenceStep("outer"),)
@test operation_reference(op) === op.reference
@test reroot_operation(op, outer).reference == reroot_reference(op.reference, outer)
@test reroot_operation(op, outer).replacement == op.replacement
evaluate_operation((document = b,), op)
@test b.elements[2].elements[1].content == "second!"
@test get_flat_selection(b) == (21, 21, true)

# Backspace at the start of the text of a line removes the break and the
# indentation before it, so the two lines join, and the caret stands at the seam.
bb  = caret(fb(Int[2, 1], 0))
bop = read_bound_gesture(bb, KeyDown(:backspace, ModifierKeys(); time = 0.0))
@test bop isa ReplaceTextRangeOperation
@test strip_reference_types(bop.reference).head == TextRangeReferenceStep(11, 14)
evaluate_operation((document = bb,), bop)
@test length(bb.elements) == 1
@test get_flat_string(bb) == "hello worldsecond"
@test get_flat_selection(bb) == (11, 11, true)

# Enter splits the line at the caret; the new line takes the indentation of the
# line, and the text after the caret.
be  = caret(fb(Int[1, 1], 3))
eop = read_bound_gesture(be, KeyPress('\n'; time = 0.0))
@test eop isa ReplaceTextRangeOperation && eop.replacement == "\n"
evaluate_operation((document = be,), eop)
@test [get_flat_length(line) for line in be.elements] == [3, 8, 8]
@test get_flat_string(be) == "hel\nlo world\n  second"
@test get_flat_selection(be) == (4, 4, true)

# A block of two lines: the break before the second counts one flat char.
flat = set_selection!(TextBlock(TextLine(TextString("ab")), TextLine(TextString("cd"))),
                      TextModule.make_flat_caret_reference(4))   # char 1 of "cd" → flat 4
@test get_flat_offsets(flat) == [0, 3]
@test get_flat_selection(flat) == (4, 4, true)
@test TextModule.get_flat_cursor_coordinate(flat) == (span = [2, 1], char = 1)
@test cflat(read_bound_gesture(flat, KeyDown(:left, ModifierKeys(); time = 0.0))) == 3

end # @testset "TextLine: line-structured blocks"

@testset "make_text_block gives a line for each line of a string" begin

style = StyleText(StyleFont("Ubuntu Mono", 20), color_red)
runs(block) = [[span.content for span in line.elements] for line in block.elements]
objects(block) = [line for line in block.elements]

# Each line holds one run in the style, an empty line an empty run, and the flat
# string is the string.
for content in ("ab\n\ncd", "", "a\n", "\nb", "one")
    block = make_text_block(content, style)
    @test all(line -> line isa TextLine, block.elements)
    @test runs(block) == [[String(text)] for text in split(content, '\n')]
    @test get_flat_string(block) == content
    @test get_flat_length(block) == length(content)
end
block = make_text_block("ab\ncd", style)
@test block.elements[2].elements[1].font == style.font
@test block.elements[2].elements[1].font_color == style.color

# From a function, a line whose text did not change keeps its object: the head and
# the tail; the lines between are new.
source = Cell("one\ntwo\nthree")
block = make_text_block(() -> source[], style)
before = objects(block)
source[] = "one\nTWO\nthree"
after = objects(block)
@test runs(block) == [["one"], ["TWO"], ["three"]]
@test after[1] === before[1] && after[3] === before[3]
@test after[2] !== before[2]

source[] = "one\nTWO\nnew\nthree"
inserted = objects(block)
@test runs(block) == [["one"], ["TWO"], ["new"], ["three"]]
@test inserted[1] === after[1] && inserted[2] === after[2] && inserted[4] === after[3]

source[] = "one\nthree"
removed = objects(block)
@test runs(block) == [["one"], ["three"]]
@test removed[1] === inserted[1] && removed[2] === inserted[4]
@test get_flat_string(block) == "one\nthree"

# Equal texts: a shorter text keeps the lines of its head.
source[] = "x\nx\nx"
three = objects(block)
source[] = "x\nx"
@test all(map(===, objects(block), three[1:2]))

# With a placeholder: one muted line while the text is empty, the same object each
# time, and the lines of the text otherwise.
code = Cell("")
block = make_text_block(() -> code[], style; placeholder = "code", empty_thunk = () -> isempty(code[]))
@test runs(block) == [["code"]]
hint = block.elements[1]
@test hint.elements[1].font_color == color_solarized_gray
@test hint.elements[1].font == style.font
code[] = "a\nb"
@test runs(block) == [["a"], ["b"]]
@test block.elements[1].elements[1].font_color == style.color
code[] = ""
@test runs(block) == [["code"]]
@test block.elements[1] === hint

end # @testset "make_text_block gives a line for each line of a string"

@testset "append_text! adds a text at the end of a block and keeps its lines" begin

style = StyleText(StyleFont("Ubuntu Mono", 20), color_red)
runs(block) = [[span.content for span in line.elements] for line in block.elements]

# The text up to the first newline goes into the last run; each line after a
# newline is a new line in the style of that run.
block = make_text_block("Hello", style)
first_line = block.elements[1]
@test append_text!(block, ", world\nand\n") === block
@test runs(block) == [["Hello, world"], ["and"], [""]]
@test get_flat_string(block) == "Hello, world\nand\n"
@test block.elements[1] === first_line
@test block.elements[2].elements[1].font == style.font
@test block.elements[2].elements[1].font_color == style.color

# An empty text changes nothing, and a block of an empty string grows as a stream
# of deltas grows the string.
@test runs(append_text!(block, "")) == [["Hello, world"], ["and"], [""]]
streamed = make_text_block("")
foreach(delta -> append_text!(streamed, delta), ["one ", "two\nthr", "ee", "\n", "four"])
@test get_flat_string(streamed) == "one two\nthree\nfour"
@test runs(streamed) == [["one two"], ["three"], ["four"]]
end # @testset "append_text! adds a text at the end of a block and keeps its lines"

@testset "get_flat_caret and get_flat_range read the flat and the structural form" begin
    # "ab" and "cd" on two lines: "cd" starts at flat offset 3.
    block = TextBlock(TextLine(TextString("ab")), TextLine(TextString("cd")))
    structural(line, s, e) = ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(line - 1, line), ConcreteReference(FieldReferenceStep("elements"),
            ConcreteReference(RangeReferenceStep(0, 1), ConcreteReference(FieldReferenceStep("content"),
                ConcreteReference(RangeReferenceStep(s, e), EmptyReference()))))))
    @test get_flat_range(block, TextModule.make_flat_range_reference(1, 4)) == (1, 4)
    @test get_flat_range(block, TextModule.make_flat_caret_reference(2)) == (2, 2)
    @test get_flat_range(block, structural(2, 0, 2)) == (3, 5)
    @test get_flat_range(block, structural(2, 1, 1)) == (4, 4)
    @test get_flat_caret(block, structural(2, 1, 1)) == 4
    @test get_flat_caret(block, structural(2, 0, 2)) === nothing
    @test get_flat_range(block, EmptyReference()) === nothing
    @test get_flat_range(block, nothing) === nothing
end # @testset "get_flat_caret and get_flat_range read the flat and the structural form"

@testset "Shift and a motion key select a range" begin
    shift = ModifierKeys(; shift = true)
    ctrl_shift = ModifierKeys(; ctrl = true, shift = true)
    at(selection) = set_selection!(TextBlock(TextLine(TextString("hello world"))), selection)
    pair(op) = (op.path.head.start, op.path.head.stop)
    caret = TextModule.make_flat_caret_reference(5)
    range = TextModule.make_flat_range_reference(3, 5)

    # From a caret, the key's direction makes the range.
    @test pair(read_bound_gesture(at(caret), KeyDown(:left, shift; time = 0.0))) == (4, 5)
    @test pair(read_bound_gesture(at(caret), KeyDown(:right, shift; time = 0.0))) == (5, 6)
    @test pair(read_bound_gesture(at(caret), KeyDown(:left, ctrl_shift; time = 0.0))) == (0, 5)
    @test pair(read_bound_gesture(at(caret), KeyDown(:right, ctrl_shift; time = 0.0))) == (5, 6)
    @test pair(read_bound_gesture(at(caret), KeyDown(:home, ctrl_shift; time = 0.0))) == (0, 5)
    @test pair(read_bound_gesture(at(caret), KeyDown(:end, ctrl_shift; time = 0.0))) == (5, 11)

    # A range stays ordered: the left keys move its start, the right keys its stop.
    @test pair(read_bound_gesture(at(range), KeyDown(:left, shift; time = 0.0))) == (2, 5)
    @test pair(read_bound_gesture(at(range), KeyDown(:right, shift; time = 0.0))) == (3, 6)
    # The ends stop at the ends of the text.
    @test pair(read_bound_gesture(at(TextModule.make_flat_range_reference(0, 11)),
                                  KeyDown(:left, shift; time = 0.0))) == (0, 11)
    # A plain arrow collapses the range to its near end, as before.
    @test read_bound_gesture(at(range), KeyDown(:left, ModifierKeys(); time = 0.0)).path.head.start == 3
    # A whole element is not a character selection, and the key declines.
    @test read_bound_gesture(at(ConcreteReference(TextSpanReferenceStep(0, 5), EmptyReference())),
                             KeyDown(:left, shift; time = 0.0)) === nothing
end # @testset "Shift and a motion key select a range"

@testset "a text step hashes as it compares" begin
    for make_step in (TextRangeReferenceStep, TextSpanReferenceStep,
                      TextColumnReferenceStep)
        first_path = Reference(FieldReferenceStep("content"), make_step(2, 4))
        second_path = Reference(FieldReferenceStep("content"), make_step(2, 4))
        @test first_path == second_path
        @test hash(first_path) == hash(second_path)
        @test length(Set([first_path, second_path])) == 1
    end
end # @testset "a text step hashes as it compares"
end # test_text
