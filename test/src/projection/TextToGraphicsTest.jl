function test_text_to_graphics()
_test_measure(cw, lh) = (text, font) -> (length(text) * cw, lh)

@testset "TextToGraphics" begin

# basic layout (wrapping is now done by WordWrapping upstream)
st_wrap = TextText(
    TextString("Hello world this is a long text", font_ubuntu_monospace_regular_24, color_red),
)
m = _test_measure(10, 18)
chain = SequentialProjection(WordWrapping(max_width=200, measure=m), TextToGraphics(measure=m))
sdl_cell = projection_print(chain, st_wrap).output
sdl_items = sdl_cell.elements
@test length(sdl_items) >= 2  # should wrap
@test sdl_items[1].y == 0
@test sdl_items[2].y == 18  # second line

# newline handling
st_nl = TextText(
    TextString("line1\nline2\nline3", font_ubuntu_monospace_regular_24, color_white),
)
sdl_nl = projection_print(TextToGraphics(measure=_test_measure(10, 20)), st_nl).output
items_nl = sdl_nl.elements
@test length(items_nl) == 3
@test items_nl[1].text == "line1"
@test items_nl[2].text == "line2"
@test items_nl[3].text == "line3"
@test items_nl[1].y == 0
@test items_nl[2].y == 20
@test items_nl[3].y == 40

# color preservation
st_color = TextText(
    TextString("red text", font_ubuntu_monospace_regular_24, color_red),
    TextString(" blue text", font_ubuntu_monospace_regular_24, color_blue),
)
sdl_color = projection_print(TextToGraphics(measure=_test_measure(10, 48)), st_color).output
items_c = sdl_color.elements
@test items_c[1].r == 0xff && items_c[1].g == 0x00  # red
@test items_c[2].r == 0x00 && items_c[2].b == 0xff  # blue

# continuation on same line
@test items_c[2].y == items_c[1].y  # same line
@test items_c[2].x > items_c[1].x   # to the right

# reactivity: text change triggers relayout
st_react = TextText(
    TextString("short", font_ubuntu_monospace_regular_24, color_white),
)
sdl_react = projection_print(TextToGraphics(measure=_test_measure(10, 48)), st_react).output
_ = length(sdl_react.elements)
@test isuptodate(getfield(sdl_react.elements, :elements))
st_react[1].content = "changed"
@test !isuptodate(getfield(sdl_react.elements, :elements))
items_r = sdl_react.elements
@test items_r[1].text == "changed"

# hex color parsing
st_hex = TextText(TextString("hex", font_ubuntu_monospace_regular_24, StyleColor(1.0, 0.53, 0.0, 1.0)))
sdl_hex = projection_print(TextToGraphics(measure=_test_measure(10, 48)), st_hex).output
h = sdl_hex.elements[1]
@test h.r == 0xff
@test h.g == 0x87  # rounding of 0.53 * 255
@test h.b == 0x00

end # @testset "TextToGraphics"

@testset "TextToGraphics ListNode path" begin

# Build a TextText with ListNode elements: two paragraphs separated by TextNewline
node = ListNode(TextString("Hello world", font_ubuntu_monospace_regular_24, color_red))
push!(node, TextNewline(font=font_ubuntu_monospace_regular_24))
push!(node, TextString("Second paragraph", font_ubuntu_monospace_regular_24, color_blue))

tt = TextText()
tt.elements = node

p = TextToGraphics(measure=_test_measure(10, 20))
iomap = projection_print(p, PreservingProjection(), tt, PrinterContext())
canvas = iomap.output

# Top-level canvas has ListNode elements, layout_vertical, non-overlapping
@test canvas.elements isa ListNode
@test canvas.layout == layout_vertical
@test canvas.overlapping_elements == false

# First paragraph sub-canvas
para1 = canvas.elements.value
@test para1 isa GraphicsCanvas
@test para1.y == 0
@test para1.elements isa CellVector
@test length(para1.elements) >= 1
@test para1.elements[1].text == "Hello world"

