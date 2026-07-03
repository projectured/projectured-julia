function test_text_to_graphics()
_test_measure(cw, lh) = (text, font) -> (length(text) * cw, lh)

# The TextToGraphics canvas carries a persistent highlight rect (behind the text)
# and cursor rect (in front) so that moving the caret never regenerates the spans;
# both are zero-width/invisible when no selection is set. The content is laid out
# as one sub-canvas per visual line (line at `y`, segments at `y` relative to it),
# so these helpers recursively flatten the tree into entries with ABSOLUTE
# coordinates, exposing the same `.x/.y/.text/.color/.w/.h` fields the assertions
# read regardless of nesting depth.
function _flat(c, ox::Int=0, oy::Int=0, acc=Tuple{Any,Int,Int}[])
    for i in 1:length(c.elements)
        e = c.elements[i]
        if e isa GraphicsCanvas
            _flat(e, ox + Int(e.x), oy + Int(e.y), acc)
        else
            push!(acc, (e, ox + Int(e.x), oy + Int(e.y)))
        end
    end
    acc
end
_all(c) = _flat(c)
_texts(c) = [(text = e.text, color = e.color, x = ax, y = ay) for (e, ax, ay) in _flat(c) if e isa GraphicsText]
_imgs(c)  = [(x = ax, y = ay, w = Int(e.w), h = Int(e.h)) for (e, ax, ay) in _flat(c) if e isa GraphicsImage]
_rects(c) = [(x = ax, y = ay, w = Int(e.w), h = Int(e.h), color = e.color) for (e, ax, ay) in _flat(c) if e isa GraphicsRect && Int(e.w) > 0]

@testset "TextToGraphics" begin

# basic layout (wrapping is now done by WordWrapping upstream)
st_wrap = TextText(
    TextString("Hello world this is a long text", font_ubuntu_monospace_regular_20, color_red),
)
m = _test_measure(10, 18)
chain = ChainingProjection(WordWrapping(max_width=200, measure=m), TextToGraphics(measure=m))
sdl_cell = projection_print(chain, st_wrap).output
texts = _texts(sdl_cell)
@test length(texts) >= 2  # should wrap
@test texts[1].y == 0
@test texts[2].y == 18  # second line

# newline handling
st_nl = TextText(
    TextString("line1\nline2\nline3", font_ubuntu_monospace_regular_20, color_white),
)
sdl_nl = projection_print(TextToGraphics(measure=_test_measure(10, 20)), st_nl).output
items_nl = _texts(sdl_nl)
@test length(items_nl) == 3
@test items_nl[1].text == "line1"
@test items_nl[2].text == "line2"
@test items_nl[3].text == "line3"
@test items_nl[1].y == 0
@test items_nl[2].y == 20
@test items_nl[3].y == 40

# color preservation
st_color = TextText(
    TextString("red text", font_ubuntu_monospace_regular_20, color_red),
    TextString(" blue text", font_ubuntu_monospace_regular_20, color_blue),
)
sdl_color = projection_print(TextToGraphics(measure=_test_measure(10, 48)), st_color).output
items_c = _texts(sdl_color)
@test items_c[1].color == color_red    # red
@test items_c[2].color == color_blue   # blue

# continuation on same line
@test items_c[2].y == items_c[1].y  # same line
@test items_c[2].x > items_c[1].x   # to the right

# reactivity: a text change invalidates that line's segment vector (but, by
# per-line locality, NOT the top-level line list — see the locality testset).
st_react = TextText(
    TextString("short", font_ubuntu_monospace_regular_20, color_white),
)
sdl_react = projection_print(TextToGraphics(measure=_test_measure(10, 48)), st_react).output
line1 = sdl_react.elements[2].elements[1]   # top[2]=line stack, [1]=first line sub-canvas
_ = length(line1.elements)
@test isuptodate(getfield(line1.elements, :elements))
st_react.elements[1].content = "changed"
@test !isuptodate(getfield(line1.elements, :elements))
items_r = _texts(sdl_react)
@test items_r[1].text == "changed"

# hex color parsing
st_hex = TextText(TextString("hex", font_ubuntu_monospace_regular_20, StyleColor(1.0, 0.53, 0.0, 1.0)))
sdl_hex = projection_print(TextToGraphics(measure=_test_measure(10, 48)), st_hex).output
h = _texts(sdl_hex)[1]
# StyleColor is now carried through unchanged (no byte round-trip).
@test h.color == StyleColor(1.0, 0.53, 0.0, 1.0)

end # @testset "TextToGraphics"

@testset "TextToGraphics ListNode path" begin

# Build a TextText with ListNode elements: two paragraphs separated by TextNewline
node = ListNode(TextString("Hello world", font_ubuntu_monospace_regular_20, color_red))
push!(node, TextNewline(font=font_ubuntu_monospace_regular_20))
push!(node, TextString("Second paragraph", font_ubuntu_monospace_regular_20, color_blue))

tt = TextText()
tt.elements = node

p = TextToGraphics(measure=_test_measure(10, 20))
iomap = projection_print(p, IdentityProjection(), tt, PrinterContext())
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
node = ListNode(TextString("Para 1", font_ubuntu_monospace_regular_20, color_white))

# Build a lazy chain of paragraphs
node2 = ListNode(TextNewline(font=font_ubuntu_monospace_regular_20))
node.next = node2
node2.prev = node

node3 = ListNode(TextString("Para 2", font_ubuntu_monospace_regular_20, color_white))
setfn!(getfield(node2, :next), () -> begin
    counter[] += 1
    node3.prev = node2
    node3
end)

