
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
# The caret at the start of the indented line sits after the indent, not before.
@test text_selection_flat(with_selection(mkblock(),
        TextModule._build_selection_path(Int[2, 1], 0))) == (14, 14, true)

# The caret inside a line is one `elements` hop deeper, and the flat offset of
# span 2 of line 1 is the length of span 1.
caret(path, k) = with_selection(mkblock(), TextModule._build_selection_path(path, k))
b = caret(Int[1, 2], 0)
@test TextModule._text_selection_range(b) == ([1, 2], 0, 0)
@test TextModule._cursor_coord(getfield(b, :selection)[]) == (span = [1, 2], char = 0)
@test text_selection_flat(b) == (5, 5, true)

# Character motion crosses span *and* line boundaries, landing on the canonical
# caret each time (the boundary duplicate is skipped, as in a flat block).
motion(path, k, key) = read_bound_gesture(caret(path, k), KeyDown(key, Modifiers())).path
@test motion(Int[1, 1], 2, :right) == TextModule._build_selection_path(Int[1, 1], 3)
@test motion(Int[1, 1], 5, :right) == TextModule._build_selection_path(Int[1, 2], 1)
@test motion(Int[1, 2], 6, :right) == TextModule._build_selection_path(Int[2, 1], 1)
@test motion(Int[2, 1], 0, :left)  == TextModule._build_selection_path(Int[1, 2], 5)

# Bare End is geometry — TextToGraphics owns it, the domain table has no binding.
@test read_bound_gesture(caret(Int[1, 1], 0), KeyDown(:end, Modifiers())) === nothing
# Ctrl+End reaches the last span of the last line; Ctrl+Left is word-wise.
@test read_bound_gesture(caret(Int[1, 1], 0), KeyDown(:end, Modifiers(; ctrl = true))).path ==
      TextModule._build_selection_path(Int[2, 1], 6)
@test read_bound_gesture(caret(Int[1, 2], 6), KeyDown(:left, Modifiers(; ctrl = true))).path ==
      TextModule._build_selection_path(Int[1, 2], 1)

# Typing edits that line's own span, and the caret advances past the insert.
b = caret(Int[2, 1], 6)
op = read_bound_gesture(b, KeyPress('!'))
@test op isa ReplaceStringRangeOperation
evaluate_operation((document = b,), op)
@test b.elements[2].elements[1].content == "second!"
@test getfield(b, :selection)[] == TextModule._build_selection_path(Int[2, 1], 7)

# Backspace at the start of a line declines rather than deleting across the line
# boundary — a cross-span edit the domain does not do yet.
@test read_bound_gesture(caret(Int[2, 1], 0), KeyDown(:backspace, Modifiers())) === nothing

# A flat block is unchanged: single-index caret paths, newline counted as one char.
flat = with_selection(TextBlock(TextString("ab"),
                                TextNewline(font = font_ubuntu_monospace_regular_20),
                                TextString("cd")),
                      TextModule._build_selection_path(3, 1))
@test text_flat_offsets(flat) == [0, 2, 3]
@test text_selection_flat(flat) == (4, 4, true)
@test TextModule._cursor_coord(getfield(flat, :selection)[]) == (span = [3], char = 1)
@test read_bound_gesture(flat, KeyDown(:left, Modifiers())).path ==
      TextModule._build_selection_path(3, 0)

end # @testset "TextLine: line-structured blocks"
end # test_text