# Second paragraph is lazily computed via .next
next_node = canvas.elements.next
@test next_node !== nothing
para2 = next_node.value
@test para2 isa GraphicsCanvas
@test para2.y == 20  # one line_height below first paragraph
@test para2.elements[1].text == "Second paragraph"

# No third paragraph
@test next_node.next === nothing

end # @testset "TextToGraphics ListNode path"

@testset "TextToGraphics ListNode lazy evaluation" begin

# Verify laziness: next paragraphs are not computed until forced
counter = Ref(0)
node = ListNode(TextString("Para 1", font_ubuntu_monospace_regular_24, color_white))

# Build a lazy chain of paragraphs
node2 = ListNode(TextNewline(font=font_ubuntu_monospace_regular_24))
node.next = node2
node2.prev = node

node3 = ListNode(TextString("Para 2", font_ubuntu_monospace_regular_24, color_white))
setfn!(getfield(node2, :next), () -> begin
    counter[] += 1
    node3.prev = node2
    node3
end)

tt = TextText()
tt.elements = node

p = TextToGraphics(measure=_test_measure(10, 20))
iomap = projection_print(p, PreservingProjection(), tt, PrinterContext())

# The first paragraph collects spans until it finds the TextNewline,
# walking past it forces node2.next thunk to find where para 2 starts
@test counter[] == 1

# But the second paragraph's sub-canvas is lazily built (output .next thunk)
# Forcing it should not increase counter (input already walked)
next_node = iomap.output.elements.next
@test next_node !== nothing
@test counter[] == 1

end # @testset "TextToGraphics ListNode lazy evaluation"

@testset "TextToGraphics inline image" begin

m = _test_measure(10, 18)
st = TextText(
    TextString("ab", font_ubuntu_monospace_regular_24, color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", font_ubuntu_monospace_regular_24, color_white),
)
canvas = projection_print(TextToGraphics(measure=m), st).output
items = [canvas.elements[i] for i in 1:length(canvas.elements)]

# Exactly one GraphicsImage, at the expected box (after "ab" = 20px).
imgs = filter(e -> e isa GraphicsImage, items)
@test length(imgs) == 1
gi = imgs[1]
@test gi.x == 20
@test gi.y == 0
@test gi.w == 64
@test gi.h == 64

# Line height follows the image height.
@test canvas.h >= 64

# Surrounding text flows before/after the image on the same line.
texts = filter(e -> e isa GraphicsText, items)
@test length(texts) == 2
@test texts[1].text == "ab" && texts[1].x == 0
@test texts[2].text == "cd" && texts[2].x == 20 + 64

end # @testset "TextToGraphics inline image"

@testset "TextToGraphics inline image hit-test" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure=m)
st = TextText(
    TextString("ab", font_ubuntu_monospace_regular_24, color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", font_ubuntu_monospace_regular_24, color_white),
)
iomap = projection_print(p, st)

# A click path encodes (segment-index → pixel offset). The image is the 2nd
# emitted segment; rx<32 is its left half, rx>=32 its right half.
click(rx) = ReplaceSelectionOperation(
    ConcreteReferencePath(RangeReference(1, 2),
        ConcreteReferencePath(PointReference(rx, 0), EmptyReferencePath())))
left  = projection_read(p, iomap, click(10))
right = projection_read(p, iomap, click(50))
@test left isa ReplaceSelectionOperation
@test right isa ReplaceSelectionOperation
# Left half → cursor before the image (content{0}); right half → after ({1}).
@test reference_equal(left.path,  Projectured.TextToGraphicsModule._build_selection_path(2, 0))
@test reference_equal(right.path, Projectured.TextToGraphicsModule._build_selection_path(2, 1))

end # @testset "TextToGraphics inline image hit-test"

end # test_text_to_graphics