tt = TextText()
tt.elements = node

p = TextToGraphics(measure=_test_measure(10, 20))
iomap = projection_print(p, IdentityProjection(), tt, PrinterContext())

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
    TextString("ab", font_ubuntu_monospace_regular_20, color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", font_ubuntu_monospace_regular_20, color_white),
)
canvas = projection_print(TextToGraphics(measure=m), st).output

# Exactly one GraphicsImage, at the expected box (after "ab" = 20px).
imgs = _imgs(canvas)
@test length(imgs) == 1
gi = imgs[1]
@test gi.x == 20
@test gi.y == 0
@test gi.w == 64
@test gi.h == 64

# Line height follows the image height.
@test canvas.h >= 64

# Surrounding text flows before/after the image on the same line.
texts = _texts(canvas)
@test length(texts) == 2
@test texts[1].text == "ab" && texts[1].x == 0
@test texts[2].text == "cd" && texts[2].x == 20 + 64

end # @testset "TextToGraphics inline image"

@testset "TextToGraphics inline image hit-test" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure=m)
st = TextText(
    TextString("ab", font_ubuntu_monospace_regular_20, color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", font_ubuntu_monospace_regular_20, color_white),
)
iomap = projection_print(p, st)

# A click path encodes (element-index → pixel offset). The persistent highlight
# rect is element 1, so the image (2nd text segment) is element index 2 (0-based);
# rx<32 is its left half, rx>=32 its right half.
click(rx) = ReplaceSelectionOperation(
    ConcreteReferencePath(RangeReference(2, 3),
        ConcreteReferencePath(PointReference(rx, 0), EmptyReferencePath())))
left  = projection_read(p, iomap, click(10))
right = projection_read(p, iomap, click(50))
@test left isa ReplaceSelectionOperation
@test right isa ReplaceSelectionOperation
# Left half → cursor before the image (content{0}); right half → after ({1}).
@test reference_equal(left.path,  Projectured.TextToGraphicsModule._build_selection_path(2, 0))
@test reference_equal(right.path, Projectured.TextToGraphicsModule._build_selection_path(2, 1))

end # @testset "TextToGraphics inline image hit-test"

@testset "TextToGraphics renders fill_color as a background rect" begin

m = _test_measure(10, 18)
hl = TextString("hi", font_ubuntu_monospace_regular_20, color_red)
hl.fill_color = color_blue              # a highlighted span opts into a swatch
plain = TextString("xy", font_ubuntu_monospace_regular_20, color_red)
st = TextText(hl, plain)
canvas = projection_print(TextToGraphics(measure=m), st).output

# Exactly one *visible* rect — the filled span; the default-`nothing` span gets
# none. The always-present highlight/cursor overlay rects are zero-width here.
rects = _rects(canvas)
@test length(rects) == 1
rect = rects[1]
@test rect.x == 0 && rect.y == 0
@test rect.w == 20 && rect.h == 18      # tight measured box of "hi"
@test rect.color == color_blue   # blue fill

# The fill rect is drawn before its text, so it paints behind.
flat = _flat(canvas)
rect_idx = findfirst(t -> t[1] isa GraphicsRect && Int(t[1].w) > 0, flat)
hi_idx   = findfirst(t -> t[1] isa GraphicsText && t[1].text == "hi", flat)
@test rect_idx !== nothing && hi_idx !== nothing
@test rect_idx < hi_idx

end # @testset "TextToGraphics fill_color rect"

@testset "TextToGraphics per-line dirty-rect locality" begin

# Lines split at TextNewline elements become independent reactive sub-canvases.
# Editing one line must invalidate only that line's segment vector — never the
# top-level line list (so the backend dirty-walk descends and repaints just the
# edited line) and never an earlier line.
m = _test_measure(10, 20)
nl() = TextNewline(font=font_ubuntu_monospace_regular_20)
st = TextText(
    TextString("alpha", font_ubuntu_monospace_regular_20, color_white), nl(),
    TextString("beta",  font_ubuntu_monospace_regular_20, color_white), nl(),
    TextString("gamma", font_ubuntu_monospace_regular_20, color_white),
)
canvas = projection_print(TextToGraphics(measure=m), st).output

# Top canvas: [highlight, vertical line stack, cursor].
stack = canvas.elements[2]
@test stack isa GraphicsCanvas
@test stack.layout == layout_vertical
@test length(stack.elements) == 3
lines = [stack.elements[i] for i in 1:3]
@test all(l -> l isa GraphicsCanvas, lines)
@test [Int(l.y) for l in lines] == [0, 20, 40]      # cumulative line heights
@test [_texts(l)[1].text for l in lines] == ["alpha", "beta", "gamma"]

# Force every line's segment vector + text, then snapshot validity.
for l in lines
    _ = length(l.elements)
    for i in 1:length(l.elements); _ = l.elements[i].text; end
end
topback   = getfield(canvas.elements, :elements)
stackback = getfield(stack.elements, :elements)
lineback(L) = getfield(lines[L].elements, :elements)
@test isuptodate(topback) && isuptodate(stackback)
@test all(L -> isuptodate(lineback(L)), 1:3)

# Edit the LAST line. Only its segment vector goes stale.
st.elements[5].content = "gamma!"          # element 5 = the 3rd TextString
@test isuptodate(topback)                  # line list is structural — untouched
@test isuptodate(stackback)
@test isuptodate(lineback(1))
@test isuptodate(lineback(2))
@test !isuptodate(lineback(3))
@test _texts(lines[3])[1].text == "gamma!"

end # @testset "TextToGraphics per-line locality"

end # test_text_to_graphics
