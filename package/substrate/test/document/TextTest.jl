
function test_text()
@testset "ReactiveText" begin

s1 = TextString("hello", font_ubuntu_monospace_bold_20, color_red)
@test s1.content == "hello"
@test s1.font == font_ubuntu_monospace_bold_20
@test s1.font_color == color_red

s1.content = "hi"
@test s1.content == "hi"

st = TextBlock(
    TextString("aaa", font_ubuntu_monospace_bold_20, color_red),
    TextString("bbb", font_ubuntu_monospace_regular_20, color_blue),
)
@test length(st.elements) == 2
@test st.elements[1].content == "aaa"

push!(st.elements, TextString("ccc", font_ubuntu_monospace_regular_20, color_default))
@test length(st.elements) == 3

deleteat!(st.elements, 2)
@test length(st.elements) == 2
@test st.elements[2].content == "ccc"

# computed text
counter = Cell(0)
dyn_span = TextString(() -> "n=$(counter[])", font_ubuntu_monospace_regular_20, color_white)
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

# Mixes cleanly with TextStrings inside a TextBlock; length / getindex hold.
st = TextBlock(
    TextString("ab", font_ubuntu_monospace_regular_20, color_red),
    TextGraphics(ImageMemory(nothing), 24, 24),
    TextString("cd", font_ubuntu_monospace_regular_20, color_blue),
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
@test text_flat_length(block.elements[1]) == 11        # the line's own spans, no break
@test text_flat_length(block.elements[2]) == 8         # 2 indent + "second"
@test text_flat_offsets(block) == [0, 12]

# The flat offsets must agree with the characters the renderers actually emit —
# indentation included, one break between lines. Anything mapping the character
# stream back to a span (the console highlight, SelectionInverting) relies on it.
@test text_flat_offsets(block)[2] + block.elements[2].indentation ==
      length("hello world\n  ")

# The caret is a flat offset in the break/indentation-aware stream. `fb(path, k)`
# is the flat offset of char `k` in the span at the structural `path` — the shape
# the old `content{c}` cursor named; the selection is now a flat `TextRangeReferenceStep`.
fb(path, k) = TextModule._flat_base(mkblock(), path) + k
caret(f)    = with_selection(mkblock(), TextModule._flat_caret_ref(f))
# flat offset carried by a caret op / ref
cflat(x)    = (r = strip_reference_types(x isa ReplaceSelectionOperation ? x.path : x);
               (r.head::TextRangeReferenceStep).start)

# The caret at the start of the indented line sits after the indent, not before.
@test fb(Int[2, 1], 0) == 14
@test text_selection_flat(caret(fb(Int[2, 1], 0))) == (14, 14, true)

# The flat offset of span 2 of line 1 is the length of span 1; a boundary offset
# resolves canonically to the earlier span's end (direction-independent).
b = caret(fb(Int[1, 2], 0))
@test text_selection_flat(b) == (5, 5, true)
@test TextModule._flat_cursor_coord(b) == (span = [1, 1], char = 5)

# Character motion is `± 1` in the flat stream. Every offset — including the break
# and the indentation gap between the lines — is now a valid caret rest (those
# positions are deletable), so motion no longer skips them.
motion(f, key) = cflat(read_bound_gesture(caret(f), KeyDown(key, ModifierKeys())))
@test motion(fb(Int[1, 1], 2), :right) == fb(Int[1, 1], 3)   # 2 → 3
@test motion(fb(Int[1, 1], 5), :right) == fb(Int[1, 2], 1)   # 5 → 6, into span 2
@test motion(fb(Int[1, 2], 6), :right) == 12                 # 11 → 12, onto the break gap
@test motion(fb(Int[2, 1], 0), :left)  == 13                 # 14 → 13, into the indent gap

# Bare End is geometry — TextToGraphics owns it, the domain table has no binding.
@test read_bound_gesture(caret(fb(Int[1, 1], 0)), KeyDown(:end, ModifierKeys())) === nothing
# Ctrl+End reaches the flat end; Ctrl+Left is word-wise.
@test cflat(read_bound_gesture(caret(fb(Int[1, 1], 0)), KeyDown(:end, ModifierKeys(; ctrl = true)))) ==
      fb(Int[2, 1], 6)
@test cflat(read_bound_gesture(caret(fb(Int[1, 2], 6)), KeyDown(:left, ModifierKeys(; ctrl = true)))) ==
      fb(Int[1, 2], 1)

# Typing edits that line's own span (a flat ReplaceTextRangeOperation, lowered to a
# span edit as it threads up), and the caret advances past the insert.
b = caret(fb(Int[2, 1], 6))
op = read_bound_gesture(b, KeyPress('!'))
@test op isa ReplaceTextRangeOperation
evaluate_operation((document = b,), op)
@test b.elements[2].elements[1].content == "second!"
@test text_selection_flat(b) == (21, 21, true)

# Backspace at the start of a line now produces a flat op targeting the position
# before it (the indentation gap); the standalone evaluate still declines a gap /
# cross-span delete (v1), leaving the line unchanged.
bb  = caret(fb(Int[2, 1], 0))
bop = read_bound_gesture(bb, KeyDown(:backspace, ModifierKeys()))
@test bop isa ReplaceTextRangeOperation
evaluate_operation((document = bb,), bop)
@test bb.elements[2].elements[1].content == "second"

# A flat block: single-index spans, the newline counted as one flat char.
flat = with_selection(TextBlock(TextString("ab"),
                                TextNewline(font = font_ubuntu_monospace_regular_20),
                                TextString("cd")),
                      TextModule._flat_caret_ref(4))   # char 1 of "cd" → flat 4
@test text_flat_offsets(flat) == [0, 2, 3]
@test text_selection_flat(flat) == (4, 4, true)
@test TextModule._flat_cursor_coord(flat) == (span = [3], char = 1)
@test cflat(read_bound_gesture(flat, KeyDown(:left, ModifierKeys()))) == 3

end # @testset "TextLine: line-structured blocks"
end # test_text
